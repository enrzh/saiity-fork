import XCTest
@testable import DictusCore

final class KeyboardOrderSettingsContractTests: XCTestCase {
    func testSettingsUsesExplicitKeyboardOrderChoicesAndAppGroupStorage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appending(path: "DictusApp/Views/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("KeyboardAccessoryOrder"))
        let storageDeclaration = try XCTUnwrap(
            source.range(of: "@AppStorage(SharedKeys.keyboardAccessoryOrder", options: .literal)
        )
        let declarationEnd = try XCTUnwrap(
            source.range(of: "keyboardAccessoryOrderRawValue", range: storageDeclaration.upperBound..<source.endIndex)
        )
        let storage = String(source[storageDeclaration.lowerBound..<declarationEnd.upperBound])
        XCTAssertTrue(storage.contains("store: UserDefaults(suiteName: AppGroup.identifier)"))
        XCTAssertEqual(source.components(separatedBy: "@AppStorage(SharedKeys.keyboardAccessoryOrder").count - 1, 1)

        XCTAssertTrue(source.contains("Picker"))
        XCTAssertTrue(source.contains("selection: keyboardAccessoryOrderBinding"))
        XCTAssertTrue(source.contains("ForEach([KeyboardAccessoryOrder.emojiFirst, .numberFirst]"))
        XCTAssertFalse(source.contains("KeyboardAccessoryOrder.allCases"))
        XCTAssertTrue(source.contains("KeyboardAccessoryOrder.emojiFirst.rawValue"))
        XCTAssertEqual(KeyboardAccessoryOrder.emojiFirst.displayName, "Emoji, 123")
        XCTAssertEqual(KeyboardAccessoryOrder.numberFirst.displayName, "123, Emoji")
        XCTAssertTrue(source.contains("Label(\"Models\", systemImage:"))

        for removedSetting in [
            "sounds", "soundFeedbackEnabled", "soundVolume", "keyboardLanguage",
            "keyboardLanguageSelection", "keyboardLayout", "numberRowEnabled",
            "hapticsEnabled", "autocorrectEnabled"
        ] {
            XCTAssertFalse(source.localizedCaseInsensitiveContains(removedSetting), "旧键盘设置仍出现在 SettingsView: \(removedSetting)")
        }
    }
}
