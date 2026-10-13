import XCTest
@testable import SyllivraKernel

final class KeyboardNumberPadLayoutTests: XCTestCase {
    func testEveryStyleIsAThreeByFourPad() {
        for style in [HostFieldPolicy.NumberPadStyle.digits, .decimal, .phone] {
            let rows = KeyboardNumberPadLayout.rows(for: style)
            XCTAssertEqual(rows.count, 4, "\(style)")
            XCTAssertTrue(rows.allSatisfy { $0.count == 3 }, "\(style)")
        }
    }

    func testDigitPadMatchesNativeNumberPad() {
        let rows = KeyboardNumberPadLayout.rows(for: .digits)
        XCTAssertEqual(inserts(in: rows[0]), ["1", "2", "3"])
        XCTAssertEqual(inserts(in: rows[1]), ["4", "5", "6"])
        XCTAssertEqual(inserts(in: rows[2]), ["7", "8", "9"])
        XCTAssertEqual(rows[3][0].kind, .letters)
        XCTAssertEqual(inserts(in: [rows[3][1]]), ["0"])
        XCTAssertEqual(rows[3][2].kind, .delete)
    }

    func testDecimalPadUsesTheProvidedSeparator() {
        let rows = KeyboardNumberPadLayout.rows(for: .decimal, decimalSeparator: ",")
        XCTAssertEqual(inserts(in: rows[3]), [",", "0"])
        XCTAssertEqual(rows[3][2].kind, .delete)
        XCTAssertEqual(rows[3][0].kind, .insert(",", holdLetters: true))
    }

    func testDecimalPadPutsTheDotOnTheBottomLeft() {
        let rows = KeyboardNumberPadLayout.rows(for: .decimal)
        XCTAssertEqual(inserts(in: rows[3]), [".", "0"])
        XCTAssertEqual(rows[3][2].kind, .delete)
        XCTAssertEqual(rows[3][0].kind, .insert(".", holdLetters: true))
    }

    func testPhonePadKeepsStarAndZeroWithDelete() {
        let rows = KeyboardNumberPadLayout.rows(for: .phone)
        XCTAssertEqual(inserts(in: rows[3]), ["*", "0"])
        XCTAssertEqual(rows[3][2].kind, .delete)
        XCTAssertEqual(rows[3][0].kind, .insert("*", holdLetters: true))
    }

    private func inserts(in row: [KeyboardNumberPadLayout.Key]) -> [String] {
        row.compactMap {
            if case .insert(let value, _) = $0.kind { return value }
            return nil
        }
    }
}
