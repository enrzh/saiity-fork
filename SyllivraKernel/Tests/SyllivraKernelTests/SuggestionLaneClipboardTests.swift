import XCTest
@testable import SyllivraKernel

final class SuggestionLaneClipboardTests: XCTestCase {
    func testEmptyClipboardProducesNoChip() {
        XCTAssertNil(SuggestionLaneClipboardItem.make(clipboardText: nil, isOneTimeCodeField: false))
        XCTAssertNil(SuggestionLaneClipboardItem.make(clipboardText: "  \n", isOneTimeCodeField: true))
    }

    func testOneTimeCodeFieldPromotesClipboardAsCode() {
        let item = SuggestionLaneClipboardItem.make(
            clipboardText: " 482 191 ",
            isOneTimeCodeField: true
        )
        XCTAssertEqual(item?.kind, .oneTimeCode)
        XCTAssertEqual(item?.title, "482 191")
        XCTAssertEqual(item?.subtitle, "Insert code")
        XCTAssertEqual(item?.insertValue, "482 191")
    }

    func testOrdinaryClipboardBecomesAPasteChip() {
        let item = SuggestionLaneClipboardItem.make(
            clipboardText: "Invoice 4412\nPaid",
            isOneTimeCodeField: false
        )
        XCTAssertEqual(item?.kind, .text)
        XCTAssertEqual(item?.title, "Invoice 4412 Paid")
        XCTAssertEqual(item?.subtitle, "Paste")
        XCTAssertEqual(item?.insertValue, "Invoice 4412\nPaid")
    }

    func testDigitGroupsBecomeACodeChipOutsideOneTimeCodeFields() {
        let item = SuggestionLaneClipboardItem.make(
            clipboardText: "12 34 56",
            isOneTimeCodeField: false
        )
        XCTAssertEqual(item?.kind, .oneTimeCode)
        XCTAssertEqual(item?.title, "12 34 56")
        XCTAssertTrue(item?.isOneTimeCode == true)
        XCTAssertEqual(item?.insertValue, "12 34 56")
    }

    func testResolvedTextPrefersPlainStringThenListThenURL() {
        XCTAssertEqual(
            SuggestionLaneClipboardItem.resolvedText(
                string: "  hello  ",
                strings: ["ignored"],
                urlString: "https://example.com"
            ),
            "  hello  "
        )
        XCTAssertEqual(
            SuggestionLaneClipboardItem.resolvedText(
                string: "   ",
                strings: ["", " second "],
                urlString: nil
            ),
            " second "
        )
        XCTAssertEqual(
            SuggestionLaneClipboardItem.resolvedText(
                string: nil,
                strings: nil,
                urlString: "https://example.com"
            ),
            "https://example.com"
        )
        XCTAssertNil(
            SuggestionLaneClipboardItem.resolvedText(string: "\n", strings: ["  "], urlString: "  ")
        )
    }

    func testLooksLikeOneTimeCodeAcceptsDigitGroups() {
        XCTAssertTrue(SuggestionLaneClipboardItem.looksLikeOneTimeCode("123456"))
        XCTAssertTrue(SuggestionLaneClipboardItem.looksLikeOneTimeCode("12 34 56"))
        XCTAssertFalse(SuggestionLaneClipboardItem.looksLikeOneTimeCode("12"))
        XCTAssertFalse(SuggestionLaneClipboardItem.looksLikeOneTimeCode("invoice"))
    }
}
