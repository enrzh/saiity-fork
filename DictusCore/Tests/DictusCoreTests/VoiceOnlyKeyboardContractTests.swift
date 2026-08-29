import XCTest

final class VoiceOnlyKeyboardContractTests: XCTestCase {
    func testVoiceOnlyKeyboardHasNoLegacyBridgeWiring() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let controller = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"), encoding: .utf8)
        let root = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"), encoding: .utf8)
        let project = try String(contentsOf: repository.appending(path: "Dictus.xcodeproj/project.pbxproj"), encoding: .utf8)

        XCTAssertFalse(controller.contains("DictusKeyboardBridge"))
        XCTAssertFalse(controller.contains("suggestionState"))
        XCTAssertFalse(root.contains("DictusKeyboardBridge"))
        XCTAssertFalse(root.contains("legacyBody"))
        XCTAssertFalse(root.contains("suggestionState"))
        XCTAssertFalse(project.contains("DictusKeyboardBridge.swift in Sources"))
    }
}
