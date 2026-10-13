import XCTest
import MLX
@testable import Qwen3ASR

final class CancellationTests: XCTestCase {
    private final class StopAfter: @unchecked Sendable {
        private let lock = NSLock()
        private var checks = 0
        func shouldStop() -> Bool { lock.withLock { checks += 1; return checks >= 4 } }
    }

    func testCancellationInterruptsBothTokenLoopsBeforeTheTokenLimit() {
        var config = TextDecoderConfig()
        config.vocabSize = 8; config.hiddenSize = 64; config.numLayers = 0
        config.numHeads = 1; config.numKVHeads = 1; config.headDim = 64; config.intermediateSize = 64
        let decoder = QuantizedTextModel(config: config)
        let logits = MLXArray([Float(1), 0, 0, 0, 0, 0, 0, 0])
        let greedyStop = StopAfter()
        let greedy = Qwen3ASRModel.generateGreedyAsyncEval(textDecoder: decoder, initialLogits: logits,
            cache: [], maxTokens: 20, shouldCancel: { greedyStop.shouldStop() })
        XCTAssertEqual(greedy.count, 2)
        let slowStop = StopAfter()
        var options = Qwen3DecodingOptions()
        options.shouldCancel = { slowStop.shouldStop() }
        let slow = Qwen3ASRModel.generateSlow(textDecoder: decoder, initialLogits: logits,
            cache: [], maxTokens: 20, options: options)
        XCTAssertEqual(slow.count, 3)
        Stream.defaultStream(.gpu).synchronize()
    }
    func testBothCancelledDecodersReturnBeforeEvaluatingTheForwardPass() {
        var config = TextDecoderConfig()
        config.vocabSize = 8; config.hiddenSize = 64; config.numLayers = 0
        config.numHeads = 1; config.numKVHeads = 1; config.headDim = 64; config.intermediateSize = 64
        let decoder = QuantizedTextModel(config: config)
        let logits = MLXArray([Float(0)])
        XCTAssertEqual(Qwen3ASRModel.generateGreedyAsyncEval(textDecoder: decoder,
            initialLogits: logits, cache: [], maxTokens: 3, shouldCancel: { true }), [])
        var options = Qwen3DecodingOptions()
        options.shouldCancel = { true }
        XCTAssertEqual(Qwen3ASRModel.generateSlow(textDecoder: decoder, initialLogits: logits,
            cache: [], maxTokens: 3, options: options), [])
    }
    func testCancellationIsCheckedWithoutLoadingWeightsOrSubmittingAudio() {
        var options = Qwen3DecodingOptions()
        options.shouldCancel = { true }
        XCTAssertThrowsError(try options.checkCancellation()) { XCTAssertTrue($0 is CancellationError) }
        options.shouldCancel = { false }
        XCTAssertNoThrow(try options.checkCancellation())
    }

    func testTaskCancellationReachesTheDefaultDecoderControl() async throws {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            XCTAssertThrowsError(try Qwen3DecodingOptions().checkCancellation())
        }
        task.cancel()
        try await task.value
    }
}
