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
        XCTAssertEqual(try OllamaHTTPContract.responseText(data: data, statusCode: 200), "  Clean text  ")
    }
}
