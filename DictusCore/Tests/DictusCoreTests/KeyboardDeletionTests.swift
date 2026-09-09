import XCTest
@testable import DictusCore

final class KeyboardDeletionTests: XCTestCase {
    func testHoldRepeatsCharactersBeforeAcceleratingToWords() {
        XCTAssertEqual(KeyboardDeletion.repeatDelay, 0.5)
        XCTAssertFalse(KeyboardDeletion.repeatsWords(after: 0))
        XCTAssertFalse(KeyboardDeletion.repeatsWords(after: 0.5))
        XCTAssertFalse(KeyboardDeletion.repeatsWords(after: 2.49))
        XCTAssertTrue(KeyboardDeletion.repeatsWords(after: 2.5))
        XCTAssertTrue(KeyboardDeletion.repeatsWords(after: 10))
    }
    func testDeletesWordAndTrailingSeparator() {
        XCTAssertEqual(KeyboardDeletion.previousWordLength(in: "hello world"), 6)
        XCTAssertEqual(KeyboardDeletion.previousWordLength(in: "hello world "), 6)
    }

    func testDeletesPunctuationAttachedToThePreviousToken() {
        XCTAssertEqual(KeyboardDeletion.previousWordLength(in: "send it now!"), 5)
    }

    func testDeletesAllWhitespaceBeforeThePreviousWord() {
        XCTAssertEqual(KeyboardDeletion.previousWordLength(in: "hello\n\tworld  "), 7)
    }

    func testCountsUnicodeGraphemeClusters() {
        XCTAssertEqual(KeyboardDeletion.previousWordLength(in: "café "), 5)
        XCTAssertEqual(KeyboardDeletion.previousWordLength(in: "Привет мир"), 4)
    }

    func testEmptyOrNilContextIsSafe() {
        XCTAssertEqual(KeyboardDeletion.previousWordLength(in: nil), 0)
        XCTAssertEqual(KeyboardDeletion.previousWordLength(in: ""), 0)
    }
}
