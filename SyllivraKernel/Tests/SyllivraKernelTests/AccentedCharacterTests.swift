// SyllivraKernel/Tests/SyllivraKernelTests/AccentedCharacterTests.swift
import XCTest
@testable import SyllivraKernel

final class AccentedCharacterTests: XCTestCase {

    func testEMapsToMultilingualAccentedVariants() {
        let accents = AccentedCharacters.accents(for: "e")
        XCTAssertEqual(accents, ["\u{00E8}", "\u{00E9}", "\u{00EA}", "\u{00EB}", "\u{0113}", "\u{0117}", "\u{0119}"])
    }

    func testAMapsToMultilingualAccentedVariants() {
        let accents = AccentedCharacters.accents(for: "a")
        XCTAssertEqual(accents, ["\u{00E0}", "\u{00E1}", "\u{00E2}", "\u{00E4}", "\u{00E3}", "\u{00E5}", "\u{0101}", "\u{00E6}"])
    }

    func testCMapsToCedillaAndSlavicVariants() {
        let accents = AccentedCharacters.accents(for: "c")
        XCTAssertEqual(accents, ["\u{00E7}", "\u{0107}", "\u{010D}"])
    }

    func testZMapsToSlavicVariants() {
        let accents = AccentedCharacters.accents(for: "z")
        XCTAssertEqual(accents, ["\u{017A}", "\u{017C}", "\u{017E}"])
    }

    func testLookupIsCaseInsensitive() {
        let lowercaseResult = AccentedCharacters.accents(for: "e")
        let uppercaseResult = AccentedCharacters.accents(for: "E")
        XCTAssertEqual(lowercaseResult, uppercaseResult)
    }

    func testUMapsToMultilingualVariants() {
        let accents = AccentedCharacters.accents(for: "u")
        XCTAssertEqual(accents, ["\u{00F9}", "\u{00FA}", "\u{00FB}", "\u{00FC}", "\u{016B}"])
    }

    func testIMapsToMultilingualVariants() {
        let accents = AccentedCharacters.accents(for: "i")
        XCTAssertEqual(accents, ["\u{00EC}", "\u{00ED}", "\u{00EE}", "\u{00EF}", "\u{012B}"])
    }

    func testOMapsToMultilingualVariants() {
        let accents = AccentedCharacters.accents(for: "o")
        XCTAssertEqual(accents, ["\u{00F2}", "\u{00F3}", "\u{00F4}", "\u{00F6}", "\u{00F5}", "\u{00F8}", "\u{014D}", "\u{0153}"])
    }

    func testYMapsToAcuteAndDiaeresis() {
        let accents = AccentedCharacters.accents(for: "y")
        XCTAssertEqual(accents, ["\u{00FD}", "\u{00FF}"])
    }

    func testNMapsToTildeAndAcute() {
        let accents = AccentedCharacters.accents(for: "n")
        XCTAssertEqual(accents, ["\u{00F1}", "\u{0144}"])
    }

    func testSMapsToEszettAndSlavicVariants() {
        let accents = AccentedCharacters.accents(for: "s")
        XCTAssertEqual(accents, ["\u{00DF}", "\u{015B}", "\u{0161}"])
    }
}
