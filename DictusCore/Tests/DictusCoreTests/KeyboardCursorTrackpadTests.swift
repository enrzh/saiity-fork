import XCTest
@testable import DictusCore

final class KeyboardCursorTrackpadTests: XCTestCase {
    func testSingleLineDoesNotMoveVertically() {
        XCTAssertEqual(
            KeyboardCursorTrackpad.characterOffset(beforeInput: "hello", afterInput: " world", lines: -1),
            0
        )
        XCTAssertEqual(
            KeyboardCursorTrackpad.characterOffset(beforeInput: "hello", afterInput: " world", lines: 1),
            0
        )
    }

    func testUpKeepsColumnOnALongerLine() {
        // "hello\nwo|rld" → "he|llo\nworld"
        XCTAssertEqual(
            KeyboardCursorTrackpad.characterOffset(beforeInput: "hello\nwo", afterInput: "rld", lines: -1),
            -6
        )
    }

    func testUpClampsToTheEndOfAShorterLine() {
        // "hi\nwor|ld" → "hi|\nworld"
        XCTAssertEqual(
            KeyboardCursorTrackpad.characterOffset(beforeInput: "hi\nwor", afterInput: "ld", lines: -1),
            -4
        )
    }

    func testDownKeepsColumnOnALongerLine() {
        // "he|llo\nworld" → "hello\nwo|rld"
        XCTAssertEqual(
            KeyboardCursorTrackpad.characterOffset(beforeInput: "he", afterInput: "llo\nworld", lines: 1),
            6
        )
    }

    func testDownClampsToTheEndOfAShorterLine() {
        // "hell|o\nhi" → "hello\nhi|"
        XCTAssertEqual(
            KeyboardCursorTrackpad.characterOffset(beforeInput: "hell", afterInput: "o\nhi", lines: 1),
            4
        )
    }

    func testCarriageReturnNewlineIsOneBreak() {
        XCTAssertEqual(
            KeyboardCursorTrackpad.characterOffset(beforeInput: "ab\r\nc", afterInput: "d", lines: -1),
            -4
        )
    }

    func testZeroAndEmptyContext() {
        XCTAssertEqual(KeyboardCursorTrackpad.characterOffset(beforeInput: nil, afterInput: nil, lines: 1), 0)
        XCTAssertEqual(KeyboardCursorTrackpad.characterOffset(beforeInput: "a", afterInput: "b", lines: 0), 0)
    }

    func testSoftWrapLetsVerticalMoveCrossAParagraph() {
        var preferred: Int?
        // "abcdefghij" wrap 4 → rows abcd / efgh / ij. Caret after "abcd" is row 1.
        XCTAssertEqual(
            KeyboardCursorTrackpad.visualOffset(
                beforeInput: "abcd",
                afterInput: "efghij",
                columns: 0,
                rows: 1,
                wrap: 4,
                preferredColumn: &preferred
            ),
            4
        )
    }

    func testHorizontalMoveCrossesNewlinesInsteadOfStoppingAtTheCurrentLine() {
        var preferred: Int?
        // The host owns document boundaries; the nearby text is only a window.
        XCTAssertEqual(
            KeyboardCursorTrackpad.visualOffset(
                beforeInput: "",
                afterInput: "abc\ndef",
                columns: 20,
                rows: 0,
                wrap: 0,
                preferredColumn: &preferred
            ),
            20
        )
    }

    func testHorizontalTravelCrossesSoftWrapsAndRollingContextWindows() {
        let text = String(repeating: "abcdefghij", count: 30) as NSString
        var caret = 50
        var preferred: Int?
        for direction in [1, -1] {
            for _ in 0..<100 {
                let before = text.substring(with: NSRange(location: max(0, caret - 12), length: min(caret, 12)))
                let after = text.substring(with: NSRange(location: caret, length: min(12, text.length - caret)))
                let offset = KeyboardCursorTrackpad.visualOffset(beforeInput: before, afterInput: after,
                    columns: direction, rows: 0, wrap: 8, preferredColumn: &preferred)
                XCTAssertEqual(offset, direction)
                caret += offset
            }
        }
        XCTAssertEqual(caret, 50)
        XCTAssertNil(preferred, "Horizontal travel must not retain a column from an older context window")
    }

    func testHorizontalReversalDoesNotHaveToUndoTravelPastADocumentEdge() {
        var preferred: Int?
        XCTAssertEqual(KeyboardCursorTrackpad.visualOffset(beforeInput: "abc", afterInput: "",
            columns: 20, rows: 0, wrap: 0, preferredColumn: &preferred), 20)
        // The host clamps the forward request at its end. One left step must
        // move immediately, without paying back the previous overshoot.
        XCTAssertEqual(KeyboardCursorTrackpad.visualOffset(beforeInput: "abc", afterInput: "",
            columns: -1, rows: 0, wrap: 0, preferredColumn: &preferred), -1)
        XCTAssertEqual(KeyboardCursorTrackpad.visualOffset(beforeInput: nil, afterInput: nil,
            columns: -2, rows: 0, wrap: 40, preferredColumn: &preferred), -2)
    }

    func testPreferredColumnRestoresAfterAShortLine() {
        var preferred: Int?
        // "hello|\nxy\nworld" down onto "xy" clamps, then down onto "world" restores column 5.
        let first = KeyboardCursorTrackpad.visualOffset(
            beforeInput: "hello",
            afterInput: "\nxy\nworld",
            columns: 0,
            rows: 1,
            wrap: 0,
            preferredColumn: &preferred
        )
        XCTAssertEqual(first, 3)
        let second = KeyboardCursorTrackpad.visualOffset(
            beforeInput: "hello\nxy",
            afterInput: "\nworld",
            columns: 0,
            rows: 1,
            wrap: 0,
            preferredColumn: &preferred
        )
        XCTAssertEqual(second, 6)
    }

    func testDiagonalJumpIsOneCombinedOffset() {
        var preferred: Int?
        // "ab|c\ndefg" right 2 (clamp to end of abc) and down 1 → "defg" at column 3.
        XCTAssertEqual(
            KeyboardCursorTrackpad.visualOffset(
                beforeInput: "ab",
                afterInput: "c\ndefg",
                columns: 2,
                rows: 1,
                wrap: 0,
                preferredColumn: &preferred
            ),
            6
        )
    }
}
