import XCTest
import CryptoKit
import SyllivraInference

final class NativeModelArtifactsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func writeManifest(_ change: (inout [String: Any]) -> Void = { _ in }) throws {
        let data = Data("owned test artifact".utf8)
        try data.write(to: directory.appendingPathComponent("model.mlmodel"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var manifest: [String: Any] = [
            "schemaVersion": 1, "modelIdentifier": "native-test", "upstreamRevision": "fixture-v1",
            "architecture": "coreml-probe", "minimumIOSMajor": 17,
            "license": ["identifier": "CC0-1.0", "source": "generated-test-fixture"],
            "files": ["model.mlmodel": digest],
            "graphs": [["name": "decoder", "path": "model.mlmodel",
                        "inputs": [["name": "input", "dataType": "float32", "shape": [2]]],
                        "outputs": [["name": "logits", "dataType": "float32", "shape": [3]]],
                        "states": []]]
        ]
        change(&manifest)
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: directory.appendingPathComponent("native-runtime.json"))
    }

    func testCompleteArtifactLoadsAndBindsRequestedIdentity() throws {
        try writeManifest()
        let artifacts = try NativeModelArtifacts(directory: directory,
            expectedModelIdentifier: "native-test", expectedRevision: "fixture-v1")
        XCTAssertEqual(artifacts.manifest.modelIdentifier, "native-test")
        XCTAssertEqual(artifacts.manifest.graphs.map(\.name), ["decoder"])
    }

    func testMissingManifestFailsClosed() {
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    func testMissingArtifactFailsClosed() throws {
        try writeManifest()
        try FileManager.default.removeItem(at: directory.appendingPathComponent("model.mlmodel"))
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    func testChangedArtifactFailsItsHash() throws {
        try writeManifest()
        try Data("modified artifact".utf8).write(to: directory.appendingPathComponent("model.mlmodel"))
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    func testMalformedHashFailsClosed() throws {
        try writeManifest { $0["files"] = ["model.mlmodel": "not-a-sha256"] }
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    func testWrongModelOrRevisionFailsClosed() throws {
        try writeManifest()
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory, expectedModelIdentifier: "other-model"))
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory, expectedRevision: "other-revision"))
    }

    func testUnsupportedSchemaAndArchitectureFailClosed() throws {
        try writeManifest { $0["schemaVersion"] = 2 }
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
        try writeManifest { $0["architecture"] = "unimplemented-model-family" }
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    func testUnlistedGraphAndEmptyGraphsFailClosed() throws {
        try writeManifest { $0["files"] = [:] }
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
        try writeManifest { $0["graphs"] = [] }
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    func testTraversalAndAbsoluteArtifactPathsFailClosed() throws {
        for path in ["../model.mlmodel", "/model.mlmodel", "nested/../../model.mlmodel", "nested\\model.mlmodel"] {
            try writeManifest { $0["files"] = [path: String(repeating: "a", count: 64)] }
            XCTAssertThrowsError(try NativeModelArtifacts(directory: directory), path)
        }
    }

    func testSymlinkArtifactFailsClosed() throws {
        try writeManifest()
        let file = directory.appendingPathComponent("model.mlmodel")
        let target = directory.appendingPathComponent("hidden.mlmodel")
        try FileManager.default.moveItem(at: file, to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    func testDuplicateGraphNamesFailClosed() throws {
        try writeManifest { manifest in
            let graph = (manifest["graphs"] as! [[String: Any]])[0]
            manifest["graphs"] = [graph, graph]
        }
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    func testInvalidOrOverflowingTensorShapesFailClosed() throws {
        for shape in [[0], [-1, 2], [Int.max, 2], [Int.max]] {
            try writeManifest { manifest in
                var graph = (manifest["graphs"] as! [[String: Any]])[0]
                graph["inputs"] = [["name": "input", "dataType": "float32", "shape": shape]]
                manifest["graphs"] = [graph]
            }
            XCTAssertThrowsError(try NativeModelArtifacts(directory: directory), "shape=\(shape)")
        }
    }

    func testStateRequiresIOS18AndMatchesContextAxis() throws {
        for major in [17, 18] {
            try writeManifest { manifest in
                manifest["minimumIOSMajor"] = major
                manifest["contextWindowTokens"] = 16
                var graph = (manifest["graphs"] as! [[String: Any]])[0]
                graph["states"] = [["name": "cache", "dataType": "float16", "shape": [1, 15, 8], "contextAxis": 1]]
                manifest["graphs"] = [graph]
            }
            XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
        }
    }

    func testDecoderArchitectureRequiresTokenizerAndTokenBudget() throws {
        try writeManifest { $0["architecture"] = "qwen2_5" }
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    private func writeTokenizer(_ vocabulary: [String: Int], endToken: Int = 2) throws {
        let data = try JSONSerialization.data(withJSONObject: ["model": ["type": "BPE", "vocab": vocabulary, "merges": []]])
        try data.write(to: directory.appendingPathComponent("tokenizer.json"))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try writeManifest { manifest in
            manifest["architecture"] = "qwen2_5"
            manifest["contextWindowTokens"] = 16
            manifest["vocabularySize"] = 3
            manifest["tokenizer"] = ["path": "tokenizer.json", "kind": "bpe", "endTokenIDs": [endToken]]
            var files = manifest["files"] as! [String: String]
            files["tokenizer.json"] = digest
            manifest["files"] = files
        }
    }

    func testValidTokenizerMetadataLoads() throws {
        try writeTokenizer(["a": 0, "b": 1, "</s>": 2])
        let artifacts = try NativeModelArtifacts(directory: directory)
        XCTAssertEqual(artifacts.manifest.tokenizer?.endTokenIDs, [2])
    }

    func testEmptyOrDuplicateVocabularyFailsClosed() throws {
        for vocabulary in [[:], ["a": 0, "b": 0, "</s>": 2]] {
            try writeTokenizer(vocabulary)
            XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
        }
    }

    func testEOSMustExistInVocabularyAndFitModelOutput() throws {
        try writeTokenizer(["a": 0, "b": 1], endToken: 2)
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
        try writeTokenizer(["a": 0, "b": 1, "</s>": 2], endToken: 3)
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }

    func testMissingLicenseAndEmptyIdentityFailClosed() throws {
        try writeManifest { $0["license"] = ["identifier": "", "source": ""] }
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
        try writeManifest { $0["modelIdentifier"] = "" }
        XCTAssertThrowsError(try NativeModelArtifacts(directory: directory))
    }
}
