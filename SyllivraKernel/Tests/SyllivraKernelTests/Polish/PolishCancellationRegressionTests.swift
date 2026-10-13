import XCTest
@testable import SyllivraKernel

final class PolishCancellationRegressionTests: XCTestCase {
    private actor FailingEngine: PolishEngineProtocol {
        let identifier = "failure-fixture"
        let code: URLError.Code
        let prohibitsPreparation: Bool
        private(set) var calls = 0

        init(code: URLError.Code, prohibitsPreparation: Bool = false) {
            self.code = code
            self.prohibitsPreparation = prohibitsPreparation
        }

        nonisolated func contextFit(input: String, targetLanguage: SupportedLanguage, mode: PolishMode) -> PolishContextFit {
            if prohibitsPreparation { XCTFail("Unused processing must skip context/prompt preparation") }
            return .fits
        }

        func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
            calls += 1
            throw URLError(code)
        }
    }

    func testAlreadyCancelledCallDoesNotReachEngine() async {
        let engine = FailingEngine(code: .badServerResponse)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await PolishPipeline.transform(
                preprocessed: "Do not send 42 EUR to Léa.",
                engine: engine, target: .english, mode: .auto
            )
        }
        let result = await task.value
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertEqual(result.engineMs, 0)
        XCTAssertNil(result.failureReason)
        let calls = await engine.calls
        XCTAssertEqual(calls, 0)
    }

    func testHTTPTimeoutAndCancellationKeepMixedLanguageStructuredFallback() async {
        let input = "Bitte nicht senden: 42 EUR an Léa.\n\n1. Keep the invoice\n  - 我明天再确认，不要发送。"
        for code in [URLError.Code.cancelled, .timedOut] {
            let result = await PolishPipeline.transform(
                preprocessed: input, engine: FailingEngine(code: code), target: .french, mode: .auto
            )
            XCTAssertEqual(result.outcome, code == .cancelled ? .cancelled : .engineFailed)
            XCTAssertEqual(PolishPipeline.resolvedOutput(
                result, preprocessed: input, target: .french, mode: .auto
            ), input)
        }
    }

    func testBlankInputSkipsPreparationAndInferenceForEveryStyle() async {
        for style in WritingStyle.allCases {
            let engine = FailingEngine(code: .badServerResponse, prohibitsPreparation: true)
            let result = await PolishPipeline.transform(preprocessed: " \n\t ", engine: engine,
                target: .french, mode: .auto, style: style)
            XCTAssertEqual(result.outcome, .skipped)
            XCTAssertEqual(result.engineMs, 0)
            let calls = await engine.calls
            XCTAssertEqual(calls, 0)
        }
    }

    func testExpiredInputSkipsPreparationAndRetainsCompleteStructuredFallback() async {
        let input = "Bitte nicht senden: 42 EUR an Léa.\n\n1. Keep the invoice\n  - 我明天再确认，不要发送。"
        let engine = FailingEngine(code: .badServerResponse, prohibitsPreparation: true)
        let result = await PolishPipeline.transform(preprocessed: input, engine: engine, target: .french,
            mode: .auto, deadline: PolishDeadline(timeout: .zero))
        XCTAssertEqual(result.outcome, .engineFailed)
        XCTAssertEqual(result.failureReason?.slug, PolishExecutionError.timedOut.rawValue)
        XCTAssertEqual(result.engineMs, 0)
        let calls = await engine.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(PolishPipeline.resolvedOutput(result, preprocessed: input, target: .french, mode: .auto), input)
    }

    #if canImport(FoundationModels)
    func testAppleEngineRejectsCancelledWorkBeforeUsingTheModel() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("Foundation Models needs iOS/macOS 26") }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await AppleFoundationModelsPolishEngine().polish(raw: "Do not send 42 EUR to Léa.",
                    targetLanguage: .english, mode: .auto)
                XCTFail("Cancelled work must not produce a model response")
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        await task.value
    }
    #endif
}
