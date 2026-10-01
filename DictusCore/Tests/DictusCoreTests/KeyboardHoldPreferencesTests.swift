import XCTest
@testable import DictusCore

final class KeyboardHoldPreferencesTests: XCTestCase {
    func testDefaultTonePersistsAndDisabledAlternatesAreRespected() {
        let defaults = AppGroup.defaults
        let keys = [SharedKeys.defaultEmojiSkinTone, SharedKeys.disabledKeyVariants]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            KeyboardVariantPreferences.reload()
        }
        defaults.removeObject(forKey: SharedKeys.disabledKeyVariants)
        KeyboardVariantPreferences.reload()
        KeyboardVariantPreferences.setToneEnabled(false, tone: "🏽")
        KeyboardVariantPreferences.setDefaultSkinTone("🏽")
        XCTAssertEqual(defaults.string(forKey: SharedKeys.defaultEmojiSkinTone), "🏽")
        XCTAssertTrue(KeyboardVariantPreferences.isToneEnabled("🏽"))
        XCTAssertEqual(KeyboardVariantPreferences.preferredEmoji("👍"), "👍🏽")
        KeyboardVariantPreferences.setEnabled(false, option: "👍🏽", key: "👍", kind: .emoji)
        XCTAssertEqual(KeyboardVariantPreferences.preferredEmoji("👍"), "👍")
        KeyboardVariantPreferences.setDefaultSkinTone("invalid")
        XCTAssertEqual(KeyboardVariantPreferences.defaultSkinTone, "🏽")
        KeyboardVariantPreferences.setToneEnabled(false, tone: "🏽")
        XCTAssertEqual(KeyboardVariantPreferences.defaultSkinTone, "")
    }

    func testDefaultSkinToneAppliesOnlyToOrdinaryUntonedEmoji() {
        for (index, tone) in EmojiSkinToneVariants.modifiers.enumerated() {
            XCTAssertEqual(KeyboardVariantPreferences.preferredEmoji("👍", tone: tone),
                           EmojiSkinToneVariants.options(for: "👍")[index + 1])
            XCTAssertEqual(KeyboardVariantPreferences.preferredEmoji("👍🏿", tone: tone), "👍🏿")
            XCTAssertEqual(KeyboardVariantPreferences.preferredEmoji("👩‍⚕️", tone: tone), "👩‍⚕️")
            XCTAssertEqual(KeyboardVariantPreferences.preferredEmoji("🐈", tone: tone), "🐈")
        }
        XCTAssertEqual(KeyboardVariantPreferences.preferredEmoji("👍", tone: "invalid"), "👍")
        XCTAssertEqual(KeyboardVariantPreferences.preferredEmoji("👍", tone: ""), "👍")
    }
    func testSpeedsKeepDefaultAndOrderTheRecognitionDelays() {
        XCTAssertEqual(KeyboardHoldSpeed.allCases.map(\.displayName), ["Slow", "Default", "Fast", "Snappy"])
        XCTAssertEqual(KeyboardHoldSpeed.allCases.map(\.duration), [0.55, 0.35, 0.25, 0.15])
        XCTAssertEqual(KeyboardHoldSpeed.default.scaled(0.3), 0.3, accuracy: 0.0001)
    }
    func testRemovingAlternatesNeverRemovesTheBaseOrReordersRemainingOptions() {
        let options = KeyboardVariantPreferences.allOptions(for: "e", kind: .letter)
        let filtered = KeyboardVariantPreferences.filter(options, key: "e", kind: .letter,
            disabled: ["letter:e": ["e", "é", "è"]])
        XCTAssertEqual(filtered.first, "e")
        XCTAssertFalse(filtered.contains("é"))
        XCTAssertEqual(filtered, options.filter { !["é", "è"].contains($0) })
        XCTAssertEqual(KeyboardVariantPreferences.filter([".", "?", "!"], key: ".", kind: .symbol,
            disabled: ["symbol:.": ["?", "!"]]), ["."])
    }
    func testSkinTonePreferencesShareOneBaseEmojiIdentity() {
        let options = KeyboardVariantPreferences.allOptions(for: "👍🏽", kind: .emoji)
        let filtered = KeyboardVariantPreferences.filter(options, key: "👍🏽", kind: .emoji,
            disabled: ["emoji:👍": ["👍🏽"]])
        XCTAssertEqual(filtered.first, "👍")
        XCTAssertFalse(filtered.contains("👍🏽"))
    }
    func testChangingAnAlternateInvalidatesTheCachedPageEvenWhenBothHavePopups() {
        let before = KeyGridPage(id: "letters", rows: [[KeyGridKey(id: "e", action: .character(base: "e", variants: ["e", "é", "è"]))]])
        let after = KeyGridPage(id: "letters", rows: [[KeyGridKey(id: "e", action: .character(base: "e", variants: ["e", "é"]))]])
        XCTAssertNotEqual(before.fingerprint, after.fingerprint)
    }
    func testGlobalSkinTonesKeepBaseAndLeaveJoinedCombinationsAlone() {
        let mask = ["emoji:tones": EmojiSkinToneVariants.modifiers]
        XCTAssertEqual(KeyboardVariantPreferences.filter(EmojiSkinToneVariants.options(for: "👍"), key: "👍",
            kind: .emoji, disabled: mask), ["👍"])
        let joined = "👩‍⚕️"
        XCTAssertEqual(KeyboardVariantPreferences.filter(EmojiSkinToneVariants.options(for: joined), key: joined,
            kind: .emoji, disabled: mask), EmojiSkinToneVariants.options(for: joined))
    }

    func testModelProfilesUseInstalledCompatibleModelsAndRespectMemoryPressure() {
        let modern = DeviceCapabilities(physicalMemoryGB: 12, availableMemoryMB: 4000,
                                       deviceModelIdentifier: "iPhone19,2", thermalState: .nominal)
        let installed: Set<String> = ["openai_whisper-tiny", "openai_whisper-small", "openai_whisper-medium", "openai_whisper-large-v3_947MB"]
        XCTAssertEqual(ModelSelectionProfile.balanced.resolvedIdentifier(installed: installed, osMajor: 27, capabilities: modern), "openai_whisper-small")
        XCTAssertEqual(ModelSelectionProfile.recommended.resolvedIdentifier(installed: installed, osMajor: 27, capabilities: modern), "openai_whisper-medium")
        XCTAssertEqual(ModelSelectionProfile.precise.resolvedIdentifier(installed: installed, osMajor: 27, capabilities: modern), "openai_whisper-large-v3_947MB")
        XCTAssertNil(ModelSelectionProfile.precise.resolvedIdentifier(installed: [], osMajor: 27, capabilities: modern))
        let old = DeviceCapabilities(physicalMemoryGB: 4, availableMemoryMB: 700, deviceModelIdentifier: "iPhone12,1", thermalState: .nominal)
        XCTAssertEqual(ModelSelectionProfile.precise.preferredIdentifier(for: old), "openai_whisper-base")
        let hot = DeviceCapabilities(physicalMemoryGB: 12, availableMemoryMB: 300,
                                    deviceModelIdentifier: "iPhone19,2", thermalState: .serious)
        XCTAssertEqual(ModelSelectionProfile.precise.resolvedIdentifier(installed: installed, osMajor: 27, capabilities: hot), "openai_whisper-tiny")
    }
    func testLocalCleanupChoiceRoundTripsWithoutSilentlySelectingApple() {
        for model in LocalCleanupModel.allCases {
            let backend = PolishCleanupBackend.local(model)
            XCTAssertEqual(PolishCleanupBackend.parse(backend.storageValue), backend)
            XCTAssertEqual(PolishCleanupBackend.resolvedEngine(preference: backend, appleFMAvailable: true,
                validOllamaIDs: []), .local(model))
        }
        XCTAssertLessThan(DictationCleanupPrompt.instructions().count, 1400)
        XCTAssertTrue(DictationCleanupPrompt.instructions().contains("Never translate"))
        XCTAssertTrue(DictationCleanupPrompt.instructions().contains("<<NL>>"))
    }
}
