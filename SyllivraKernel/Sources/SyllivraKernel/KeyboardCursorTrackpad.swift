import CoreGraphics
import Foundation

/// One trackpad sample: character steps on X, line steps on Y.
public struct KeyboardCursorStep: Equatable, Sendable {
    public var characters: Int
    public var lines: Int

    public init(characters: Int = 0, lines: Int = 0) {
        self.characters = characters
        self.lines = lines
    }

    public var isEmpty: Bool { characters == 0 && lines == 0 }
}

/// Maps a 2D spacebar drag onto `adjustTextPosition` offsets.
///
/// Native trackpad movement is a pointer in the text view: the caret jumps to
/// the closest layout position instead of walking the UTF-16 string. Custom
/// keyboards only get `documentContextBeforeInput` / `AfterInput`, so this
/// rebuilds hard newlines and optional soft wraps and snaps to that grid.
/// ponytail: proxy context is a window, not the whole document.
public enum KeyboardCursorTrackpad {
    public static let pointsPerCharacter: CGFloat = 8
    public static let pointsPerLine: CGFloat = 20

    public static func characterOffset(
        beforeInput: String?,
        afterInput: String?,
        lines: Int
    ) -> Int {
        var preferredColumn: Int?
        return visualOffset(
            beforeInput: beforeInput,
            afterInput: afterInput,
            columns: 0,
            rows: lines,
            wrap: 0,
            preferredColumn: &preferredColumn
        )
    }

    /// Horizontal travel goes directly to the host, which owns document bounds.
    /// Vertical/diagonal travel uses nearby visual rows (soft wraps when `wrap`
    /// is positive). `preferredColumn` preserves X across shorter vertical rows.
    public static func visualOffset(
        beforeInput: String?,
        afterInput: String?,
        columns: Int,
        rows: Int,
        wrap: Int,
        preferredColumn: inout Int?
    ) -> Int {
        guard columns != 0 || rows != 0 else { return 0 }
        if rows == 0 {
            // Proxy context can end at a newline or a cached window even when
            // the document continues. Never use it to bound horizontal travel.
            preferredColumn = nil
            return columns
        }
        let before = (beforeInput ?? "") as NSString
        let after = (afterInput ?? "") as NSString
        let text = ((before as String) + (after as String)) as NSString
        let caret = max(0, min(before.length, text.length))
        let layout = visualRows(in: text, wrap: wrap)
        let (rowIndex, column) = locate(caret: caret, in: layout)
        if preferredColumn == nil {
            preferredColumn = column
        }
        if columns != 0 {
            preferredColumn = (preferredColumn ?? column) + columns
        }
        let targetRow = min(layout.count - 1, max(0, rowIndex + rows))
        let row = layout[targetRow]
        let targetColumn = min(row.length, max(0, preferredColumn ?? column))
        return (row.location + targetColumn) - caret
    }

    private struct VisualRow: Equatable {
        var location: Int
        var length: Int
    }

    private static let newlines = CharacterSet.newlines

    private static func visualRows(in text: NSString, wrap: Int) -> [VisualRow] {
        let length = text.length
        let wrapLimit = wrap > 0 ? wrap : Int.max
        var rows: [VisualRow] = []
        var index = 0
        while index < length {
            if isNewline(in: text, at: index) {
                rows.append(VisualRow(location: index, length: 0))
                index = skipNewline(in: text, at: index)
                continue
            }
            let start = index
            while index < length, !isNewline(in: text, at: index) {
                let advance = utf16Advance(in: text, at: index)
                if wrapLimit != Int.max, index > start, (index - start) + advance > wrapLimit {
                    break
                }
                index += advance
            }
            rows.append(VisualRow(location: start, length: index - start))
            if index < length, isNewline(in: text, at: index) {
                index = skipNewline(in: text, at: index)
            }
        }
        if length == 0 || endsWithNewline(text) {
            rows.append(VisualRow(location: length, length: 0))
        }
        if rows.isEmpty {
            rows.append(VisualRow(location: 0, length: 0))
        }
        return rows
    }

    private static func locate(caret: Int, in rows: [VisualRow]) -> (Int, Int) {
        for index in rows.indices {
            let row = rows[index]
            let start = row.location
            let end = start + row.length
            let nextStart = index + 1 < rows.count ? rows[index + 1].location : Int.max
            if caret < start {
                return (index, 0)
            }
            if caret < end {
                return (index, caret - start)
            }
            if caret == end {
                if nextStart == caret {
                    continue
                }
                return (index, row.length)
            }
        }
        let last = rows.count - 1
        return (last, rows[last].length)
    }

    private static func isNewline(in text: NSString, at index: Int) -> Bool {
        skipNewline(in: text, at: index) != index
    }

    private static func endsWithNewline(_ text: NSString) -> Bool {
        guard text.length > 0 else { return false }
        return isNewline(in: text, at: newlineLocation(endingAt: text.length, in: text))
    }

    private static func utf16Advance(in text: NSString, at index: Int) -> Int {
        guard index < text.length else { return 0 }
        let unit = text.character(at: index)
        if UTF16.isLeadSurrogate(unit),
           index + 1 < text.length,
           UTF16.isTrailSurrogate(text.character(at: index + 1)) {
            return 2
        }
        return 1
    }

    private static func skipNewline(in text: NSString, at index: Int) -> Int {
        guard index < text.length else { return index }
        let unit = text.character(at: index)
        if unit == 13, index + 1 < text.length, text.character(at: index + 1) == 10 {
            return index + 2
        }
        if let scalar = UnicodeScalar(unit), newlines.contains(scalar) {
            return index + 1
        }
        return index
    }

    /// First UTF-16 index of the newline sequence that ends immediately before `endExclusive`.
    private static func newlineLocation(endingAt endExclusive: Int, in text: NSString) -> Int {
        guard endExclusive > 0 else { return 0 }
        let last = endExclusive - 1
        if last > 0, text.character(at: last) == 10, text.character(at: last - 1) == 13 {
            return last - 1
        }
        return last
    }
}
