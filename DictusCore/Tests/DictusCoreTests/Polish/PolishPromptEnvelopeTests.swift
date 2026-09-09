import XCTest
@testable import DictusCore

final class PolishPromptEnvelopeTests: XCTestCase {
    func testUserTurnKeepsInputBoundedByExplicitOutputMarkers() {
        let input = "first line\nsecond line"
        let prompt = PolishPromptEnvelope.userTurn(raw: input)

        XCTAssertTrue(prompt.hasPrefix("Polish this text. Output only the polished version, nothing else."))
        XCTAssertTrue(prompt.contains("Input:\n\(input)\n\nPolished output:"))
        XCTAssertEqual(prompt.components(separatedBy: "Input:").count - 1, 1)
        XCTAssertEqual(prompt.components(separatedBy: "Polished output:").count - 1, 1)
    }
}
