import XCTest
import CoreML
import SyllivraKernel
@testable import SyllivraInference

final class NativeModelLoadingTests: XCTestCase {
    private func cacheArtifacts() throws -> NativeModelArtifacts {
        let directory = try XCTUnwrap(Bundle.module.url(forResource: "qwen-cache", withExtension: nil,
                                                        subdirectory: "Fixtures"))
        return try NativeModelArtifacts(directory: directory, expectedModelIdentifier: "native-qwen-cache-probe")
    }

    func testOwnedDecoderPrefillsAndStopsAtEOSWithFreshState() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("Stateful decoding needs iOS 18/macOS 15") }
        let artifacts = try cacheArtifacts()
        let model = try await artifacts.loadModel(named: "decoder")
        let first = try await artifacts.generate(using: model, inputTokens: [3, 7, 11, 5],
            maximumNewTokens: 4, endTokenIDs: [5])
        XCTAssertEqual(first, [])
        let fresh = try await artifacts.generate(using: model, inputTokens: [3],
            maximumNewTokens: 4, endTokenIDs: [3])
        XCTAssertEqual(fresh, [])
    }

    func testOwnedDecoderDoesNotPublishTruncatedOutput() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("Stateful decoding needs iOS 18/macOS 15") }
        let artifacts = try cacheArtifacts()
        let model = try await artifacts.loadModel(named: "decoder")
        do {
            _ = try await artifacts.generate(using: model, inputTokens: [3, 7],
                maximumNewTokens: 2, endTokenIDs: [31])
            XCTFail("Reaching the output cap without EOS must reject the incomplete result")
        } catch { XCTAssertEqual(error as? PolishExecutionError, .outputTruncated) }
    }

    func testOwnedDecoderChecksContextAndTokenAdmission() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("Stateful decoding needs iOS 18/macOS 15") }
        let artifacts = try cacheArtifacts()
        let model = try await artifacts.loadModel(named: "decoder")
        do {
            _ = try await artifacts.generate(using: model, inputTokens: Array(repeating: 3, count: 16),
                maximumNewTokens: 1, endTokenIDs: [3])
            XCTFail("A request must reserve output space before predictions")
        } catch { XCTAssertEqual(error as? PolishExecutionError, .contextExceeded) }
        let invalid: [([Int32], Set<Int32>)] = [([], [3]), ([-1], [3]), ([32], [3]), ([3], []), ([3], [32])]
        for (input, ends) in invalid {
            do {
                _ = try await artifacts.generate(using: model, inputTokens: input,
                    maximumNewTokens: 1, endTokenIDs: ends)
                XCTFail("Invalid prompt or EOS metadata must fail before prediction")
            } catch { XCTAssertEqual(error as? NativeModelArtifacts.ValidationError, .invalidTokenizer) }
        }
    }

    func testOwnedDecoderChecksExpiredAndCancelledWork() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else { throw XCTSkip("Stateful decoding needs iOS 18/macOS 15") }
        let artifacts = try cacheArtifacts()
        let model = try await artifacts.loadModel(named: "decoder")
        do {
            _ = try await artifacts.generate(using: model, inputTokens: [3],
                maximumNewTokens: 1, endTokenIDs: [3], deadline: PolishDeadline(timeout: .zero))
            XCTFail("Expired work must not predict")
        } catch { XCTAssertEqual(error as? PolishExecutionError, .timedOut) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await artifacts.generate(using: model, inputTokens: [3],
                maximumNewTokens: 1, endTokenIDs: [3])
        }
        do { _ = try await task.value; XCTFail("Cancelled work must not predict") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testOwnedGreedySelectionKeepsTieOrderAndRejectsNonfiniteLogits() throws {
        let logits = try MLMultiArray(shape: [1, 3], dataType: .float32)
        logits[0] = 2; logits[1] = 2; logits[2] = 1
        XCTAssertEqual(try NativeModelArtifacts.greedyToken(from: logits, vocabularySize: 3), 0)
        logits[1] = NSNumber(value: Float.nan)
        XCTAssertThrowsError(try NativeModelArtifacts.greedyToken(from: logits, vocabularySize: 3))
        logits[1] = NSNumber(value: Float.infinity)
        XCTAssertThrowsError(try NativeModelArtifacts.greedyToken(from: logits, vocabularySize: 3))
    }

    private struct CacheGolden: Decodable {
        let tokens: [Int]
        let logits: [[[Double]]]
        let absoluteTolerance: Double
    }

    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "linear", withExtension: nil, subdirectory: "Fixtures"))
    }

    func testOwnedLinearGraphCompilesAndPredictsKnownLogits() async throws {
        let artifacts = try NativeModelArtifacts(directory: fixture(), expectedModelIdentifier: "native-linear-probe")
        let model = try await artifacts.loadModel(named: "decoder")
        let input = try MLMultiArray(shape: [2], dataType: .float32)
        input[0] = 1
        input[1] = 2
        let features = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: input)])
        let prediction = try await model.prediction(from: features)
        let output = try XCTUnwrap(prediction.featureValue(for: "logits")?.multiArrayValue)
        XCTAssertEqual(output.count, 3)
        for (index, expected) in [2.5, 5, -1].enumerated() {
            XCTAssertEqual(output[index].doubleValue, expected, accuracy: 0.00001)
        }
    }

    func testUnknownGraphFailsBeforePrediction() async throws {
        let artifacts = try NativeModelArtifacts(directory: fixture())
        do {
            _ = try await artifacts.loadModel(named: "not-declared")
            XCTFail("Unknown graph must not load")
        } catch {
            XCTAssertEqual(error as? NativeModelArtifacts.ValidationError, .unknownGraph)
        }
    }

    func testTensorContractMismatchFailsBeforeModelCanBeUsed() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture(), to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("native-runtime.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        var graph = (json["graphs"] as! [[String: Any]])[0]
        graph["outputs"] = [["name": "logits", "dataType": "float32", "shape": [4]]]
        json["graphs"] = [graph]
        try JSONSerialization.data(withJSONObject: json).write(to: path)
        let artifacts = try NativeModelArtifacts(directory: directory)
        do {
            _ = try await artifacts.loadModel(named: "decoder")
            XCTFail("Incompatible tensor contract must not load")
        } catch {
            XCTAssertEqual(error as? NativeModelArtifacts.ValidationError, .incompatibleModel)
        }
    }

    func testCancellationStopsModelLoading() async throws {
        let artifacts = try NativeModelArtifacts(directory: fixture())
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await artifacts.loadModel(named: "decoder")
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled loading must not produce a model")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testTamperingAfterInspectionFailsBeforeLoading() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture(), to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifacts = try NativeModelArtifacts(directory: directory)
        try Data("changed model".utf8).write(to: directory.appendingPathComponent("linear.mlmodel"))
        do {
            _ = try await artifacts.loadModel(named: "decoder")
            XCTFail("Changed artifacts must not reach the compiler")
        } catch {
            XCTAssertEqual(error as? NativeModelArtifacts.ValidationError, .hashMismatch)
        }
    }

    func testOwnedQwenCacheGraphMatchesReferenceAndStartsFresh() async throws {
        guard #available(iOS 18.0, macOS 15.0, *) else {
            throw XCTSkip("Stateful Core ML requires iOS 18 or macOS 15")
        }
        let directory = try XCTUnwrap(Bundle.module.url(forResource: "qwen-cache", withExtension: nil,
                                                        subdirectory: "Fixtures"))
        let artifacts = try NativeModelArtifacts(directory: directory,
            expectedModelIdentifier: "native-qwen-cache-probe", expectedRevision: "owned-qwen-cache-v1")
        let golden = try JSONDecoder().decode(CacheGolden.self,
            from: Data(contentsOf: directory.appendingPathComponent("cache-golden.json")))
        let model = try await artifacts.loadModel(named: "decoder")
        XCTAssertEqual(artifacts.manifest.graphs[0].states.count, 4)
        let state = model.makeState()

        func predict(token: Int, position: Int, state: MLState) async throws -> MLMultiArray {
            let ids = try MLMultiArray(shape: [1, 1], dataType: .int32)
            ids[0] = NSNumber(value: token)
            let offset = try MLMultiArray(shape: [1], dataType: .int32)
            offset[0] = NSNumber(value: position)
            let mask = try MLMultiArray(shape: [1, 1, 1, 16], dataType: .float32)
            for index in 0..<16 { mask[index] = index <= position ? 0 : -10000 }
            let input = try MLDictionaryFeatureProvider(dictionary: ["input_ids": MLFeatureValue(multiArray: ids),
                "position": MLFeatureValue(multiArray: offset), "causal_mask": MLFeatureValue(multiArray: mask)])
            let output = try await model.prediction(from: input, using: state)
            return try XCTUnwrap(output.featureValue(for: "logits")?.multiArrayValue)
        }

        for (position, token) in golden.tokens.enumerated() {
            let output = try await predict(token: token, position: position, state: state)
            let expected = golden.logits[position][0]
            XCTAssertEqual(output.count, expected.count)
            for index in expected.indices {
                XCTAssertEqual(output[index].doubleValue, expected[index], accuracy: golden.absoluteTolerance)
            }
        }
        let fresh = try await predict(token: golden.tokens[0], position: 0, state: model.makeState())
        for index in golden.logits[0][0].indices {
            XCTAssertEqual(fresh[index].doubleValue, golden.logits[0][0][index], accuracy: golden.absoluteTolerance)
        }
    }
}
