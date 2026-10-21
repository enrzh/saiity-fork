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

    func testKeyPopupsEnabledKeyExists() {
        XCTAssertEqual(SharedKeys.keyPopupsEnabled, "dictus.keyPopupsEnabled")
        XCTAssertEqual(SharedKeys.keyPopupMode, "dictus.keyPopupMode")
        XCTAssertEqual(SharedKeys.liquidGlassEnabled, "dictus.liquidGlassEnabled")
        XCTAssertEqual(SharedKeys.keyContainersEnabled, "dictus.keyContainersEnabled")
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
            SharedKeys.keyPopupsEnabled,
            SharedKeys.keyPopupMode,
            SharedKeys.liquidGlassEnabled,
            SharedKeys.keyContainersEnabled,
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
        XCTAssertTrue(SharedKeys.keyPopupsEnabled.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.keyPopupMode.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.liquidGlassEnabled.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.keyContainersEnabled.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.dictationPresenceMode.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.recentDictations.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.hasCompletedOnboarding.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.keyboardAudioReady.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.modelLoadFailure.hasPrefix("dictus."))
        XCTAssertTrue(SharedKeys.modelLoadFailureTimestamp.hasPrefix("dictus."))
    }

    func testKeyPopupsDefaultToEnabled() {
        let defaults = AppGroup.defaults
        let storedEnabled = defaults.object(forKey: SharedKeys.keyPopupsEnabled)
        let storedMode = defaults.object(forKey: SharedKeys.keyPopupMode)
        defer {
            if let storedEnabled {
                defaults.set(storedEnabled, forKey: SharedKeys.keyPopupsEnabled)
            } else {
                defaults.removeObject(forKey: SharedKeys.keyPopupsEnabled)
            }
            if let storedMode {
                defaults.set(storedMode, forKey: SharedKeys.keyPopupMode)
            } else {
                defaults.removeObject(forKey: SharedKeys.keyPopupMode)
            }
        }

        defaults.removeObject(forKey: SharedKeys.keyPopupsEnabled)
        defaults.removeObject(forKey: SharedKeys.keyPopupMode)
        XCTAssertTrue(KeyboardInteractionPreferences.keyPopupsEnabled)
        XCTAssertEqual(KeyPopupMode.active, .popup)
    }

    func testLiquidGlassDefaultsToEnabled() {
        let defaults = AppGroup.defaults
        let storedValue = defaults.object(forKey: SharedKeys.liquidGlassEnabled)
        defer {
            if let storedValue {
                defaults.set(storedValue, forKey: SharedKeys.liquidGlassEnabled)
            } else {
                defaults.removeObject(forKey: SharedKeys.liquidGlassEnabled)
            }
        }

        defaults.removeObject(forKey: SharedKeys.liquidGlassEnabled)
        XCTAssertTrue(KeyboardInteractionPreferences.liquidGlassEnabled)
    }

    func testKeyContainersDefaultToEnabled() {
        let defaults = AppGroup.defaults
        let storedValue = defaults.object(forKey: SharedKeys.keyContainersEnabled)
        defer {
            if let storedValue {
                defaults.set(storedValue, forKey: SharedKeys.keyContainersEnabled)
            } else {
                defaults.removeObject(forKey: SharedKeys.keyContainersEnabled)
            }
        }

        defaults.removeObject(forKey: SharedKeys.keyContainersEnabled)
        // On by default: the platform draws a plate on every key, and a keyboard
        // of bare glyphs floating on the panel is the most obvious way this one
        // stops looking like the system keyboard.
        XCTAssertTrue(KeyboardInteractionPreferences.keyContainersEnabled)
        defaults.set(false, forKey: SharedKeys.keyContainersEnabled)
        XCTAssertFalse(KeyboardInteractionPreferences.keyContainersEnabled)
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
