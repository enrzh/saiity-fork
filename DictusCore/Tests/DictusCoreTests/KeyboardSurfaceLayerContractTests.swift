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

        XCTAssertTrue(source.contains("let gridSize = CGSize(width: proxy.size.width, height: proxy.size.height)"))
        XCTAssertTrue(source.contains(".frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)"))
        XCTAssertFalse(source.contains("leadingReservedWidths"))
        XCTAssertFalse(source.contains("positionedKeys(in: gridSize).filter"))
    }

    func testSymbolButtonsCommitTapsAndPageToggleRemainsAvailable() throws {
        let source = try read("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(source.contains("ImmediateVariantKey("))
        XCTAssertFalse(source.contains("simultaneousGesture(symbolDragGesture(frames: frames))"))
        XCTAssertTrue(source.contains("case .symbols2ToSymbols1:"))
        XCTAssertTrue(source.contains("case .togglePage:"))
    }

    func testAuxiliaryPagesUseOneTransparentSharedSurfaceAndNativeBottomLane() throws {
        let root = try read("DictusKeyboard/KeyboardRootView.swift")
        let emoji = try read("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try read("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(root.contains("areaSurface(layout: layout, contentFrame: surfaceFrame)"))
        XCTAssertTrue(emoji.contains("keyboardGlass(in: Capsule(), interactive: false)"))
        XCTAssertFalse(categories.contains("glassEffect"))
        XCTAssertTrue(emoji.contains("floatingEmojiCategoryFrame"),
                      "category bookmarks float over the emoji grid")
        XCTAssertTrue(emoji.contains("EmojiCategoryBar("))
        XCTAssertTrue(root.contains("availableWidth: surfaceFrame.width"))
        XCTAssertTrue(emoji.contains("UICollectionView"),
                      "emoji categories must use the native paged collection surface")
        XCTAssertFalse(emoji.contains("TabView("), "nested SwiftUI paging must be removed")
        XCTAssertFalse(emoji.contains("ScrollView(.vertical"), "nested vertical scrolling must be removed")
        XCTAssertTrue(emoji.contains("for row in 0..<4"),
                      "the native emoji surface must reserve four rows")
    }

    func testInsetSurfaceUsesOpaqueSystemFillForAccessibilityFallback() throws {
        let source = try read("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(source.contains("if reduceTransparency || accessibilityContrast == .increased"))
        XCTAssertTrue(source.contains("shape.fill(Color(uiColor: accessibilityContrast == .increased ? .systemFill : .secondarySystemFill))"))
        XCTAssertTrue(source.contains("glassEffect(.regular.interactive(), in: shape)"))
        XCTAssertTrue(source.contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
        XCTAssertTrue(source.contains("background(Color.clear)"))
        XCTAssertTrue(source.contains("Color(uiColor: .tertiarySystemFill)"))
        XCTAssertFalse(source.contains("systemGroupedBackground"),
                       "solid dictation board must not paint a nested grouped slab")
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
        XCTAssertTrue(bar.contains("touchesMoved"))
        XCTAssertTrue(bar.contains("continueTracking"))
        XCTAssertTrue(bar.contains("beginTracking"))
        XCTAssertTrue(bar.contains("final class EmojiCategoryScrubControl: UIControl"))
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

        XCTAssertTrue(source.contains("chromeNumbersFrame"))
        XCTAssertTrue(source.contains("chromeLettersFrame"))
        XCTAssertFalse(source.contains("chromeWideLettersFrame"))
        XCTAssertTrue(source.contains("showsLettersControl"))
        XCTAssertTrue(source.contains("showsEmojiControl"))
        XCTAssertFalse(source.contains("layout.auxiliaryMicrophoneFrame"))
        XCTAssertFalse(source.contains("Text(\"|\")"))
        XCTAssertTrue(source.contains("commandHitSize"))
        XCTAssertTrue(source.contains("Open letter keyboard"))
        XCTAssertTrue(source.contains("glassEffect(.regular.interactive(), in: shape)"))
        XCTAssertTrue(source.contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
        XCTAssertTrue(source.contains("Color(uiColor: .tertiarySystemFill)"))
        XCTAssertFalse(source.contains("systemGroupedBackground"),
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
        XCTAssertTrue(picker.contains("KeyboardDeleteButton("))
        XCTAssertTrue(picker.contains("EmojiCategoryBar("))
        XCTAssertFalse(root.contains("EmojiCategoryBar("))
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

        XCTAssertTrue(source.contains("controls.isUserInteractionEnabled = true"))
        XCTAssertTrue(source.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
    }

    func testAuxiliaryUIKitControlsAreHiddenDisabledAndNonInteractive() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(source.contains("controls.isHidden = false"))
        XCTAssertTrue(source.contains("controls.isUserInteractionEnabled = true"))
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

        XCTAssertTrue(source.contains(".frame(width: availableWidth, height: availableHeight)"))
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

    private func read(_ path: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOfFile: repository.appendingPathComponent(path).path, encoding: .utf8)
    }
}
