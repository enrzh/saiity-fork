import XCTest
@testable import DictusCore

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
            source.range(of: "settingsPanel(\"Keyboard\"")
        )
        let nextSection = try XCTUnwrap(
            source.range(of: "settingsPanel(\"Activity\"", range: keyboardSection.upperBound..<source.endIndex)
        )
        let keyboardSectionSource = String(source[keyboardSection.lowerBound..<nextSection.lowerBound])
        XCTAssertTrue(keyboardSectionSource.contains("Keyboard layout"))
        XCTAssertFalse(keyboardSectionSource.contains("Control order"))
        XCTAssertTrue(keyboardSectionSource.contains("Label(\"Models\", systemImage:"))
        XCTAssertTrue(source.contains("Toggle(\"Haptic feedback\", isOn: $hapticsEnabled)"))
        XCTAssertTrue(source.contains("Toggle(\"Key popups\", isOn: $keyPopupsEnabled)"))

        for removedSetting in [
            "sounds", "soundFeedbackEnabled", "soundVolume", "keyboardLanguage",
            "keyboardLanguageSelection", "numberRowEnabled",
            "autocorrectEnabled"
        ] {
            XCTAssertFalse(source.localizedCaseInsensitiveContains(removedSetting), "旧键盘设置仍出现在 SettingsView: \(removedSetting)")
        }
    }
}
