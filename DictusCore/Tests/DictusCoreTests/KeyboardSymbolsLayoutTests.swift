// DictusCore/Tests/DictusCoreTests/KeyboardSymbolsLayoutTests.swift
//
// The two symbols pages are three rows of content. A test for that sounds
// trivial until the page factory removed its last row on the assumption that
// every symbols page ended in a space/return rail — which deleted a row of
// punctuation and shipped the page two rows deep.

import XCTest
@testable import DictusCore

final class KeyboardSymbolsLayoutTests: XCTestCase {

    /// Both pages have three content rows, and none of them is a rail.
    ///
    /// The rail — ABC, emoji, space, return — belongs to the shared bottom bar
    /// now, so it is not in this data. If a row of bar-owned keys ever comes back
    /// here it has to be removed deliberately, not by dropping whichever row
    /// happens to be last.
    func testBothSymbolPagesAreThreeRowsOfContent() {
        for (name, page) in [("numbers", KeyboardSymbolsLayout.numbers),
                             ("symbols", KeyboardSymbolsLayout.symbols)] {
            XCTAssertEqual(page.count, 3, "\(name) page should have three rows")
            for (index, row) in page.enumerated() {
                XCTAssertFalse(row.isEmpty, "\(name) row \(index) is empty")
                for key in row {
                    switch key.kind {
                    case .space, .returnKey, .emoji, .voice:
                        XCTFail("\(name) row \(index) holds a bar-owned key; "
                                + "the bar owns those, so the page must not")
                    case .insert, .pageToggle, .delete, .spacer:
                        break
                    }
                }
            }
        }
    }

    /// The last row is the one the factory re-shapes: a page toggle, the
    /// punctuation keys, and delete. Losing it is what left the page two rows
    /// deep, so it is pinned here explicitly.
    func testTheLastRowIsTogglePunctuationAndDelete() {
        for (name, page) in [("numbers", KeyboardSymbolsLayout.numbers),
                             ("symbols", KeyboardSymbolsLayout.symbols)] {
            let last = page[2]
            XCTAssertEqual(last.first?.kind, .pageToggle, "\(name) row 2 starts with the toggle")
            XCTAssertEqual(last.last?.kind, .delete, "\(name) row 2 ends with delete")
            let punctuation = last.filter { $0.kind == .insert(".") || $0.kind == .insert(",") }
            XCTAssertEqual(punctuation.count, 2,
                           "\(name) row 2 should keep its period and comma")
        }
    }

    /// Ten keys across each of the first two rows, matching the system keyboard's
    /// 10 / 10 / 7 shape.
    func testTheFirstTwoRowsAreTenKeysWide() {
        for (name, page) in [("numbers", KeyboardSymbolsLayout.numbers),
                             ("symbols", KeyboardSymbolsLayout.symbols)] {
            XCTAssertEqual(page[0].count, 10, "\(name) row 0")
            XCTAssertEqual(page[1].count, 10, "\(name) row 1")
        }
    }
}
