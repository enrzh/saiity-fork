import XCTest
@testable import DictusCore

final class KeyboardRegressionTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
        return try paths.map { try source($0) }.joined(separator: "\n")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    func testLetterPageDoesNotCommitSwipeTyping() throws {
        let root = try source("DictusKeyboard/LetterKeyboardSurface.swift")
        let grid = try source("DictusKeyboard/LetterKeyGridView.swift")
        XCTAssertFalse(root.contains("swipeWord"))
        XCTAssertFalse(root.contains("SwipeTypingDecoder"))
        XCTAssertFalse(grid.contains("swipeWord"))
        // Hold-for-accents stays on the letter page; swipe is not wired there. The
        // gesture now lives in the UIKit grid, so that is where the assertion belongs.
        XCTAssertTrue(grid.contains("override func touchesMoved("),
                      "hold-for-accents stays on the letter page; swipe is not wired there")
        XCTAssertTrue(grid.contains("KeyVariantPopup.selectedIndex("),
                      "the accent popup must follow the finger on the letter page")
        let engine = try source("DictusKeyboard/TextPrediction/TextPredictionEngine.swift")
        XCTAssertTrue(engine.contains("func swipeWord(from path: String)"))
        let settings = try source("DictusApp/Views/SettingsView.swift")
        XCTAssertTrue(settings.contains("LastDictationIssueReportView()"))
        XCTAssertFalse(settings.contains("DragGesture(minimumDistance: 0)"))
    }

    func testLetterSurfaceAddsARealPeriodKeyWithSharedHoldRouting() throws {
        let root = try source("DictusKeyboard/LetterKeyboardSurface.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")

        XCTAssertTrue(root.contains("periodFrame: surfaceLayout.letterPeriodFrame"))
        XCTAssertTrue(root.contains("showsPeriodKey: true"))
        XCTAssertTrue(layouts.contains("KeyDefinition(type: .fullStop"))
        XCTAssertTrue(bar.contains("ImmediateVariantKey("))
        XCTAssertTrue(bar.contains("SymbolKeyVariants.options(for: \".\")"))
    }

    func testEmojiSelectionDoesNotCloseThePicker() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(root.contains("routeText(emoji)"))
        XCTAssertFalse(root.contains("routeText(emoji)\n                    state.closeArea()"))
    }

    func testSymbolPageDoesNotPlaceACompetingDragGestureAboveTapButtons() throws {
        let root = try source("DictusKeyboard/SymbolKeyboardSurface.swift")
        let pageStart = try XCTUnwrap(root.range(of: "struct SymbolKeyboardSurface"))
        let keyStart = try XCTUnwrap(root.range(of: "private struct LiquidSymbolKey"))
        let page = String(root[pageStart.lowerBound..<keyStart.lowerBound])

        XCTAssertFalse(page.contains(".simultaneousGesture(symbolDragGesture(frames: frames))"))
        XCTAssertFalse(page.contains(".simultaneousGesture(symbolPointerGesture(frames: frames))"),
                       "the grid must not commit a second action after a key-owned hold")
        // Variant tracking now runs through the shared UIKit owner's callbacks
        // rather than a control per key, so the page carries handlers instead.
        XCTAssertTrue(page.contains(".keyGridInput("))
        XCTAssertTrue(page.contains("refreshedGridHandlers("))
        // The handlers live in the shared-owner section, which sits before the key
        // builder rather than inside it.
        XCTAssertTrue(root.contains("private func handleGridMove("),
                      "variant tracking must update selection while the finger moves")
    }

    func testLetterAndSymbolPlatesKeepNativeGaps() throws {
        let root = try source("DictusKeyboard/LetterKeyboardSurface.swift")
        let symbols = try source("DictusKeyboard/SymbolKeyboardSurface.swift")
        // Solved rows are zipped against the key rows, so the drawn plate and the
        // hit cell arrive as a matched pair rather than being indexed independently.
        XCTAssertTrue(root.contains("visualFrame: pair.1"),
                      "plates must use the original key frames, not the gap-absorbed hit cells")
        XCTAssertTrue(root.contains("frame: pair.0"),
                      "the hit cell must come from the solved hit row")
        XCTAssertFalse(root.contains("visualFrame: rowHits[columnIndex]"),
                       "drawing on hit cells makes every key the same size and removes native gaps")
        XCTAssertTrue(root.contains("KeyboardKeyHitGeometry.frames("))
        // The press highlight is now drawn by the surface from the press state the
        // touch owner reports, sized to the drawn plate rather than the hit cell.
        XCTAssertTrue(root.contains("if pressedKeyIDs.values.contains(keyID)"),
                      "press feedback must be driven by the touch owner")
        XCTAssertTrue(root.contains(".frame(width: visualFrame.width, height: visualFrame.height)"),
                      "press highlights must match the drawn plate, not the hit cell")
        XCTAssertTrue(symbols.contains("visualFrame: pair.1"))
        XCTAssertTrue(symbols.contains("frame: pair.0"))
        XCTAssertFalse(symbols.contains("visualFrame: rowHits[columnIndex]"))
    }

    func testSymbolButtonsUseAStableNativeTapSurface() throws {
        let root = try source("DictusKeyboard/SymbolKeyboardSurface.swift")
        let start = try XCTUnwrap(root.range(of: "private func symbolKey"))
        let end = try XCTUnwrap(root.range(of: "private func insertVariants"))
        let body = String(root[start.lowerBound..<end.lowerBound])

        // Symbol keys are faces only now; the shared UIKit owner resolves the touch
        // and the surface supplies the press/move/release behaviour.
        XCTAssertFalse(body.contains("ImmediateVariantKey("),
                       "symbol keys must not install a control per key")
        XCTAssertFalse(body.contains("ImmediateKeyButton("),
                       "symbol keys must not install a control per key")
        XCTAssertTrue(body.contains(".frame(width: frame.width, height: frame.height)"))
        XCTAssertTrue(body.contains("pressedKeyIDs.values.contains(keyID)"),
                      "press feedback comes from the owner, so a rebuilt key keeps its highlight")
        XCTAssertTrue(root.contains("private func handleGridPress("),
                      "press behaviour must be reachable from the owner's callback")
        XCTAssertTrue(root.contains("private func handleGridMove("),
                      "accent drag must be reachable from the owner's callback")
        XCTAssertTrue(root.contains("private func handleGridRelease("),
                      "release behaviour must be reachable from the owner's callback")
    }

    func testLanguageIndicatorShowsBareOutputCode() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(root.contains("return target.shortCode"))
        XCTAssertFalse(root.contains("return \"->\\(target.shortCode)\""))
    }

    func testVariantPopupDisablesImplicitSelectionAnimation() throws {
        let popup = try source("DictusKeyboard/Views/KeyVariantPopup.swift")
        XCTAssertTrue(popup.contains("transaction.animation = nil"))
        XCTAssertTrue(popup.contains(".keyboardGlass("),
                      "key popups use the same plate as the keys")
        XCTAssertFalse(popup.contains("KeyboardInteractionPreferences.liquidGlassEnabled"),
                       "popup material must not fork away from KeyboardGlassSurface")
        XCTAssertTrue(popup.contains("cornerRadius"))
        XCTAssertFalse(popup.contains("fill(Color(uiColor: .systemBackground))"))
        XCTAssertTrue(popup.contains("struct KeyPreviewPopup"),
                      "press previews sit above keys when Key popups is popup")
        XCTAssertTrue(popup.contains("struct KeyPopoutPreview"),
                      "popout enlarges from the pressed key and fades")
        XCTAssertTrue(popup.contains("struct KeyPressPreviewHost"))
        XCTAssertTrue(popup.contains("static let expansionScale: CGFloat = 1.55"),
                      "popout geometry uses one shared scale for layout and rendering")
    }

    func testKeyPopupsMayCrossTheGlassSurfaceButStayInsideTheKeyboardEdge() throws {
        let popup = try source("DictusKeyboard/Views/KeyVariantPopup.swift")

        XCTAssertTrue(
            popup.contains("topOverflow: CGFloat = 0"),
            "popup geometry must accept the amount of surface overflow available"
        )
        XCTAssertTrue(
            popup.contains("let topBoundary = -max(0, topOverflow)"),
            "the top boundary must be the keyboard edge, not the glass surface"
        )
        XCTAssertTrue(
            popup.contains("let bottomBoundary = max(topBoundary, bounds.height - size.height - 4)"),
            "popup clamping must still respect the lower keyboard canvas limit"
        )
        XCTAssertTrue(
            popup.contains("source.width * expansionScale") &&
                popup.contains("source.height * expansionScale"),
            "popout previews reserve their transformed size before rendering"
        )

        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("topOverflow: CGFloat(surfaceLayout.surfaceFrame.minY)"))
        XCTAssertTrue(root.contains("popupTopOverflow: CGFloat(layout.surfaceFrame.minY)"))
    }

    func testKeyPopupSurfaceStacksAboveSuggestionBarControls() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(
            root.contains(".position(x: surfaceFrame.midX, y: surfaceFrame.midY)\n                    // Popups may extend into the suggestion lane. Keep the\n                    // entire surface above that lane's controls so the popup\n                    // is visible without changing the controls' hit targets.\n                    .zIndex(3)"),
            "the popup surface must outrank the suggestion bar's zIndex"
        )
        XCTAssertTrue(root.contains(".zIndex(2)"),
                      "the suggestion bar keeps a lower explicit stacking level")
    }

    func testEmojiTapCannotBeRejectedByAStaleDragAxis() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let start = try XCTUnwrap(picker.range(of: "@objc private func tapped()"))
        let end = try XCTUnwrap(picker.range(of: "// MARK: - Supporting types"))
        let tap = String(picker[start.lowerBound..<end.lowerBound])
        let ownerStart = try XCTUnwrap(picker.range(of: "private final class EmojiPagerCollectionView"))
        let ownerEnd = try XCTUnwrap(picker.range(of: "private final class EmojiPageCell"))
        let owner = String(picker[ownerStart.lowerBound..<ownerEnd.lowerBound])

        XCTAssertFalse(picker.contains("emojiDragAxis"),
                      "a normal emoji tap must still commit if a prior drag left transient state")
        XCTAssertTrue(tap.contains("suppressNextTap"),
                      "only a recognized variant hold may suppress the base tap")
        XCTAssertTrue(tap.contains("onTap?(item.emoji)"))
        XCTAssertTrue(picker.contains("onTap: insertEmoji"))
        XCTAssertTrue(picker.contains("onTap: { [weak self] emoji in self?.onTap?(emoji) }"))
        XCTAssertTrue(picker.contains("button.onTap = onTap"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("cancelsTouchesInView = false"),
                      "the pager hold must not cancel blank-area paging")
        let releaseStart = try XCTUnwrap(owner.range(of: "case .ended:"))
        let cancelStart = try XCTUnwrap(owner.range(of: "case .cancelled, .failed:"))
        let release = String(owner[releaseStart.lowerBound..<cancelStart.lowerBound])
        XCTAssertTrue(release.contains("let session = variantSession\n            cancelVariantSelection()"),
                      "consume the held selection before invoking the insertion callback")
        XCTAssertTrue(release.contains("session.options.indices.contains(session.selectedIndex)"))
        XCTAssertEqual(release.components(separatedBy: "onEmojiInsert?(").count - 1, 1)
        let cancelEnd = try XCTUnwrap(owner.range(of: "default:", range: cancelStart.upperBound..<owner.endIndex))
        let cancelled = String(owner[cancelStart.lowerBound..<cancelEnd.lowerBound])
        XCTAssertTrue(cancelled.contains("cancelVariantSelection()"))
        XCTAssertFalse(cancelled.contains("onEmojiInsert"))
        XCTAssertTrue(owner.contains("variantSession = nil"))
        XCTAssertFalse(owner.contains("panGestureRecognizer.isEnabled = true"),
                       "the active pager pan must not be reset during hold cleanup")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer)"),
                      "an active emoji popup must not be cancelled by the scroll view")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("if state == .began || state == .changed { return false }"),
                      "the hold recognizer owns movement after the popup appears")
        let updateStart = try XCTUnwrap(picker.range(of: "func updateUIView"))
        let updateEnd = try XCTUnwrap(picker.range(of: "private func hideTopEdgeEffect",
                                                   range: updateStart.upperBound..<picker.endIndex))
        let update = String(picker[updateStart.lowerBound..<updateEnd.lowerBound])
        XCTAssertFalse(update.contains("cancelVariantSelection()"),
                       "a SwiftUI refresh must not dismiss a stationary emoji popup")
        let layoutStart = try XCTUnwrap(owner.range(of: "override func layoutSubviews()"))
        let layoutEnd = try XCTUnwrap(owner.range(of: "onLayoutReady?()",
                                                  range: layoutStart.upperBound..<owner.endIndex))
        let layout = String(owner[layoutStart.lowerBound..<layoutEnd.upperBound])
        XCTAssertFalse(layout.contains("cancelVariantSelection()"),
                       "a pager layout pass must not dismiss a stationary emoji popup")
        let scrollStart = try XCTUnwrap(picker.range(of: "func scroll(to request:"))
        let scrollEnd = try XCTUnwrap(picker.range(of: "func retryPendingScroll", range: scrollStart.upperBound..<picker.endIndex))
        let scroll = String(picker[scrollStart.lowerBound..<scrollEnd.lowerBound])
        XCTAssertFalse(scroll.contains("cancelVariantSelection()"),
                       "programmatic pager updates must not dismiss a live popup")
    }

    func testLeftUtilityGapsUseOneSharedSpacingValue() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390, controlOrder: .emojiFirst)
        let frames = layout.leftUtilityFrames

        XCTAssertEqual(frames.emoji.minY - frames.at.maxY,
                       VoiceOnlyKeyboardPolicy.railSpacing,
                       accuracy: 0.001)
        XCTAssertEqual(frames.number.minX - frames.emoji.maxX,
                       VoiceOnlyKeyboardPolicy.railSpacing,
                       accuracy: 0.001)
    }

    func testSurfaceFallbackRestoresExtendedHeight() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeightScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight,
                       VoiceOnlyKeyboardPolicy.nativePortraitReferenceHeight
                        * VoiceOnlyKeyboardPolicy.surfaceHeightScale,
                       accuracy: 0.001)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight,
                       216,
                       accuracy: 0.001)
    }

    func testRuntimeHeightAppliesTheTenPercentScaleToTheNativeProvider() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("KeyboardHeightProvider.height"))
        XCTAssertTrue(controller.contains("VoiceOnlyKeyboardPolicy.surfaceHeightScale"))
        XCTAssertTrue(controller.contains("VoiceOnlyKeyboardPolicy.horizontalExpansionScale"))
        XCTAssertTrue(controller.contains("* CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeightScale)"))
        XCTAssertTrue(controller.contains("* CGFloat(expansion)"))
        XCTAssertFalse(controller.contains("heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight)"))
    }

    func testDictateControlStartsAndStopsFromBothUIKitAndSwiftUI() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let state = try source("DictusKeyboard/KeyboardState.swift")
        XCTAssertTrue(controller.contains("handleMicPressBegan()"))
        XCTAssertTrue(controller.contains("handleMicPressEnded()"))
        XCTAssertTrue(controller.contains("micButton?.isEnabled = false"))
        XCTAssertTrue(controller.contains("micButton?.isUserInteractionEnabled = false"))
        XCTAssertTrue(controller.contains("micButton?.frame = .zero"))
        XCTAssertTrue(state.contains("func handleMicPressBegan()"))
        XCTAssertTrue(state.contains("func handleMicPressEnded()"))
        let voice = try source("DictusKeyboard/VoiceBoardSurface.swift")
        let start = try XCTUnwrap(voice.range(of: "private func dictateButton(frame:"))
        let end = try XCTUnwrap(voice.range(of: "private func dictationControlVisual",
                                           range: start.upperBound..<voice.endIndex))
        let dictateButton = String(voice[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(dictateButton.contains("openDictusForRecovery"),
                       "the dictate control must not open sAiity; that is the recovery control's job")
        XCTAssertFalse(dictateButton.contains("appNeedsAppAction"),
                       "the dictate control must not branch on the app-handoff state")
        XCTAssertTrue(dictateButton.contains("holdDuration: isCancellationStage"),
                      "the dictation-board control must wait for a hold before starting")
        XCTAssertTrue(dictateButton.contains("onHold: isCancellationStage"))
        XCTAssertFalse(dictateButton.contains("onTouchDown: { state.handleMicPressBegan() }"),
                       "a tap must not start dictation on the dictation board")
        XCTAssertTrue(state.contains("dictationReleaseTailDuration"),
                      "release keeps the microphone open for the final-word tail")
        XCTAssertTrue(state.contains("cancelDictationReleaseTail()"),
                      "a new hold cancels the pending release stop")
        XCTAssertFalse(
            controller.contains("guard state.appNeedsAppAction || state.failedRequiresApp else { return false }"),
            "the mic no longer performs the app handoff, so it must not gate on that state"
        )
    }

    func testBackgroundDarwinStartReportsUnavailableWithoutOpeningTheApp() throws {
        let coordinator = try source("DictusApp/DictationCoordinator.swift")
        let start = try XCTUnwrap(coordinator.range(of: "if !fromURL && appState != .active && !audioEngine.isEngineRunning"))
        let end = try XCTUnwrap(coordinator.range(of: "PersistentLog.log(.dictationStarted", range: start.upperBound..<coordinator.endIndex))
        let body = String(coordinator[start.lowerBound..<end.lowerBound])

        XCTAssertFalse(body.contains("pendingColdStartDictation = true"))
        XCTAssertFalse(body.contains("resolvePendingColdStartOnBackground()"),
                       "a background assertion cannot authorize a cold microphone start")
        XCTAssertTrue(body.contains("disposition: .requiresApp"))
    }

    func testHeldDictationNeverAutomaticallyLaunchesAnApp() throws {
        let state = try source("DictusKeyboard/KeyboardState.swift")
        let start = try XCTUnwrap(state.range(of: "func startRecording()"))
        let end = try XCTUnwrap(state.range(of: "private func openModelPreparation()"))
        let recording = String(state[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(recording.contains("DarwinNotificationCenter.post(DarwinNotificationName.startRecording)"))
        XCTAssertTrue(recording.contains("self.refreshFromDefaults()"))
        XCTAssertTrue(recording.contains("failKeyboardStart()"))
        XCTAssertFalse(recording.contains("openDictusURL("))
        XCTAssertFalse(recording.contains("openAppForPendingDictation"))
        XCTAssertFalse(recording.contains("deferRecordingForModelPreparation("))
    }

    func testKeyboardDownDismissesDirectlyOnEveryPage() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let start = try XCTUnwrap(root.range(of: "private func accessoryBar("))
        let end = try XCTUnwrap(root.range(of: "private let preparationURL"))
        let accessory = String(root[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(root.contains("action: routeDismiss"))
        XCTAssertTrue(root.contains("state.closeArea()"))
        XCTAssertTrue(root.contains("Return to dictation board"))
        XCTAssertTrue(accessory.contains("dismissAccessoryButton"))
        XCTAssertTrue(accessory.contains("dictationBoardButton"))
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("dismissButton?.isHidden = false"))
        XCTAssertTrue(controller.contains("voiceBoardButton?.isHidden = !isAuxiliary"))
        XCTAssertTrue(controller.contains("emojiCategoryScrubber"))
        XCTAssertTrue(controller.contains("floatingEmojiCategoryFrame"))
        XCTAssertTrue(controller.contains("selectEmojiCategory(at:"))
        XCTAssertTrue(root.contains("bindEmojiCategoryScrubber()"))
        XCTAssertTrue(root.contains("emojiCategoryJumpToken"))
        XCTAssertTrue(controller.contains("isExclusiveTouch = false"))
        XCTAssertTrue(controller.contains("keyboardWindowAccessoryHeight"))
        XCTAssertTrue(root.contains("accessoryHitSize"))
        let moved = try relocatedKeyboardSource()
        XCTAssertTrue(moved.contains("scaledKeyGeometry"))
        XCTAssertTrue(moved.contains("VoiceOnlyKeyboardPolicy.keySpacing") || moved.contains("geometry.keySpacing"))
        XCTAssertTrue(moved.contains(".letterKeyPlate()"))
        XCTAssertTrue(root.contains(".allowsHitTesting(false)"))
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        let keyStyle = try source("DictusKeyboard/KeyboardKeyStyle.swift")
        XCTAssertTrue(keyStyle.contains("commandKeyPlate"))
        let periodStart = try XCTUnwrap(bar.range(of: "private func periodKey"))
        let periodEnd = try XCTUnwrap(bar.range(of: "private func periodBegan", range: periodStart.upperBound..<bar.endIndex))
        let period = String(bar[periodStart.lowerBound..<periodEnd.lowerBound])
        XCTAssertTrue(period.contains("periodKeyPlateWidth"))
        XCTAssertTrue(period.contains("commandVisualSize"),
                      "the period plate uses the same face height as the bottom-bar keys")
        XCTAssertTrue(period.contains("height: source.height"),
                      "the period hit target stays the full command slot")
        XCTAssertTrue(bar.contains("KeyboardDeleteRepeatControl"))
        XCTAssertTrue(controller.contains("hostingController?.view.isUserInteractionEnabled = true"))
        XCTAssertTrue(controller.contains("boardDeleteButton"))
    }

    func testEmojiPagerCancelsEmojiControlTouchesForHorizontalSwipes() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains("override func touchesShouldCancel(in view: UIView) -> Bool"))
        XCTAssertTrue(picker.contains("filler.isUserInteractionEnabled = false"))
        XCTAssertTrue(picker.contains("panHost.isUserInteractionEnabled = false"),
                      "blank Recents space must stay with the collection view pan")
        XCTAssertFalse(picker.contains("shouldBeRequiredToFailBy otherGestureRecognizer"),
                       "a stationary long press must not wait for the pager pan to fail")
    }

    func testEmojiPagerDoesNotReloadOrResetDuringLiveScroll() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let updateStart = try XCTUnwrap(picker.range(of: "func updateUIView"))
        let updateEnd = try XCTUnwrap(picker.range(of: "private func hideTopEdgeEffect",
                                                    range: updateStart.upperBound..<picker.endIndex))
        let update = String(picker[updateStart.lowerBound..<updateEnd.lowerBound])
        let pagerStart = try XCTUnwrap(picker.range(of: "private final class EmojiPagerCollectionView"))
        let pager = String(picker[pagerStart.lowerBound..<picker.endIndex])

        XCTAssertFalse(update.contains("uiView.reloadData()"),
                       "SwiftUI updates must defer collection reloads while a swipe is active")
        XCTAssertTrue(update.contains("markNeedsReload()"))
        XCTAssertTrue(picker.contains("guard request != lastScrollRequest"),
                      "the same SwiftUI request must not snap a live free scroll back")
        XCTAssertTrue(picker.contains("var onLayoutChanged"))
        XCTAssertTrue(picker.contains("decelerationRate = .fast"),
                      "emoji swipes should settle quickly instead of coasting")
        XCTAssertFalse(pager.contains("reloadData()"),
                       "layoutSubviews must not invalidate the active collection pan")
    }

    func testEmojiCategoryScrubOffsetWinsWhileExpanded() throws {
        let bar = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        let state = try source("DictusKeyboard/KeyboardState.swift")

        XCTAssertTrue(bar.contains("guard !isExpanded else { return }"),
                      "category callbacks must not recenter an active scrub")
        XCTAssertTrue(bar.contains(".onChange(of: isExpanded)"))
        let surface = try source("DictusCore/Sources/DictusCore/KeyboardSurfaceState.swift")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("guard self.expanded != expanded else { return false }"))
        XCTAssertTrue(surface.contains("guard selectionIndex != normalized else { return false }"))
        XCTAssertTrue(state.contains("guard surface.setExpanded(expanded) else { return }"))
        XCTAssertTrue(state.contains("guard surface.setSelectionIndex(index) else { return }"))
    }

    func testEmojiCategoryScrubMovesByFingerDeltaAndReachesTheEdges() throws {
        let bar = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue((try relocatedKeyboardSource()).contains("setExpanded(true)"),
                      "the compact category circle should expand when a horizontal drag starts")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("EmojiCategoryBarMetrics.travelGain"),
                      "a short drag must be able to reach both ends of the category bar")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("selectCategory(at: scrollOffset)"),
                      "selection must use the moving handle position")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("setScrollOffset(handleOffset(for: index))"),
                      "release should snap the handle to the selected category")
        XCTAssertFalse(bar.contains("select(centerMarkerPoint)"),
                       "the old fixed-marker/content-translation model must be gone")
    }

    func testEmojiCategoryScrubberProvidesAccessibleSelectionActions() throws {
        let bar = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue((try relocatedKeyboardSource()).contains("isAccessibilityElement = true"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("accessibilityTraits = [.button, .adjustable]"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("override func accessibilityActivate()"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("override func accessibilityIncrement()"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("override func accessibilityDecrement()"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("onIndexChanged?(normalized)"))
        XCTAssertTrue(controller.contains("categoryScrubber.categoryNames = CategoryInfo.emojiBarSections.map(\\.name)"))
    }

    func testEmojiCategoryControlStaysCenteredAndUsesCompactSlots() throws {
        let bar = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(bar.contains("let collapsedCenterX = trackWidth / 2"),
                      "the collapsed current-category button must stay centered")
        XCTAssertTrue(bar.contains("EmojiCategoryBarMetrics.renderedSlotWidth("),
                      "category slots must fit the compact capsule without stretching")
        XCTAssertTrue(bar.contains("static let slotSpacing: CGFloat = 2"),
                      "category icons should retain a small native-style gap")
        XCTAssertTrue(bar.contains("Circle()"),
                      "the selected category should be represented by a circular center marker")
        XCTAssertTrue(bar.contains("let handleCenterX ="),
                      "the Liquid Glass handle must have its own moving position")
        XCTAssertTrue(bar.contains(".position(x: handleCenterX"),
                      "the complete capsule should move with the selected category")
        XCTAssertTrue(bar.contains("glassSurface(in: Capsule())"),
                      "Liquid Glass must be attached to the moving handle")
        XCTAssertTrue(bar.contains("let barContentWidth ="),
                      "the category icons should be rendered inside the moving glass bar")
        XCTAssertTrue(bar.contains("let markerPositionInBar ="),
                      "the fixed center selector must drive category selection")
        XCTAssertTrue(bar.contains(".position(x: trackWidth / 2"),
                      "the selected category marker must stay centered while the bar moves")
        XCTAssertTrue(bar.contains("static let expandedBarWidth: CGFloat = 176"),
                      "the expanded handle should remain compact")
    }

    func testEmojiCategoryBarHasCompactWidthAndInsetContentClip() throws {
        let policy = try source("DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift")
        let bar = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(bar.contains("static let slotWidth: CGFloat = 16"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("static let slotSpacing: CGFloat = 2"))
        XCTAssertTrue(policy.contains("floatingEmojiCategoryBarMaxWidth: Double = 176"))
        XCTAssertTrue(picker.contains("private let gridVerticalInset: CGFloat = 4"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains(".clipShape(shape.inset(by: 2))"),
                      "emoji content must stay inside the glass rim")
    }

    func testEmojiCellsDoNotOverlapAdjacentTouchTargets() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let start = try XCTUnwrap(picker.range(of: "private final class EmojiKeyButton"))
        let button = String(picker[start.lowerBound..<picker.endIndex])

        XCTAssertTrue(button.contains("return bounds.contains(point)"),
                      "emoji cells already meet the target size and must not steal adjacent swipes")
    }

    func testEmojiHoldLetsPagerWinBeforeRecognitionButTracksAfterward() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let ownerStart = try XCTUnwrap(picker.range(of: "private final class EmojiPagerCollectionView"))
        let ownerEnd = try XCTUnwrap(picker.range(of: "private final class EmojiPageCell",
                                                    range: ownerStart.upperBound..<picker.endIndex))
        let owner = String(picker[ownerStart.lowerBound..<ownerEnd.lowerBound])

        XCTAssertTrue(owner.contains("private let preRecognitionMovement: CGFloat = 8"))
        XCTAssertTrue(owner.contains("EmojiGestureCoordinator("))
        XCTAssertTrue(owner.contains("allowableMovement: preRecognitionMovement"))
        let hold = try source("DictusKeyboard/Views/EmojiGestureCoordinator.swift")
        XCTAssertTrue(hold.contains("self.state = .began"),
                      "the hold owner must begin from its timer and keep tracking after recognition")
        XCTAssertTrue(hold.contains("arbitration.endTouch()"),
                      "release fails a hold that has not begun and ends one that has")
        let arbitration = try source("DictusCore/Sources/DictusCore/EmojiHoldArbitration.swift")
        XCTAssertTrue(arbitration.contains("case .began, .changed:\n            phase = .changed"),
                      "movement after recognition keeps the hold instead of cancelling it")
        XCTAssertTrue(owner.contains("panGestureRecognizer.require(toFail: hold)"),
                      "the pager must wait for the hold to fail instead of resetting it mid-touch")
        XCTAssertTrue(owner.contains("Receive every touch and fail immediately"),
                      "empty Recents space must fail the hold so the pager can move")
        XCTAssertFalse(owner.contains("return canBeginVariantHold(at: touch.location(in: self))"),
                       "excluding a blank cell from the hold leaves the pager waiting forever")
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        let control = try source("DictusKeyboard/Views/EmojiCategoryControl.swift")
        XCTAssertFalse(control.contains("collapsedCircleFrame"),
                       "the bar must not collapse to a small circle: the full visible track is the target")
        XCTAssertTrue(control.contains("return bounds.insetBy(dx: 0, dy: -hitExpansion)"),
                      "the whole visible track must be the interaction target")
        XCTAssertTrue(control.contains("selectAccessibilityCategory(nearestIndex(toX:"),
                      "a stationary tap on the bar must select a category, not be dropped")
        XCTAssertTrue(control.contains("Tap or swipe left or right to choose an emoji category."))
        XCTAssertFalse(control.contains("accept scrub starts"))
        XCTAssertFalse(categories.contains("accept scrub starts"))
        XCTAssertFalse(owner.contains("panGestureRecognizer.isEnabled = false"),
                       "disabling the pager pan after recognition cancels the active hold")
        XCTAssertFalse(owner.contains("guard !isDragging, !isDecelerating"),
                       "small pager jitter must not cancel a pending emoji hold")
    }

    func testEmojiSurfaceKeepsTheSharedGlassInset() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertFalse(root.contains("withoutGlassRim: state.areaMode == .emoji"),
                       "emoji must use the same inset surface treatment as the other pages")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("if state.areaMode == .emoji"),
                      "emoji content needs the rounded inset clipping path")
        XCTAssertTrue((try relocatedKeyboardSource()).contains(".clipShape(shape)"),
                      "emoji glyphs must not render through the Liquid Glass edge")
    }

    func testDictationBoardUsesABCAndSharedCommandGlassRadius() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue((try relocatedKeyboardSource()).contains("voiceBoardChrome(text: \"ABC\""))
        XCTAssertFalse(root.contains("utilityGlyph(systemName: \"keyboard\")"))
        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.commandKeyCornerRadius"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("CommandKeyFace("))
        XCTAssertFalse(root.contains("RoundedRectangle(cornerRadius: 18, style: .continuous)"))
    }

    /// Delete must occupy the same rectangle on every page. The emoji page used
    /// `boardDeleteFrame` directly while the letter page pushed its backspace
    /// through the prediction seamer, so the key visibly moved and changed size
    /// when the emoji page opened.
    func testDeleteUsesOneSharedFrameOnEveryPage() throws {
        let letters = try source("DictusKeyboard/LetterKeyboardSurface.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(letters.contains("hitFrames[lastRow][index] = deleteFrame"),
                      "the letter backspace hit frame must be pinned to the shared delete frame")
        XCTAssertTrue(letters.contains("frames[lastRow][index] = deleteFrame"),
                      "the letter backspace visual frame must be pinned to the shared delete frame")
        XCTAssertTrue(root.contains("hitWidth: layout.boardDeleteFrame.width"),
                      "the emoji page delete must use the shared board delete frame for its hit rect")
        XCTAssertTrue(root.contains("hitHeight: layout.boardDeleteFrame.height"))
    }

    /// The board's primary slot used to be one control that changed its mind.
    /// Its label consulted only `appNeedsAppAction` while its UIKit action also
    /// honoured `failedRequiresApp`, so a failed session rendered "Hold to
    /// dictate" and opened the app on press. These assertions pin the split: one
    /// gate, two mutually exclusive controls, and no app handoff left inside the
    /// dictate button.
    func testRecoveryAndDictationAreSeparateControlsWithOneGate() throws {
        let board = try source("DictusKeyboard/VoiceBoardSurface.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let state = try source("DictusKeyboard/KeyboardState.swift")

        // One gate, defined once.
        XCTAssertTrue(state.contains("var showsRecoveryAction: Bool"))
        XCTAssertTrue(state.contains("return appNeedsAppAction || failedRequiresApp"),
                      "the gate must include the failed-session case the label used to miss")
        XCTAssertTrue(state.contains("guard !dictationStatus.ownsKeyboardArea else { return false }"),
                      "a live session must keep the dictate control")

        // Exactly one control is mounted in the slot.
        XCTAssertTrue(board.contains("if state.showsRecoveryAction {"))
        XCTAssertTrue(board.contains("recoveryButton(frame: frame)"))
        XCTAssertTrue(board.contains("dictateButton(frame: frame)"))
        XCTAssertTrue(board.contains("private func recoveryButton(frame: CGRect)"))
        XCTAssertTrue(board.contains("private func dictateButton(frame: CGRect)"))

        // Dictation must not be able to open the app any more.
        let dictateBody = board.components(separatedBy: "private func dictateButton(frame: CGRect)")
        XCTAssertEqual(dictateBody.count, 2, "expected exactly one dictateButton")
        XCTAssertFalse(
            dictateBody[1].components(separatedBy: "private func spaceBar").first!
                .contains("openDictusForRecovery"),
            "the dictate control must not perform the app handoff"
        )
        XCTAssertFalse(
            dictateBody[1].components(separatedBy: "private func spaceBar").first!
                .contains("appNeedsAppAction"),
            "the dictate control must not branch on the app-handoff state"
        )

        // A separate UIKit owner, exclusive with the mic, sharing its frame.
        XCTAssertTrue(controller.contains("private var recoveryButton: UIButton?"))
        XCTAssertTrue(controller.contains("identifier: \"open-saiity-button\""))
        XCTAssertTrue(controller.contains("let recoveryVisible = micVisible && KeyboardState.shared.showsRecoveryAction"))
        XCTAssertTrue(controller.contains("let dictateVisible = micVisible && !recoveryVisible"))
        XCTAssertTrue(controller.contains("recoveryButton?.frame = layout.dictateFrame"))
        XCTAssertTrue(controller.contains("$0.accessibilityIdentifier == \"open-saiity-button\""))

        // Both the face and the hit owner label themselves from the one label.
        XCTAssertTrue(board.contains("state.primaryBoardActionLabel"))
        XCTAssertTrue(controller.contains("KeyboardState.shared.primaryBoardActionLabel"))
        XCTAssertFalse(state.contains("appNeedsAppAction ? \"Open sAiity to prepare dictation\""),
                       "the label must not re-derive its own gate")
    }

    /// A per-instance UUID in the per-key `ForEach` identity made SwiftUI
    /// destroy and rebuild every key's touch control on each surface rebuild, so
    /// a finger down at that moment never received its release. Measured on
    /// device: 13 presses began, 4 ended, 0 cancelled.
    func testLetterKeyIdentityIsStableAcrossSurfaceRebuilds() throws {
        let letters = try source("DictusKeyboard/LetterKeyboardSurface.swift")
        XCTAssertFalse(
            letters.contains("keyboardSurfaceID"),
            "per-key identity must not embed a per-instance UUID or the controls are recreated mid-touch"
        )
        XCTAssertTrue(letters.contains("id: \"letter-\\(rowIndex)-\\(columnIndex)\""),
                      "per-key identity must be stable row/column")
    }

    /// The key popup is a single slot, so two fingers put two keys through it in
    /// quick succession. The second used to overwrite the first and the first
    /// finger lifting then dismissed a preview it did not own — 24 of 40
    /// committed keys on device were typing without owning their popup.
    func testKeyPreviewHasASingleOwnerUnderTwoFingerTyping() throws {
        let letters = try source("DictusKeyboard/LetterKeyboardSurface.swift")
        let popup = try source("DictusKeyboard/Views/KeyVariantPopup.swift")

        XCTAssertTrue(popup.contains("var ownerKeyID: String?"),
                      "the preview session must record which key owns it")
        XCTAssertTrue(letters.contains("ownerKeyID: String"),
                      "presentKeyPreview must take the owner")
        XCTAssertTrue(letters.contains("existing.ownerKeyID != ownerKeyID"),
                      "a second key must not steal an owned preview")
        XCTAssertTrue(letters.contains("dismissKeyPreview(ownerKeyID: String? = nil)"),
                      "dismissal must be owner-scoped")
        XCTAssertTrue(letters.contains("owner != ownerKeyID"),
                      "a non-owner release must leave the preview alone")
    }

    /// The device trace must never be able to record typed text. It used to log
    /// `label=<accessibilityLabel>`, which for a real sentence is a verbatim copy
    /// of everything the user typed, and `routeProxyText` logged nothing on the
    /// success path, so the one stage that proves a character reached the host
    /// was invisible.
    func testTouchTraceNeverLogsTypedText() throws {
        let surface = try source("DictusKeyboard/LetterKeyboardSurface.swift")
        let input = try source("DictusKeyboard/KeyboardKeyInput.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let owner = try source("DictusKeyboard/KeyGridTouchOwner.swift")

        // The trace used to log `label=<accessibilityLabel>` on every press, which
        // for a real sentence is a verbatim copy of what the user typed. It has
        // since been removed from the per-touch path for performance, which is a
        // second reason it must not return: the privacy problem and the cost
        // problem have the same fix.
        for (name, text) in [("LetterKeyboardSurface", surface),
                            ("KeyboardKeyInput", input),
                            ("KeyboardViewController", controller),
                            ("KeyGridTouchOwner", owner)] {
            XCTAssertFalse(text.contains("label=\\(key.accessibilityLabel"),
                           "\(name) logs a key label, which is typed text")
            XCTAssertFalse(text.contains("accessibilityLabel(for: page) ?? \"?\")"),
                           "\(name) logs the pressed key's character")
        }
    }

    /// The availability timer republishes the area mode every two seconds, and
    /// that reaches `applyLayout`. Assigning an Auto Layout constant is not a
    /// no-op even when the value is unchanged — it invalidates layout and
    /// re-lays-out every SwiftUI key control. Unguarded, the keyboard rebuilt its
    /// own geometry under the user's fingers twice a second, which is what made
    /// keys intermittently stop responding. The device trace showed
    /// `hostingSet_letters` with `old` equal to `new` on a two-second cadence.
    func testApplyLayoutIsIdempotentSoTheTimerCannotRebuildGeometry() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        let start = try XCTUnwrap(controller.range(of: "private func applyLayout(for mode: KeyboardAreaMode)"))
        let end = try XCTUnwrap(controller.range(
            of: "case .emoji:", range: start.upperBound..<controller.endIndex))
        let body = String(controller[start.lowerBound..<end.lowerBound])

        let guardRange = try XCTUnwrap(body.range(
            of: "guard lastLayoutMode != mode || lastLayoutHeight != liveHeight else { return }"))
        let guardEnd = try XCTUnwrap(body.range(
            of: "heightConstraint?.constant = liveHeight", range: guardRange.upperBound..<body.endIndex))
        // Every constraint write must sit behind the guard.
        XCTAssertTrue(guardRange.upperBound < guardEnd.lowerBound,
                      "applyLayout must return before touching any height constraint when nothing changed")
        XCTAssertTrue(body.contains("lastLayoutMode = mode"),
                      "the guard must record the mode it just applied")
        XCTAssertTrue(body.contains("lastLayoutHeight = liveHeight"),
                      "the guard must record the height it just applied")

        // And a returning keyboard must forget the memo, or it would skip layout.
        let appear = try XCTUnwrap(controller.range(of: "override func viewWillAppear"))
        let appearEnd = try XCTUnwrap(controller.range(
            of: "publishFullAccessHandshake()", range: appear.upperBound..<controller.endIndex))
        let appearLimit = controller.index(appearEnd.upperBound, offsetBy: 400, limitedBy: controller.endIndex) ?? controller.endIndex
        let appearBody = String(controller[appear.lowerBound..<appearLimit])
        XCTAssertTrue(appearBody.contains("lastLayoutMode = nil"),
                      "viewWillAppear must clear the memo so layout is re-applied on return")
        XCTAssertTrue(appearBody.contains("lastLayoutHeight = nil"),
                      "viewWillAppear must clear the memo so layout is re-applied on return")
    }

    /// The letter grid must have exactly one touch owner.
    ///
    /// It used to give every key its own `UIControl` — around thirty views. Any
    /// SwiftUI state change runs `updateUIView` across all of them and may destroy
    /// and recreate any, and a control that has left the hierarchy receives
    /// neither `touchesEnded` nor `touchesCancelled`, so the character is lost.
    /// That is why the keyboard only failed when typing fast: the slower the
    /// typing, the more likely each gesture finished before the next rebuild.
    /// Stable key identities made destruction rarer (31% → 93% delivery) but could
    /// not make it impossible, because the lifecycle was still per key.
    func testLetterSurfaceHasExactlyOneTouchOwnerAndNoPerKeyControls() throws {
        let surface = try source("DictusKeyboard/LetterKeyboardSurface.swift")
        let grid = try source("DictusKeyboard/LetterKeyGridView.swift")

        // One owner for the whole grid, and it is the thing that draws the keys.
        // The surface no longer draws key faces at all, so there is no second
        // description of the grid that could disagree with the touch targets.
        XCTAssertFalse(surface.contains(".keyGridInput("),
                       "the letter surface must not publish a separate hit geometry")
        XCTAssertFalse(surface.contains("ForEach(frames)"),
                       "the letter surface must not draw key faces")
        XCTAssertTrue(surface.contains(".allowsHitTesting(false)"),
                      "the space the grid occupies must not compete for touches")

        // No per-key control survives anywhere in the new layer, and nothing in it
        // is a UIKit control that SwiftUI could destroy mid-gesture.
        XCTAssertFalse(grid.contains("UIButton("))
        XCTAssertFalse(grid.contains("ImmediateKeyButton("))
        XCTAssertFalse(grid.contains("ImmediateVariantKey("))
        XCTAssertTrue(grid.contains("private var activeTouches: [ObjectIdentifier: ActiveTouch]"),
                      "touches must be tracked by touch identity, not by key")
        XCTAssertTrue(grid.contains("isMultipleTouchEnabled = true"),
                      "two fingers on two keys must both be live")
        XCTAssertFalse(grid.contains("isExclusiveTouch = true"),
                       "one finger per key is the point, so the view must not be exclusive")

        // The shared geometry and the resolver are still the single source of truth.
        XCTAssertTrue(grid.contains("KeyboardKeyHitResolver.keyIndex(at: point, rows: tiles)"))
        XCTAssertTrue(grid.contains("private var plates: [[CGRect]] = []"))
    }

    /// The owner must attribute each release to the key its own press began on.
    ///
    /// Tracking by key rather than by touch would let a second finger overwrite
    /// the first's record, so whichever lifted last would win and the other
    /// character would be lost.
    func testCaptureViewTracksEachTouchSeparately() throws {
        let capture = try source("DictusKeyboard/KeyGridTouchOwner.swift")

        XCTAssertTrue(capture.contains("private var activeTouches: [ObjectIdentifier: ActiveTouch]"),
                      "touches must be tracked by touch identity, not by key")
        XCTAssertTrue(capture.contains("activeTouches[ObjectIdentifier(touch)] = ActiveTouch("),
                      "a press must record the key that touch began on")
        XCTAssertTrue(capture.contains("activeTouches.removeValue(forKey: ObjectIdentifier(touch))"),
                      "a release must report the key recorded at press, not the nearest key")
        XCTAssertTrue(capture.contains("KeyboardKeyHitResolver.keyIndex(at: point, rows: rows)"),
                      "position must be resolved to a key by the shared resolver")
        // The owner is updated in place rather than recreated, which is the whole
        // point: an in-flight gesture must survive any SwiftUI state change.
        XCTAssertTrue(capture.contains("func updateUIView(_ owner: KeyGridTouchOwner, context: Context)"),
                      "the owner must update in place so in-flight gestures survive")
        XCTAssertTrue(capture.contains("func makeUIView(context: Context) -> KeyGridTouchOwner"),
                      "one owner is created and then reused")
        // Claiming only the grid keeps the owner from swallowing the bottom bar,
        // where space, return and the emoji key live.
        XCTAssertTrue(capture.contains("guard let claimsRect else { return false }"),
                      "the owner must claim only the grid it was given")
        // Per-tap tracing is gone for cost reasons; the rare orphan report is the
        // cheap signal that survives, because it only fires when the owner is
        // genuinely unwired.
        XCTAssertFalse(capture.contains("action: \"ownerHitTest\""),
                       "the owner must not log on the per-touch path")
        XCTAssertTrue(capture.contains("KeyGridTouchBus.reportOrphanedGesture()"),
                      "an owner with no surface listening must still report it")
    }

    func testGridFingerKeepsItsOriginalReleaseHandler() throws {
        let capture = try source("DictusKeyboard/KeyGridTouchOwner.swift")

        XCTAssertTrue(capture.contains("onRelease: handlers.onRelease"),
                      "the finger must snapshot its release callback when it begins")
        XCTAssertTrue(capture.contains("active.onRelease?(active.press, cancelled || stale)"),
                      "a redraw may refresh callbacks, but a replaced page must cancel the old press")
        XCTAssertFalse(capture.contains("onGesture?(.release, active.keyID"),
                       "release must not use whichever handler happens to be registered later")
    }

    /// Letters must insert on press, the way every other keyboard does.
    ///
    /// History, because this has been flipped once already. Insertion briefly moved
    /// to press to remove the dependency on `touchesEnded` (measured at 93%), and
    /// that was a clear regression: about 13 of 30 characters survived a two-finger
    /// sentence. The cause was not press-insertion itself. `commit` flips the page
    /// from `.shifted` to `.normal`, so a press rebuilt the key layout — and at that
    /// time every letter installed its own `ImmediateKeyButton`, so the rebuild
    /// destroyed the very control holding the other finger's touch.
    ///
    /// Both causes are gone. One stable UIKit `KeyGridTouchOwner` resolves position
    /// to key, so no re-render can destroy the view that owns a gesture, and the
    /// geometry is memoized. That makes the feel of a press the deciding factor: on
    /// a device, inserting on lift reads as "the key did not respond" for the whole
    /// duration of the tap.
    ///
    /// Accent keys are the deliberate exception and still commit on release, because
    /// a hold has to be able to commit the popup option instead of the base letter.
    func testLettersInsertOnPressNotOnRelease() throws {
        let letters = try source("DictusKeyboard/LetterKeyboardSurface.swift")

        // Insert happens in the press handler, so the character appears with the
        // finger going down.
        let pressStart = try XCTUnwrap(letters.range(of: "private func handleCapturedPress("))
        let pressLimit = try XCTUnwrap(letters.range(
            of: "private func handleCapturedMove(", range: pressStart.upperBound..<letters.endIndex))
        let pressBody = String(letters[pressStart.lowerBound..<pressLimit.lowerBound])
        XCTAssertTrue(pressBody.contains("commit(key)"),
                      "letters must insert on touch-down, not wait for the lift")

        let releaseStart = try XCTUnwrap(letters.range(of: "private func handleCapturedRelease("))
        let releaseLimit = try XCTUnwrap(letters.range(
            of: "@ViewBuilder", range: releaseStart.upperBound..<letters.endIndex))
        let releaseBody = String(letters[releaseStart.lowerBound..<releaseLimit.lowerBound])
        XCTAssertFalse(releaseBody.contains("if !cancelled { commit(key) }"),
                       "a second commit on release would insert every letter twice")
        XCTAssertTrue(releaseBody.contains("dismissKeyPreview(ownerKeyID: press.id)"),
                      "the release must also clear the preview it owns")
        XCTAssertTrue(releaseBody.contains("handleLetterVariantEnded("),
                      "accent keys still commit on release, so a hold can pick an option")

        // The precondition that makes press-insertion safe, asserted where it can
        // actually regress: per-key controls are what made a press-time rebuild
        // destroy an in-flight gesture.
        let keyStart = try XCTUnwrap(letters.range(of: "private func letterKey("))
        let keyLimit = try XCTUnwrap(letters.range(
            of: "private func letterKeyLabel(", range: keyStart.upperBound..<letters.endIndex))
        let keyBody = String(letters[keyStart.lowerBound..<keyLimit.lowerBound])
        let defaultStart = try XCTUnwrap(keyBody.range(of: "            default:"))
        let letterCase = String(keyBody[defaultStart.lowerBound...])
        XCTAssertFalse(letterCase.contains("ImmediateKeyButton("),
                       "letters must not install a control, or a press-time render can destroy an in-flight touch")
    }

    /// A touch that drifts one point off a key is cancelled, and the old code
    /// re-derived liveness from `event.allTouches` — where that touch is still
    /// listed as `.moved` on the same view. The key then never finished and the
    /// character was skipped, which surfaced as dropped characters when typing
    /// fast with two fingers.
    func testCancelledTouchesAreTreatedAsTerminal() throws {
        let input = try source("DictusKeyboard/KeyboardKeyInput.swift")
        let cancelStart = try XCTUnwrap(input.range(of: "override func touchesCancelled"))
        let cancelEnd = try XCTUnwrap(input.range(of: "private func finish(", range: cancelStart.upperBound..<input.endIndex))
        let cancelBody = String(input[cancelStart.lowerBound..<cancelEnd.lowerBound])

        XCTAssertFalse(cancelBody.contains("event?.allTouches"),
                       "cancelled touches must not be re-checked against event.allTouches; a slid-off touch is still listed there")
        XCTAssertFalse(cancelBody.contains("stillActive"))
        XCTAssertTrue(cancelBody.contains("activeTouches.removeValue(forKey: id)"),
                      "every cancelled touch must leave the active set")
    }

    /// The blocked-link hint used to show whenever a handoff was pending, which
    /// read as a permanent warning on a healthy board.
    func testBlockedLinkHintOnlyAppearsAfterAFailure() throws {
        let board = try source("DictusKeyboard/VoiceBoardSurface.swift")
        XCTAssertFalse(
            board.contains("if state.appNeedsAppAction { return \"If the link is blocked"),
            "the hint must not be driven by the pending-handoff state"
        )
        XCTAssertTrue(board.contains("guard state.dictationStatus == .failed else { return \"\" }"))
    }

    /// Solving key rows must never read past the end of a solved row.
    ///
    /// The device crash report was blunt: `EXC_BREAKPOINT` in
    /// `Array._checkSubscript`, from `LetterKeyboardSurface.positionedKeys`, via the
    /// grid cache. The row index came from the key row while the array it indexed
    /// was a *solved* row, and the solver can return fewer rows — or a shorter row
    /// than the keys — when the available size is briefly degenerate. That killed
    /// the extension on launch, so nothing typed at all and no trace was written.
    /// There were 87 crash reports on the device by the time it was found.
    func testSolvedKeyRowsAreZippedRatherThanIndexed() throws {
        for (name, path) in [
            ("letter", "DictusKeyboard/LetterKeyboardSurface.swift"),
            ("symbol", "DictusKeyboard/SymbolKeyboardSurface.swift"),
            ("number", "DictusKeyboard/NumberKeyboardSurface.swift")
        ] {
            let surface = try source(path)
            XCTAssertFalse(surface.contains("frame: rowHits[columnIndex]"),
                           "\(name) indexes a solved row by a key-row column; the counts can differ")
            XCTAssertFalse(surface.contains("frame: pair.1.1[columnIndex]"),
                           "\(name) indexes a hit row by a column zipped against a different row")
            XCTAssertTrue(surface.contains("zip("),
                          "\(name) must zip solved rows against key rows so they cannot diverge")
        }
    }

    /// The keyboard must not write a trace on the per-touch path.
    ///
    /// The trace fired from `hitTest`, which UIKit re-runs for every phase of a
    /// touch — roughly four times per tap. With the per-press sites that came to
    /// about twenty-three interpolated strings and serial-queue file appends per
    /// keystroke, around 180 writes a second at typing speed. That is enough I/O
    /// contention to make typing feel chunky.
    func testNoTracingRunsOnThePerTouchPath() throws {
        let hot = ["0-arrival", "2-overlay", "3-host", "4-key", "5-commit",
                   "5b-commit", "6-surface", "7-multi", "8-host", "1-inputView"]
        for path in [
            "DictusKeyboard/KeyboardViewController.swift",
            "DictusKeyboard/KeyboardKeyInput.swift",
            "DictusKeyboard/KeyGridTouchOwner.swift",
            "DictusKeyboard/LetterKeyboardSurface.swift"
        ] {
            let source = try source(path)
            for stage in hot {
                XCTAssertFalse(source.contains("instanceID: \"\(stage)\""),
                               "\(path) still traces on the per-touch path (\(stage))")
            }
        }
    }
}
