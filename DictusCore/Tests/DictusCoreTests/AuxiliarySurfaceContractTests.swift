import XCTest

final class AuxiliarySurfaceContractTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testAuxiliarySurfacesUseOneSharedInsetSurfaceWithoutLegacyAccessoryRow() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertTrue(root.contains("embeddedSurface("))
        XCTAssertTrue(root.contains("EmojiPickerView("))
        XCTAssertTrue(root.contains("LiquidSymbolPageView("))
    }

    func testEmojiCategoryBarHasFixedLeadingVoiceReturnAndNoPerCategoryGlass() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(picker.contains("let onBackToVoice: () -> Void"))
        XCTAssertTrue(picker.contains("onBackToVoice: onBackToVoice"))
        XCTAssertTrue(categories.contains("let onBackToVoice: () -> Void"))
        XCTAssertTrue(categories.contains("mic.fill"))
        XCTAssertTrue(categories.contains("Button(action: onBackToVoice)"))
        XCTAssertFalse(categories.contains("keyboardGlassEffect()"))
        XCTAssertTrue(categories.contains("ScrollView(.horizontal"))
    }

    func testSymbolsKeepThreeRowsAndRouteBottomControlsThroughExistingCallbacks() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")

        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 3"))
        XCTAssertTrue(root.contains("onDelete: { routeProxyCommand(.delete) }"))
        XCTAssertTrue(root.contains("onReturn: { routeProxyCommand(.returnKey) }"))
        XCTAssertTrue(root.contains("onTogglePage: { nextPage in symbolPage = nextPage }"))
        XCTAssertTrue(root.contains("case .togglePage"))
        XCTAssertTrue(root.contains("case .emoji"))
        XCTAssertTrue(root.contains("mic.fill"))
        XCTAssertTrue(root.contains("frame(minWidth: 44, minHeight: 44)"))
        XCTAssertTrue(root.contains("onEmoji: { state.presentArea(.emoji) }"))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }
}
