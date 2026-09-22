import XCTest
@testable import DictusCore

final class TypingFactTests: XCTestCase {
    func testAmountsCodesAndClockTimesStayUntouched() {
        for token in ["125.50", "1,250.00", "16:30", "4am", "4PM", "AB-120", "120-AB"] {
            XCTAssertTrue(TypingFact.shouldLeaveUntouched(token), token)
        }
        XCTAssertFalse(TypingFact.shouldLeaveUntouched("Peter"))
        XCTAssertFalse(TypingFact.shouldLeaveUntouched("invoice"))
    }

    func testAnUnfinishedCodeOrNumberHasNoLetterPrior() {
        XCTAssertTrue(TypingFact.isOpenPrefix("AB-"))
        XCTAssertTrue(TypingFact.isOpenPrefix("12"))
        XCTAssertTrue(TypingFact.isOpenPrefix("125."))
        XCTAssertFalse(TypingFact.isOpenPrefix("Pe"))
        XCTAssertFalse(TypingFact.isOpenPrefix("inv"))
    }

    func testContextSkipsTheFactAndKeepsTheWordBeforeIt() {
        XCTAssertEqual(
            TypingFact.contextWords(from: ["invoice", "AB-120", "125.50"]),
            ["invoice"]
        )
        XCTAssertEqual(TypingFact.contextWords(from: ["AB-120"]), [])
    }

    func testRecallPullsTheNextLetterOfAKnownName() {
        let weights = TypingFact.recallWeights(prefix: "Pe", tokens: ["Peter", "Petra"])
        XCTAssertEqual(weights["t"], 72)
        XCTAssertNil(weights["o"])
        XCTAssertTrue(TypingFact.recallWeights(prefix: "12", tokens: ["125.50"]).isEmpty)
    }

    func testNamesAreAnchoredAndSentenceOpenersAreNot() {
        XCTAssertEqual(TypingFact.anchoredNames(in: "Please send Peter the invoice"), ["Peter"])
        XCTAssertEqual(TypingFact.anchoredNames(in: "Hey Jack, meet SNCF tomorrow"), ["Jack", "SNCF"])
        XCTAssertNil(TypingFact.openingName(in: "Please send Peter"))
        XCTAssertEqual(TypingFact.openingName(in: "Peter called"), "Peter")
    }

    func testClockTimesAndCodesCompareInReadingOrder() {
        XCTAssertEqual(
            TypingFact.atomicFacts(in: "Meet at 4 a.m., then 4pm, invoice AB-120"),
            ["4am", "4pm", "ab-120"]
        )
        XCTAssertEqual(
            TypingFact.atomicFacts(in: "Meet at 4am"),
            TypingFact.atomicFacts(in: "Meet at 4 a. m.")
        )
    }

    func testACorrectedFactMayDropTheSupersededTokenOnly() {
        XCTAssertFalse(TypingFact.keepsFacts(["4am"], from: ["2am", "4am"]))
        XCTAssertFalse(TypingFact.keepsFacts(["5am"], from: ["2am", "4am"]))
        XCTAssertFalse(TypingFact.keepsFacts([], from: ["Peter"]))
        XCTAssertTrue(TypingFact.keepsFacts(["ab-120"], from: ["ab-120", "ab-120"]))
        let corrected = "Meet at 2am, oh sorry, it's 4am"
        let marker = TypingFact.lastCorrectionMarkerOffset(in: corrected)
        XCTAssertTrue(TypingFact.preservesSpokenFacts(
            polishedTokens: ["4am"],
            rawFacts: TypingFact.atomicFactSpans(in: corrected),
            correctionMarkerUTF16: marker))
        XCTAssertFalse(TypingFact.preservesSpokenFacts(
            polishedTokens: ["5am"],
            rawFacts: TypingFact.atomicFactSpans(in: corrected),
            correctionMarkerUTF16: marker))
        let polite = "I actually want 125.50"
        XCTAssertFalse(TypingFact.preservesSpokenFacts(
            polishedTokens: [],
            rawFacts: [TypingFact.SpokenFact(token: "125.50", utf16Offset: 16)],
            correctionMarkerUTF16: TypingFact.lastCorrectionMarkerOffset(in: polite)))
        XCTAssertFalse(TypingFact.preservesSpokenFacts(
            polishedTokens: ["Jack"],
            rawFacts: TypingFact.nameSpans(in: "Sorry, send Peter and Jack"),
            correctionMarkerUTF16: TypingFact.lastCorrectionMarkerOffset(in: "Sorry, send Peter and Jack")))
    }
}
