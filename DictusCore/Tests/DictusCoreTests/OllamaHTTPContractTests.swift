import XCTest
@testable import DictusCore

final class OllamaHTTPContractTests: XCTestCase {
    func testBuildsOpenAICompatibleEndpoint() {
        XCTAssertEqual(
            OllamaHTTPContract.endpoint(baseURL: "http://127.0.0.1:11434")?.absoluteString,
            "http://127.0.0.1:11434/v1/chat/completions"
        )
    }

    func testDoesNotDuplicateExistingV1Path() {
        XCTAssertEqual(
            OllamaHTTPContract.endpoint(baseURL: "http://127.0.0.1:11434/v1")?.absoluteString,
            "http://127.0.0.1:11434/v1/chat/completions"
        )
        XCTAssertEqual(
            OllamaHTTPContract.endpoint(baseURL: "http://127.0.0.1:11434/v1/")?.absoluteString,
            "http://127.0.0.1:11434/v1/chat/completions"
        )
    }

    func testRejectsHTTPStatus() {
        XCTAssertThrowsError(try OllamaHTTPContract.responseText(data: Data("busy".utf8), statusCode: 503)) { error in
            XCTAssertEqual(error as? OllamaHTTPContract.Error, .httpStatus(503, "busy"))
        }
    }

    func testRejectsMalformedResponse() {
        XCTAssertThrowsError(try OllamaHTTPContract.responseText(data: Data(#"{"choices":[]}"#.utf8), statusCode: 200)) { error in
            XCTAssertEqual(error as? OllamaHTTPContract.Error, .malformedResponse)
        }
    }

    func testReadsSuccessfulMessageContent() throws {
        let data = Data(#"{"choices":[{"message":{"content":"  Clean text  "}}]}"#.utf8)
        XCTAssertEqual(try OllamaHTTPContract.responseText(data: data, statusCode: 200), "Clean text")
    }

    func testRejectsTruncatedOrFilteredResponsesEvenWithPlausibleContent() {
        for reason in ["length", "content_filter", "tool_calls"] {
            let data = Data("{\"choices\":[{\"finish_reason\":\"\(reason)\",\"message\":{\"content\":\"Do not send 42 EUR to Léa\"}}]}".utf8)
            XCTAssertThrowsError(try OllamaHTTPContract.responseText(data: data, statusCode: 200)) {
                XCTAssertEqual($0 as? OllamaHTTPContract.Error, .incompleteResponse)
            }
        }
    }

    func testReasoningMustFinishAndContainAnAnswer() throws {
        for content in ["<think>unfinished", "<think>done</think>  "] {
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
            XCTAssertThrowsError(try OllamaHTTPContract.responseText(data: data, statusCode: 200))
        }
        let data = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"<think>internal</think> Do not send 42 EUR to Léa."}}]}"#.utf8)
        XCTAssertEqual(try OllamaHTTPContract.responseText(data: data, statusCode: 200), "Do not send 42 EUR to Léa.")
    }

    func testLiteralClosingTagDoesNotDiscardTranscriptPrefix() throws {
        let data = Data(#"{"choices":[{"message":{"content":"Keep the literal </think> tag."}}]}"#.utf8)
        XCTAssertEqual(try OllamaHTTPContract.responseText(data: data, statusCode: 200), "Keep the literal </think> tag.")
    }
}
