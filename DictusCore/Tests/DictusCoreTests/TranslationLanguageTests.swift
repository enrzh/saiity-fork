import Foundation
import XCTest
@testable import DictusCore

final class TranslationLanguageTests: XCTestCase {
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
