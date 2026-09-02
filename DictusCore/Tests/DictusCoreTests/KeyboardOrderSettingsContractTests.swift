import XCTest
@testable import DictusCore

final class KeyboardOrderSettingsContractTests: XCTestCase {
    func testSettingsUsesAppGroupPickerWithOnlyCurrentKeyboardOrderChoices() throws {
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
        XCTAssertTrue(source.contains("@AppStorage(SharedKeys.keyboardAccessoryOrder"))
        XCTAssertTrue(source.contains("store: UserDefaults(suiteName: AppGroup.identifier)"))
        XCTAssertTrue(source.contains("Picker"))
        XCTAssertTrue(source.contains("selection: keyboardAccessoryOrderBinding"))
        XCTAssertTrue(source.contains("KeyboardAccessoryOrder.allCases"))
        XCTAssertTrue(source.contains("order.displayName"))
        XCTAssertTrue(source.contains("KeyboardAccessoryOrder.emojiFirst.rawValue"))
        XCTAssertEqual(KeyboardAccessoryOrder.allCases.map(\.displayName), ["Emoji, 123", "123, Emoji"])
        XCTAssertFalse(source.contains("keyboardLanguage"))
        XCTAssertFalse(source.contains("keyboardLayout"))
        XCTAssertFalse(source.contains("numberRow"))
        XCTAssertFalse(source.contains("haptic"))
        XCTAssertFalse(source.contains("autocorrect"))
    }
}
