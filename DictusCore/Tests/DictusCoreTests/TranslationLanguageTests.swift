import Foundation
import XCTest
@testable import DictusCore

final class TranslationLanguageTests: XCTestCase {
    func testBaseChineseDoesNotSatisfyAnExplicitSimplifiedOutput() {
        let traditional = "我們今天需要檢查這張發票並討論會議安排。"
        XCTAssertFalse(TranslationLanguage.chineseSimplified.alreadyContains(traditional, sourceHint: "zh-Hant"))
        XCTAssertFalse(TranslationLanguage.chineseSimplified.satisfiesOutputScript(traditional))
        let simplified = "我们今天需要检查这张发票并讨论会议安排。"
        XCTAssertTrue(TranslationLanguage.chineseSimplified.alreadyContains(simplified, sourceHint: "zh-Hans"))
        XCTAssertFalse(TranslationLanguage.chineseSimplified.alreadyContains("字幕", sourceHint: "zh"))
        XCTAssertFalse(TranslationLanguage.english.alreadyContains("Please send the invoice 明日の予定を確認します", sourceHint: "en"))
    }
    func testAllCasesAreTheOrderedTopTenTargetSet() {
        XCTAssertEqual(
            TranslationLanguage.allCases,
            [.english, .chineseSimplified, .hindi, .spanish, .arabic,
             .french, .bengali, .portuguese, .russian, .indonesian, .urdu, .german]
        )
    }

    func testCodesAreStableAndMatchTranslationIdentifiers() {
        XCTAssertEqual(TranslationLanguage.allCases.map(\.code),
                       ["en", "zh-Hans", "hi", "es", "ar", "fr", "bn", "pt", "ru", "id", "ur", "de"])
        XCTAssertEqual(TranslationLanguage.allCases.map(\.translationIdentifier),
                       TranslationLanguage.allCases.map(\.code))
    }

    func testDisplayNamesAreStableAndDistinct() {
        let names = TranslationLanguage.allCases.map(\.displayName)
        XCTAssertEqual(names, ["English", "Chinese (Simplified)", "Hindi", "Spanish", "Arabic",
                               "French", "Bengali", "Portuguese", "Russian", "Indonesian", "Urdu", "Deutsch"])
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testFoundationLanguageIdentifiersRoundTrip() {
        for language in TranslationLanguage.allCases {
            XCTAssertEqual(language.localeLanguage, Locale.Language(identifier: language.translationIdentifier))
        }
    }

    func testCodableRoundTripUsesStableCode() throws {
        for language in TranslationLanguage.allCases {
            let data = try JSONEncoder().encode(language)
            XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(language.code)\"")
            XCTAssertEqual(try JSONDecoder().decode(TranslationLanguage.self, from: data), language)
        }
    }

    func testRegistryIsIndependentFromKeyboardLanguages() {
        let translationCodes = Set(TranslationLanguage.allCases.map(\.code))
        let keyboardCodes = Set(SupportedLanguage.allCases.map(\.rawValue))
        XCTAssertNotEqual(translationCodes, keyboardCodes)
        XCTAssertFalse(translationCodes.isSubset(of: keyboardCodes))
        XCTAssertFalse(keyboardCodes.isSubset(of: translationCodes))
        XCTAssertEqual(TranslationLanguage.chineseSimplified.code, "zh-Hans")
    }
}
