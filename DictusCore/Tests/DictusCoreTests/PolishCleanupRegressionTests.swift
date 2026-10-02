import XCTest
@testable import DictusCore

final class PolishCleanupRegressionTests: XCTestCase {
    func testForeignLanguageAnnotationIsRemovedWithoutRewritingTraditionalChinese() {
        let chinese = "那會不會是暗吧"
        for label in ["(speaking in foreign language)", "[speaking in foreign language]", "*speaking in foreign language*", "(Speaking In Foreign Language)"] {
            let input = label + chinese
            XCTAssertEqual(PolishPostpass.cleanupFloor(input, language: nil), chinese)
            XCTAssertEqual(TranscriptionPipeline.assemble(cleaned: input, grammarLanguage: nil,
                insertAsIs: true).formatted, chinese)
        }
        let ordinary = "They are speaking in a foreign language (see attached)."
        XCTAssertEqual(PolishPostpass.cleanupFloor(ordinary, language: nil), ordinary)
        XCTAssertEqual(PolishPostpass.removeNonSpeechEventLabels("(foreign language department)"), "(foreign language department)")
    }
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
