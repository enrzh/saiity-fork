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
        XCTAssertFalse(root.contains("EmojiKeyboardSurface("))
        XCTAssertFalse(root.contains("SymbolKeyboardSurface("))
        XCTAssertFalse(root.contains("NumberKeyboardSurface("))
        XCTAssertTrue(root.contains("KeyboardViewController.nextKeyboardModes.contains(state.areaMode) || state.areaMode == .emoji"))
        XCTAssertTrue(root.contains(".allowsHitTesting(false)"))
    }

    func testAllFourPagesRenderInsideTheSameInsetSurface() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertEqual(root.components(separatedBy: "areaSurface(layout: layout, contentFrame: surfaceFrame)").count - 1, 1)
        XCTAssertTrue(root.contains("case .keys, .recording:"))
        XCTAssertTrue(root.contains("case .letters, .panel, .emoji, .numberPad:"))
        XCTAssertFalse(root.contains("contentFrame: layout.auxiliaryContentFrame"))
        XCTAssertFalse(root.contains("contentFrame: contentFrame"))
    }

    func testSharedSurfaceHelperUsesAValidSurfaceFrameParameter() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("private func areaSurface(layout: VoiceOnlyKeyboardPolicy.Layout, contentFrame: CGRect)"))
    }

    func testSuggestionsAndGlobeAccessoryWiringAreAbsent() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let inputView = try source("DictusKeyboard/InputView.swift")

        for source in [root, controller, inputView] {
            XCTAssertFalse(source.contains("SuggestionBarView"))
            XCTAssertFalse(source.localizedCaseInsensitiveContains("globe"))
            XCTAssertFalse(source.contains("alternateAccessoryRow"))
        }
    }

    func testEmojiCategoryBarHasOneSharedGlassStripAndContinuousScrollOffset() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        let data = try source("DictusKeyboard/Models/EmojiData.swift")

        XCTAssertTrue(picker.contains("let onBackToVoice: () -> Void"))
        XCTAssertTrue(picker.contains("_ = onBackToVoice"))
        XCTAssertFalse(categories.contains("let onBackToVoice: () -> Void"))
        XCTAssertTrue(categories.contains("Image(systemName: section.icon)"))
        XCTAssertFalse(categories.contains("representativeEmoji"))
        XCTAssertFalse(categories.contains("Text(emoji)"))
        XCTAssertFalse(categories.contains("keyboardGlass(in: Capsule())"))
        XCTAssertFalse(categories.contains("contentOffset"))
        let control = try source("DictusKeyboard/Views/EmojiCategoryControl.swift")
        XCTAssertTrue(control.contains("final class EmojiCategoryControl: UIControl"),
                       "the UIKit scrubber remains the single hit owner for the floating strip")
        XCTAssertTrue(control.contains("continueTracking"))
        XCTAssertTrue(categories.contains("EmojiCategoryScrubControl"))
        XCTAssertTrue(categories.contains("Color.primary : Color.secondary"), "The full rail keeps semantic glyph tint")
        XCTAssertFalse(data.contains("representativeEmoji"), "category navigation must not retain emoji-only icon data")
    }

    func testEmojiCategoryBarUsesNativeSystemImagesForCategories() throws {
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(categories.contains("Image(systemName: section.icon)"))
        XCTAssertTrue(categories.contains("Color.primary"))
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
        XCTAssertTrue(symbolsLayout.contains("bottomRow()"))
        XCTAssertFalse(symbolsLayout.contains("bottomRow(toggle:"))
        XCTAssertFalse(root.contains("leadingReservedWidths:"))
        XCTAssertFalse(root.contains("onTogglePage:"))
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("surface.bottomBar.onInsert = { [weak self] in self?.routeProxyText($0) }"))
        XCTAssertTrue(controller.contains("surface.bottomBar.onReturn = { [weak self] in self?.routeProxyCommand(.returnKey) }"))
        XCTAssertTrue(controller.contains("surface.bottomBar.spaceControl.onTap = { [weak self] in self?.routeProxyCommand(.space) }"))
        XCTAssertTrue(controller.contains("surface.bottomBar.onLetters = { KeyboardState.shared.presentArea(.letters) }"))
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        XCTAssertTrue(factory.contains("id: \"symbolPageToggle\""))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("spaceFrame: surfaceLayout.chromeWideSpaceFrame"))
    }

    func testSymbolGridDoesNotDuplicateBottomPageToggleControl() throws {
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

        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        XCTAssertTrue(factory.contains("id: \"symbolPageToggle\""),
                      "123/#+= stays on the symbol key row")
        XCTAssertTrue(factory.contains("page == .symbolsNumbers ? \"#+=\" : \"123\""))
        XCTAssertFalse(bar.contains("\"#+=\""),
                       "the bottom bar must not also host #+=/123")
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
        XCTAssertTrue((try relocatedKeyboardSource()).contains("AuxiliaryBottomBar("))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("onReturn: onReturn"))
    }

    func testLetterAndSymbolBottomBarsUseTheDedicatedRightSideSwitchSlot() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")

        XCTAssertTrue((try relocatedKeyboardSource()).contains("spaceFrame: surfaceLayout.chromeWideSpaceFrame"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("returnFrame: surfaceLayout.chromeReturnFrame"))
        XCTAssertTrue(bar.contains("roundControl(text: numbersTitle, label: \"Open symbols keyboard\", action: onNumbers)"))
        XCTAssertTrue(bar.contains("roundControl(text: \"ABC\", label: \"Open letter keyboard\", action: onLetters)"))
        XCTAssertTrue(bar.contains("showsNumbersControl"))
        XCTAssertTrue(bar.contains("showsLettersControl"))
        XCTAssertTrue(bar.contains("showsEmojiControl"))
        XCTAssertTrue(bar.contains("chromeNumbersFrame"))
        XCTAssertTrue(bar.contains("chromeLettersFrame"))
        XCTAssertFalse(bar.contains("chromeEmojiFrame"),
                       "ABC/123 emoji uses the compact letters slot, not the voice-page right-of-space slot")
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        XCTAssertTrue(factory.contains("id: \"symbolPageToggle\""),
                      "the page toggle stays on the symbol row, not in a second bottom-bar slot")
        XCTAssertFalse(bar.contains("showsNumbersControl: false"))
        XCTAssertFalse(bar.contains("roundControl(systemName: \"mic.fill\", label: \"Back to dictation board\", action: onVoice)"))
    }

    func testEmojiMotionUsesUIKitHighlightFeedbackWithoutSwiftUIScaleAnimation() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains("applyEmojiFont(.systemFont(ofSize: 22))"))
        XCTAssertTrue(picker.contains("override var isHighlighted: Bool"))
        XCTAssertFalse(picker.contains(".scaleEffect("))
        XCTAssertFalse(picker.contains(".snappy(duration: 0.16)"))
    }

    func testSymbolsToggleUsesPageSpecificTransitionIncludingReturnToNumbers() throws {
        let host = try source("DictusKeyboard/Next/NextKeyboardHost.swift")
        let policy = try source("DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift")

        XCTAssertTrue(host.contains("case .page(let id):"))
        XCTAssertTrue(host.contains("symbolPage = (symbolPage == .symbolsNumbers) ? .symbolsPunctuation : .symbolsNumbers"))
        XCTAssertTrue(policy.contains("case .symbols2: return .symbols2ToSymbols1"))
        XCTAssertFalse(try source("DictusKeyboard/KeyboardRootView.swift").contains("onTogglePage("))
    }

    func testSymbolPageDoesNotAttachAncestorHitShapeToInteractiveKeys() throws {
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        let model = try source("DictusCore/Sources/DictusCore/NextKeyGridModel.swift")

        XCTAssertFalse(grid.contains(".contentShape(Rectangle())"),
                       "the symbol grid must not install a parent hit shape that can swallow key taps")
        XCTAssertTrue(grid.contains("layout.key(at: point)"),
                      "a touch resolves to one placed key")
        XCTAssertTrue(model.contains("item.target.contains(point)"),
                      "touch cells come from the solved targets")
        XCTAssertFalse(grid.contains("inset(by: -6)"),
                       "individual controls must not add a second overlapping hit expansion")
        XCTAssertTrue(grid.contains("updateVariantPopup()"),
                      "the long-press popup is owned by the grid only while a variant is visible")
    }

    func testSymbolsSecondPageToggleDisplaysNumbersLabel() throws {
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(factory.contains("page == .symbolsNumbers ? \"#+=\" : \"123\""))
        XCTAssertFalse(factory.contains("page == .symbolsNumbers ? \"#+=\" : \"ABC\""))
        XCTAssertFalse(root.contains("page == .symbols1 ? \"#+=\" : \"ABC\""))
    }

    func testSymbolsKeepFourRowsAndRouteBottomControlsThroughExistingCallbacks() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")

        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 3"))
        XCTAssertTrue(root.contains("onDelete: { routeProxyCommand(.delete) }"))
        XCTAssertFalse(root.contains("onTogglePage:"))
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("surface.bottomBar.onReturn = { [weak self] in self?.routeProxyCommand(.returnKey) }"))
        XCTAssertTrue(controller.contains("surface.emojiDelete.onDelete = { [weak self] in self?.routeProxyCommand(.delete) }"))
        XCTAssertTrue(controller.contains("surface.bottomBar.onEmoji = { KeyboardState.shared.presentArea(.emoji) }"))
        let host = try source("DictusKeyboard/Next/NextKeyboardHost.swift")
        XCTAssertTrue(host.contains("case .page(let id):"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("AuxiliaryBottomBar("))
    }

    func testSymbolGridUsesContentAbovePolicyReservedBottomLane() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let host = try source("DictusKeyboard/Next/NextKeyboardHost.swift")
        let placement = try source("DictusCore/Sources/DictusCore/NextKeyGridPlacement.swift")
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, surfaceHeight: 228)

        XCTAssertEqual(layout.alternateContentFrame, layout.surfaceFrame)
        XCTAssertFalse(root.contains("availableHeight: contentFrame.height"))
        XCTAssertTrue(host.contains("let lane = KeyGridPlacement.bottomBarLaneHeight"))
        XCTAssertTrue(host.contains("let height = max(0, surface.height - lane)"))
        XCTAssertTrue(placement.contains("public static var bottomBarLaneHeight: CGFloat"))
        XCTAssertFalse(host.contains("SymbolGrid.framesWithPinnedLastRow("))
    }

    func testEmojiBarAnchorsToSurfaceBottomAndKeepsMicrophoneFixed() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let native = try source("DictusKeyboard/Next/KeyboardSurfaceView.swift")

        XCTAssertFalse(picker.contains("EmojiCategoryBar("))
        XCTAssertTrue(native.contains("EmojiCategoryBar("))
        XCTAssertTrue(root.contains("KeyboardDeleteButton("))
        XCTAssertTrue(controller.contains("emojiCategoryScrubber"))
        XCTAssertTrue(native.contains("floatingEmojiCategoryFrame"))
        XCTAssertTrue(picker.contains("AuxiliaryBottomBar("))
        XCTAssertTrue(picker.contains("showsEmojiControl: false"))
        XCTAssertTrue(picker.contains("chromeWideSpaceFrame"))
        XCTAssertFalse(picker.contains("systemName: \"mic.fill\""))
        XCTAssertTrue(categories.contains("EmojiCategoryBarMetrics.railInset"))
        XCTAssertTrue(categories.contains("EmojiCategoryScrubControl"))
    }

    func testEmojiPickerDoesNotCreateASecondGlassSurfaceForPointerFeedback() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertFalse(picker.contains(".thinMaterial"))
        XCTAssertFalse(picker.contains("keyboardGlassEffect()"))
        XCTAssertTrue(picker.contains("override var isHighlighted: Bool"))
    }

    func testSymbolControlLabelsFollowPurposeAndPage() throws {
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")

        XCTAssertTrue(factory.contains("label: page == .symbolsNumbers ? \"#+=\" : \"123\""))
        XCTAssertTrue(bar.contains("firstControl.accessibilityLabel = mode == .panel ? \"Open letter keyboard\" : \"Open symbols keyboard\""))
        XCTAssertTrue(bar.contains("struct AuxiliaryBottomBar"))
    }

    func testSymbolsEmojiControlUsesTheNativeFaceSymbol() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue((try relocatedKeyboardSource()).contains("AuxiliaryBottomBar("),
                      "the symbols page must use the shared bottom control bar")
    }

    func testSymbolsReturnControlUsesACompactNativeSymbolAndKeepsReturnLabel() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue((try relocatedKeyboardSource()).contains("AuxiliaryBottomBar("))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("onReturn: onReturn"))
    }


    private func relocatedKeyboardSource() throws -> String {
        let paths = [
            "DictusKeyboard/KeyboardRootView.swift",
            "DictusKeyboard/KeyboardChrome.swift",
            "DictusKeyboard/KeyboardKeyStyle.swift",
            "DictusKeyboard/KeyboardKeyInput.swift",
            "DictusKeyboard/VoiceBoardSurface.swift",
            "DictusKeyboard/KeyboardState.swift",
            "DictusKeyboard/Views/EmojiPickerView.swift",
            "DictusKeyboard/Views/EmojiGestureCoordinator.swift",
            "DictusKeyboard/Views/EmojiCategoryBar.swift",
            "DictusKeyboard/Views/EmojiCategoryControl.swift",
            "DictusCore/Sources/DictusCore/KeyboardSurfaceState.swift",
            "DictusCore/Sources/DictusCore/EmojiSurfaceModel.swift",
        ]
        return try paths.map { try source($0) }.joined(separator: "\n")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }
}
