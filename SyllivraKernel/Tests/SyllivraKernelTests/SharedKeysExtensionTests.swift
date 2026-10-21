// SyllivraKernel/Tests/SyllivraKernelTests/SharedKeysExtensionTests.swift
// Tests for SharedKeys extensions: language, interaction preferences, onboarding.
import XCTest
@testable import SyllivraKernel

final class SharedKeysExtensionTests: XCTestCase {

    func testLanguageKeyExists() {
        XCTAssertEqual(SharedKeys.language, "dictus.language")
    }

    func testHapticsEnabledKeyExists() {
        XCTAssertEqual(SharedKeys.hapticIntensity, "dictus.hapticIntensity")
    }

    func testHasCompletedOnboardingKeyExists() {
        XCTAssertEqual(SharedKeys.hasCompletedOnboarding, "dictus.hasCompletedOnboarding")
    }

    func testKeyboardAudioReadinessKeyExists() {
        XCTAssertEqual(SharedKeys.keyboardAudioReady, "dictus.keyboardAudioReady")
        XCTAssertEqual(SharedKeys.modelLoadFailure, "dictus.modelLoadFailure")
        XCTAssertEqual(SharedKeys.modelLoadFailureTimestamp, "dictus.modelLoadFailureTimestamp")
    }

    func testNewKeysAreUnique() {
        let newKeys = [
            SharedKeys.language,
            SharedKeys.hapticsEnabled,
            SharedKeys.hapticIntensity,
            SharedKeys.dictationPresenceMode,
            SharedKeys.recentDictations,
            SharedKeys.hasCompletedOnboarding,
            SharedKeys.keyboardAudioReady,
            SharedKeys.modelLoadFailure,
            SharedKeys.modelLoadFailureTimestamp,
        ]
        XCTAssertEqual(newKeys.count, Set(newKeys).count, "SharedKeys must be unique")
    }

    func testNewKeysHaveDictusPrefix() {
        XCTAssertTrue(SharedKeys.language.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.hapticsEnabled.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.hapticIntensity.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.dictationPresenceMode.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.recentDictations.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.hasCompletedOnboarding.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.keyboardAudioReady.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.modelLoadFailure.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.modelLoadFailureTimestamp.hasPrefix("dictus."))
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
