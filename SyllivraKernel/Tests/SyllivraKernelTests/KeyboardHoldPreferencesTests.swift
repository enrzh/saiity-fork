import XCTest
@testable import SyllivraKernel

final class KeyboardHoldPreferencesTests: XCTestCase {
    func testHoldDelaysUseTheDefaultTiming() {
        XCTAssertEqual(KeyboardDeletion.holdRecognitionDuration, 0.35)
        XCTAssertEqual(KeyboardDeletion.cursorHoldDuration, 0.3)
        XCTAssertEqual(KeyboardDeletion.repeatDelay, 0.5)
        XCTAssertEqual(KeyboardDeletion.dictationHoldRecognitionDuration, 0.15)
    }
    func testEveryKeyOffersItsBaseFirstAndEveryAlternate() {
        let letters = KeyboardVariantPreferences.options(for: "e", kind: .letter)
        XCTAssertEqual(letters.first, "e")
        XCTAssertTrue(letters.contains("é"))
        XCTAssertEqual(KeyboardVariantPreferences.options(for: "👍", kind: .emoji),
                       EmojiSkinToneVariants.options(for: "👍"))
        XCTAssertEqual(KeyboardVariantPreferences.options(for: "0", kind: .phone), ["0", "+"])
    }
    func testChangingAnAlternateInvalidatesTheCachedPageEvenWhenBothHavePopups() {
        let before = KeyGridPage(id: "letters", rows: [[KeyGridKey(id: "e", action: .character(base: "e", variants: ["e", "é", "è"]))]])
        let after = KeyGridPage(id: "letters", rows: [[KeyGridKey(id: "e", action: .character(base: "e", variants: ["e", "é"]))]])
        XCTAssertNotEqual(before.fingerprint, after.fingerprint)
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
    func testCleanupPromptStaysCompactAndKeepsLanguagesInPlace() {
        XCTAssertLessThan(DictationCleanupPrompt.instructions().count, 1400)
        XCTAssertTrue(DictationCleanupPrompt.instructions().contains("Never translate"))
        XCTAssertTrue(DictationCleanupPrompt.instructions().contains("<<NL>>"))
    }
}
