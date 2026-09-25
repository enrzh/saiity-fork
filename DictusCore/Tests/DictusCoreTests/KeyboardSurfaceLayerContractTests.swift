import XCTest

final class KeyboardSurfaceLayerContractTests: XCTestCase {
    func testRootUsesSurfaceLocalCoordinatesWithoutSecondGlobalOffset() throws {
        let source = try read("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertFalse(source.contains(".offset(x: surfaceFrame.minX, y: surfaceFrame.minY)"))
        XCTAssertTrue(source.contains("contentFrame: surfaceFrame"))
        XCTAssertTrue(source.contains("frame(width: surfaceFrame.width, height: surfaceFrame.height"))
    }

    func testInputControllerContainerDoesNotPaintASecondKeyboardBackdrop() throws {
        let source = try read("DictusKeyboard/InputView.swift")

        XCTAssertTrue(source.contains("backgroundColor = .clear"))
        XCTAssertTrue(source.contains("isOpaque = false"))
        XCTAssertTrue(source.contains("layer.backgroundColor = UIColor.clear.cgColor"))
    }

    func testInputControllerReassertsTransparencyAfterUIKitAttachmentAndLayout() throws {
        let source = try read("DictusKeyboard/InputView.swift")

        XCTAssertTrue(source.contains("override func didMoveToWindow()"))
        XCTAssertTrue(source.contains("override func layoutSubviews()"))
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: "reassertTransparentBackdrop()").count - 1,
            2
        )
        XCTAssertTrue(source.contains("private func reassertTransparentBackdrop()"))
    }

    func testHostingAndUIKitOverlayStayTransparentAndDoNotInstallGlassLayers() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(source.contains("hosting.view.isOpaque = false"))
        XCTAssertTrue(source.contains("hosting.view.layer.backgroundColor = UIColor.clear.cgColor"))
        XCTAssertTrue(source.contains("controls.isOpaque = false"))
        XCTAssertTrue(source.contains("controls.layer.backgroundColor = UIColor.clear.cgColor"))
        XCTAssertFalse(source.contains("UIVisualEffectView"))
        XCTAssertFalse(source.contains("UIGlassEffect"))
    }

    func testSymbolsUseExplicitGridHeightWithoutOverlayWidthCompensation() throws {
        let source = try read("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue((try relocatedKeyboardSource()).contains("let gridSize = CGSize(width: proxy.size.width, height: proxy.size.height)"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains(".frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)"))
        XCTAssertFalse(source.contains("leadingReservedWidths"))
        XCTAssertFalse(source.contains("positionedKeys(in: gridSize).filter"))
    }

    func testSymbolButtonsCommitTapsAndPageToggleRemainsAvailable() throws {
        let source = try read("DictusKeyboard/KeyboardRootView.swift")

        // Symbol keys are faces only; the shared UIKit owner owns their touches.
        XCTAssertTrue((try relocatedKeyboardSource()).contains(".keyGridInput("))
        XCTAssertFalse(source.contains("simultaneousGesture(symbolDragGesture(frames: frames))"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("case .symbols2ToSymbols1:"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("case .togglePage:"))
    }

    func testAuxiliaryPagesUseOneTransparentSharedSurfaceAndNativeBottomLane() throws {
        let root = try read("DictusKeyboard/KeyboardRootView.swift")
        let emoji = try read("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try read("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(root.contains("areaSurface(layout: layout, contentFrame: surfaceFrame)"))
        XCTAssertFalse(root.contains("withoutGlassRim: state.areaMode == .emoji"),
                       "emoji uses the same shared glass inset as the other keyboard pages")
        XCTAssertTrue(categories.contains("glassEffect(.regular.interactive(), in: shape)"))
        XCTAssertTrue(categories.contains("contentOffset"))
        XCTAssertTrue(root.contains("floatingEmojiCategoryFrame"),
                      "category bookmarks float over the emoji grid")
        XCTAssertTrue(root.contains("EmojiCategoryBar("))
        XCTAssertTrue(root.contains("KeyboardDeleteButton("))
        XCTAssertTrue(root.contains("availableWidth: surfaceFrame.width"))
        XCTAssertTrue(emoji.contains("UICollectionView"),
                      "emoji categories must use the native paged collection surface")
        XCTAssertFalse(emoji.contains("TabView("), "nested SwiftUI paging must be removed")
        XCTAssertFalse(emoji.contains("ScrollView(.vertical"), "nested vertical scrolling must be removed")
        XCTAssertTrue(emoji.contains("for row in 0..<4"),
                      "the native emoji surface must reserve four rows")
    }

    func testInsetSurfaceUsesOpaqueSystemFillForAccessibilityFallback() throws {
        let root = try read("DictusKeyboard/KeyboardRootView.swift")
        let plates = try read("DictusKeyboard/KeyboardKeyStyle.swift")

        XCTAssertTrue(plates.contains("if reduceTransparency || accessibilityContrast == .increased"))
        XCTAssertTrue(plates.contains("shape.fill(Color(uiColor: accessibilityContrast == .increased ? .systemFill : .secondarySystemFill))"))
        XCTAssertTrue(plates.contains("glassEffect(.regular.interactive(), in: shape)"))
        XCTAssertTrue(plates.contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
        XCTAssertTrue(plates.contains("Color(uiColor: .tertiarySystemFill)"))
        XCTAssertTrue(root.contains("background(Color.clear)"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("keyboardGlass(in: shape, role: role)"))
        XCTAssertFalse(root.contains("glassEffect("),
                       "material branches live in KeyboardGlassSurface")
        XCTAssertFalse(root.contains("systemGroupedBackground"),
                       "solid dictation board must not paint a nested grouped slab")
        XCTAssertFalse(plates.contains("systemGroupedBackground"),
                       "solid key plates use tertiary fill, not a grouped board slab")
    }

    func testDictationBoardChromeStacksAboveTheGlassSurface() throws {
        let source = try read("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(source.contains(".zIndex(3)"),
                      "the shared surface remains above the suggestion lane for key popups")
        XCTAssertTrue(source.contains(".zIndex(4)"),
                      "dictation-board controls must render above the shared surface")
        let chrome = try read("DictusKeyboard/KeyboardChrome.swift")
        XCTAssertTrue(chrome.contains("Group {\n            if voiceBoardUsesUIKitHits"),
                      "both visual and SwiftUI-owned board chrome must share the elevated layer")
    }

    func testLegacySuggestionRowIsNotReachableFromTheKeyboardToolbar() throws {
        let source = try read("DictusKeyboard/Views/ToolbarView.swift")

        XCTAssertFalse(source.contains("SuggestionBarView("))
        XCTAssertFalse(source.contains("var suggestions:"))
        XCTAssertFalse(source.contains("suggestions.isEmpty"))
        XCTAssertFalse(source.contains("onSuggestionTap"))
    }

    func testStatusMessageKeepsItsDisplayLifecycleCallbacksAfterSuggestionRemoval() throws {
        let source = try read("DictusKeyboard/Views/ToolbarView.swift")

        XCTAssertTrue(source.contains("KeyboardState.shared.noteStatusMessageDisplayed("))
        XCTAssertTrue(source.contains("KeyboardState.shared.noteStatusMessageHidden("))
    }

    func testEmojiCategoryBarUsesNativeSystemImages() throws {
        let bar = try read("DictusKeyboard/Views/EmojiCategoryBar.swift")
        let data = try read("DictusKeyboard/Models/EmojiData.swift")

        XCTAssertTrue(bar.contains("Image(systemName: section.icon)"))
        XCTAssertTrue(bar.contains("EmojiCategoryScrubControl"))
        let control = try read("DictusKeyboard/Views/EmojiCategoryControl.swift")
        XCTAssertTrue(control.contains("continueTracking"))
        XCTAssertTrue(control.contains("beginTracking"))
        XCTAssertTrue(control.contains("dragActivationDistance"))
        XCTAssertTrue(control.contains("onExpansionChanged"))
        XCTAssertTrue(control.contains("final class EmojiCategoryControl: UIControl"))
        XCTAssertFalse(bar.contains("section.icon.contains"))
        XCTAssertFalse(bar.contains("Text(section.icon)"))
        XCTAssertTrue(data.contains("icon: \"face.smiling\""))
        XCTAssertTrue(data.contains("icon: \"person\""))
        XCTAssertTrue(data.contains("icon: \"leaf\""))
        XCTAssertTrue(data.contains("id: \"flags\""))
        XCTAssertTrue(data.contains("name: \"Flags\""))
        XCTAssertFalse(data.contains("icon: \":)\""))
    }

    func testSharedBottomBarUsesNativeChromeInsteadOfMicrophoneReturn() throws {
        let source = try read("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        let style = try read("DictusKeyboard/KeyboardKeyStyle.swift")

        XCTAssertTrue(source.contains("chromeNumbersFrame"))
        XCTAssertTrue(source.contains("chromeLettersFrame"))
        XCTAssertFalse(source.contains("chromeWideLettersFrame"))
        XCTAssertTrue(source.contains("showsLettersControl"))
        XCTAssertTrue(source.contains("showsEmojiControl"))
        XCTAssertFalse(source.contains("layout.auxiliaryMicrophoneFrame"))
        XCTAssertFalse(source.contains("Text(\"|\")"))
        XCTAssertTrue(source.contains("commandHitSize"))
        XCTAssertTrue(source.contains("Open letter keyboard"))
        XCTAssertTrue(style.contains("glassEffect(.regular.interactive(), in: shape)"))
        XCTAssertTrue(style.contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
        XCTAssertTrue(style.contains("Color(uiColor: .tertiarySystemFill)"))
        XCTAssertFalse(style.contains("systemGroupedBackground"),
                       "solid key plates use tertiary fill, not a grouped board slab")
        XCTAssertFalse(source.contains("layout.leftUtilityFrames"))
    }

    func testEmojiRecentsCategoryUsesNativeClockSymbol() throws {
        let source = try read("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(source.contains("name: \"Recents\""))
        XCTAssertTrue(source.contains("icon: \"clock\""))
        XCTAssertFalse(source.contains("name: \"Recents\", icon: \"R\""))
    }

    func testEmojiCategoryLaneHasAnExplicitBottomAlignedContainer() throws {
        let picker = try read("DictusKeyboard/Views/EmojiPickerView.swift")
        let root = try read("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(picker.contains(".frame(width: availableWidth, height: availableHeight)"))
        XCTAssertTrue(root.contains("KeyboardDeleteButton("))
        XCTAssertTrue(root.contains("EmojiCategoryBar("))
        XCTAssertFalse(picker.contains("EmojiCategoryBar("))
        XCTAssertFalse(picker.contains("let categoryBarHeight: CGFloat = 44"))
        XCTAssertTrue(root.contains("private func accessoryBar("))
    }

    func testEmojiCategoriesAreMonochromeOrASCIIWithoutLegacySearch() throws {
        let source = try read("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(source.contains("Image(systemName: section.icon)"))
        XCTAssertTrue(source.contains(".foregroundStyle(.primary)"))
        XCTAssertFalse(source.contains("symbolRenderingMode"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("magnifyingglass"))
        XCTAssertFalse(source.contains("representativeEmoji"))
    }

    func testUIKitOverlayOnlyReceivesTouchesOnVoiceModes() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        // The overlay is transparent, so hiding it is the only thing that stops its
        // buttons eating touches meant for the visible SwiftUI surface. This test
        // previously asserted `isUserInteractionEnabled = true` unconditionally,
        // which is the exact opposite of its own name and the cause of letter keys
        // being swallowed by an invisible `return-to-dictation-board`.
        XCTAssertTrue(source.contains("let overlayVisible = uikitOwnsVoiceChrome || mode == .emoji"),
                      "overlay interaction must be gated on the modes where UIKit owns the surface")
        XCTAssertTrue(source.contains("controls.isUserInteractionEnabled = overlayVisible"),
                      "the overlay must not be interactive while SwiftUI owns the surface")
        XCTAssertFalse(source.contains("controls.isUserInteractionEnabled = true\n"),
                       "an unconditional enable lets invisible chrome eat letter-grid touches")
        XCTAssertTrue(source.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
    }

    func testAuxiliaryUIKitControlsAreHiddenDisabledAndNonInteractive() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        // Was `controls.isHidden = false`, which undid the hide that `applyLayout`
        // had just performed and left transparent buttons hit-testing the letter
        // grid. Visibility now follows the same rule as the controls inside it.
        XCTAssertTrue(source.contains("controls.isHidden = !overlayVisible"),
                      "the overlay must hide whenever SwiftUI owns the visible surface")
        XCTAssertFalse(source.contains("controls.isHidden = false"),
                       "forcing the overlay visible leaves invisible buttons eating letter-grid touches")
        XCTAssertTrue(source.contains("$0.isEnabled = !$0.isHidden"))
        XCTAssertTrue(source.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("accessory row"))
    }

    func testUIKitVoiceHitTargetsStayVisuallyTransparentWhenPressed() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(source.contains("if control.isHighlighted || !control.isEnabled"))
        XCTAssertTrue(source.contains("control.backgroundColor = .clear"))
    }

    func testSymbolBottomLaneUsesSharedBottomInsetForItsAnchor() throws {
        let source = try read("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue((try relocatedKeyboardSource()).contains(".frame(width: availableWidth, height: availableHeight)"))
    }

    func testLayoutUsesStableInputViewHeightAndNativeFallbackForEveryMode() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(source.contains("let liveHeight = computeKeyboardHeight(for: KeyboardState.shared.areaMode)"))
        XCTAssertTrue(source.contains("heightConstraint?.constant = liveHeight"))
        XCTAssertTrue(source.contains("layoutVoiceActionControls(surfaceHeight: liveHeight)"))
        XCTAssertTrue(source.contains("let initialHeight = computeKeyboardHeight(for: KeyboardState.shared.areaMode)"))
        XCTAssertFalse(source.contains("equalToConstant: toolbarHeight"))
    }

    func testComputeKeyboardHeightUsesInputViewAndIgnoresControllerBounds() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(source.contains("let observedInputViewHeight = inputView?.bounds.height ?? 0"))
        XCTAssertTrue(source.contains("let inputViewHeight = max(0, observedInputViewHeight - previousAccessoryHeight)"))
        XCTAssertTrue(source.contains("VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight("))
        XCTAssertTrue(source.contains("inputViewHeight: Double(inputViewHeight)"))
        XCTAssertTrue(source.contains("controllerViewHeight: view.bounds.height > 0"))
        XCTAssertTrue(source.contains("fallbackHeight: Double(nativeHeight)"))
    }

    func testLayoutRefreshesHeightConstraintFromTheLiveInputViewHeight() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(source.contains("let liveHeight = computeKeyboardHeight(for: KeyboardState.shared.areaMode)"))
        XCTAssertTrue(source.contains("hostingHeightConstraint?.constant = liveHeight"))
        XCTAssertTrue(source.contains("heightConstraint?.constant = liveHeight"))
        XCTAssertTrue(source.contains("layoutVoiceActionControls(surfaceHeight: liveHeight)"))
        XCTAssertTrue(source.contains("let height = computeKeyboardHeight(for: KeyboardState.shared.areaMode)"))
        XCTAssertTrue(source.contains("heightConstraint?.constant = liveHeight"))
        XCTAssertFalse(source.contains("heightConstraint?.constant = fullHeight"))
    }


    private func relocatedKeyboardSource() throws -> String {
        let paths = [
            "DictusKeyboard/KeyboardRootView.swift",
            "DictusKeyboard/KeyboardChrome.swift",
            "DictusKeyboard/KeyboardKeyStyle.swift",
            "DictusKeyboard/KeyboardKeyInput.swift",
            "DictusKeyboard/VoiceBoardSurface.swift",
            "DictusKeyboard/LetterKeyboardSurface.swift",
            "DictusKeyboard/NumberKeyboardSurface.swift",
            "DictusKeyboard/SymbolKeyboardSurface.swift",
            "DictusKeyboard/KeyboardState.swift",
            "DictusKeyboard/Views/EmojiPickerView.swift",
            "DictusKeyboard/Views/EmojiGestureCoordinator.swift",
            "DictusKeyboard/Views/EmojiCategoryBar.swift",
            "DictusKeyboard/Views/EmojiCategoryControl.swift",
            "DictusCore/Sources/DictusCore/KeyboardSurfaceState.swift",
            "DictusCore/Sources/DictusCore/EmojiSurfaceModel.swift",
        ]
        return try paths.map { try read($0) }.joined(separator: "\n")
    }

    private func read(_ path: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOfFile: repository.appendingPathComponent(path).path, encoding: .utf8)
    }
}
