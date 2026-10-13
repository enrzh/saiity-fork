import XCTest
@testable import SyllivraKernel

final class PolishCleanupRegressionTests: XCTestCase {
    func testAutoProducesTypedMessageFromClearEnglishRestartsAndCorrections() {
        let raw = "Um, I I I will send the invoice to Léa tomorrow at 2, actually 3. Please confirm receipt."
        let expected = "I will send the invoice to Léa tomorrow at 3. Please confirm receipt."
        XCTAssertEqual(PolishPostpass.cleanupFloor(raw, language: nil), expected)
        XCTAssertEqual(PolishPostpass.cleanupFloor(expected, language: nil), expected)
    }

    func testAdjacentNumberCorrectionsKeepUnrelatedFactsAndProtectedTokens() {
        for (raw, expected) in [
            ("Send invoice AB-120 for 42 EUR; meet at 2, actually 3 tomorrow.",
             "Send invoice AB-120 for 42 EUR; meet at 3 tomorrow."),
            ("Please send 12, I mean 15 euros to Léa, not 50 euros.",
             "Please send 15 euros to Léa, not 50 euros."),
            ("Please pay 12.5, I mean 15.5 euros for invoice 120.",
             "Please pay 15.5 euros for invoice 120."),
            ("Meet on 2026-10-13, actually 14; keep invoice AB-120, actually 130.",
             "Meet on 2026-10-13, actually 14; keep invoice AB-120, actually 130."),
            ("Visit https://example.test/2, actually 3 tomorrow.",
             "Visit https://example.test/2, actually 3 tomorrow."),
            ("Keep `2, actually 3` unchanged in the example.",
             "Keep `2, actually 3` unchanged in the example."),
            ("Pay 2 kg, actually 3 EUR, not 4 EUR.",
             "Pay 2 kg, actually 3 EUR, not 4 EUR."),
            ("Please keep values 1,2,3, actually 4 on the invoice and confirm receipt.",
             "Please keep values 1,2,3, actually 4 on the invoice and confirm receipt.")
        ] {
            XCTAssertEqual(PolishPostpass.cleanupFloor(raw, language: .english), expected, raw)
        }
    }

    func testAutoKeepsMeaningfulRepetitionAndLanguageSpecificFunctionWords() {
        for raw in [
            "I like this very very much and I had had enough; do not change invoice AB-120.",
            "Ich komme um 15 Uhr, and I I will send the invoice tomorrow. 我确认。",
            "a escola fica perto de casa e um amigo vem comigo"
        ] {
            let expected = String(raw.prefix(1)).uppercased() + raw.dropFirst()
            XCTAssertEqual(PolishPostpass.cleanupFloor(raw, language: nil), expected, raw)
        }
        let restart = "Um, I I I will send the invoice tomorrow."
        XCTAssertEqual(PolishPostpass.cleanupFloor(restart, language: nil), restart,
            "The language validator declines this repetitive fragment; preserve it")
        let longRestart = "Um, " + String(repeating: "I ", count: 128) + "will send the invoice tomorrow."
        XCTAssertEqual(PolishPostpass.cleanupFloor(longRestart, language: nil), longRestart,
            "A long recognition loop has uncertain language; keep it recoverable")
    }

    func testEnglishAndFrenchDictatedStructureSurvivesAutomaticCleanup() {
        for (raw, language, expected) in [
            ("Notes full stop new paragraph bullet point send invoice AB-120 bullet point call Léa",
             "en", "Notes.\n\n• Send invoice AB-120\n• Call Léa"),
            ("Notes nouveau paragraphe point de liste payer 17,50 euros point de liste appeler Léa",
             "fr", "Notes\n\n• Payer 17,50 euros\n• Appeler Léa")
        ] {
            let preprocessed = PolishPipeline.autoPreprocess(raw, detectedCode: language)
            let cleaned = PolishPostpass.cleanupFloor(preprocessed, language: nil)
            XCTAssertEqual(cleaned, expected, raw)
            XCTAssertEqual(PolishPostpass.cleanupFloor(cleaned, language: nil), expected)
        }
    }

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
