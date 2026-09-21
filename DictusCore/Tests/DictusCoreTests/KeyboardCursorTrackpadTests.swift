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

    func testHorizontalMoveStaysOnTheVisualLineInsteadOfWalkingNewlines() {
        var preferred: Int?
        // "|abc\ndef" dragging far right clamps to "abc|" rather than entering the next line.
        XCTAssertEqual(
            KeyboardCursorTrackpad.visualOffset(
                beforeInput: "",
                afterInput: "abc\ndef",
                columns: 20,
                rows: 0,
                wrap: 0,
                preferredColumn: &preferred
            ),
            3
        )
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
