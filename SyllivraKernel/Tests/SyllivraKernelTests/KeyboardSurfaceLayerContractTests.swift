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
        let host = try read("DictusKeyboard/Next/NextKeyboardHost.swift")

        XCTAssertTrue(host.contains("let height = max(0, surface.height - lane)"))
        XCTAssertTrue(host.contains("return CGRect(x: surface.minX, y: surface.minY,"))
        XCTAssertFalse(source.contains("leadingReservedWidths"))
        XCTAssertFalse(source.contains("positionedKeys(in: gridSize).filter"))
    }

    func testSymbolButtonsCommitTapsAndPageToggleRemainsAvailable() throws {
        let source = try read("DictusKeyboard/KeyboardRootView.swift")
        let grid = try read("DictusKeyboard/Next/KeyGridView.swift")
        let host = try read("DictusKeyboard/Next/NextKeyboardHost.swift")

        XCTAssertTrue(grid.contains("override func touchesBegan("))
        XCTAssertTrue(grid.contains("case .insert(let text):"))
        XCTAssertFalse(source.contains("simultaneousGesture(symbolDragGesture(frames: frames))"))
        XCTAssertTrue(host.contains("case .page(let id):"))
        XCTAssertTrue(host.contains("symbolPage = (symbolPage == .symbolsNumbers) ? .symbolsPunctuation : .symbolsNumbers"))
    }

    func testAuxiliaryPagesUseOneTransparentSharedSurfaceAndNativeBottomLane() throws {
        let root = try read("DictusKeyboard/KeyboardRootView.swift")
        let emoji = try read("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try read("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(root.contains("areaSurface(layout: layout, contentFrame: surfaceFrame)"))
        XCTAssertTrue(try read("DictusKeyboard/KeyboardViewController.swift").contains("surfaceBackdrop.configureInset(layout"))
        XCTAssertFalse(emoji.contains("view.backgroundView = material"))
        XCTAssertFalse(categories.contains("keyboardGlass(in: Capsule())"))
        XCTAssertFalse(categories.contains("contentOffset"))
        let native = try read("DictusKeyboard/Next/KeyboardSurfaceView.swift")
        XCTAssertFalse(native.contains("emojiInset"), "The inset has one owner for all pages")
        XCTAssertTrue(emoji.contains("view.decelerationRate = .normal"))
        XCTAssertTrue(native.contains("floatingEmojiCategoryFrame"),
                      "category bookmarks float over the native emoji grid")
        XCTAssertTrue(native.contains("EmojiCategoryBar("))
        XCTAssertTrue(native.contains("emojiDelete.keyboardFace.configure("))
        XCTAssertTrue(native.contains("attachKeyboardVisualController(emojiChrome, from: emojiCategory)"))
        XCTAssertFalse(root.contains("EmojiCategoryBar("))
        XCTAssertTrue(root.contains("KeyboardDeleteButton("))
        XCTAssertTrue(native.contains("layout.boardDeleteFrame.minX - surface.minX - VoiceOnlyKeyboardPolicy.visibleControlGap"),
                      "emoji content must stop before the shared Delete target")
        XCTAssertFalse(root.contains("availableWidth: surfaceFrame.width"))
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
        XCTAssertTrue(plates.contains("role.solidFill(increasedContrast: reduceTransparency || accessibilityContrast == .increased)"))
        XCTAssertTrue(plates.contains("glassEffect(.regular.interactive(), in: shape)"))
        XCTAssertTrue(plates.contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
        XCTAssertTrue(plates.contains("case .input, .control: return .tertiarySystemBackground"))
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
        let root = try read("DictusKeyboard/KeyboardRootView.swift")
        let controller = try read("DictusKeyboard/KeyboardViewController.swift")
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appending(path: "DictusKeyboard/Views/ToolbarView.swift").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.appending(path: "DictusKeyboard/Views/SuggestionBarView.swift").path))
        XCTAssertFalse(root.contains("SuggestionBarView("))
        XCTAssertFalse(controller.contains("SuggestionBarView("))
        XCTAssertFalse(root.contains("onSuggestionTap"))
    }

    func testStatusMessageKeepsItsDisplayLifecycleCallbacksAfterSuggestionRemoval() throws {
        let board = try read("DictusKeyboard/VoiceBoardSurface.swift")
        let state = try read("DictusKeyboard/KeyboardState.swift")

        XCTAssertTrue(board.contains("if let message = state.statusMessage { return message }"),
                      "the voice board still shows a status message after the suggestion row is gone")
        XCTAssertTrue(state.contains("func noteStatusMessageDisplayed(rootView: String, controller: String)"))
        XCTAssertTrue(state.contains("func noteStatusMessageHidden(rootView: String, controller: String)"))
        XCTAssertFalse(board.contains("SuggestionBarView("))
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
        XCTAssertTrue(control.contains("EmojiCategoryBarMetrics.index(atX:"))
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
        XCTAssertTrue(style.contains("case .input, .control: return .tertiarySystemBackground"))
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
        let native = try read("DictusKeyboard/Next/KeyboardSurfaceView.swift")

        XCTAssertTrue(picker.contains(".frame(width: availableWidth, height: availableHeight)"))
        XCTAssertTrue(root.contains("KeyboardDeleteButton("))
        XCTAssertTrue(native.contains("EmojiCategoryBar("))
        XCTAssertFalse(picker.contains("EmojiCategoryBar("))
        XCTAssertFalse(picker.contains("let categoryBarHeight: CGFloat = 44"))
        XCTAssertFalse(root.contains("private func accessoryBar("))
        XCTAssertTrue(native.contains("floatingEmojiCategoryFrame"))
    }

    func testEmojiCategoriesAreMonochromeOrASCIIWithoutLegacySearch() throws {
        let source = try read("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(source.contains("Image(systemName: section.icon)"))
        XCTAssertTrue(source.contains("Color.primary"))
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
        XCTAssertTrue(source.contains("let overlayVisible = true"),
                      "one native accessory owner stays available in both materials")
        XCTAssertFalse(source.contains("forwardHitTest"), "the transparent accessory canvas must never forward misses into SwiftUI")
        XCTAssertTrue(source.contains("inputView.addSubview(surface)"),
                      "the whole native Emoji board stays outside the voice overlay")
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

    func testNativeVoiceControlsOwnTheirFacesAndPressFeedback() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(source.contains("control.existingKeyboardFace?.setPressed(control.isHighlighted)"))
        XCTAssertTrue(source.contains("recoveryButton.keyboardFace.configure("))
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
            "DictusKeyboard/KeyboardState.swift",
            "DictusKeyboard/Views/EmojiPickerView.swift",
            "DictusKeyboard/Views/EmojiGestureCoordinator.swift",
            "DictusKeyboard/Views/EmojiCategoryBar.swift",
            "DictusKeyboard/Views/EmojiCategoryControl.swift",
            "SyllivraKernel/Sources/SyllivraKernel/KeyboardSurfaceState.swift",
            "SyllivraKernel/Sources/SyllivraKernel/EmojiSurfaceModel.swift",
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
