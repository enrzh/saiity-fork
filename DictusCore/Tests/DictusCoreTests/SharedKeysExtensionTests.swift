// DictusCore/Tests/DictusCoreTests/SharedKeysExtensionTests.swift
// Tests for SharedKeys extensions: language, interaction preferences, onboarding.
import XCTest
@testable import DictusCore

final class SharedKeysExtensionTests: XCTestCase {

    func testLanguageKeyExists() {
        XCTAssertEqual(SharedKeys.language, "dictus.language")
    }

    func testHapticsEnabledKeyExists() {
        XCTAssertEqual(SharedKeys.hapticsEnabled, "dictus.hapticsEnabled")
    }

    func testKeyPopupsEnabledKeyExists() {
        XCTAssertEqual(SharedKeys.keyPopupsEnabled, "dictus.keyPopupsEnabled")
    }

    func testHasCompletedOnboardingKeyExists() {
        XCTAssertEqual(SharedKeys.hasCompletedOnboarding, "dictus.hasCompletedOnboarding")
    }

    func testNewKeysAreUnique() {
        let newKeys = [
            SharedKeys.language,
            SharedKeys.hapticsEnabled,
            SharedKeys.keyPopupsEnabled,
            SharedKeys.hasCompletedOnboarding,
        ]
        XCTAssertEqual(newKeys.count, Set(newKeys).count, "SharedKeys must be unique")
    }

    func testNewKeysHaveDictusPrefix() {
        XCTAssertTrue(SharedKeys.language.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.hapticsEnabled.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.keyPopupsEnabled.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.hasCompletedOnboarding.hasPrefix("dictus."))
    }

    func testKeyPopupsDefaultToEnabled() {
        let defaults = AppGroup.defaults
        let storedValue = defaults.object(forKey: SharedKeys.keyPopupsEnabled)
        defer {
            if let storedValue {
                defaults.set(storedValue, forKey: SharedKeys.keyPopupsEnabled)
            } else {
                defaults.removeObject(forKey: SharedKeys.keyPopupsEnabled)
            }
        }

        defaults.removeObject(forKey: SharedKeys.keyPopupsEnabled)
        XCTAssertTrue(KeyboardInteractionPreferences.keyPopupsEnabled)
    }

    func testMissingTranscriptionLanguageDefaultsToAutomaticDetection() {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)!
        defaults.removeObject(forKey: SharedKeys.transcriptionLanguage)
        XCTAssertEqual(
            TranscriptionLanguageMode(storedValue: defaults.string(forKey: SharedKeys.transcriptionLanguage)),
            .autoDetect
        )
    }
}
