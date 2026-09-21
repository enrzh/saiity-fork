import XCTest
@testable import DictusCore

final class PredictionLanguageSafetyTests: XCTestCase {
    func testShortContextUsesNormalKeyboardFallback() {
        XCTAssertFalse(PredictionLanguageSafety.shouldAbstain(for: "你好"))
    }

    func testLongLatinContextIsEligibleForLocalPrediction() {
        XCTAssertFalse(PredictionLanguageSafety.shouldAbstain(
            for: "This is a normal English sentence with enough words."
        ))
    }

    func testMixedLatinAndCJKContextAbstains() {
        XCTAssertTrue(PredictionLanguageSafety.shouldAbstain(
            for: "Please send die Rechnung 我晚上再确认 tomorrow."
        ))
    }

    func testUnsupportedCyrillicContextAbstains() {
        XCTAssertTrue(PredictionLanguageSafety.shouldAbstain(
            for: "Это длинный русский текст для проверки модели."
        ))
    }
}
