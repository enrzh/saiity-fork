import XCTest
@testable import SyllivraKernel

final class PolishFactPreservationTests: XCTestCase {
    func testLocalSelfCorrectionCannotDeleteEarlierUnrelatedFacts() {
        let raw = "Please send invoice 120 for 42 euros. Meet at 2pm, actually 3pm tomorrow."
        XCTAssertTrue(PolishGuardrail.preservesFacts(raw: raw,
            polished: "Please send invoice 120 for 42 euros. Meet at 3pm tomorrow.", mode: .auto))
        XCTAssertFalse(PolishGuardrail.preservesFacts(raw: raw,
            polished: "Please meet at 3pm tomorrow.", mode: .auto))
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "Please send Peter the invoice. Speak to John, actually Jack tomorrow.",
            polished: "Please speak to Jack tomorrow.", mode: .auto))
    }

    func testTypedCleanupRetainsMeaningWhenModelDropsDetails() async {
        let raw = "Um, I I will send invoice 120 for 42 euros. Meet at 2, actually 3 tomorrow."
        let floor = PolishPostpass.cleanupFloor(raw, language: nil)
        let result = await PolishPipeline.transform(preprocessed: floor,
            engine: OutputEngine(output: "Please meet at 3 tomorrow."), target: .english, mode: .auto)
        XCTAssertEqual(result.outcome, .rejectedGuardrail)
        XCTAssertEqual(PolishPipeline.resolvedOutput(result, preprocessed: floor,
            target: .english, mode: .auto), "I will send invoice 120 for 42 euros. Meet at 3 tomorrow.")
    }

    private struct OutputEngine: PolishEngineProtocol {
        let output: String
        var identifier: String { "test-output" }
        func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
            output
        }
    }

    func testChangedFactsAndTranslatedCJKFallBack() async {
        let cases = [
            ("Please send Peter 125.50 euros tomorrow", "Please send Peter 125.60 euros tomorrow."),
            ("Please do not send the invoice tomorrow", "Please do send the invoice tomorrow."),
            ("Ich schicke dir the invoice tomorrow und 我晚上再确认。",
             "Ich schicke dir the invoice tomorrow und I will confirm tonight."),
            ("Please send invoice AB-120 tomorrow", "Please send invoice AB-210 tomorrow."),
            ("Meet at 2am, oh sorry, it's 4am", "Meet at 5am.")
        ]
        for (raw, output) in cases {
            let result = await PolishPipeline.transform(preprocessed: raw,
                engine: OutputEngine(output: output), target: .english, mode: .auto)
            XCTAssertEqual(result.outcome, .rejectedGuardrail, raw)
            XCTAssertEqual(PolishPipeline.resolvedOutput(result, preprocessed: raw, target: .english, mode: .auto),
                           PolishPostpass.cleanupFloor(raw, language: nil))
        }
    }

    func testPunctuationAndCapitalizationKeepFacts() {
        XCTAssertTrue(PolishGuardrail.preservesFacts(
            raw: "send Peter 125.50 euros not 150 我确认",
            polished: "Send Peter 125.50 euros, not 150. 我确认。", mode: .auto))
        XCTAssertTrue(PolishGuardrail.preservesFacts(
            raw: "Please send invoice AB-120 tomorrow, 17.50 EUR, 3 kg",
            polished: "Please send invoice AB-120 tomorrow, 17.50 EUR, 3 kg.", mode: .auto))
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "Please send invoice AB-120 tomorrow, 17.50 EUR, 3 kg",
            polished: "Please send invoice AB-210 tomorrow, 17.50 EUR, 3 kg.", mode: .auto))
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "Please send Peter the invoice tomorrow",
            polished: "Please send Paul the invoice tomorrow.", mode: .auto))
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "Please send invoice AB-120 tomorrow",
            polished: "Please send invoice XY-120 tomorrow.", mode: .auto))
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "Meet Peter at 4am",
            polished: "Meet Peter at 4pm.", mode: .auto))
        XCTAssertTrue(PolishGuardrail.preservesFacts(
            raw: "Peter called about invoice AB-120",
            polished: "Peter called about invoice AB-120.", mode: .auto))
    }

    func testNumericSelfCorrectionKeepsTheCorrectedTime() {
        XCTAssertTrue(PolishGuardrail.preservesFacts(
            raw: "I got an appointment at 2am, oh sorry, it's 4am",
            polished: "I got an appointment at 4am.",
            mode: .auto))
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "Hey Jack I got like a appointment at 2am, oh sorry, it's 4am Um, yeah. So basically I got a poem at 4 a. m. Can you come by please?",
            polished: "Hey Jack I got an appointment at 4am. Can you come by please?",
            mode: .auto))
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "Meet at 2am, oh sorry, it's 4am",
            polished: "Meet at 5am.",
            mode: .auto),
                       "invented times must still fail")
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "I actually want 125.50 euros",
            polished: "I want the euros.",
            mode: .auto),
                       "a filler must not delete the only amount")
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "Sorry, send Peter and Jack the invoice",
            polished: "Send Jack the invoice.",
            mode: .auto),
                       "a greeting sorry must not drop a later name")
        XCTAssertTrue(PolishGuardrail.preservesFacts(
            raw: "Send Peter, oh sorry, Jack the invoice",
            polished: "Send Jack the invoice.",
            mode: .auto))
    }

    func testAutoAcceptsShortenedSpokenCleanup() {
        let raw = "Hey Jack I got like a appointment at 2am, oh sorry, it's 4am Um, yeah. So basically I got a poem at 4 a. m. Can you come by please?"
        let polished = "Hey Jack I got an appointment at 4am. Can you come by please?"
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .auto))
    }

    func testSameTimeInDistinctClausesIsNotATokenStutter() {
        XCTAssertFalse(PolishGuardrail.preservesFacts(
            raw: "I have a call at 2pm. I have a meeting at 2pm.",
            polished: "I have a call at 2pm.", mode: .auto))
        XCTAssertTrue(PolishGuardrail.preservesFacts(
            raw: "Pay 12 12 euros.", polished: "Pay 12 euros.", mode: .auto))
    }

    func testListsAndSelfCorrectionsKeepNumbersAndMarkers() {
        XCTAssertTrue(PolishGuardrail.preservesStructure(
            raw: "Do not send.\n1. Keep invoice 1042\n2. Keep 17.50 EUR",
            polished: "Do not send.\n1. Keep invoice 1042\n2. Keep 17.50 EUR.",
            mode: .auto))
        XCTAssertFalse(PolishGuardrail.preservesStructure(
            raw: "Do not send.\n1. Keep invoice 1042\n2. Keep 17.50 EUR",
            polished: "Do not send. Keep invoice 1042 and 17.50 EUR.",
            mode: .auto))
    }
}
