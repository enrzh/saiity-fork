import XCTest

final class VoiceOnlyKeyboardContractTests: XCTestCase {
    func testVoiceOnlyKeyboardHasNoLegacyBridgeWiring() throws {
        // These are source-contract checks only. They do not instantiate UIKit or
        // prove runtime keyboard behavior.
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let controller = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"), encoding: .utf8)
        let root = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"), encoding: .utf8)
        let state = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardState.swift"), encoding: .utf8)
        let project = try String(contentsOf: repository.appending(path: "Dictus.xcodeproj/project.pbxproj"), encoding: .utf8)
        let bridge = repository.appending(path: "DictusKeyboard/DictusKeyboardBridge.swift")

        XCTAssertFalse(controller.contains("DictusKeyboardBridge"))
        XCTAssertFalse(controller.contains("suggestionState"))
        XCTAssertFalse(root.contains("DictusKeyboardBridge"))
        XCTAssertFalse(root.contains("legacyBody"))
        XCTAssertFalse(root.contains("suggestionState"))
        XCTAssertFalse(root.contains("fullAreaToolbar"))
        XCTAssertFalse(root.contains("togglePanel"))
        XCTAssertFalse(root.contains("openURL"))
        XCTAssertFalse(controller.contains("toggleEmojiPicker"))
        XCTAssertFalse(controller.contains("dictusTextDidChange"))
        XCTAssertFalse(controller.contains("UserDictionary.shared.reload"))
        XCTAssertFalse(controller.contains("pruneTrieDuplicatesIfNeeded"))
        XCTAssertFalse(state.contains("toggleEmojiPresentation"))
        XCTAssertFalse(state.contains("togglePanelPresentation"))
        XCTAssertFalse(state.contains("presentAreaMode("))
        XCTAssertFalse(state.contains("var openURL:"))
        XCTAssertFalse(state.contains("func openDictusApp("))
        XCTAssertFalse(project.contains("DictusKeyboardBridge"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.path))

        XCTAssertTrue(state.contains("openURLFromExtension"))
        XCTAssertTrue(state.contains("extensionContext.open(url, completionHandler: completion)"))
        XCTAssertTrue(state.contains("openDictusURL(url)"))

        XCTAssertTrue(root.contains("state.startRecording()"))
        XCTAssertTrue(root.contains("advanceToNextInputMode()"))
        XCTAssertTrue(root.contains("DragGesture(minimumDistance: 0)"))
        XCTAssertTrue(root.contains(".onEnded"))
        XCTAssertTrue(root.contains("state.requestStop()"))
        XCTAssertTrue(root.contains("textDocumentProxy.deleteBackward()"))
        XCTAssertTrue(root.contains("textDocumentProxy.insertText(\"\\n\")"))
        XCTAssertTrue(root.contains("textDocumentProxy.insertText(\"@\")"))
        XCTAssertTrue(root.contains("state.controller?.dismissKeyboard()"))
        XCTAssertTrue(controller.contains("registerControllerAppearance(controllerID: controllerID)"))
        XCTAssertTrue(controller.contains("case .recording:"))
        XCTAssertTrue(controller.contains("setHostingExpanded(true)"))
    }
}
