import XCTest
@testable import DictusCore

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
        XCTAssertEqual(root.components(separatedBy: "embeddedSurface(").count - 1, 1)
        XCTAssertTrue(root.contains("areaSurface(layout: layout, contentFrame: contentFrame, surfaceHeight: surfaceHeight)"))
        XCTAssertTrue(root.contains(".offset(x: surfaceFrame.minX, y: surfaceFrame.minY)"))
        XCTAssertFalse(root.contains("Color.clear.frame(height: max(0, contentFrame.minY))"))
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

    func testEmojiMotionDisablesScaleFeedbackWhenReduceMotionIsEnabled() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains(".scaleEffect(reduceMotion ? 1 : pressedEmojiIndex == itemIndex ? 1.08 : 1)"))
        XCTAssertTrue(picker.contains(".animation(reduceMotion ? nil : .snappy(duration: 0.16), value: pressedEmojiIndex)"))
    }

    func testSymbolsToggleUsesPageSpecificTransitionIncludingClosePath() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("symbolControl(page == .symbols1 ? \"#+=\" : \"ABC\", purpose: .togglePage) {"))
        XCTAssertTrue(root.contains("page == .symbols1 ? onTogglePage(.symbols2) : onClose()"))
        XCTAssertTrue(root.contains("case .symbols2ToClose:"))
        XCTAssertTrue(root.contains("onClose()"))
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

    func testSymbolGridUsesContentAbovePolicyReservedBottomLane() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 228)

        XCTAssertTrue(layout.surfaceFrame.contains(layout.bottomAuxiliaryControlFrame))
        XCTAssertTrue(layout.surfaceFrame.contains(layout.auxiliaryContentFrame))
        XCTAssertFalse(layout.auxiliaryContentFrame.intersects(layout.bottomAuxiliaryControlFrame))
        XCTAssertTrue(root.contains("let gridHeight = max(0, proxy.size.height - VoiceOnlyKeyboardPolicy.controlSize - VoiceOnlyKeyboardPolicy.visibleControlGap)"))
        XCTAssertTrue(root.contains("SymbolGrid.frames("))
        XCTAssertTrue(root.contains("in: size, spacing: keySpacing"))
    }

    func testSymbolControlLabelsFollowPurposeAndPage() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains(".accessibilityLabel(accessibilityLabel(for: purpose))"))
        XCTAssertTrue(root.contains("case .emoji: return \"Emoji\""))
        XCTAssertTrue(root.contains("case .voice: return \"Return to voice keyboard\""))
        XCTAssertTrue(root.contains("case .togglePage: return page == .symbols1 ? \"More symbols\" : \"Return to voice keyboard/ABC\""))
        XCTAssertTrue(root.contains("symbolControl(page == .symbols1 ? \"#+=\" : \"ABC\", purpose: .togglePage"))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }
}
