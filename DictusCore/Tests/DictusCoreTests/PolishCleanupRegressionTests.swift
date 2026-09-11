import XCTest
@testable import DictusCore

final class PolishCleanupRegressionTests: XCTestCase {
    func testAutoCleanupPreservesMixedLanguageTranscript() {
        let input = "Ich schicke dir the invoice tomorrow und 我晚上再确认。"
        let cleaned = PolishPostpass.cleanupFloor(input, language: nil)

        XCTAssertEqual(cleaned, input)
        XCTAssertTrue(cleaned.contains("Ich schicke dir"))
        XCTAssertTrue(cleaned.contains("the invoice tomorrow"))
        XCTAssertTrue(cleaned.contains("我晚上再确认"))
    }

    func testAutoCleanupPreservesBulletsIndentationAndPunctuation() {
        let input = "- send the invoice , today !\n  * 付款完成后再确认。\n  2. follow up tomorrow?"
        let cleaned = PolishPostpass.cleanupFloor(input, language: nil)

        XCTAssertEqual(cleaned, "- Send the invoice, today!\n  * 付款完成后再确认。\n  2. Follow up tomorrow?")
    }

    func testAutoCleanupIsIdempotent() {
        let input = "- Ich schicke dir the invoice tomorrow und 我晚上再确认。"
        let once = PolishPostpass.cleanupFloor(input, language: nil)
        XCTAssertEqual(PolishPostpass.cleanupFloor(once, language: nil), once)
    }

    func testAutoCleanupDoesNotAddLatinSpacingAroundCJKText() {
        let input = "你好，can you send me die Rechnung bitte?"
        let cleaned = PolishPostpass.cleanupFloor(input, language: nil)

        XCTAssertEqual(cleaned, input)
        XCTAssertFalse(cleaned.contains("你好， "))
        XCTAssertTrue(cleaned.contains("can you send me"))
        XCTAssertTrue(cleaned.contains("die Rechnung bitte"))
    }
}
