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
        XCTAssertTrue(popup.contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
        XCTAssertTrue(popup.contains("fill(Color(uiColor: .tertiarySystemFill))"),
                      "hold-option menus match opaque letter-key plates when glass is off")
        XCTAssertFalse(popup.contains("fill(Color(uiColor: .systemBackground))"))
        XCTAssertTrue(popup.contains("struct KeyPreviewPopup"),
                      "press previews sit above keys when Key popups is popup")
        XCTAssertTrue(popup.contains("struct KeyPopoutPreview"),
                      "popout enlarges from the pressed key and fades")
        XCTAssertTrue(popup.contains("struct KeyPressPreviewHost"))
        XCTAssertTrue(popup.contains("return source"),
                      "popout stays on the key face and zooms out of it")
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
        XCTAssertTrue(owner.contains("hold.cancelsTouchesInView = true"),
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
        XCTAssertTrue(owner.contains("panGestureRecognizer.isEnabled = true"),
                      "after release/cancellation a swipe and subsequent tap must work again")
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
        let state = try source("DictusKeyboard/KeyboardState.swift")
        XCTAssertTrue(controller.contains("handleMicPressBegan()"))
        XCTAssertTrue(controller.contains("handleMicPressEnded()"))
        XCTAssertTrue(controller.contains("micButton?.isEnabled = false"))
        XCTAssertTrue(controller.contains("micButton?.isUserInteractionEnabled = false"))
        XCTAssertTrue(controller.contains("micButton?.frame = .zero"))
        XCTAssertTrue(state.contains("func handleMicPressBegan()"))
        XCTAssertTrue(state.contains("func handleMicPressEnded()"))
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

    func testDictationBoardUsesABCAndSharedCommandGlassRadius() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("voiceBoardChrome(text: \"ABC\""))
        XCTAssertFalse(root.contains("utilityGlyph(systemName: \"keyboard\")"))
        XCTAssertTrue(root.contains("RoundedRectangle(cornerRadius: 18, style: .continuous)"))
    }
}
