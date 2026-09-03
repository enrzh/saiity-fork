import XCTest
@testable import DictusCore

final class SymbolKeyVariantsTests: XCTestCase {
    func testKeysWithoutNativeExtrasHaveNoPopup() {
        XCTAssertEqual(SymbolKeyVariants.options(for: "1"), [])
        XCTAssertEqual(SymbolKeyVariants.options(for: "4"), [])
        XCTAssertEqual(SymbolKeyVariants.options(for: ":"), [])
        XCTAssertEqual(SymbolKeyVariants.options(for: ";"), [])
    }

    func testNumberPageLongPressMatchesNativeExtras() {
        XCTAssertEqual(SymbolKeyVariants.options(for: "0").first, "0")
        XCTAssertTrue(SymbolKeyVariants.options(for: "0").contains("°"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "-").contains("–"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "-").contains("—"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "/").contains("\\"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "$").contains("€"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "&").contains("§"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "\"").contains("“"))
        XCTAssertTrue(SymbolKeyVariants.options(for: ".").contains("…"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "?").contains("¿"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "!").contains("¡"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "'").contains("’"))
    }

    func testSymbolsPageLongPressMatchesNativeExtras() {
        XCTAssertTrue(SymbolKeyVariants.options(for: "%").contains("‰"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "=").contains("≠"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "+").contains("±"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "<").contains("≤"))
        XCTAssertTrue(SymbolKeyVariants.options(for: ">").contains("≥"))
        XCTAssertTrue(SymbolKeyVariants.options(for: "€").contains("$"))
    }

    func testPopupKeepsTheBaseCharacterFirst() {
        let options = SymbolKeyVariants.options(for: "0")
        XCTAssertEqual(options.first, "0")
        XCTAssertGreaterThan(options.count, 1)
    }
}
