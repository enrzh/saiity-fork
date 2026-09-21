import XCTest
@testable import DictusCore

final class KeyboardLanguagePreferenceTests: XCTestCase {
    private func values() -> UserDefaults {
        let result = UserDefaults(suiteName: "dictus.plan.keyboard-language-tests")!
        result.removePersistentDomain(forName: "dictus.plan.keyboard-language-tests")
        return result
    }

    func testSystemLocalesMapOntoTypingLanguages() {
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "de-DE"), defaults: values()), .german)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "en-US"), defaults: values()), .english)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "es-ES"), defaults: values()), .spanish)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "fr-FR"), defaults: values()), .french)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "it-IT"), defaults: values()), .italian)
    }

    func testPersistedFrenchStaysFrench() {
        let defaults = values()
        KeyboardLanguageSelection.explicit(.french).persist(to: defaults)
        XCTAssertEqual(KeyboardLanguageSelection.resolve(locale: Locale(identifier: "en-US"), defaults: defaults), .french)
    }

    func testLegacyStoredFrenchBecomesExplicitFrench() {
        let defaults = values()
        defaults.set("fr", forKey: SharedKeys.language)
        defaults.set("auto", forKey: SharedKeys.transcriptionLanguage)
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        XCTAssertEqual(KeyboardLanguageSelection.load(from: defaults), .explicit(.french))
        XCTAssertEqual(defaults.string(forKey: SharedKeys.transcriptionLanguage), "auto")
    }

    func testExplicitFrenchMigrationIsIdempotent() {
        let defaults = values()
        KeyboardLanguageSelection.explicit(.french).persist(to: defaults)
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        XCTAssertEqual(KeyboardLanguageSelection.load(from: defaults), .explicit(.french))
    }

    func testMissingSelectionDefaultsToAutomatic() {
        XCTAssertEqual(KeyboardLanguageSelection.load(from: values()), .automatic)
    }

}
