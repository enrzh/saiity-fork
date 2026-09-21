import XCTest
@testable import DictusCore

final class PolishCancellationRegressionTests: XCTestCase {
    private actor FailingEngine: PolishEngineProtocol {
        let identifier = "failure-fixture"
        let code: URLError.Code
        private(set) var calls = 0

        init(code: URLError.Code) { self.code = code }

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
}
