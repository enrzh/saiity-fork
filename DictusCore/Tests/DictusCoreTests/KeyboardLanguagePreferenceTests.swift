import XCTest
@testable import DictusCore

final class KeyboardLanguagePreferenceTests: XCTestCase {
    private func values() -> UserDefaults {
        let result = UserDefaults(suiteName: "dictus.plan.keyboard-language-tests")!
        result.removePersistentDomain(forName: "dictus.plan.keyboard-language-tests")
        return result
    }

    func testUnsupportedSystemLocalesFallbackToEnglish() {
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "de-DE"), defaults: values()), .german)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "en-US"), defaults: values()), .english)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "es-ES"), defaults: values()), .english)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "fr-FR"), defaults: values()), .english)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "it-IT"), defaults: values()), .english)
    }

    func testPersistedUnsupportedLanguageFallsBackToEnglish() {
        let defaults = values()
        KeyboardLanguageSelection.explicit(.french).persist(to: defaults)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "en-US"), defaults: defaults), .english)
    }

    func testImplicitLegacyFrenchBecomesAutomaticWithoutTouchingSTT() {
        let defaults = values()
        defaults.set("fr", forKey: SharedKeys.language)
        defaults.set("auto", forKey: SharedKeys.transcriptionLanguage)
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        XCTAssertEqual(KeyboardLanguageSelection.load(from: defaults), .automatic)
        XCTAssertEqual(defaults.string(forKey: SharedKeys.transcriptionLanguage), "auto")
    }

    func testExplicitFrenchMigrationFallsBackAndIsIdempotent() {
        let defaults = values()
        KeyboardLanguageSelection.explicit(.french).persist(to: defaults)
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        XCTAssertEqual(KeyboardLanguageSelection.load(from: defaults), .explicit(.english))
    }

    func testMissingSelectionDefaultsToAutomatic() {
        XCTAssertEqual(KeyboardLanguageSelection.load(from: values()), .automatic)
    }

}
