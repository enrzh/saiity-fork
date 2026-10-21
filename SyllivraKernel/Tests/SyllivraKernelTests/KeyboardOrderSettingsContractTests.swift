import XCTest
@testable import SyllivraKernel

final class KeyboardOrderSettingsContractTests: XCTestCase {
    func testSettingsDoesNotExposeTheRemovedKeyboardOrderChoice() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appending(path: "DictusApp/Views/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("keyboardAccessoryOrder"))
        XCTAssertFalse(source.contains("Control order"))
        XCTAssertEqual(KeyboardAccessoryOrder.emojiFirst.displayName, "Emoji, 123")
        XCTAssertEqual(KeyboardAccessoryOrder.numberFirst.displayName, "123, Emoji")
        let keyboardSection = try XCTUnwrap(
            source.range(of: "LabeledContent(\"Layout\")")
        )
        let nextSection = try XCTUnwrap(
            source.range(of: "struct HelpView", range: keyboardSection.upperBound..<source.endIndex)
        )
        let keyboardSectionSource = String(source[keyboardSection.lowerBound..<nextSection.lowerBound])
        XCTAssertTrue(keyboardSectionSource.contains("TypingLanguagesPanel()"))
        XCTAssertFalse(keyboardSectionSource.contains("Control order"))
        XCTAssertTrue(keyboardSectionSource.contains("DefaultKeyboardModePicker()"))
        XCTAssertFalse(keyboardSectionSource.contains("ModelManagerView"))
        XCTAssertTrue(source.contains("Picker(\"Haptics\", selection: hapticPresetBinding)"))
        XCTAssertTrue(source.contains("Toggle(\"Show Top Bar\""))
        XCTAssertFalse(source.contains("Toggle(\"Key Containers\""))
        XCTAssertFalse(source.contains("KeyPopupPicker()"))
        XCTAssertTrue(source.contains("DictationPresencePicker()"))
        XCTAssertTrue(source.contains("if polishEnabled && cleanupAvailable {"),
                      "writing style must not be offered when cleanup cannot run")
        XCTAssertFalse(source.contains("usesIOSStyling"))
        XCTAssertFalse(source.contains("Toggle(\"Liquid glass\""))
        XCTAssertFalse(source.contains("Toggle(\"Live Activity\""))
        XCTAssertTrue(source.contains("struct HelpView"))
        XCTAssertTrue(source.contains("struct AboutView"))
        XCTAssertFalse(source.contains("settingsPanel("))
        XCTAssertFalse(source.contains("moreGroup("))

        for removedSetting in [
            "sounds", "soundFeedbackEnabled", "soundVolume", "keyboardLanguage",
            "keyboardLanguageSelection", "numberRowEnabled",
        ] {
            XCTAssertFalse(source.localizedCaseInsensitiveContains(removedSetting), "旧键盘设置仍出现在 SettingsView: \(removedSetting)")
        }
    }

    func testAutocorrectionIsAUserSettingAndKeepsTheExistingDefault() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appending(path: "DictusApp/Views/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private var autocorrectEnabled = true"))
        XCTAssertTrue(source.contains("Toggle(\"Autocorrection\", isOn: $autocorrectEnabled)"))
        XCTAssertTrue(source.contains("KeyboardInteractionPreferences.notifyChanged()"))

        let suggestionState = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/TextPrediction/SuggestionState.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(suggestionState.contains("hostPolicy.autocorrectAllowed,\n           autocorrectEnabled"),
                      "disabled autocorrection must skip space-time replacement")
        XCTAssertTrue(suggestionState.contains("if self.autocorrectEnabled,"),
                      "disabled autocorrection must skip async correction suggestions")
        XCTAssertTrue(suggestionState.contains("guard enabled != lastAutocorrectEnabled else { return }"))
        XCTAssertTrue(suggestionState.contains("guard !enabled else { return }"),
                      "preference refresh must clear stale correction UI when disabled")
    }
}
