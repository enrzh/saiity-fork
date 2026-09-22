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

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    func testLetterPageDoesNotCommitSwipeTyping() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertFalse(root.contains("swipeWord"))
        XCTAssertFalse(root.contains("SwipeTypingDecoder"))
        XCTAssertTrue(root.contains("ImmediateVariantKey("),
                      "hold-for-accents stays on the letter page; swipe is not wired there")
        XCTAssertTrue(root.contains("KeyPressPreviewHost("),
                      "key popups must draw a press preview above letter keys")
        let engine = try source("DictusKeyboard/TextPrediction/TextPredictionEngine.swift")
        XCTAssertTrue(engine.contains("func swipeWord(from path: String)"))
        let settings = try source("DictusApp/Views/SettingsView.swift")
        XCTAssertTrue(settings.contains("LastDictationIssueReportView()"))
        XCTAssertFalse(settings.contains("DragGesture(minimumDistance: 0)"))
    }

    func testLetterSurfaceAddsARealPeriodKeyWithSharedHoldRouting() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
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
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let pageStart = try XCTUnwrap(root.range(of: "private struct LiquidSymbolPageView"))
        let keyStart = try XCTUnwrap(root.range(of: "private struct LiquidSymbolKey"))
        let page = String(root[pageStart.lowerBound..<keyStart.lowerBound])

        XCTAssertFalse(page.contains(".simultaneousGesture(symbolDragGesture(frames: frames))"))
        XCTAssertFalse(page.contains(".simultaneousGesture(symbolPointerGesture(frames: frames))"),
                       "the grid must not commit a second action after a key-owned hold")
        XCTAssertTrue(page.contains("ImmediateVariantKey("))
        XCTAssertTrue(page.contains("onBegan:"))
        XCTAssertTrue(page.contains("onMoved:"))
    }

    func testLetterAndSymbolPlatesKeepNativeGaps() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(root.contains("visualFrame: rowPlates[columnIndex]"),
                      "plates must use the original key frames, not the gap-absorbed hit cells")
        XCTAssertFalse(root.contains("visualFrame: rowHits[columnIndex]"),
                       "drawing on hit cells makes every key the same size and removes native gaps")
        XCTAssertTrue(root.contains("Gaps stay visible. The enlarged rect is only the touch target."))
        XCTAssertTrue(root.contains("highlightSize: visualFrame.size"),
                      "press highlights must match the drawn plate, not the hit cell")
    }

    func testSymbolButtonsUseAStableNativeTapSurface() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let start = try XCTUnwrap(root.range(of: "private func symbolKey"))
        let end = try XCTUnwrap(root.range(of: "private func commitSymbolFromTap"))
        let body = String(root[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(body.contains("ImmediateVariantKey("))
        XCTAssertEqual(body.components(separatedBy: ".contentShape(Rectangle().inset(by: -6))").count - 1, 2,
                       "plain and variant symbol keys retain the same expanded rectangular tap surface")
        XCTAssertTrue(body.contains(".frame(width: frame.width, height: frame.height)"))
        XCTAssertTrue(body.contains("onEnded:"),
                      "keys with native extras get a hold popup through the same gesture owner")
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
        XCTAssertTrue(root.contains("topOverflow: CGFloat(surfaceLayout.surfaceFrame.minY)"))
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
        XCTAssertFalse(tap.contains("guard"), "native tap release has no stale hold/drag gate")
        XCTAssertTrue(tap.contains("onTap?(item.emoji)"))
        XCTAssertTrue(picker.contains("onTap: insertEmoji"))
        XCTAssertTrue(picker.contains("onTap: { [weak self] emoji in self?.onTap?(emoji) }"))
        XCTAssertTrue(picker.contains("button.onTap = onTap"))
        XCTAssertTrue(picker.contains("cancelsTouchesInView = true"),
                      "the pager hold cancels UIButton release instead of a stale suppression flag")
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
        XCTAssertTrue(picker.contains("override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer)"),
                      "an active emoji popup must not be cancelled by the scroll view")
        XCTAssertTrue(picker.contains("if state == .began || state == .changed { return false }"),
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
        let start = try XCTUnwrap(root.range(of: "private func dictateButton(frame:"))
        let end = try XCTUnwrap(root.range(of: "private func dictationControlVisual",
                                           range: start.upperBound..<root.endIndex))
        let dictateButton = String(root[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(dictateButton.contains("if appNeedsAppAction || state.appNeedsAppAction {"),
                      "a short tap opens sAiity when the visible or live state requires recovery")
        XCTAssertTrue(dictateButton.contains("holdDuration: appNeedsAppAction || isCancellationStage"),
                      "the dictation-board control must wait for a hold before starting")
        XCTAssertTrue(dictateButton.contains("onHold: appNeedsAppAction || isCancellationStage"))
        XCTAssertFalse(dictateButton.contains("onTouchDown: { state.handleMicPressBegan() }"),
                       "a tap must not start dictation on the dictation board")
        XCTAssertTrue(state.contains("dictationReleaseTailDuration"),
                      "release keeps the microphone open for the final-word tail")
        XCTAssertTrue(state.contains("cancelDictationReleaseTail()"),
                      "a new hold cancels the pending release stop")
        XCTAssertTrue(controller.contains("guard state.appNeedsAppAction || state.failedRequiresApp else { return false }"),
                      "an accessibility tap must not start a new recording without a hold")
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
        XCTAssertTrue(root.contains("scaledKeyGeometry"))
        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.keySpacing") || root.contains("geometry.keySpacing"))
        XCTAssertTrue(root.contains(".letterKeyPlate()"))
        XCTAssertTrue(root.contains(".allowsHitTesting(false)"))
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        XCTAssertTrue(bar.contains("commandKeyPlate"))
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
        XCTAssertTrue(picker.contains("panHost.isUserInteractionEnabled = true"))
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
        XCTAssertTrue(state.contains("guard emojiCategoryBarExpanded != expanded else { return }"))
        XCTAssertTrue(state.contains("guard emojiCategorySelectionIndex != normalized else { return }"))
    }

    func testEmojiCategoryScrubMovesByFingerDeltaAndReachesTheEdges() throws {
        let bar = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertTrue(bar.contains("setExpanded(true)"),
                      "the compact category circle should expand when a horizontal drag starts")
        XCTAssertTrue(bar.contains("EmojiCategoryBarMetrics.travelGain"),
                      "a short drag must be able to reach both ends of the category bar")
        XCTAssertTrue(bar.contains("selectCategory(at: scrollOffset)"),
                      "selection must use the moving handle position")
        XCTAssertTrue(bar.contains("setScrollOffset(handleOffset(for: index))"),
                      "release should snap the handle to the selected category")
        XCTAssertFalse(bar.contains("select(centerMarkerPoint)"),
                       "the old fixed-marker/content-translation model must be gone")
    }

    func testEmojiCategoryScrubberProvidesAccessibleSelectionActions() throws {
        let bar = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(bar.contains("isAccessibilityElement = true"))
        XCTAssertTrue(bar.contains("accessibilityTraits = [.button, .adjustable]"))
        XCTAssertTrue(bar.contains("override func accessibilityActivate()"))
        XCTAssertTrue(bar.contains("override func accessibilityIncrement()"))
        XCTAssertTrue(bar.contains("override func accessibilityDecrement()"))
        XCTAssertTrue(bar.contains("onIndexChanged?(normalized)"))
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
        XCTAssertTrue(bar.contains("static let slotSpacing: CGFloat = 2"))
        XCTAssertTrue(policy.contains("floatingEmojiCategoryBarMaxWidth: Double = 176"))
        XCTAssertTrue(picker.contains("private let gridVerticalInset: CGFloat = 4"))
        XCTAssertTrue(root.contains(".clipShape(shape.inset(by: 2))"),
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
        XCTAssertTrue(owner.contains("EmojiHoldGestureRecognizer("))
        XCTAssertTrue(owner.contains("allowableMovement: preRecognitionMovement"))
        XCTAssertTrue(picker.contains("self.state = .began"),
                      "the hold owner must begin from its timer and keep tracking after recognition")
        XCTAssertTrue(picker.contains("state = state == .possible ? .failed : .ended"),
                      "the hold owner must release without a movement cancellation path")
        XCTAssertTrue(owner.contains("panGestureRecognizer.require(toFail: hold)"),
                      "the pager must wait for the hold to fail instead of resetting it mid-touch")
        XCTAssertTrue(owner.contains("Receive every touch and fail immediately"),
                      "empty Recents space must fail the hold so the pager can move")
        XCTAssertFalse(owner.contains("return canBeginVariantHold(at: touch.location(in: self))"),
                       "excluding a blank cell from the hold leaves the pager waiting forever")
        let categories = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")
        XCTAssertTrue(categories.contains("collapsedCircleFrame"))
        XCTAssertTrue(categories.contains("Swipe left or right to choose an emoji category."))
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
        XCTAssertTrue(root.contains("if state.areaMode == .emoji"),
                      "emoji content needs the rounded inset clipping path")
        XCTAssertTrue(root.contains(".clipShape(shape)"),
                      "emoji glyphs must not render through the Liquid Glass edge")
    }

    func testDictationBoardUsesABCAndSharedCommandGlassRadius() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("voiceBoardChrome(text: \"ABC\""))
        XCTAssertFalse(root.contains("utilityGlyph(systemName: \"keyboard\")"))
        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.commandKeyCornerRadius"))
        XCTAssertTrue(root.contains("CommandKeyFace("))
        XCTAssertFalse(root.contains("RoundedRectangle(cornerRadius: 18, style: .continuous)"))
    }
}
