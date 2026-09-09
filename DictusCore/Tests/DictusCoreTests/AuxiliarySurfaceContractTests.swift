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
        XCTAssertFalse(root.localizedCaseInsensitiveContains("suggestion row"))
        XCTAssertFalse(root.localizedCaseInsensitiveContains("accessory row"))
        XCTAssertEqual(root.components(separatedBy: "embeddedSurface(").count - 1, 1)
        XCTAssertTrue(root.contains("areaSurface(layout: layout, contentFrame: surfaceFrame)"))
        XCTAssertFalse(root.contains("bottomControlFrame"))
        XCTAssertFalse(root.contains("auxiliaryContentFrame"), "all modes must use the shared surfaceFrame")
        XCTAssertFalse(root.contains(".offset(x: surfaceFrame.minX, y: surfaceFrame.minY)"))
        XCTAssertFalse(root.contains("Color.clear.frame(height: max(0, contentFrame.minY))"))
        XCTAssertTrue(root.contains("EmojiPickerView("))
        XCTAssertTrue(root.contains("LiquidSymbolPageView("))
    }

    func testAllFourPagesRenderInsideTheSameInsetSurface() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertEqual(root.components(separatedBy: "areaSurface(layout: layout, contentFrame: surfaceFrame)").count - 1, 1)
        XCTAssertTrue(root.contains("case .keys:"))
        XCTAssertTrue(root.contains("case .letters:"))
        XCTAssertTrue(root.contains("case .recording:"))
        XCTAssertTrue(root.contains("case .emoji:"))
        XCTAssertTrue(root.contains("case .panel:"))
        XCTAssertFalse(root.contains("contentFrame: layout.auxiliaryContentFrame"))
        XCTAssertFalse(root.contains("contentFrame: contentFrame"))
    }

    func testSharedSurfaceHelperUsesAValidSurfaceFrameParameter() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("private func areaSurface(layout: VoiceOnlyKeyboardPolicy.Layout, contentFrame: CGRect)"))
    }

    func testSuggestionBarIsKeyboardModeOnlyAndGlobeAccessoryWiringIsAbsent() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let inputView = try source("DictusKeyboard/InputView.swift")

        for source in [root, controller, inputView] {
            if source == root {
                XCTAssertTrue(source.contains("SuggestionBarView"))
            }
            XCTAssertFalse(source.localizedCaseInsensitiveContains("globe"))
            XCTAssertFalse(source.contains("alternateAccessoryRow"))
        }
    }

    func testEmojiCategoryBarHasFixedLeadingVoiceReturnAndNoPerCategoryGlass() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        let data = try source("DictusKeyboard/Models/EmojiData.swift")

        XCTAssertTrue(picker.contains("let onBackToVoice: () -> Void"))
        XCTAssertTrue(picker.contains("action: onBackToVoice"))
        XCTAssertFalse(categories.contains("let onBackToVoice: () -> Void"))
        XCTAssertTrue(categories.contains("Image(systemName: section.icon)"))
        XCTAssertFalse(categories.contains("representativeEmoji"))
        XCTAssertFalse(categories.contains("Text(emoji)"))
        XCTAssertFalse(categories.contains("keyboardGlassEffect()"))
        XCTAssertTrue(categories.contains("ScrollView(.horizontal"))
        XCTAssertFalse(categories.contains("Color.secondary"), "category icons must keep the primary semantic tint")
        XCTAssertFalse(data.contains("representativeEmoji"), "category navigation must not retain emoji-only icon data")
    }

    func testEmojiCategoryBarUsesNativeSystemImagesForCategories() throws {
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(categories.contains("Image(systemName: section.icon)"))
        XCTAssertTrue(categories.contains(".foregroundStyle(.primary)"))
    }

    func testCurrentKeyboardSymbolPagesHaveFourRowsAndAllActions() throws {
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")
        let symbolsLayout = try source("DictusCore/Sources/DictusCore/KeyboardSymbolsLayout.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("let layout = VoiceOnlyKeyboardPolicy.layout("))
        XCTAssertEqual(layouts.components(separatedBy: "private static func numbersPage").count - 1, 1)
        XCTAssertEqual(layouts.components(separatedBy: "private static func symbolsPage").count - 1, 1)
        XCTAssertTrue(symbolsLayout.contains("public static let numbers: [[Key]"))
        XCTAssertTrue(symbolsLayout.contains("public static let symbols: [[Key]"))
        XCTAssertTrue(root.contains("AuxiliaryBottomBar("))
        XCTAssertTrue(root.contains("onSpace: { routeProxyCommand(.space) }"))
        XCTAssertTrue(symbolsLayout.contains("bottomRow()"))
        XCTAssertFalse(symbolsLayout.contains("bottomRow(toggle:"))
        XCTAssertTrue(root.contains("onInsert: { text in routeProxyText(text) }"))
        XCTAssertTrue(root.contains("onDelete: { routeProxyCommand(.delete) }"))
        XCTAssertTrue(root.contains("onReturn: { routeProxyCommand(.returnKey) }"))
        XCTAssertTrue(root.contains("onTogglePage: { nextPage in symbolPage = nextPage }"))
        XCTAssertFalse(root.contains("leadingReservedWidths:"))
    }

    func testSymbolGridDoesNotDuplicateBottomPageToggleControl() {
        XCTAssertTrue(KeyboardSymbolsLayout.numbers[2].contains { key in
            if case .pageToggle = key.kind { return true }
            return false
        })
        XCTAssertTrue(KeyboardSymbolsLayout.symbols[2].contains { key in
            if case .pageToggle = key.kind { return true }
            return false
        })
        XCTAssertEqual(KeyboardSymbolsLayout.numbers.count, 3)
        XCTAssertEqual(KeyboardSymbolsLayout.symbols.count, 3)
    }

    func testSymbolDeleteStaysAboveTheSharedReturnControl() throws {
        for rows in [KeyboardSymbolsLayout.numbers, KeyboardSymbolsLayout.symbols] {
            guard let bottomRow = rows.last else {
                XCTFail("symbol page must have a bottom symbol row")
                continue
            }

            guard case .delete = bottomRow.last?.kind else {
                XCTFail("delete must be the last key in the third symbol row")
                continue
            }
            XCTAssertEqual(bottomRow.dropLast().count, 6)
        }

        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(root.contains("AuxiliaryBottomBar("))
        XCTAssertTrue(root.contains("onReturn: onReturn"))
    }

    func testEmojiMotionDisablesScaleFeedbackWhenReduceMotionIsEnabled() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains(".scaleEffect(reduceMotion ? 1 : isPressed ? 1.08 : 1)"))
        XCTAssertTrue(picker.contains(".animation(reduceMotion ? nil : .snappy(duration: 0.16), value: isPressed)"))
    }

    func testSymbolsToggleUsesPageSpecificTransitionIncludingReturnToNumbers() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("case .togglePage:"))
        XCTAssertTrue(root.contains("onTogglePage(.symbols2)"))
        XCTAssertTrue(root.contains("onTogglePage(.symbols1)"))
        XCTAssertTrue(root.contains("case .symbols2ToSymbols1:"))
    }

    func testSymbolPageDoesNotAttachAncestorHitShapeToInteractiveKeys() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let symbolPageStart = try XCTUnwrap(root.range(of: "private struct LiquidSymbolPageView"))
        let symbolPage = String(root[symbolPageStart.lowerBound...])

        XCTAssertFalse(
            symbolPage.contains(".frame(width: gridSize.width, height: gridSize.height)\n                    .contentShape(Rectangle())"),
            "the symbol grid must not install a parent hit shape that can swallow child Button taps"
        )
        XCTAssertTrue(
            symbolPage.contains("variantOverlay"),
            "the long-press overlay may own a hit shape only while a variant popup is visible"
        )
        XCTAssertTrue(
            symbolPage.contains(".contentShape(Rectangle())"),
            "symbol keys must keep the complete rectangular edge hit target"
        )
    }

    func testSymbolsSecondPageToggleDisplaysNumbersLabel() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("page == .symbols1 ? \"#+=\" : \"123\""))
        XCTAssertFalse(root.contains("page == .symbols1 ? \"#+=\" : \"ABC\""))
    }

    func testSymbolsKeepFourRowsAndRouteBottomControlsThroughExistingCallbacks() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")

        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 3"))
        XCTAssertTrue(root.contains("onDelete: { routeProxyCommand(.delete) }"))
        XCTAssertTrue(root.contains("onReturn: { routeProxyCommand(.returnKey) }"))
        XCTAssertTrue(root.contains("onTogglePage: { nextPage in symbolPage = nextPage }"))
        XCTAssertTrue(root.contains("case .togglePage"))
        XCTAssertTrue(root.contains("AuxiliaryBottomBar("))
        XCTAssertTrue(root.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)"))
        XCTAssertTrue(root.contains("onEmoji: { state.presentArea(.emoji) }"))
    }

    func testSymbolGridUsesContentAbovePolicyReservedBottomLane() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 228)

        XCTAssertEqual(layout.alternateContentFrame, layout.surfaceFrame)
        XCTAssertTrue(root.contains("availableHeight: surfaceFrame.height"))
        XCTAssertFalse(root.contains("availableHeight: contentFrame.height"))
        XCTAssertTrue(root.contains("let gridSize = CGSize(width: proxy.size.width, height: proxy.size.height)"))
        XCTAssertTrue(root.contains("SymbolGrid.frames("))
        XCTAssertTrue(root.contains("in: size, spacing: keySpacing"))
    }

    func testEmojiBarAnchorsToSurfaceBottomAndKeepsMicrophoneFixed() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(picker.contains("EmojiCategoryBar("))
        XCTAssertTrue(picker.contains("systemName: \"mic.fill\""))
        XCTAssertTrue(picker.contains("KeyboardDeleteButton(onDelete: onDelete, onDeleteWord: onDeleteWord)"))
        XCTAssertFalse(picker.contains("AuxiliaryBottomBar("),
                      "the emoji page keeps only microphone, categories, and delete")
        XCTAssertTrue(categories.contains(".frame(width: 44, height: 44)"))
    }

    func testEmojiPickerDoesNotCreateASecondGlassSurfaceForPointerFeedback() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertFalse(picker.contains(".thinMaterial"))
        XCTAssertFalse(picker.contains("keyboardGlassEffect()"))
        XCTAssertTrue(picker.contains(".allowsHitTesting(false)"))
    }

    func testSymbolControlLabelsFollowPurposeAndPage() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("case .togglePage: return label == \"#+=\" ? \"More symbols\" : \"Return to numbers keyboard\""))
        XCTAssertTrue(root.contains("AuxiliaryBottomBar("))
    }

    func testSymbolsEmojiControlUsesTheNativeFaceSymbol() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("AuxiliaryBottomBar("),
                      "the symbols page must use the shared bottom control bar")
    }

    func testSymbolsReturnControlUsesACompactNativeSymbolAndKeepsReturnLabel() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("AuxiliaryBottomBar("))
        XCTAssertTrue(root.contains("onReturn: onReturn"))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }
}
