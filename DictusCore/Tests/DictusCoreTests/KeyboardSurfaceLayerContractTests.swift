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

        XCTAssertTrue(source.contains("Button { commitSymbolFromTap(key) } label:"))
        XCTAssertFalse(source.contains("simultaneousGesture(symbolDragGesture(frames: frames))"))
        XCTAssertTrue(source.contains("case .symbols2ToSymbols1:"))
        XCTAssertTrue(source.contains("case .togglePage:"))
    }

    func testAuxiliaryPagesUseOneTransparentSharedSurfaceAndNativeBottomLane() throws {
        let root = try read("DictusKeyboard/KeyboardRootView.swift")
        let emoji = try read("DictusKeyboard/Views/EmojiPickerView.swift")
        let categories = try read("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(root.contains("areaSurface(layout: layout, contentFrame: surfaceFrame)"))
        XCTAssertFalse(emoji.contains("keyboardGlassEffect()"))
        XCTAssertFalse(categories.contains("glassEffect"))
        XCTAssertTrue(emoji.contains("availableHeight - headerHeight - bottomBarHeight - edgeInset * 2"))
        XCTAssertTrue(emoji.contains("ScrollView(.horizontal"))
    }

    func testInsetSurfaceUsesOpaqueSystemFillForAccessibilityFallback() throws {
        let source = try read("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(source.contains("if reduceTransparency || accessibilityContrast == .increased"))
        XCTAssertTrue(source.contains("shape.fill(Color(uiColor: accessibilityContrast == .increased ? .systemFill : .secondarySystemFill))"))
        XCTAssertTrue(source.contains("glassEffect(.regular.interactive(), in: shape)"))
        XCTAssertTrue(source.contains("background(Color.clear)"))
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
        XCTAssertTrue(bar.contains("proxy.scrollTo(id, anchor: .center)"))
        XCTAssertTrue(bar.contains("proxy.scrollTo(selectedCategoryID, anchor: .center)"))
        XCTAssertFalse(bar.contains("section.icon.contains"))
        XCTAssertFalse(bar.contains("Text(section.icon)"))
        XCTAssertTrue(data.contains("icon: \"face.smiling\""))
        XCTAssertTrue(data.contains("icon: \"person\""))
        XCTAssertTrue(data.contains("icon: \"leaf\""))
        XCTAssertFalse(data.contains("icon: \":)\""))
    }

    func testSharedBottomBarUsesNativeMicrophoneReturnButton() throws {
        let source = try read("DictusKeyboard/Views/AuxiliaryBottomBar.swift")

        XCTAssertTrue(source.contains("layout.auxiliaryMicrophoneFrame"))
        XCTAssertFalse(source.contains("Text(\"|\")"))
        XCTAssertTrue(source.contains("width: 44, height: 44"))
        XCTAssertTrue(source.contains("Return to voice keyboard"))
        XCTAssertTrue(source.contains("glassEffect(.regular.interactive(), in: shape)"))
        XCTAssertTrue(source.contains("layout.leftUtilityFrames"))
    }

    func testEmojiRecentsCategoryUsesNativeClockSymbol() throws {
        let source = try read("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(source.contains("name: \"Recents\""))
        XCTAssertTrue(source.contains("icon: \"clock\""))
        XCTAssertFalse(source.contains("name: \"Recents\", icon: \"R\""))
    }

    func testEmojiCategoryLaneHasAnExplicitBottomAlignedContainer() throws {
        let source = try read("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(source.contains(".frame(width: availableWidth, height: availableHeight)"))
        XCTAssertTrue(source.contains("EmojiCategoryBar("))
        XCTAssertTrue(source.contains("let categoryBarHeight: CGFloat = 44"))
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

        XCTAssertTrue(source.contains("controls.isUserInteractionEnabled = !isAuxiliary"))
        XCTAssertTrue(source.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
    }

    func testAuxiliaryUIKitControlsAreHiddenDisabledAndNonInteractive() throws {
        let source = try read("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(source.contains("controls.isHidden = isAuxiliary"))
        XCTAssertTrue(source.contains("controls.isUserInteractionEnabled = !isAuxiliary"))
        XCTAssertTrue(source.contains("$0.isHidden = true"))
        XCTAssertTrue(source.contains("$0.isEnabled = false"))
        XCTAssertTrue(source.contains("$0.isUserInteractionEnabled = false"))
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

        XCTAssertTrue(source.contains("let inputViewHeight = inputView?.bounds.height ?? 0"))
        XCTAssertTrue(source.contains("VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight("))
        XCTAssertTrue(source.contains("inputViewHeight: Double(inputViewHeight)"))
        XCTAssertTrue(source.contains("controllerViewHeight: view.bounds.height > 0 ? Double(view.bounds.height) : nil"))
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
