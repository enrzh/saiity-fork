import XCTest
@testable import DictusCore

final class PolishPromptEnvelopeTests: XCTestCase {
    func testUserTurnKeepsInputBoundedByExplicitOutputMarkers() {
        let input = "first line\nsecond line"
        let prompt = PolishPromptEnvelope.userTurn(raw: input)

        XCTAssertTrue(prompt.hasPrefix("Edit the dictated transcript below conservatively."))
        XCTAssertTrue(prompt.contains("<DICTATION_TRANSCRIPT>\n\(input)\n</DICTATION_TRANSCRIPT>"))
        XCTAssertTrue(prompt.contains("original language"))
        XCTAssertTrue(prompt.contains("bullet points"))
        XCTAssertEqual(prompt.components(separatedBy: "<DICTATION_TRANSCRIPT>").count - 1, 1)
        XCTAssertEqual(prompt.components(separatedBy: "</DICTATION_TRANSCRIPT>").count - 1, 1)
    }
}
