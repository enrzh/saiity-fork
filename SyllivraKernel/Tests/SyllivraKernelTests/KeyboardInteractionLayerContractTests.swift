import XCTest

final class KeyboardInteractionLayerContractTests: XCTestCase {
    func testMaterialChangesAreExplicitInputsToEveryNativeVisualHost() throws {
        let style = try source("DictusKeyboard/KeyboardKeyStyle.swift")
        XCTAssertTrue(style.contains("@Environment(\\.keyboardLiquidGlassEnabled)"))
        XCTAssertTrue(style.contains("if !liquidGlassEnabled || (role != .board && role != .popup) {"))
        for path in ["DictusKeyboard/Next/KeyboardSurfaceView.swift",
                     "DictusKeyboard/Next/NextKeyboardHost.swift",
                     "DictusKeyboard/Views/KeyVariantPopup.swift"] {
            let visual = try source(path)
            XCTAssertTrue(visual.contains("liquidGlassEnabled: Bool") || visual.contains("var liquidGlassEnabled ="), path)
            XCTAssertTrue(visual.contains(".environment(\\.keyboardLiquidGlassEnabled, liquidGlassEnabled)"), path)
        }
        let category = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        XCTAssertFalse(category.contains("keyboardGlass(in: Capsule())"))
        XCTAssertFalse(category.contains(".glassEffect("), "categories must not remain permanently glass in Solid mode")
        let native = try source("DictusKeyboard/KeyboardKeyInput.swift")
        XCTAssertTrue(native.contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
        XCTAssertTrue(native.contains("plate.effect = UIGlassEffect(style: .regular)"))
        XCTAssertTrue(native.contains("plate.isUserInteractionEnabled = false"))
    }

    func testLiveBarsAndBlankEmojiHaveStableNativeOwnersInBothMaterials() throws {
        let surface = try source("DictusKeyboard/Next/KeyboardSurfaceView.swift")
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let style = try source("DictusKeyboard/KeyboardKeyStyle.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(surface.contains("addSubview(bottomBar)"))
        XCTAssertTrue(bar.contains("let period = KeyboardPeriodKeyView()"))
        XCTAssertTrue(bar.contains("addSubview(period)"))
        XCTAssertFalse(picker.contains("blankCanvas"))
        XCTAssertFalse(picker.contains("EmojiBlankPanControl"))
        XCTAssertTrue(try source("DictusKeyboard/InputView.swift").contains("var nativeTouchOwners: [UIView] = []"))
        XCTAssertTrue(controller.contains("nativeTouchOwners = ["))
        XCTAssertTrue(style.contains("content.background {\n            plate(Color.clear).allowsHitTesting(false)"),
                      "a material must never disable the content's native targets")
        XCTAssertFalse(controller.contains("forwardHitTest"))
        XCTAssertTrue(controller.contains("hostingController?.view.isUserInteractionEnabled = true"))
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(root.contains(".environment(\\.keyboardLiquidGlassEnabled, KeyboardInteractionPreferences.liquidGlassEnabled)\n        .allowsHitTesting(false)"),
                      "the visual SwiftUI tree is non-hittable without disabling its UIKit host")
        XCTAssertTrue(controller.contains("recoveryButton?.isHidden = !recoveryVisible"))
        XCTAssertFalse(controller.contains("recoveryButton?.frame = .zero"))
        XCTAssertTrue(controller.contains("onOpen?()"))
    }

    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    func testLiveGridUsesPopupSettingWithoutChangingTouchOwnership() throws {
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        let previews = try source("DictusKeyboard/Views/KeyVariantPopup.swift")
        XCTAssertTrue(grid.contains("KeyboardInteractionPreferences.keyPopupMode.showsPreview"))
        XCTAssertTrue(grid.contains("KeyPressPreviewHost(session: .constant(session), identity:"))
        XCTAssertFalse(grid.contains("UIColor.secondarySystemBackground.setFill()"),
                       "the live preview must not paint an opaque UIKit plate")
        XCTAssertTrue(previews.contains("KeyPreviewPopup(text: preview.text"))
        XCTAssertTrue(previews.contains("KeyPopoutPreview("))
        XCTAssertTrue(previews.contains(".keyboardGlass("),
                      "popup and popout follow the same material setting as the key faces")
        XCTAssertTrue(grid.contains("updateVariantPopup()"))
        XCTAssertTrue(grid.contains("UIHostingController(rootView: popup)"),
                      "disabling ordinary previews must not disable accent choices")
        XCTAssertTrue(grid.contains("previewOwner = identity"))
    }

    func testLivePagesCarryBothKindsOfHoldVariantsAndKeepCommandFaces() throws {
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        let host = try source("DictusKeyboard/Next/NextKeyboardHost.swift")
        XCTAssertTrue(factory.contains("KeyboardVariantPreferences.options(for: value, kind: .symbol)"))
        XCTAssertTrue(factory.contains("KeyboardVariantPreferences.options(for: value, kind: .letter)"))
        XCTAssertTrue(factory.contains("symbolVariants: true"))
        XCTAssertTrue(factory.contains("systemImage: CommandKeyStyle.deleteSymbolName"))
        XCTAssertTrue(grid.contains("press.popupWork?.cancel()"))
        XCTAssertTrue(grid.contains("guard popupOwner == identity, var press = presses[identity]"))
        XCTAssertTrue(host.contains("CommandKeyFace(systemName: systemName,"))
        XCTAssertTrue(host.contains("CommandKeyFace(text: label,"),
                      "grid commands must use the same face as Emoji and the bottom bar")
        XCTAssertTrue(grid.contains("if item.key.isCommand, onCommandFacesChanged != nil { return }"),
                      "the grid must not paint a duplicate command face")
        XCTAssertTrue(grid.contains("guard specs != publishedCommandSpecs else { return }"),
                      "ordinary letters must not rebuild hosted command faces")
        XCTAssertTrue(grid.contains("let labelPlate = item.key.isCommand"),
                      "command glyphs must sit in the visible plate, not the wider hit cell")
        XCTAssertTrue(host.contains("gridView.refreshAppearance()"),
                      "returning from emoji must restore plates on an unchanged page")
    }

    func testSymbolPageToggleUsesTheSharedBottomBarLabelStyle() throws {
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        let face = try source("DictusKeyboard/KeyboardKeyStyle.swift")
        XCTAssertTrue(factory.contains("glyphSize: CommandKeyStyle.textSize"))
        XCTAssertTrue(factory.contains("glyphWeight: CommandKeyStyle.glyphWeight"))
        XCTAssertTrue(face.contains("textPointSize: CGFloat = CommandKeyStyle.textSize"))
    }

    func testLiveGridRebuildsForLayoutButNotVisualPreferences() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let host = try source("DictusKeyboard/Next/NextKeyboardHost.swift")
        let preference = try source("SyllivraKernel/Sources/SyllivraKernel/KeyboardLayoutPreference.swift")
        XCTAssertTrue(controller.contains("refreshVisibleKeyboardLayoutIfNeeded()"))
        XCTAssertTrue(controller.contains("language != lastTypingLanguage || layout != lastTypingLayout"))
        XCTAssertTrue(host.contains("func refreshKeyLayout()"))
        XCTAssertTrue(host.contains("next = aligned(KeyGridPageFactory.letters())"))
        XCTAssertTrue(host.contains("guard next.fingerprint != current.fingerprint"))
        XCTAssertTrue(host.contains("KeyGridPlacement.alignLastRow("))
        XCTAssertTrue(preference.contains("KeyboardInteractionPreferences.notifyChanged()"))
    }

    func testGlassPlatesDoNotGlideBetweenKeyboardPages() throws {
        let host = try source("DictusKeyboard/Next/NextKeyboardHost.swift")
        XCTAssertTrue(host.contains("transaction.disablesAnimations = true"))
        XCTAssertTrue(host.contains(".id(pageID)"),
                      "page changes must replace the glass subtree without interpolating plates")
        XCTAssertTrue(host.contains(".position(x: spec.rect.midX, y: spec.rect.midY)"))
        XCTAssertFalse(host.contains("glassFallbacks"),
                       "opaque backing beneath live glass darkens every key")
    }

    func testEveryGlassHostStartsTransparentAtItsFinalFrame() throws {
        let host = try source("DictusKeyboard/Next/NextKeyboardHost.swift")
        let shared = try source("DictusKeyboard/KeyboardKeyInput.swift")
        XCTAssertTrue(host.contains("private var glassHost: UIHostingController<GlassPlates>?"),
                      "one hosted layer must serve the whole grid instead of one host per key")
        XCTAssertTrue(shared.contains("host.safeAreaRegions = []"))
        XCTAssertTrue(shared.contains("host.view.backgroundColor = .clear"))
        XCTAssertTrue(shared.contains("host.view.isOpaque = false"))
        XCTAssertTrue(shared.contains("host.view.isUserInteractionEnabled = false"))
        let addChild = try XCTUnwrap(shared.range(of: "parent.addChild(host)"))
        let addView = try XCTUnwrap(shared.range(of: "container.addSubview(host.view)", range: addChild.upperBound..<shared.endIndex))
        let didMove = try XCTUnwrap(shared.range(of: "host.didMove(toParent: parent)"))
        XCTAssertLessThan(addChild.lowerBound, addView.lowerBound)
        XCTAssertLessThan(addView.lowerBound, didMove.lowerBound)
        for path in ["DictusKeyboard/Next/NextKeyboardHost.swift",
                     "DictusKeyboard/Next/KeyboardSurfaceView.swift"] {
            XCTAssertTrue(try source(path).contains("attachKeyboardVisualController("), path)
        }
        XCTAssertFalse(host.contains("GlassPlateView"))
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        XCTAssertFalse(bar.contains("private var chrome: UIHostingController"))
        XCTAssertTrue(bar.contains("firstControl.keyboardFace.configure("))
        XCTAssertTrue(shared.contains("control.existingKeyboardFace") || shared.contains("var existingKeyboardFace:"))
    }

    func testPeriodUsesOneNativeTargetAboveTheSharedBottomBar() throws {
        let host = try source("DictusKeyboard/Next/NextKeyboardHost.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        let surface = try source("DictusKeyboard/Next/KeyboardSurfaceView.swift")
        XCTAssertFalse(root.contains("showsPeriodKey"))
        XCTAssertTrue(controller.contains("fieldKeys: KeyboardState.shared.hostLetterFieldKeys"))
        XCTAssertTrue(surface.contains("bottomBar.show(next, layout: layout, inputHeight: inputHeight, fieldKeys: fieldKeys)"))
        XCTAssertTrue(controller.contains("surface.period.onInsert = { [weak self] in self?.routeProxyText($0) }"))
        XCTAssertTrue(surface.contains("let bottomBar = KeyboardBottomBarView()"))
        XCTAssertTrue(bar.contains("let period = KeyboardPeriodKeyView()"))
        XCTAssertTrue(bar.contains("period.isHidden = mode != .letters || self.fieldKeys.rightInsert != nil"))
        XCTAssertFalse(surface.contains("keyContainersEnabled"), "the bottom-bar period always keeps its plate")
        XCTAssertTrue(surface.contains("onInsert?(\".\")"))
        XCTAssertTrue(surface.contains("onDelete?()"))
        XCTAssertTrue(surface.contains("let control = KeyboardKeyTouchControl()"))
        XCTAssertTrue(surface.contains("plate.isUserInteractionEnabled = false"))
        XCTAssertFalse(surface.contains("KeyboardNativeSurfaceHost"),
                       "the native period must not be reparented from SwiftUI")
        XCTAssertTrue(bar.contains("nativeMode: .letters"))
        XCTAssertTrue(bar.contains("periodInserted = true\n        onPeriod(\".\")"))
        XCTAssertTrue(bar.contains("onDelete()\n        onPeriod(variant)"))
        XCTAssertFalse(host.contains("periodControl"), "there must be only one period implementation")
        XCTAssertTrue(controller.contains("frame: layout.inputFrame(frame, inputViewHeight: inputView.bounds.height)"),
                      "the native grid and hosted bottom bar must use the same origin")
        XCTAssertTrue(host.contains("guard gridView.superview != nil || glassLayer.superview != nil"),
                      "idle page refreshes must not repeatedly unmount an already detached grid")
    }

    func testEmojiBlankSpaceReachesNativePagerBeforeHostedSurface() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let input = try source("DictusKeyboard/InputView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let mount = try source("DictusKeyboard/KeyboardKeyInput.swift")
        let surface = try source("DictusKeyboard/Next/KeyboardSurfaceView.swift")
        XCTAssertTrue(controller.contains("let surface = KeyboardSurfaceView(frame: inputView.bounds)"))
        XCTAssertTrue(controller.contains("inputView.addSubview(surface)"))
        XCTAssertTrue(input.contains("weak var emojiPager: UIView?"))
        XCTAssertFalse(controller.contains("kbInputView.priorityHitTest ="))
        XCTAssertTrue(surface.contains("let emoji = EmojiPagerView()"))
        XCTAssertTrue(surface.contains("addSubview(emojiCategory)"))
        XCTAssertTrue(surface.contains("addSubview(emojiDelete)"))
        XCTAssertFalse(surface.contains("emojiDeleteRegion"),
                       "Emoji Delete belongs to the board, not a passthrough root overlay")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertFalse(root.contains("KeyboardNativeOverlay("))
        XCTAssertTrue(surface.contains("for owner in [emojiDelete, bottomBar, emoji, emojiCategory]"))
        XCTAssertFalse(surface.contains("super.hitTest(point, with: event)"))
        XCTAssertTrue(picker.contains("final class EmojiPagerView: EmojiPagerCollectionView"))
        XCTAssertTrue(picker.contains("dataSource = coordinator"))
        XCTAssertTrue(picker.contains("KeyboardNativeSurfaceHost(surface: view, requiredMode: .emoji)"))
        XCTAssertTrue(picker.contains("host.surface.cancelVariantSelection()"))
        XCTAssertTrue(picker.contains("scrollViewDidEndDragging("),
                      "blank-area pan should remain native free scrolling")
        XCTAssertFalse(picker.contains("vertical.isUserInteractionEnabled = !page.items.isEmpty"),
                       "empty Recents must stay in the pager hit hierarchy")
        XCTAssertFalse(picker.contains("horizontal.isUserInteractionEnabled = !page.items.isEmpty"))
    }

    func testNativeSurfacesSharePlacementAndReleaseTheirOwnRegistrations() throws {
        let mount = try source("DictusKeyboard/KeyboardKeyInput.swift")
        let input = try source("DictusKeyboard/InputView.swift")
        let bridgeStart = try XCTUnwrap(mount.range(of: "final class KeyboardNativeSurfaceHost"))
        let bridgeEnd = try XCTUnwrap(mount.range(of: "struct KeyboardNativeOverlay"))
        let bridge = String(mount[bridgeStart.lowerBound..<bridgeEnd.lowerBound])
        XCTAssertFalse(bridge.contains("isUserInteractionEnabled = false"),
                       "the hosted hit map must not exclude the marker's blank area")
        XCTAssertTrue(bridge.contains("surface.hitTest(surface.convert(point, from: self), with: event)"),
                      "hosted and root hits must reach the same native owner")
        XCTAssertTrue(bridge.contains("hostedOwns=\\(hostedOwns)"),
                      "the on-device probe must check the hosted route as well as the root shortcut")
        XCTAssertTrue(mount.contains("let rect = convert(bounds, to: input)"))
        XCTAssertTrue(mount.contains("input.addSubview(surface)"))
        XCTAssertTrue(mount.contains("surface.isHidden = KeyboardState.shared.areaMode != requiredMode"))
        XCTAssertTrue(mount.contains("if input.periodKey === surface { input.periodKey = nil }"))
        XCTAssertTrue(mount.contains("if input.emojiPager === surface { input.emojiPager = nil }"))
        XCTAssertTrue(mount.contains("host.surface.cancelInteraction()"))
        XCTAssertTrue(mount.contains("registersInput: false, layerPosition: 300"),
                      "floating chrome must not replace the pager's native registration")
        XCTAssertTrue(mount.contains("hitRect.contains(point)"),
                      "the overlay's clear canvas must not swallow blank swipes or bottom-bar taps")
        XCTAssertTrue(input.contains("for mount in nativeMounts.allObjects"),
                      "an ancestor-frame change must update native placement even if the local size is unchanged")
    }

    func testRebuiltPagesDeactivateLegacyTouchOwner() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("let nextGridOwnsInput = Self.nextKeyboardModes.contains(mode)"))
        XCTAssertTrue(controller.contains("keyGridOwner?.isUserInteractionEnabled = !nextGridOwnsInput"))
        XCTAssertTrue(controller.contains("if nextGridOwnsInput {\n            KeyGridTouchBus.deactivate()"))
    }

    func testEmojiPagerIsNotBehindTheVoiceOverlay() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("let overlayVisible = true"))
        XCTAssertFalse(controller.contains("forwardHitTest"), "accessory misses must use ordinary native sibling hit testing")
        XCTAssertTrue(controller.contains("inputView.addSubview(surface)"))
        XCTAssertFalse(controller.contains("inputView.addSubview(categoryScrubber)"),
                       "the category control must stay inside the same native Emoji board")
    }

    func testEverySurfaceUsesSharedKeyGeometryAndMaterialIsDecorative() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let plates = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        let style = try source("DictusKeyboard/KeyboardKeyStyle.swift")
        let chrome = try source("DictusKeyboard/KeyboardChrome.swift")
        let input = try source("DictusKeyboard/KeyboardKeyInput.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")

        XCTAssertFalse(root.contains("LetterKeyboardSurface("))
        XCTAssertFalse(root.contains("NumberKeyboardSurface("))
        XCTAssertFalse(root.contains("SymbolKeyboardSurface("))
        XCTAssertTrue(input.contains("final class KeyboardKeyTouchControl"))
        XCTAssertTrue(input.contains("bounds.contains(point)"))
        XCTAssertFalse(controller.contains("interactiveTarget(in:"))
        XCTAssertFalse(plates.contains("keyHitFrames"))
        XCTAssertTrue(style.contains("opacity(KeyboardInteractionPreferences.keyContainersEnabled ? 1 : 0)"))
        XCTAssertTrue(style.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(chrome.contains(".allowsHitTesting(!voiceBoardUsesUIKitHits)"))
        XCTAssertTrue(factory.contains("static func letters() -> KeyGridPage"))
        XCTAssertTrue(factory.contains("static func symbols(_ page: Page) -> KeyGridPage"))
        XCTAssertTrue(factory.contains("static func numberPad(style: HostFieldPolicy.NumberPadStyle) -> KeyGridPage"))
        XCTAssertTrue(grid.contains("final class KeyGridView: UIView"))
        XCTAssertTrue(grid.contains("override func touchesBegan("),
                      "the key grid must own its own touches")
        XCTAssertTrue(grid.contains("KeyGridPlacement.solve("),
                      "hit targets must come from the shared geometry, which tiles the grid contiguously")
        XCTAssertFalse(grid.contains("ForEach(frames)"),
                       "the key grid must not draw a second set of SwiftUI key faces")
        XCTAssertTrue(controller.contains("NextKeyboardHost()"),
                      "the controller must host the key grid on the input view")
        XCTAssertFalse(controller.contains("LetterKeyGridView"),
                       "the legacy letter grid is deleted; the controller must not name it at all")
        XCTAssertFalse(grid.contains("NumberInteractionOverlay"))
        XCTAssertFalse(grid.contains("SymbolInteractionOverlay"))
        XCTAssertFalse(root.contains("GiellaKeyboardView("))
    }

    func testLegacyGiellaKeyboardViewIsNotInstalledAtRuntime() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(controller.contains("GiellaKeyboardView("))
        XCTAssertFalse(controller.contains("installLetterKeyboard("))
        XCTAssertFalse(controller.contains("giellaKeyboard"))
        XCTAssertFalse(controller.contains("GiellaKeyboardViewDelegate"))
    }

    func testKeyboardInteractionLayerKeepsVoiceOnlyPolicyAsGeometrySource() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let surfaces = try [
            source("DictusKeyboard/Next/NextKeyboardHost.swift"),
            source("DictusKeyboard/Next/KeyboardSurfaceView.swift"),
            source("DictusKeyboard/VoiceBoardSurface.swift"),
            source("SyllivraKernel/Sources/SyllivraKernel/NextKeyGridPlacement.swift")
        ]

        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.layout("))
        XCTAssertTrue(controller.contains("VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight("))
        XCTAssertTrue(controller.contains("VoiceOnlyKeyboardPolicy.layout("))
        for surface in surfaces {
            XCTAssertTrue(surface.contains("VoiceOnlyKeyboardPolicy."))
        }
    }
}
