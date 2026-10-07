import XCTest
@testable import DictusCore

final class VoiceOnlyKeyboardContractTests: XCTestCase {
    func testPolicyDoesNotExposeRemovedTopAccessoryContract() throws {
        let policy = try source("DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift")

        for obsoleteName in [
            "alternateAccessoryRowFrame",
            "alternateContentBelowAccessoryFrame",
            "accessoryRevertFrame",
            "accessoryMicFrame",
            "accessoryDeleteFrame",
            "accessoryReturnFrame",
            "alternateAccessoryFrames",
            "hasValidAccessoryFrames"
        ] {
            XCTAssertFalse(policy.contains(obsoleteName), "obsolete policy API remains: \(obsoleteName)")
        }
    }

    func testPolicyExposesAlternatePageAccessoryAndContentGeometry() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 375, surfaceHeight: 228)

        XCTAssertEqual(layout.bottomAuxiliaryControlFrame.minX, layout.surfaceFrame.minX)
        XCTAssertEqual(layout.bottomAuxiliaryControlFrame.maxX, layout.surfaceFrame.maxX)
        XCTAssertEqual(layout.auxiliaryContentFrame.minY, layout.surfaceFrame.minY)
        XCTAssertEqual(layout.auxiliaryContentFrame,
                       CGRect(x: layout.surfaceFrame.minX,
                              y: layout.surfaceFrame.minY,
                              width: layout.surfaceFrame.width,
                              height: layout.bottomAuxiliaryControlFrame.minY - VoiceOnlyKeyboardPolicy.visibleControlGap - layout.surfaceFrame.minY))
    }

    func testSettingsKeyboardSectionUsesNativePickerSyntax() throws {
        let settings = try source("DictusApp/Views/SettingsView.swift")
        let keyboardStart = try XCTUnwrap(settings.range(of: "LabeledContent(\"Keyboard layout\")"))
        let nextSection = try XCTUnwrap(settings.range(of: "Section(\"Help\")", range: keyboardStart.upperBound..<settings.endIndex))
        let keyboardSection = String(settings[keyboardStart.lowerBound..<nextSection.lowerBound])

        XCTAssertFalse(keyboardSection.contains("Control order"))
        XCTAssertTrue(keyboardSection.contains("DefaultKeyboardModePicker()"))
        XCTAssertTrue(keyboardSection.contains("KeyboardMaterialPicker()"))
        XCTAssertFalse(keyboardSection.contains("ModelManagerView"))
    }

    func testUIKitAndSwiftUIConsumeTheCurrentAccessoryOrder() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(controller.contains("controlOrder: KeyboardAccessoryOrder.current"))
        XCTAssertTrue(root.contains("controlOrder: KeyboardAccessoryOrder.current"))
        let emojiFirst = VoiceOnlyKeyboardPolicy.layout(for: 390, controlOrder: .emojiFirst)
        let numberFirst = VoiceOnlyKeyboardPolicy.layout(for: 390, controlOrder: .numberFirst)
        XCTAssertNotEqual(emojiFirst.leftUtilityFrames.emoji, numberFirst.leftUtilityFrames.emoji)
        XCTAssertEqual(numberFirst.controlOrder, .numberFirst)
    }

    func testAuxiliaryUIKitControlsAreHiddenDisabledAndPassThroughToSwiftUI() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = !overlayVisible"))
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = overlayVisible"))
        XCTAssertTrue(controller.contains("$0.isEnabled = !$0.isHidden"))
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
    }

    func testHostedHitTestFallbackReachesEverySwiftUIKeySurface() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(
            !controller.contains("hostingView.hitTest(hostedPoint, with: event)"),
            "the visual hosting canvas must not intercept native control or blank-area touches"
        )
    }

    func testAuxiliaryModeSkipsAllUIKitFrameAndZOrderUpdates() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let start = try XCTUnwrap(controller.range(of: "private func layoutVoiceActionControls(surfaceHeight: CGFloat? = nil)"))
        let end = try XCTUnwrap(controller.range(of: "@objc private func handleMicTouchDown"))
        let body = String(controller[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(body.contains("let isAuxiliary = mode == .panel || mode == .emoji || mode == .letters || mode == .numberPad"))
        XCTAssertFalse(body.contains("micButton?.frame = .zero"), "relayout must preserve the active mic without a hide/reset cycle")
        XCTAssertTrue(body.contains("let micVisible = uikitOwnsVoiceChrome && !layout.dictateFrame.isEmpty"),
                      "the UIKit mic is active only when it owns the voice board")
        XCTAssertTrue(body.contains("let uikitOwnsVoiceChrome = voiceBoardMode"),
                      "visual material must not change UIKit control ownership")
        XCTAssertFalse(body.contains("let uikitOwnsVoiceChrome = voiceBoardMode && KeyboardInteractionPreferences.liquidGlassEnabled"),
                       "material switching must not strand a stale hit layer")
        XCTAssertTrue(body.contains("micButton?.frame = inputFrame(layout.dictateFrame)"),
                      "the active UIKit mic must cover the hosted dictate frame")
        XCTAssertTrue(body.contains("micButton?.isEnabled = dictateVisible"))
        XCTAssertTrue(body.contains("micButton?.isUserInteractionEnabled = dictateVisible"))
        XCTAssertTrue(controller.contains("micButton.onTouchDown ="),
                      "the transparent UIKit mic must deliver touch-down directly")
        XCTAssertTrue(controller.contains("micButton.onTouchUp ="),
                      "the transparent UIKit mic must deliver touch-up directly")
        XCTAssertTrue(controller.contains("micButton.onTouchCancelled ="),
                      "the transparent UIKit mic must deliver cancellation directly")
        XCTAssertTrue(body.contains("keyboardModeButton?.frame ="))
        XCTAssertTrue(body.contains("layout.dictationServiceToggleFrame"))
        XCTAssertTrue(body.contains("dictation-service-toggle") || controller.contains("\"dictation-service-toggle\""))
        XCTAssertTrue(controller.contains("setKeyboardDictationEnabled"))
        XCTAssertTrue(controller.contains("foreground: enabled ? .saiityAction : .secondaryLabel, role: .accessory"))
        XCTAssertTrue(body.contains("inputView.bringSubviewToFront(controls)"))
    }

    func testCurrentSymbolPagesHaveThreeContentRowsAndPageToggle() throws {
        for page in [KeyboardSymbolsLayout.numbers, KeyboardSymbolsLayout.symbols] {
            XCTAssertEqual(page.count, 3)
            XCTAssertTrue(page.flatMap { $0 }.contains { $0.kind == .insert(".") })
            XCTAssertTrue(page[2].contains { $0.kind == .pageToggle })
        }
    }

    func testSymbolFunctionalFramesClearTheActualBottomControlFootprint() {
        let spacing: CGFloat = 5
        let inset: CGFloat = 4

        for height in [CGFloat(216), CGFloat(228)] {
            let surfaceHeight = height - CGFloat(VoiceOnlyKeyboardPolicy.verticalPadding * 2)
            let gridHeight = surfaceHeight
            for rows in [KeyboardSymbolsLayout.numbers, KeyboardSymbolsLayout.symbols] {
                let widths = rows.map { row in row.map { CGFloat($0.width) } }
                let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
                    for: widths,
                    in: CGSize(width: 390, height: gridHeight),
                    spacing: spacing,
                    inset: inset,
                    rowSpacing: 6
                )
                let functionalFrames = zip(rows, frames).flatMap { row, rowFrames in
                    zip(row, rowFrames).compactMap { key, frame in
                        switch key.kind {
                        case .insert, .pageToggle, .emoji, .voice, .space, .delete, .returnKey: return frame
                        case .spacer: return nil
                        }
                    }
                }
                for keyFrame in functionalFrames {
                    XCTAssertLessThanOrEqual(keyFrame.maxY, gridHeight,
                                         "functional key frame must stay inside the shared surface at height \(height)")
                }
                XCTAssertTrue(frames.flatMap { $0 }.allSatisfy { $0.height >= 40 })
                XCTAssertEqual(frames[1][0].minX, inset, accuracy: 0.001)
            }
        }
    }


    func testMicrophoneSwiftUIHitTargetOwnsPressLifecycle() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertFalse(controller.contains("micButton?.frame = .zero"))
        XCTAssertTrue(controller.contains("micButton?.isUserInteractionEnabled = dictateVisible"))
        XCTAssertTrue(controller.contains("mic.bounds.insetBy(dx: -20, dy: -20)"),
                      "the recovery target must keep an explicit expanded UIKit hit region")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("ImmediateKeyButton("))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("highlightSize: frame.size"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains(".frame(width: frame.width, height: frame.height)"))
        XCTAssertFalse(root.contains("Link(destination:"))
        XCTAssertTrue(!controller.contains("hostingView.hitTest(hostedPoint, with: event)"),
                      "overlay misses must fall through to native sibling owners, not the visual host")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("holdDuration: isCancellationStage"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("onHold: isCancellationStage"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("state.openDictusForRecovery()"))
        XCTAssertFalse(root.contains("onTouchDown: { state.handleMicPressBegan() }"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("state.handleMicPressEnded()"))
        // The cancel-versus-dictate decision now reads one shared property
        // instead of three inline status comparisons that could drift apart.
        XCTAssertTrue((try relocatedKeyboardSource()).contains("state.dictationStatus.isCancellationStage"))
        XCTAssertFalse((try relocatedKeyboardSource()).contains("state.dictationStatus == .transcribing"))
        XCTAssertFalse((try relocatedKeyboardSource()).contains("state.dictationStatus == .processing"))
        XCTAssertTrue(try source("DictusKeyboard/KeyboardState.swift").contains("isFinishingRecording ? \"Finishing…\" : \"Finish\""))
        XCTAssertFalse(root.contains("HoldToSpeakButton("))
        XCTAssertFalse(controller.contains("layout.dictateFrame.insetBy(dx: -8, dy: -8)"))
        XCTAssertFalse(controller.contains("#selector(handleMicTap)"))
    }

    func testMicrophoneTouchDownGuardsBusyStatuses() throws {
        let state = try source("DictusKeyboard/KeyboardState.swift")

        XCTAssertTrue(state.contains("case .transcribing, .processing:"))
        XCTAssertTrue(state.contains("cancelActiveDictation()"))
        XCTAssertTrue(state.contains("case .requested, .recording:"))
    }

    func testDictationHapticsFollowHoldRecognitionAndFingerLift() throws {
        let state = try source("DictusKeyboard/KeyboardState.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        let beganStart = try XCTUnwrap(state.range(of: "func handleMicPressBegan()"))
        let beganEnd = try XCTUnwrap(state.range(of: "/// Cancel an active dictation", range: beganStart.upperBound..<state.endIndex))
        let beganBody = String(state[beganStart.lowerBound..<beganEnd.lowerBound])
        XCTAssertTrue(beganBody.contains("HapticFeedback.recordingStarted()"))
        XCTAssertTrue(beganBody.contains("startRecording()"))

        let endedStart = try XCTUnwrap(state.range(of: "func handleMicPressEnded()"))
        let endedEnd = try XCTUnwrap(state.range(of: "/// Keep the microphone open briefly", range: endedStart.upperBound..<state.endIndex))
        let endedBody = String(state[endedStart.lowerBound..<endedEnd.lowerBound])
        XCTAssertTrue(endedBody.contains("HapticFeedback.recordingStopped()"))
        XCTAssertTrue(endedBody.contains("scheduleDictationReleaseTail()"))

        XCTAssertTrue(controller.contains("self.micHoldRecognized = true"))
        XCTAssertTrue(controller.contains("state.handleMicPressBegan()"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("onHold: isCancellationStage"))
        XCTAssertFalse(root.contains("onPressBegan:"))
        XCTAssertFalse(controller.contains("HapticFeedback.dictationPressBegan()"))
    }

    func testMicrophoneVisualRemainsSwiftUIOnlyAndDoesNotInstallGestureStartStop() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(try source("DictusKeyboard/VoiceBoardSurface.swift").contains("appleControlSurface("))
        XCTAssertFalse(root.contains("appleControlSurface("))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("dictationButtonBackground"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("dictationButtonForeground"))
        // The recovery glyph belongs to the recovery control now; dictation is
        // always the mic. The two controls no longer swap symbols in one branch.
        XCTAssertTrue((try relocatedKeyboardSource()).contains("symbol: state.isOpeningForDictation ? \"ellipsis\" : \"arrow.up.right.square.fill\""))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("case .failed, .idle, .ready: return \"mic.fill\""))
        XCTAssertTrue(root.contains("voiceBoardUsesUIKitHits"))
        XCTAssertTrue(root.contains(".allowsHitTesting(!voiceBoardUsesUIKitHits)"),
                      "the SwiftUI mic must yield to the single UIKit voice-board owner")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
        XCTAssertFalse(root.contains("state.startRecording()"))
        XCTAssertFalse(root.contains("state.requestStop()"))
    }

    func testKeyboardRootUsesOnlyTheInsetSurfaceAndLeavesNativeBackdropToInputView() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("let surfaceFrame = layout.surfaceFrame"))
        XCTAssertTrue(root.contains("frame: surfaceFrame"))
        XCTAssertFalse(root.contains("Color(uiColor: .systemBackground)"),
                      "the UIInputView owns the keyboard backdrop")

        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390)
        XCTAssertEqual(layout.surfaceFrame.minX, 0)
        XCTAssertEqual(layout.surfaceFrame.minY, 4)
    }

    func testAlternatePagesLeaveTheInsetSurfaceAndUseTheNativeCanvas() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"),
                       "alternate content must use the complete shared surface")
        XCTAssertTrue(controller.contains("KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)"),
                      "the UIKit input view must provide the native adaptive backdrop")
        XCTAssertFalse(controller.contains("kbInputView.backgroundColor"),
                       "a transparent input view leaks the host wallpaper behind the keyboard")
        XCTAssertTrue(controller.contains("return CGFloat(resolution.height)"),
                      "alternate pages must keep the live native keyboard height")
        XCTAssertFalse(controller.contains("alternateMinimumHeight"),
                       "alternate pages must not grow for the removed accessory row")
    }

    func testMainTabsKeepSpeakAndSettingsAndOpenModelsFromSpeak() throws {
        let mainTabs = try source("DictusApp/Views/MainTabView.swift")
        let settings = try source("DictusApp/Views/SettingsView.swift")
        let home = try source("DictusApp/Views/HomeView.swift")

        XCTAssertFalse(mainTabs.contains("Label(\"Models\", systemImage:"),
                       "Models is a Speak destination, not a root tab")
        XCTAssertTrue(settings.contains("ModelManagerView(modelManager:"), "Models must also be reachable from Settings")
        XCTAssertTrue(home.contains("ModelManagerView(modelManager: modelManager)"),
                       "Models opens from Speak")
    }

    func testDictationErrorsRenderOutsideTheMicButton() throws {
        let root = try source("DictusKeyboard/VoiceBoardSurface.swift")
        let dictateButton = try XCTUnwrap(root.range(of: "private func dictateButton(frame:"))
        let dictateEnd = try XCTUnwrap(root.range(of: "private var dictationFaceStyle"))
        let buttonBody = String(root[dictateButton.lowerBound..<dictateEnd.lowerBound])

        XCTAssertTrue(root.contains("private var dictationErrorMessage"))
        XCTAssertTrue(root.contains("Text(dictationErrorMessage)"))
        XCTAssertTrue(root.contains(".foregroundStyle(.red)"))
        XCTAssertTrue(root.contains("layout.dictationErrorFrame"),
                      "the error must have its own bounded layout lane")
        XCTAssertTrue(root.contains("accessibilityIdentifier(\"dictation-error\")"),
                      "the error line must remain independently targetable")
        XCTAssertFalse(buttonBody.contains("statusMessage"),
                       "the mic capsule must remain reserved for its action state")
        // The recovery action is a separate control now, so the dictate capsule
        // no longer selects between the two labels. It must never render error
        // copy either — that belongs in the bounded error lane above.
        let stateSource = try source("DictusKeyboard/KeyboardState.swift")
        let failedBranch = try XCTUnwrap(stateSource.range(of: "case .idle, .ready, .failed: return"))
        let failedLine = String(stateSource[failedBranch.upperBound...].prefix(80))
        XCTAssertTrue(failedLine.contains("\"Hold to dictate\""),
                      "a failed dictation that can retry in-keyboard must offer the hold action")
        XCTAssertFalse(failedLine.contains("\"Open sAiity\""),
                       "the recovery label belongs to the recovery control, not the dictate capsule")
        XCTAssertFalse(failedLine.contains("statusMessage"),
                       "failure copy belongs in the separate error line")
    }

    func testEmojiRowsNeverOverflowTheCategoryBar() throws {
        let emoji = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(emoji.contains("private let headerHeight: CGFloat = 0"),
                      "the search-free emoji page must not reserve a hidden header")
        XCTAssertTrue(emoji.contains("UICollectionView"), "emoji rows use the native collection surface")
        XCTAssertTrue(emoji.contains("view.clipsToBounds = true"))
        XCTAssertTrue(emoji.contains("contentView.clipsToBounds = true"))
        XCTAssertFalse(emoji.contains("ScrollView(.vertical"))
        XCTAssertTrue(emoji.contains("for row in 0..<4"),
                      "emoji pages have four rows")
        XCTAssertFalse(emoji.contains("Text(selectedCategoryName)"),
                       "the removed search/header lane must not leave a second offset")
    }

    func testEmojiGridUsesOnePointerHighlightInsteadOfPerCellGlass() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertFalse(picker.contains(".keyboardGlassEffect()"),
                       "emoji cells must not own individual glass containers")
        XCTAssertFalse(picker.contains("stroke(Color.primary.opacity(0.16)"),
                       "duplicate SwiftUI glow/highlight rendering must be removed")
        XCTAssertTrue(picker.contains("UICollectionView"), "native cells own emoji interaction")
    }

    func testAuxiliaryKeysHaveOneGestureOwnerAndCancelPendingHolds() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertFalse(root.contains(".simultaneousGesture(symbolPointerGesture"))
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        XCTAssertTrue(grid.contains("override func touchesBegan("),
                      "letter variants use the shared native UIKit touch owner")
        XCTAssertTrue(grid.contains("override func touchesMoved("),
                      "variant tracking must update selection while the finger moves")
        XCTAssertTrue(grid.contains("if cancelled { continue }"),
                      "cancelled touches must not commit a key")
        XCTAssertTrue(grid.contains("presses[identity]"),
                      "multi-key tracking must only let the active touch finish")
        XCTAssertFalse(root.contains("letterTouchActive"))
        XCTAssertFalse(root.contains(".nativeKeyboardKeySurface()"))
        let buttons = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        XCTAssertTrue(buttons.contains("SpaceTrackingButton("))
        XCTAssertTrue(buttons.contains("DeleteRepeatControl("))
        let input = try source("DictusKeyboard/KeyboardKeyInput.swift")
        XCTAssertTrue(buttons.contains("KeyboardDeleteRepeatSession()"))
        XCTAssertTrue(input.contains("hold.begin(after: KeyboardDeletion.repeatDelay)"))
        XCTAssertTrue(input.contains("KeyboardDeletion.repeatInterval"))
        XCTAssertTrue(input.contains("KeyboardDeletion.repeatAction"))
        let repeatStart = try XCTUnwrap(input.range(of: "private func tick()"))
        let repeatEnd = try XCTUnwrap(input.range(of: "func cancel()", range: repeatStart.upperBound..<input.endIndex))
        let repeatBody = String(input[repeatStart.lowerBound..<repeatEnd.lowerBound])
        XCTAssertTrue(repeatBody.contains("HapticFeedback.keyTapped()"),
                      "a held delete key must click on every repeat tick")
    }

    func testKeyboardKeyFeedbackUsesSystemInputClick() throws {
        let haptics = try source("DictusCore/Sources/DictusCore/HapticFeedback.swift")
        XCTAssertTrue(
            haptics.contains("private static let keyGenerator = UIImpactFeedbackGenerator(style: .rigid)"),
            "keyboard feedback keeps its warm rigid generator"
        )
        XCTAssertTrue(haptics.contains("UIDevice.current.playInputClick()"),
                      "ordinary keys must use UIKit's native input-click path")
        let start = try XCTUnwrap(haptics.range(of: "public static func playInputClick()"))
        let end = try XCTUnwrap(
            haptics.range(of: "/// Immediate acknowledgement", range: start.upperBound..<haptics.endIndex)
        )
        let body = String(haptics[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(body.contains("guard isEnabled() else { return }"),
                       "the vibration switch must not suppress the system keyboard click")
        XCTAssertTrue(body.contains("emitKeyTap()"))
        XCTAssertTrue(body.contains("UIDevice.current.playInputClick()"))
        let emitterStart = try XCTUnwrap(haptics.range(of: "private static func emitKeyTap()"))
        let emitter = String(haptics[emitterStart.lowerBound...])
        XCTAssertTrue(emitter.contains("_intensity.keyTapIntensity"),
                      "keys and delete must use the same selected preset")
        let impact = try XCTUnwrap(emitter.range(of: "impactOccurred(intensity:"))
        let prime = try XCTUnwrap(emitter.range(of: "keyGenerator.prepare()"))
        XCTAssertLessThan(impact.lowerBound, prime.lowerBound,
                          "priming the Taptic Engine before the impact delays the tick")
    }

    func testEmojiPointerUsesSharedGridGeometryAndReleaseContract() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains("private var emojiColumnCount: Int"),
                      "grid geometry must compute one shared column count")
        XCTAssertTrue(picker.contains("Int((emojiGridWidth - gridHorizontalPadding * 2) / minimumEmojiTargetWidth)"),
                      "the column count must preserve the minimum emoji target width")
        XCTAssertTrue(picker.contains("minimumEmojiTargetWidth: CGFloat = 44"),
                      "emoji targets must be at least 44pt")
        XCTAssertTrue(picker.contains("max(1, "),
                      "narrow widths must still produce a valid positive column count")
        XCTAssertTrue(picker.contains("private let gridHorizontalPadding: CGFloat = 0"),
                      "page edges must touch so category transitions do not create a dead gap")
        XCTAssertTrue(picker.contains("emojiGridWidth - gridHorizontalPadding * 2"),
                      "cell width must use the shared horizontal padding")
        XCTAssertTrue(picker.contains("private var emojiGridWidth: CGFloat"),
                      "the scrolling viewport must use one full-width geometry")
        XCTAssertTrue(picker.contains("max(0, availableWidth)"),
                      "the emoji grid may render beneath the fixed delete target")
        XCTAssertTrue(picker.contains("override var isHighlighted: Bool"),
                      "the highlight must be owned by the native emoji button")
        XCTAssertTrue(picker.contains("UICollectionView"), "categories use a native collection view")
        XCTAssertTrue(picker.contains("EmojiNavigation.scrollResolution("),
                      "category-bar jumps must use the first page containing the category")
        let pages = try source("DictusCore/Sources/DictusCore/EmojiSurfaceModel.swift")
        XCTAssertTrue(pages.contains("for category in categories"),
                      "each standard category must be chunked independently")
        XCTAssertFalse(picker.contains("let standardItems = categories.flatMap"),
                       "categories must not share a page")
        XCTAssertTrue(pages.contains("let pageCount = EmojiNavigation.pageCount"),
                      "each category should own complete native-style pages")
        XCTAssertTrue(picker.contains("private let pageGap: CGFloat = 0"),
                      "category pages must use exact viewport-width offsets")
        XCTAssertTrue(picker.contains("private var pageWidths: [CGFloat]"),
                      "incomplete category pages must use measured widths")
        XCTAssertTrue(picker.contains("pageWidths: pageWidths.map(Double.init)"),
                      "programmatic jumps must use cumulative responsive widths")
        XCTAssertTrue(pages.contains("columns: emojiColumnCount"),
                      "recents must remain a full-width viewport page")
        XCTAssertTrue(picker.contains("EmojiSurfaceModel.pages("),
                      "the picker renders the extracted page plan")
        XCTAssertFalse(picker.contains("TabView("))
        XCTAssertFalse(picker.contains("ScrollView(.vertical"))
        XCTAssertTrue(picker.contains("EmojiGestureCoordinator"),
                      "skin-tone extras use the unified tap/hold gesture owner")
        XCTAssertFalse(picker.contains("emojiDragAxis"),
                       "horizontal scrolling owns drag; there is no second drag-select axis")
        XCTAssertTrue(picker.contains("UIButton"),
                      "emoji taps must remain native button interactions")
        XCTAssertTrue(picker.contains("onTap?(inputEmoji)"),
                      "emoji release must call the tap insertion callback")
        XCTAssertTrue(picker.contains("let index = column * 4 + row"),
                      "emoji cells must fill top-to-bottom before moving right")
        let ownerStart = try XCTUnwrap(picker.range(of: "class EmojiPagerCollectionView:"))
        let ownerEnd = try XCTUnwrap(picker.range(of: "private final class EmojiPageCell"))
        let owner = String(picker[ownerStart.lowerBound..<ownerEnd.lowerBound])
        XCTAssertTrue(owner.contains("private lazy var hold = EmojiGestureCoordinator("),
                      "one stable pager recognizer survives cell reuse and category changes")
        XCTAssertTrue(owner.contains("addGestureRecognizer(hold)"))
        let hold = try source("DictusKeyboard/Views/EmojiGestureCoordinator.swift")
        XCTAssertTrue(hold.contains("cancelsTouchesInView = false"),
                      "a failed hold must leave blank-area paging with the collection view")
        XCTAssertTrue(picker.contains("suppressNextTapAfterVariantHold"),
                      "a recognized hold must still suppress the UIButton base tap")
        XCTAssertTrue(picker.contains("allowableMovement: preRecognitionMovement"),
                      "emoji holds must tolerate normal finger jitter before recognition")
        XCTAssertTrue(hold.contains("self.state = .began"),
                      "the popup owner must keep tracking after the hold begins")
        XCTAssertTrue(owner.contains("hypot(translation.x, translation.y) < preRecognitionMovement"),
                      "a still hold must beat scrolling; a swipe still pages")
        XCTAssertFalse(owner.contains("guard !isDragging, !isDecelerating"),
                       "small pager jitter must not cancel a pending emoji hold")
        XCTAssertFalse(owner.contains("panGestureRecognizer.require(toFail: hold)"),
                       "blank pager space must be able to pan without waiting on a hold")
        XCTAssertTrue(owner.contains("button.convert(button.bounds, to: self)"))
        XCTAssertTrue(owner.contains("frame.offsetBy(dx: bounds.minX, dy: bounds.minY)"),
                      "source and popup must share scrolled content coordinates")
        XCTAssertTrue(owner.contains("addSubview(popup)"),
                      "the gesture owner presents synchronously without a SwiftUI state round trip")
        XCTAssertTrue(owner.contains("updateVariantSelection(at: recognizer.location(in: self))"))
        XCTAssertFalse(owner.contains("guard selectedIndex >= 0 else { return }"),
                       "selection must not be cancelled by leaving the popup corridor")
        XCTAssertTrue(owner.contains("EmojiToneHitTesting.selectedIndex"),
                      "selection must use the shared horizontal clamping geometry")
        XCTAssertFalse(owner.contains("panGestureRecognizer.isEnabled = false"),
                       "the pager pan must not be toggled during an active hold")
        XCTAssertTrue(owner.contains("case .cancelled, .failed:\n            cancelVariantSelection()"))
        XCTAssertTrue(picker.contains("!view.hasVariantSelection"),
                      "a content reload must not dismantle a held selection")
        XCTAssertTrue(picker.contains("accessibilityCustomActions = EmojiSkinToneVariants.options"),
                      "VoiceOver must retain direct access to every tone")
        XCTAssertFalse(picker.contains(".simultaneousGesture(emojiGesture)"),
                      "the hold recognizer must not take ownership of horizontal scrolling")
        XCTAssertTrue(picker.contains("minimumPressDuration: KeyboardDeletion.holdRecognitionDuration"),
                      "scrolling must cancel a pending emoji hold")
        XCTAssertTrue(picker.contains("scrollViewDidScroll"),
                      "category highlight follows the selected native page")
        XCTAssertTrue(picker.contains("scrollViewWillBeginDragging"),
                      "manual swipes must cancel stale category jump requests")
        XCTAssertTrue(picker.contains("onManualScroll: { scrollRequest = nil }"),
                      "manual navigation must clear the programmatic scroll request")
        let insertStart = try XCTUnwrap(picker.range(of: "private func insertEmoji"))
        let insertEnd = try XCTUnwrap(picker.range(of: "// MARK: - Scroll canvas"))
        let insertBody = String(picker[insertStart.lowerBound..<insertEnd.lowerBound])
        XCTAssertTrue(insertBody.contains("RecentEmojis.add(emoji, limit:"))
        XCTAssertFalse(insertBody.contains("recentEmojis = RecentEmojis.load("),
                       "inserting an emoji must not rebuild the grid from recents")
    }

    func testEmojiPagerUsesStablePagesAndFreeScrollingWithoutTouchReloads() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains("@State private var pageRevision = 0"))
        XCTAssertTrue(picker.contains("pageRevision: pageRevision"),
                      "the coordinator must detect page changes without rebuilding emoji signatures")
        XCTAssertTrue(picker.contains("private func reloadIfIdle"))
        XCTAssertTrue(picker.contains("context.coordinator.reloadWhenIdle(uiView)"))
        XCTAssertTrue(picker.contains("isPagingEnabled = false"),
                      "variable-width emoji pages cannot use equal UIKit paging")
        XCTAssertFalse(picker.contains("scrollViewWillEndDragging"),
                       "manual swipes keep UIKit's projected offset; category jumps set the offset themselves")
        XCTAssertFalse(picker.contains("targetContentOffset.pointee.x"),
                       "rewriting the release offset snaps pages the user did not ask to snap")
        XCTAssertTrue(picker.contains("setContentOffset"),
                      "an explicit category jump still moves to the measured page")
        XCTAssertTrue(picker.contains("VoiceOnlyKeyboardPolicy.emojiHighlightCornerRadius"))
        XCTAssertFalse(picker.contains("layer.cornerRadius = 13"))
    }

    func testEmojiGridRoundsRowsDownToKeepTheFourthRowVisible() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains("usable / rows"))
        XCTAssertTrue(picker.contains("for row in 0..<4"))
    }

    func testEmojiSearchHasNoReachableUI() throws {
        let emoji = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let categoryBar = try source("DictusKeyboard/Views/EmojiCategoryBar.swift")

        XCTAssertFalse(emoji.contains("isSearchActive"))
        XCTAssertFalse(emoji.contains("searchMode"))
        XCTAssertFalse(emoji.contains("MiniSearchKeyboard"))
        XCTAssertFalse(emoji.contains("EmojiSearchFR"))
        XCTAssertFalse(categoryBar.contains("onSearch"))
        XCTAssertFalse(categoryBar.contains("magnifyingglass"))
    }

    func testSymbolsPageDoesNotReserveAHiddenPatchRow() throws {
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        let numbersStart = try XCTUnwrap(layouts.range(of: "private static func numbersPage"))
        let symbolsStart = try XCTUnwrap(layouts.range(of: "private static func symbolsPage"))
        let helperStart = try XCTUnwrap(layouts.range(of: "// MARK: - Bottom Rows"))
        let numberBody = String(layouts[numbersStart.lowerBound..<symbolsStart.lowerBound])
        let symbolsBody = String(layouts[symbolsStart.lowerBound..<helperStart.lowerBound])

        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 3"))
        XCTAssertFalse(numberBody.contains("blankRow()"))
        XCTAssertFalse(symbolsBody.contains("blankRow()"))
        XCTAssertFalse(controller.contains("contentFrame.size.height = max(contentFrame.height"))
        XCTAssertFalse(root.contains("SymbolKeyboardSurface("))
        XCTAssertFalse(root.contains("NumberKeyboardSurface("))
        XCTAssertTrue(root.contains("KeyboardViewController.nextKeyboardModes.contains(state.areaMode)"))
        XCTAssertTrue(root.contains(".frame(width: surfaceFrame.width, height: surfaceFrame.height)"),
                      "the clear canvas must fill the shared inset surface")
    }

    func testAuxiliaryContentUsesTheCompleteSurfaceWithoutUIKitAccessoryRow() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"))
        XCTAssertTrue(root.contains("areaSurface(layout: layout, contentFrame: surfaceFrame)"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = overlayVisible"),
                      "overlay interaction must follow the surface that owns input")
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"))
    }

    func testAuxiliaryControlsAreOwnedBySwiftUISurface() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(root.contains("alternateAccessoryRow(layout:"),
                       "the alternate accessory row must not be rendered inside SwiftUI")
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"),
                       "UIKit must not install an alternate accessory row")
        // A hidden UIKit view does not pass touches through, and keeping the
        // container "live" is exactly what let an invisible
        // `return-to-dictation-board` sit over the letter grid and swallow taps
        // meant for the top row of letters.
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = overlayVisible"),
                      "the overlay must be gated on the surfaces UIKit actually owns")
    }

    func testAuxiliaryLayoutRaisesUIKitControlsAboveEveryAuxiliarySubview() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"))
    }

    func testAuxiliaryAccessoryUsesUIKitNativeVisualsWithoutSwiftUIActions() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"),
                       "the removed accessory row must not have a UIKit styling path")
        XCTAssertFalse(controller.contains("installGlassBackground"),
                       "auxiliary UIKit controls must not add another glass/background layer")
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("dictationButtonBackground"),
                      "the voice page keeps the shared dictation button state styling")
        XCTAssertTrue((try relocatedKeyboardSource()).contains("KeyboardDictationFaceStyle"),
                      "the voice page exposes a distinct cancellation state")
        XCTAssertFalse(root.contains("state.startRecording()"))
        XCTAssertFalse(root.contains("state.requestStop()"))
    }

    func testAuxiliaryModeOwnsOnlyRevertMicDeleteAndReturnControls() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = !overlayVisible"),
                      "SwiftUI-owned surfaces must hide the UIKit overlay entirely")
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = overlayVisible"))
        XCTAssertFalse(controller.contains("micButton?.frame = .zero"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"))
    }

    func testAuxiliaryControlsHideWhenAccessoryRowIsUnavailable() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = !overlayVisible"))
        XCTAssertTrue(controller.contains("$0.isEnabled = !$0.isHidden"))
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
    }

    func testReturningToVoiceRemovesAuxiliaryGlassBackgrounds() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertFalse(controller.contains("glassBackgroundTag"),
                       "there must be no auxiliary glass layer to leak into voice mode")
        XCTAssertFalse(controller.contains("installGlassBackground"),
                       "voice mode must reuse the shared SwiftUI surface")
    }

    func testAuxiliaryUIKitAccessoryRowFailsClosedWithItsGeometry() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = overlayVisible"),
                      "the overlay fails closed on surfaces SwiftUI owns")
    }

    func testUIKitBackdropAndPressedRadiusUseActualFrames() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let inputView = try source("DictusKeyboard/InputView.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(inputView.contains("inputViewStyle: .keyboard"))
        XCTAssertTrue(inputView.contains("backgroundColor = .clear"))
        XCTAssertTrue(inputView.contains("isOpaque = false"))
        XCTAssertTrue(controller.contains("hosting.view.isOpaque = false"),
                      "the hosting view must not create a rectangular backdrop")
        XCTAssertTrue(controller.contains("$0.layer.cornerRadius = $0.bounds.height / 2"))
        XCTAssertTrue(controller.contains("micButton?.layer.cornerRadius = (micButton?.bounds.height ?? 0) / 2"))
        XCTAssertFalse(root.contains("Color(uiColor: .systemBackground)"))
    }

    func testAuxiliaryReturnUsesSharedAppleControlSurfaceSemantics() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertFalse(root.contains("onBackToVoice:"))
        XCTAssertTrue(controller.contains("label: \"Back to dictation\""))
        XCTAssertTrue(controller.contains("KeyboardState.shared.closeArea()"))
        XCTAssertFalse(controller.contains("imageName: \"arrow.uturn.backward\""))
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
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    func testKeyboardSymbolLayerHasNativeHeightAndReturnsToLetters() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")

        XCTAssertFalse(root.contains("SymbolKeyboardSurface("))
        XCTAssertFalse(root.contains("onTogglePage:"))
        let host = try source("DictusKeyboard/Next/NextKeyboardHost.swift")
        XCTAssertTrue(host.contains("case .page(let id):"))
        XCTAssertTrue(host.contains("symbolPage = (symbolPage == .symbolsNumbers) ? .symbolsPunctuation : .symbolsNumbers"))
        XCTAssertTrue(controller.contains("KeyboardHeightProvider.height"))
        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"))
        XCTAssertTrue(controller.contains("min(requestedHeight, inputView.bounds.height)"), "the accessory lane must fit the actual host height")
        XCTAssertTrue(controller.contains("surfaceHeight: Double(max(1, resolvedHeight))"))
        let bottomBar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        XCTAssertTrue(bottomBar.contains("DeleteRepeatControl("))
        XCTAssertTrue(try source("DictusKeyboard/KeyboardKeyInput.swift").contains("RunLoop.main.add(timer, forMode: .common)"))
        XCTAssertTrue(layouts.contains("KeyDefinition(type: .shiftSymbols"))
        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 3"))
    }

    func testLetterKeyboardUsesPerKeyUIKitControlsAndSharedBottomRow() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")
        let policy = try source("DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift")

        XCTAssertFalse(controller.contains("GiellaKeyboardView("))
        XCTAssertFalse(controller.contains("GiellaKeyboardViewDelegate"))
        XCTAssertTrue(grid.contains("final class KeyGridView: UIView"))
        XCTAssertTrue(grid.contains("override func touchesBegan("))
        XCTAssertFalse(grid.contains("ImmediateKeyButton"))
        XCTAssertFalse(grid.contains("LetterInteractionSurface"))
        XCTAssertTrue(factory.contains("static func letters() -> KeyGridPage"))
        XCTAssertTrue(controller.contains("case .keyboardMode:"))
        XCTAssertTrue(controller.contains("case .symbols:"))
        XCTAssertTrue(controller.contains("applyCursorStep"))
        XCTAssertTrue(layouts.contains("private static func letterBottomRow"))
        XCTAssertTrue(layouts.contains("emojiKeyGlyph"))
        XCTAssertTrue(layouts.contains("KeyDefinition(type: .keyboardMode"))
        XCTAssertTrue(policy.contains("public var letterKeyboardFrame"))
        XCTAssertFalse(policy.contains("public var letterMicFrame"),
                       "letter mode must not reserve a dictation button")
    }

    func testRuntimeSurfaceUsesOneSharedLayoutContract() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(controller.contains("controlOrder: KeyboardAccessoryOrder.current"))
        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"))
        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.layout("))
        XCTAssertTrue(root.contains("surfaceHeight: Double(surfaceHeight)"))
    }

    func testEmojiPickerReceivesTheInsetContentHeight() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let emoji = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        let native = try source("DictusKeyboard/Next/KeyboardSurfaceView.swift")
        XCTAssertTrue(native.contains("emoji.frame = layout.inputFrame(pager, inputViewHeight: inputHeight)"),
                      "emoji pager height must match the inset content above the category lane")
        XCTAssertTrue(emoji.contains("private let edgeInset: CGFloat = VoiceOnlyKeyboardPolicy.keyGridInset"),
                      "emoji geometry must use the same 8pt breathing room as ABC/123")
        XCTAssertFalse(root.contains("availableHeight: surfaceHeight"),
                       "the outer keyboard height includes the surface inset")
    }

    func testSymbolsReserveTheBottomRowForTheTopmostABCControlGeometryOnly() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 3"))
        XCTAssertFalse(root.contains("SymbolKeyboardSurface("))
        XCTAssertFalse(root.contains("NumberKeyboardSurface("))
        XCTAssertTrue(controller.contains("static let nextKeyboardModes: Set<KeyboardAreaMode> = [.letters, .panel, .numberPad]"))
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"),
                      "the UIKit mode control must remain above the symbols surface")
    }

    func testBothAuxiliaryModeControlsUseOnlyTheirSmallUtilityHitFrame() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertEqual(controller.components(separatedBy: "numberButton?.frame = inputFrame(layout.chromeNumbersFrame)").count - 1, 1,
                       "both auxiliary modes must share one compact frame assignment")
    }

    func testAuxiliaryModeControlUpdatesAccessibilitySemantics() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(controller.contains("label: \"Back to dictation\""),
                      "the voice-return control must describe its action")
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        XCTAssertTrue(factory.contains("label: page == .symbolsNumbers ? \"#+=\" : \"123\""),
                      "the symbol page toggle must describe its page")
        XCTAssertTrue(controller.contains("Open symbols keyboard"),
                      "normal mode must announce opening symbols")
        XCTAssertTrue(controller.contains("KeyboardState.shared.closeArea()"),
                      "auxiliary mode must announce returning to the voice keyboard")
        XCTAssertTrue(controller.contains("surface.bottomBar.onDictation = { KeyboardState.shared.presentArea(.keys) }"),
                      "holding the bottom layer control must reach dictation")
        XCTAssertTrue(controller.contains("self?.presentNumbersArea()"),
                      "123 must open the pad on numeric fields and symbols otherwise")
        XCTAssertTrue(root.contains("state.presentNumbersArea()"),
                      "letter and emoji 123 must use the same numbers destination")
    }

    func testAuxiliaryKeyboardUsesFullSurfaceAndActionControlsStayOnTop() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controlOrder: KeyboardAccessoryOrder.current"))
        XCTAssertTrue(controller.contains("actionControlsView = controls"))
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"))
    }

    func testAuxiliarySpacebarKeepsSwiftUIOwnershipForCursorDragging() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")

        XCTAssertTrue(controller.contains("let isAuxiliary = mode == .panel || mode == .emoji || mode == .letters || mode == .numberPad"))
        XCTAssertFalse(controller.contains("micButton?.frame = .zero"))
        XCTAssertTrue(controller.contains("surface.bottomBar.spaceControl.onCursorMoved = { [weak self] in self?.applyCursorStep($0) }"))
        XCTAssertTrue(controller.contains("space.onCursorMoved = { [weak self] in self?.applyCursorStep($0) }"))
        XCTAssertTrue(bar.contains("struct SpaceBarControl: View"))
        XCTAssertTrue(bar.contains("onCursorMoved: onSpaceCursorMoved"))
        XCTAssertTrue(bar.contains("SpaceTrackingButton("))
        XCTAssertTrue(bar.contains("continueTracking"))
        XCTAssertTrue(bar.contains("cursorHoldDuration"))
        XCTAssertTrue(bar.contains("KeyboardDeletion.cursorHoldDuration"))
        XCTAssertTrue(bar.contains("UIPanGestureRecognizer"),
                      "spacebar cursor tracking needs an edge-safe pan fallback")
        XCTAssertTrue(bar.contains("cancelsTouchesInView = false"),
                      "cursor tracking must not cancel neighboring key touches")
        XCTAssertTrue(bar.contains("trackingCoordinateView"),
                      "cursor tracking must use a stable coordinate space outside the control")
        XCTAssertTrue(bar.contains("joystickOrigin"),
                      "cursor tracking must freeze the joystick origin at press")
        XCTAssertTrue(bar.contains("KeyboardCursorJoystickSampler"),
                      "cursor tracking must follow the finger, then cruise from the origin")
        XCTAssertTrue(bar.contains("sampler.tick("),
                      "cursor tracking must sample finger travel every tick")
        XCTAssertFalse(bar.contains("KeyboardCursorJoystick.tickInterval"),
                       "cursor tracking must not synthesize movement while still")
        XCTAssertFalse(bar.contains("startJoystickTimer()"),
                       "cursor tracking must not use a repeating joystick timer")
        XCTAssertFalse(bar.contains("CADisplayLink"),
                       "cursor movement must be driven by touch deltas")
        XCTAssertTrue(bar.contains("handleCursorPan"),
                      "cursor tracking must handle movement after leaving the spacebar")
        XCTAssertFalse(bar.contains("HapticFeedback.trackpadActivated()"),
                       "spacebar cursor drag must not play activation haptics")
        XCTAssertTrue(controller.contains("HapticFeedback.cursorMoved()"),
                       "each horizontal character move must provide selection feedback")
        XCTAssertTrue(controller.contains("KeyboardCursorTrackpad.visualOffset("),
                      "cursor drag must jump to a 2D layout position, not walk the string")
        XCTAssertTrue(controller.contains("let space = SpaceTrackingButton.TrackingControl()"),
                      "dictation and typing must share the same press origin and cursor component")
        let cursor = try source("DictusKeyboard/Vendored/Controllers/LongPressController.swift")
        XCTAssertTrue(cursor.contains("KeyboardCursorJoystickSampler"),
                      "dictation spacebar must use the same finger-following sampler")
        XCTAssertTrue(cursor.contains("sampler.tick("),
                      "dictation spacebar must sample finger travel every tick")
        XCTAssertFalse(cursor.contains("KeyboardCursorJoystick.tickInterval"),
                       "dictation spacebar must not synthesize movement while still")
        XCTAssertFalse(cursor.contains("CADisplayLink"),
                       "dictation spacebar cursor movement must be driven by touch deltas")
        XCTAssertFalse(cursor.contains("HapticFeedback.trackpadActivated()"),
                       "dictation spacebar cursor drag must not play activation haptics")
        XCTAssertFalse(controller.contains("spaceButton?.frame = layout.letterSpaceFrame"),
                       "auxiliary pages must not cover the SwiftUI spacebar with UIKit")
    }

    func testLetterKeyboardOwnsTheCompleteNativeBottomRow() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")

        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        XCTAssertTrue(bar.contains("firstControl.keyboardFace.configure(text: mode == .panel ? \"ABC\" : \"123\""),
                      "letter mode must expose an explicit 123 control")
        XCTAssertTrue(controller.contains("surface.bottomBar.spaceControl.onTap = { [weak self] in self?.routeProxyCommand(.space) }"),
                      "letter mode must route its spacebar through the keyboard command")
        XCTAssertTrue(controller.contains("case .spacebar:"))
        XCTAssertTrue(controller.contains("case .backspace:"))
        XCTAssertTrue(factory.contains("systemImage: CommandKeyStyle.deleteSymbolName"),
                      "letter mode's delete key must have a visible glyph")
        XCTAssertTrue(try source("DictusCore/Sources/DictusCore/CommandKeyStyle.swift").contains("deleteSymbolName = \"delete.backward\""))
        XCTAssertTrue(root.contains("onDelete: { routeProxyCommand(.delete) }"),
                      "the dictation board delete key must route to the text proxy")
        XCTAssertTrue(bar.contains("roundControl(text: numbersTitle"),
                      "the shared bottom row must render 123 as a real button")
        XCTAssertTrue(bar.contains("HapticFeedback.keyTapped()"),
                      "bottom-row actions must provide optional haptic feedback")
    }

    func testBothAuxiliaryPagesKeepModeControlAvailableToReturnToNormal() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = !overlayVisible"))
        XCTAssertTrue(controller.contains("layoutVoiceActionControls()"),
                      "mode visibility must be refreshed after each layout transition")
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"),
                      "UIKit action controls must be restored above auxiliary content")
    }

    func testAuxiliaryAccessoryUsesUIKitRevertControlInsteadOfVoiceABCVisual() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        XCTAssertTrue(bar.contains("roundControl(systemName: \"face.smiling\", label: \"Emoji\", action: onEmoji)"))
        XCTAssertTrue(bar.contains("roundControl(text: \"ABC\", label: \"Open letter keyboard\", action: onLetters)"))
        XCTAssertFalse(bar.contains("layout.auxiliaryMicrophoneFrame"))
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
    }

    func testEmojiGridReservesTheCategoryBarLaneExplicitly() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(picker.contains("gridHeight: emojiGridHeight"),
                      "emoji scrolling stays on a compact 4-row inset instead of stretching the glass")
        XCTAssertTrue(picker.contains("usable / rows"))
        XCTAssertTrue(picker.contains("UICollectionView"),
                      "emoji categories keep a stable native collection surface")
        XCTAssertFalse(picker.contains("TabView("))
        XCTAssertFalse(picker.contains("ScrollView(.vertical"))
        XCTAssertTrue(picker.contains("AuxiliaryBottomBar("))
        let native = try source("DictusKeyboard/Next/KeyboardSurfaceView.swift")
        XCTAssertTrue(native.contains("EmojiCategoryBar("),
                      "the native board owns the visible category chrome")
        XCTAssertTrue(native.contains("selectedCategoryID: sections.indices.contains(index)"),
                      "the full category bar mirrors the native selection")
        XCTAssertFalse(root.contains("KeyboardNativeOverlay("))
        XCTAssertTrue(native.contains("let emojiDelete = KeyboardDeleteRepeatControl()"))
        XCTAssertTrue(native.contains("floatingEmojiCategoryFrame"))
        XCTAssertTrue(native.contains("boardDeleteFrame"))
        XCTAssertFalse(picker.contains("systemName: \"mic.fill\""))
    }

    func testSymbolsReserveTheBottomLeftControlFootprintAcrossLastTwoRows() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertFalse(root.contains("bottomControlReservedUnits"))
        XCTAssertFalse(root.contains("leadingReservedWidths"))
        XCTAssertFalse(root.contains("positionedKeys(in: gridSize).filter"),
                       "functional symbol keys must remain available")
    }

    /// The delete key must stop repeating on both release and cancellation.
    ///
    /// This used to assert against the vendored `GiellaKeyboardView`, which is
    /// not in the render or hit path any more — the live owner is
    /// `KeyboardDeleteRepeatControl`. Pinning the dead file meant the assertion
    /// could pass while the real control regressed.
    func testDeleteRepeatStopsOnCancelAndEnd() throws {
        let bar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        let start = try XCTUnwrap(bar.range(of: "final class KeyboardDeleteRepeatControl"))
        let body = String(bar[start.lowerBound...])

        XCTAssertTrue(body.contains("override func touchesEnded"),
                      "release must be handled explicitly")
        XCTAssertTrue(body.contains("override func touchesCancelled"),
                      "a cancelled gesture must be handled, not ignored")
        let ended = try XCTUnwrap(body.range(of: "override func touchesEnded"))
        let cancelled = try XCTUnwrap(body.range(of: "override func touchesCancelled"))
        let endedBody = String(body[ended.upperBound..<cancelled.lowerBound])
        XCTAssertTrue(endedBody.contains("finish()"),
                      "release must run the same teardown as cancellation")
        XCTAssertTrue(body.contains("deleteRepeat.cancel()"),
                      "release must cancel the shared clock so another tick cannot fire")
    }

    func testPredictedLetterWinsOverlappingExpandedHitTargets() throws {
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        let placement = try source("DictusCore/Sources/DictusCore/NextKeyGridPlacement.swift")
        let geometry = try source("DictusCore/Sources/DictusCore/AdaptiveTouchRouting.swift")
        let buttons = try source("DictusKeyboard/KeyboardKeyInput.swift")

        XCTAssertTrue(grid.contains("KeyGridPlacement.retarget(neutralLayout, probabilities: hitPrediction)"))
        XCTAssertTrue(placement.contains("KeyboardKeyHitGeometry.contiguousTiles("))
        XCTAssertTrue(geometry.contains("public enum KeyboardKeyHitGeometry"))
        XCTAssertTrue(geometry.contains("maximumPredictionShift: CGFloat = 4"))
        XCTAssertTrue(buttons.contains("bounds.contains(point)"),
                      "the target control owns exactly its precomputed hit frame")
        XCTAssertFalse(buttons.contains("keyClaims("),
                       "key ownership must not depend on a global overlapping-frame registry")
    }

    func testVoiceOnlyKeyboardHasNoLegacyBridgeWiring() throws {
        // These are source-contract checks only. They do not instantiate UIKit or
        // prove runtime keyboard behavior.
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let controller = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"), encoding: .utf8)
        let root = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"), encoding: .utf8)
        let state = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardState.swift"), encoding: .utf8)
        let suggestionState = try String(contentsOf: repository.appending(path: "DictusKeyboard/TextPrediction/SuggestionState.swift"), encoding: .utf8)
        let settings = try String(contentsOf: repository.appending(path: "DictusApp/Views/SettingsView.swift"), encoding: .utf8)
        let project = try String(contentsOf: repository.appending(path: "Dictus.xcodeproj/project.pbxproj"), encoding: .utf8)
        let bridge = repository.appending(path: "DictusKeyboard/DictusKeyboardBridge.swift")

        XCTAssertFalse(controller.contains("DictusKeyboardBridge"))
        XCTAssertFalse(controller.contains("suggestionState"))
        XCTAssertFalse(root.contains("DictusKeyboardBridge"))
        XCTAssertFalse(root.contains("legacyBody"))
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        let placement = try source("DictusCore/Sources/DictusCore/NextKeyGridPlacement.swift")
        XCTAssertTrue(grid.contains("KeyGridPlacement.retarget(neutralLayout, probabilities: hitPrediction)"),
                      "local prediction is used only for invisible key-area expansion")
        XCTAssertTrue(placement.contains("KeyboardKeyHitGeometry.contiguousTiles("))
        XCTAssertTrue(controller.contains("SuggestionState.shared.adaptiveTouchPrediction"))
        XCTAssertFalse(root.contains("LetterKeyboardSurface("))
        XCTAssertFalse(root.contains("fullAreaToolbar"))
        XCTAssertFalse(root.contains("togglePanel"))
        XCTAssertFalse(root.contains("keyboard-controls"))
        XCTAssertTrue(controller.contains("keyboard.chevron.compact.down"))
        XCTAssertFalse(root.contains("keyboard.chevron.compact.down"))
        XCTAssertFalse(root.contains("usesInteractiveSurface: false"))
        XCTAssertTrue(controller.contains("surface.bottomBar.onEmoji = { KeyboardState.shared.presentArea(.emoji) }"))
        XCTAssertTrue(root.contains("state.presentArea(.emoji)"))
        XCTAssertFalse(root.contains("private func utilityButton("))
        XCTAssertFalse(root.contains("LazyVGrid"))
        XCTAssertTrue(root.contains("allowsHitTesting(false)"))
        XCTAssertTrue(controller.contains("numbers.accessibilityIdentifier = \"number-layer\""))
        XCTAssertTrue(controller.contains("KeyboardState.shared.closeArea()"))
        XCTAssertTrue(controller.contains("identifier: \"letter-mode\""))
        XCTAssertTrue(controller.contains("identifier: \"emoji-picker\""))
        XCTAssertTrue(controller.contains("numbers.accessibilityIdentifier = \"number-layer\""))
        XCTAssertEqual(controller.components(separatedBy: "self?.handleDismissTouchDown()").count - 1, 1)
        XCTAssertEqual(root.components(separatedBy: "usesInteractiveSurface: false").count - 1, 0)
        XCTAssertTrue(root.contains("@Environment(\\.openURL)"),
                      "foreground handoff must use SwiftUI's public URL action")
        XCTAssertFalse(root.contains("UIApplication.shared"))
        XCTAssertFalse(controller.contains("toggleEmojiPicker"))
        XCTAssertFalse(controller.contains("dictusTextDidChange"))
        XCTAssertFalse(controller.contains("UserDictionary.shared.reload"))
        XCTAssertFalse(controller.contains("pruneTrieDuplicatesIfNeeded"))
        XCTAssertFalse(state.contains("toggleEmojiPresentation"))
        XCTAssertFalse(state.contains("togglePanelPresentation"))
        XCTAssertFalse(state.contains("presentAreaMode("))
        XCTAssertFalse(state.contains("var openURL:"))
        XCTAssertFalse(state.contains("func openDictusApp("))
        XCTAssertFalse(project.contains("DictusKeyboardBridge"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bridge.path))

        XCTAssertTrue(state.contains("openURLFromExtension"))
        XCTAssertTrue(state.contains("let fallback = openContainingApp"))
        XCTAssertTrue(state.contains("extensionContext.open(url) { succeeded in"))
        XCTAssertTrue(state.contains("openDictusURL(url)"))

        XCTAssertFalse(root.contains("state.startRecording()"))
        XCTAssertFalse(root.contains("advanceToNextInputMode()"))
        XCTAssertFalse(root.contains("DragGesture(minimumDistance: 0)"))
        XCTAssertFalse(root.contains("state.requestStop()"))
        XCTAssertFalse(root.contains("Button(\"ABC\")"))
        XCTAssertFalse(root.contains("identifier: \"delete-backward\""))
        XCTAssertFalse(root.contains("identifier: \"return-key\""))
        XCTAssertTrue(controller.contains("UIAction(title: \"Dismiss keyboard\""))
        XCTAssertFalse(root.contains(".accessibilityIdentifier(\"dismiss-keyboard\")"))
        XCTAssertTrue(controller.contains("makeKeyboardActionButton"))
        XCTAssertFalse(controller.contains("handleInputModeList(from: sender, with: event)"))
        XCTAssertFalse(controller.contains("nextInputModeButton"))
        XCTAssertFalse(root.contains("utilityGlyph(systemName: \"globe\")"))
        XCTAssertTrue(root.contains("voiceBoardChrome(text: \"123\""))
        XCTAssertTrue(root.contains("systemName: \"face.smiling\",\n                            label: \"Emoji\",\n                            visualWidth:"),
                      "the dictation-board Emoji face must use the same command visual size as ABC/123")
        XCTAssertTrue(root.contains("case .letters, .panel, .emoji, .numberPad:"))
        XCTAssertTrue(controller.contains("keyboardModeButton"))
        XCTAssertFalse(root.contains("dictateButton(frame: layout.letterMicFrame)"),
                       "letter mode must not render the dictation button")
        XCTAssertFalse(controller.contains("micButton?.frame = layout.letterMicFrame"),
                       "letter mode must not install the dictation hit target")
        XCTAssertFalse(root.contains("showsSymbolsControl:"))
        XCTAssertFalse(root.contains("Text(\"AUTO\")"))
        XCTAssertTrue(root.contains("title: \"AUTO\""))
        XCTAssertTrue(root.contains("state.selectTranscription()"))
        XCTAssertFalse(root.contains("state.selectAutomaticTypingLanguage()"))
        XCTAssertFalse(root.contains("state.selectKeyboardLayout(layout)"))
        XCTAssertTrue(root.contains("title: \"AUTO\""))
        XCTAssertTrue(root.contains("\"Keep spoken language\""))
        XCTAssertTrue(controller.contains("LanguageMenuButton.menuItems()"))
        XCTAssertFalse(root.contains("LanguageMenuButton()"))
        XCTAssertFalse(root.contains("suggestionState.suggestions"),
                       "prediction must not reintroduce a visible suggestion list")
        XCTAssertFalse(root.contains("TypingSuggestionLane()"))
        XCTAssertFalse(root.contains("liveSuggestions"))
        XCTAssertFalse(root.contains("acceptLiveSuggestion(at:"))
        XCTAssertFalse(root.contains("Insert suggestion:"))
        XCTAssertFalse(root.contains("postDictationSuggestion"))
        XCTAssertFalse(root.contains("routePostDictationSuggestion"))
        XCTAssertFalse(suggestionState.contains("offerPostDictationSuggestion"))
        XCTAssertFalse(suggestionState.contains("postDictationPredictionEnabled"))
        XCTAssertFalse(settings.contains("Offer continuation after dictation"))
        XCTAssertFalse(settings.contains("postDictationPredictionEnabled"))
        XCTAssertTrue(suggestionState.contains("reconcilePendingAutocorrection"))
        XCTAssertTrue(suggestionState.contains("UserDictionary.shared.learn(word)"),
                      "a user replacement is persisted only after reconciliation")
        XCTAssertTrue(suggestionState.contains("isSafeUserOverride"),
                      "unsafe tokens must not be learned from autocorrection edits")
        XCTAssertTrue(suggestionState.contains("after == pending.afterContext"),
                      "caret moves away from the correction must invalidate learning")
        XCTAssertTrue(controller.contains("KeyboardShiftState.doubleTapWindow"))
        XCTAssertTrue(controller.contains("SuggestionState.shared.handleSpace(proxy:"))
        XCTAssertFalse(controller.contains("refreshTypingSuggestions()"))
        XCTAssertTrue(root.contains("UIDeferredMenuElement"))
        XCTAssertTrue(controller.contains("title: state.isOneTimeCodeField ? \"Insert one-time code\" : \"Paste\""))
        XCTAssertTrue(controller.contains("doc.on.clipboard"))
        XCTAssertFalse(root.contains("pasteButton"))
        XCTAssertFalse(root.contains("if state.areaMode != .emoji"),
                       "the shared clipboard control must remain visible on the emoji page")
        XCTAssertTrue(root.contains("startClipboardMonitoring()"))
        XCTAssertFalse(state.contains("clipboardPollTimer"),
                       "the keyboard must not poll the pasteboard")
        XCTAssertFalse(state.contains("timeInterval: 0.8"),
                       "the keyboard must not poll the pasteboard on a timer")
        XCTAssertFalse(state.contains("UIPasteboard.changedNotification"),
                       "the keyboard must not subscribe to pasteboard changes")
        XCTAssertFalse(controller.contains("refreshClipboardSuggestion(force: true)"),
                       "appear and layout retries must not read the pasteboard")
        XCTAssertTrue(controller.contains("readPasteboardText(from: .general)"),
                      "paste still reads the pasteboard on an explicit tap")
        XCTAssertTrue(state.contains("readPasteboardText(from board:"))
        XCTAssertTrue(state.contains("board.hasStrings"))
        XCTAssertTrue(state.contains("board.hasURLs"))
        XCTAssertFalse(root.contains("Menu {"),
                       "AUTO must use a UIKit deferred menu, not a SwiftUI Menu that rebuilds while scrolling")
        XCTAssertFalse(root.contains("LanguageTargetPickerSheet("))
        XCTAssertFalse(root.contains("clipboardSuggestionChip"))
        XCTAssertTrue(controller.contains("Opening uses the saved dictation/keyboard preference"))
        XCTAssertTrue(controller.contains("presentPreferredOpeningArea()"))
        XCTAssertTrue(controller.contains("shouldApplyOpeningPreference"),
                      "a live controller swap must not reset the page the user is typing on")
        XCTAssertTrue(state.contains("HostInputTraits.prefersNumberPad(for:"))
        XCTAssertTrue(state.contains("presentPreferredOpeningArea()"))
        XCTAssertTrue(state.contains("hostPrefersNumberPad"))
        XCTAssertFalse(root.contains("state.hostPrefersNumberPad"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains(".accessibilityHidden(true)"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("Text(title)"),
                      "the shared capsule builder renders whichever control's title")
        XCTAssertTrue(root.contains("onDelete: { routeProxyCommand(.delete) }"))
        XCTAssertFalse(root.contains("onDismiss: onDismiss"))
        XCTAssertFalse(controller.contains("hostingController?.view.isHidden = true"))
        XCTAssertTrue(controller.contains("setVoiceActionControlsHidden(mode == .panel || mode == .letters || mode == .numberPad)"))
        XCTAssertTrue(root.contains("layout.chromeLettersFrame"))
        XCTAssertFalse(root.contains("private var languageIndicator"))
        XCTAssertTrue(controller.contains("LanguageMenuButton.menuItems()"))
        XCTAssertTrue(controller.contains("dismissKeyboard()"))
        XCTAssertTrue(controller.contains("routeDismiss: { [weak self] in self?.dismissKeyboard() }"),
                      "the controller must own dismissal through the SwiftUI callback")
        XCTAssertFalse(root.contains("SuggestionBarIconButton("))
        XCTAssertFalse(root.contains("action: routeDismiss"))
        XCTAssertTrue(controller.contains("UIAction(title: \"Dismiss keyboard\""))
        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.layout("))
        XCTAssertFalse(root.contains("SymbolKeyboardSurface("))
        XCTAssertFalse(root.contains("NumberKeyboardSurface("))
        XCTAssertTrue(root.contains("case .letters, .panel, .emoji, .numberPad:"))
        XCTAssertTrue(state.contains("hostNumberPadStyle"))
        XCTAssertTrue(state.contains("presentArea(.numberPad, registerUserDismissal: false)"))
        XCTAssertTrue(state.contains("func presentNumbersArea()"))
        XCTAssertFalse(root.contains("number-pad-surface"))
        XCTAssertTrue(try source("DictusKeyboard/Next/KeyGridPageFactory.swift").contains("Locale.current.decimalSeparator"))
        XCTAssertTrue(root.contains("state.presentNumbersArea()"))
        XCTAssertTrue(controller.contains("numbers.accessibilityIdentifier = \"number-layer\""))
        XCTAssertTrue(controller.contains("self?.presentNumbersArea()"))
        XCTAssertTrue(controller.contains("case .numberPad:"))
        XCTAssertTrue(controller.contains("case .symbols:"))
        XCTAssertTrue(controller.contains("KeyboardState.shared.closeArea()"))
        XCTAssertTrue(controller.contains("registerControllerAppearance(controllerID: controllerID)"))
        XCTAssertTrue(controller.contains("case .recording:"))
        XCTAssertTrue(controller.contains("setHostingExpanded(true)"))
        XCTAssertFalse(controller.contains("micCenterArea"),
                       "the symbols keyboard must no longer be constrained to the voice center area")
        XCTAssertFalse(controller.contains("contentHeight = 110"))
    }

    func testUtilityVisualContainerKeepsIndependentActionWidthAndHeight() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"), encoding: .utf8)

        XCTAssertTrue((try relocatedKeyboardSource()).contains("width: CGFloat(width), height: CGFloat(height)"))
        XCTAssertTrue(root.contains("KeyboardDeleteButton("))
        XCTAssertTrue(root.contains("systemName: \"return\""))
        XCTAssertTrue(root.contains("width: VoiceOnlyKeyboardPolicy.actionHitSize.width"))
        XCTAssertTrue(root.contains("height: VoiceOnlyKeyboardPolicy.actionHitSize.height"))
        XCTAssertFalse(root.contains("SuggestionBarIconButton("))
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("keyboard.chevron.compact.down"))
    }

    func testKeyboardHasNoGlobeGenerationOrRenderingPath() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let systemKeys = try source("DictusKeyboard/Vendored/Models/SystemKeys.swift")
        let soundPolicy = try source("DictusKeyboard/KeySoundPolicy.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let inputView = try source("DictusKeyboard/InputView.swift")
        XCTAssertFalse(systemKeys.contains("type: .keyboard,"))
        XCTAssertFalse(soundPolicy.contains(".keyboard,"))
        XCTAssertFalse(controller.contains("case .keyboard:"))
        // The vendored `KeyView` that used to be searched for "globe" is deleted;
        // a file that no longer exists cannot render one. The live assertion is
        // that the input view still asks UIKit for keyboard behaviour.
        XCTAssertTrue(inputView.contains("inputViewStyle: .keyboard"))
    }

    func testKeyboardDisablesTheSeparateSystemDictationKey() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("hasDictationKey = true"),
                      "the extension's own microphone control must suppress iOS's duplicate dictation key")
    }

    func testAuxiliaryUIKitControlsUseSemanticForegroundColors() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("configuration?.baseForegroundColor = .label"),
                      "auxiliary controls must adapt to light and dark appearance")
        XCTAssertTrue(controller.contains("button.tintColor = .label"),
                      "symbol controls must not use the default blue tint")
    }

    func testTranslationMenuUsesSemanticTint() throws {
        let rootView = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertFalse(rootView.contains(".tint(.primary)"),
                       "the translation menu is UIKit and must not pin a SwiftUI tint")
        XCTAssertTrue(rootView.contains("struct LanguageMenuButton: UIViewRepresentable"))
        XCTAssertTrue(controller.contains("configuration?.baseForegroundColor = .label"),
                      "auxiliary controls must use the system label color")
        XCTAssertTrue(controller.contains("button.tintColor = .label"))
    }

    func testKeyboardRootUsesEmbeddedGlassSurfaceAndStableMicPlacement() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        let plates = try source("DictusKeyboard/KeyboardKeyStyle.swift")

        XCTAssertTrue((try relocatedKeyboardSource()).contains("RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("keyboardGlass(in: shape, role: role)"))
        XCTAssertFalse(root.contains("glassEffect("),
                       "KeyboardRootView must use KeyboardGlassSurface instead of its own material branch")
        XCTAssertTrue(plates.contains("glassEffect(.regular"))
        XCTAssertTrue(plates.contains(".regularMaterial"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("dictationButtonBackground"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("KeyboardDictationFaceStyle"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("dictationButtonForeground"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("dictateFrame"))
        // The recovery and dictation controls share one capsule builder so they
        // cannot drift apart visually.
        XCTAssertTrue((try relocatedKeyboardSource()).contains("private func boardCapsuleVisual("))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("private func recoveryControlVisual(frame: CGRect)"))
        XCTAssertTrue(root.contains("surfaceFrame.midX"))
        XCTAssertTrue(try source("DictusKeyboard/Next/KeyboardSurfaceView.swift").contains("let pager = CGRect(x: surface.minX, y: surface.minY, width: surface.width,"),
                      "emoji content must receive the complete embedded surface width")
        XCTAssertFalse(root.contains("availableWidth: surfaceFrame.width"))
        XCTAssertFalse(root.contains("auxiliaryContentFrame"))
    }

    func testLatestVoiceLayoutUsesThreeLeftTargetsAndBottomDismiss() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 216)
            XCTAssertEqual(VoiceOnlyKeyboardPolicy.leftRailControlCount, 3)
            XCTAssertEqual(layout.leftUtilityFrames.at.width, 44)
            XCTAssertEqual(layout.leftUtilityFrames.at.minY,
                           layout.leftUtilityFrames.emoji.minY
                           - VoiceOnlyKeyboardPolicy.railSpacing
                           - VoiceOnlyKeyboardPolicy.controlSize)
            XCTAssertEqual(layout.leftUtilityFrames.at.maxY,
                           layout.leftUtilityFrames.emoji.minY
                           - VoiceOnlyKeyboardPolicy.railSpacing)
            XCTAssertEqual(layout.leftUtilityFrames.emoji.minY - layout.leftUtilityFrames.at.maxY,
                           VoiceOnlyKeyboardPolicy.railSpacing)
            XCTAssertEqual(layout.leftUtilityFrames.emoji.minX, layout.leftUtilityFrames.at.minX)
            XCTAssertEqual(layout.leftUtilityFrames.number.minX,
                           layout.leftUtilityFrames.emoji.maxX + VoiceOnlyKeyboardPolicy.railSpacing)
            XCTAssertEqual(layout.leftUtilityFrames.number.minY, layout.leftUtilityFrames.emoji.minY)
            XCTAssertEqual(layout.dismissFrame.size, CGSize(width: 88, height: 54))
            XCTAssertEqual(layout.dismissFrame.maxY, layout.surfaceFrame.maxY - VoiceOnlyKeyboardPolicy.chromeBottomInset, accuracy: 0.001)
            XCTAssertTrue(layout.actionRectangles.allSatisfy { $0.width >= 44 && $0.height >= 44 })
        }
    }

    func testDeleteAndReturnUseCenteredWideVisualCapsulesInsideActionFrames() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"), encoding: .utf8)

        XCTAssertTrue(root.contains("visualWidth: VoiceOnlyKeyboardPolicy.commandVisualSize(for: VoiceOnlyKeyboardPolicy.actionHitSize).width"))
        XCTAssertTrue(root.contains("visualHeight: VoiceOnlyKeyboardPolicy.commandVisualSize(for: VoiceOnlyKeyboardPolicy.actionHitSize).height"))
        XCTAssertTrue(root.contains("visualCornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("CommandKeyFace("))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("plateWidth: plate.width"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("plateHeight: plate.height"))
    }

    func testUIKitActionOverlayRemainsInteractiveAlongsideSeparateDismissAndDictateControls() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"), encoding: .utf8)

        XCTAssertTrue(controller.contains("controls.isHidden = hidden"))
        XCTAssertFalse(controller.contains("controls.isHidden = hidden || !hasRightRail"))
        XCTAssertTrue(controller.contains("layout = VoiceOnlyKeyboardPolicy.layout"))
    }

    func testEmojiAndSymbolsSurfacesUseThePolicyCenterRegion() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"), encoding: .utf8)

        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390)
        XCTAssertEqual(layout.centerAreaWidth, 162)
        XCTAssertTrue(try source("DictusKeyboard/Next/KeyboardSurfaceView.swift").contains("let pager = CGRect(x: surface.minX, y: surface.minY, width: surface.width,"))
        XCTAssertFalse(root.contains("availableWidth: surfaceFrame.width"))
        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"))
    }

    func testMicUIKitTargetIsHiddenOutsideKeysAndRecordingAndOwnsAccessibility() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(controller.contains("uikitOwnsVoiceChrome"),
                      "the UIKit mic target owns glass dictation-board recovery")
        XCTAssertFalse(root.contains("accessoryDictationLabel"))
        XCTAssertFalse(controller.contains("micButton?.frame = isAuxiliary ? layout.accessoryMicrophoneFrame"))
        XCTAssertTrue(controller.contains("micButton?.isHidden = !dictateVisible"),
                      "an inactive mic must be hidden without resetting the active target")
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
        XCTAssertTrue(controller.contains("identifier: \"dictate-button\", label: \"Hold to dictate\""))
        XCTAssertTrue(controller.contains("moreButton?.isHidden = !showsTopBar"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains(".accessibilityHidden(true)"))
    }

    func testSwiftUIVoiceOwnershipDoesNotDependOnMaterial() throws {
        let root = try source("DictusKeyboard/KeyboardChrome.swift")
        let start = try XCTUnwrap(root.range(of: "var voiceBoardUsesUIKitHits"))
        let end = try XCTUnwrap(root.range(of: "@ViewBuilder\n    func appleControlSurface", range: start.upperBound..<root.endIndex))
        let body = String(root[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(body.contains("state.areaMode == .keys || state.areaMode == .recording"))
        XCTAssertFalse(body.contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
    }

    func testFailedMicUsesRecoveryOnlyWhenRequiredAndRetriesOtherwise() throws {
        let state = try source("DictusKeyboard/KeyboardState.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(state.contains("case .failed:"))
        XCTAssertTrue(state.contains("if failedRequiresApp"))
        XCTAssertTrue(state.contains("openDictusForRecovery()"))
        XCTAssertTrue(state.contains("startRecording()"))
        XCTAssertTrue(controller.contains("state.handleMicPressBegan()"))
        XCTAssertTrue(controller.contains("state.handleMicPressEnded()"))
    }

    func testMicVisualUsesReadableSemanticForegroundAndIdleGlyph() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        // Both primary controls now render through one capsule builder, so the
        // semantic foreground is applied there rather than per control.
        XCTAssertTrue((try relocatedKeyboardSource()).contains(".foregroundStyle(foreground)"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("foreground: dictationButtonForeground"))
        XCTAssertTrue((try relocatedKeyboardSource()).contains("case .failed, .idle, .ready: return \"mic.fill\""))
    }

    func testLanguageIndicatorIsPresentOnEveryKeyboardPage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"), encoding: .utf8)
        let controller = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"), encoding: .utf8)

        XCTAssertFalse(root.contains("if isBoard && layout.showsLanguageIndicator"),
                       "AUTO must remain available on every page")
        XCTAssertTrue(controller.contains("LanguageMenuButton.menuItems()"),
                      "the more menu owns output language on every page")
        XCTAssertTrue(root.contains("title: \"AUTO\""))
    }

    func testKeyboardRuntimeLanguageDefaultsUseTheResolvedProductLanguage() throws {
        let prediction = try source("DictusKeyboard/TextPrediction/TextPredictionEngine.swift")
        let emoji = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(prediction.contains(
            "private var language: String = SupportedLanguage.active.rawValue"
        ))
        XCTAssertFalse(prediction.contains("private var language: String = \"fr\""))
        XCTAssertFalse(emoji.contains("SharedKeys.language) ?? \"fr\""))
    }

    /// Dark-mode keyboard surfaces must come from semantic system colors.
    ///
    /// Repointed from the deleted vendored `Theme.swift` to the two files that
    /// actually paint the keyboard now: the shared color tokens and the material
    /// plate. The invariant is unchanged — no hardcoded black/white.
    func testDarkKeyboardUsesSemanticBackgroundOrMaterial() throws {
        let colors = try source("DictusCore/Sources/DictusCore/Design/DictusColors.swift")
        let plates = try source("DictusKeyboard/KeyboardKeyStyle.swift")

        XCTAssertTrue(colors.contains(".systemBackground") ||
                      colors.contains(".secondarySystemBackground"),
                      "the shared background tokens must be system colors")
        XCTAssertTrue(plates.contains(".tertiarySystemFill") ||
                      plates.contains(".regularMaterial"),
                      "key plates must use a semantic system fill or material")
        XCTAssertFalse(plates.contains("backgroundColor: .black"),
                       "dark keyboard background must not be a fixed black color")
    }

    func testNumberPadDigitsHaveNoGlassKeycaps() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let factory = try source("DictusKeyboard/Next/KeyGridPageFactory.swift")
        let grid = try source("DictusKeyboard/Next/KeyGridView.swift")
        let start = try XCTUnwrap(factory.range(of: "static func numberPad(style: HostFieldPolicy.NumberPadStyle)"))
        let end = try XCTUnwrap(factory.range(of: "private static func digitKey", range: start.upperBound..<factory.endIndex))
        let pad = String(factory[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(factory.contains("glyphSize: 22"))
        XCTAssertTrue(pad.contains("action: .letters, label: \"ABC\""),
                      "the digits pad keeps an ABC key instead of a glass keycap")
        XCTAssertFalse(pad.contains("keyboardGlass("))
        XCTAssertFalse(pad.contains("letterKeyPlate"))
        XCTAssertTrue(grid.contains("final class KeyGridView: UIView"),
                      "pad digits are drawn by the same grid as letters")
        XCTAssertTrue(factory.contains("Locale.current.decimalSeparator"))
        XCTAssertTrue(root.contains("state.presentNumbersArea()"))
        XCTAssertFalse(root.contains("accessoryLettersButton"),
                       "ABC must not sit in the suggestion bar on the number pad")
        XCTAssertFalse(root.contains("NumberKeyboardSurface("))
    }

    func testNormalAndSymbolsModesShareTheSameNativeSurfaceHeight() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"),
            encoding: .utf8
        )
        let root = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(controller.contains("case .symbols:"),
                      "the symbols presentation must be covered by the height contract")
        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"),
                       "symbols mode must use the complete shared surface")
        XCTAssertFalse(root.contains("SymbolKeyboardSurface("))
        XCTAssertFalse(root.contains("NumberKeyboardSurface("))
        XCTAssertTrue(controller.contains("static let nextKeyboardModes: Set<KeyboardAreaMode> = [.letters, .panel, .numberPad]"))
        XCTAssertTrue(root.contains("let surfaceHeight = max(proxy.size.height, 1)"),
                      "voice and symbols surfaces must consume the runtime native surface height")
    }

    func testSymbolsReturnRestoresTheSwiftUISymbolPage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"),
            encoding: .utf8
        )
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertFalse(root.contains("onClose:"))
        XCTAssertTrue(controller.contains("surface.bottomBar.onLetters = { KeyboardState.shared.presentArea(.letters) }"),
                      "ABC on the symbol page returns to letters")
        XCTAssertTrue(controller.contains("layoutVoiceActionControls()"),
                      "leaving the symbols surface must immediately restore the native action hit areas")
    }

    /// Appearance adaptation now comes from SwiftUI semantic colors rather than
    /// a theme factory that branched on `userInterfaceStyle`. The assertions keep
    /// the same intent: every keyboard color resolves from the system palette and
    /// nothing is pinned to a literal white or black.
    func testKeyboardThemeResolvesSemanticColorsForBothAppearances() throws {
        let colors = try source("DictusCore/Sources/DictusCore/Design/DictusColors.swift")
        let plates = try source("DictusKeyboard/KeyboardKeyStyle.swift")

        XCTAssertTrue(colors.contains("static var dictusBackground: Color"),
                      "the background token must be computed so SwiftUI re-resolves it on appearance change")
        XCTAssertTrue(colors.contains(".systemBackground") && colors.contains(".secondarySystemBackground"),
                      "keyboard surfaces must use semantic system backgrounds")
        XCTAssertTrue(colors.contains(".secondaryLabel"),
                      "keyboard foreground colors must remain semantic in light and dark mode")
        XCTAssertTrue(plates.contains("@Environment(\\.colorSchemeContrast)"),
                      "the plate must still react to accessibility contrast changes")
        XCTAssertTrue(colors.contains("static var dictusBackground: Color { Color(.systemBackground) }"),
                      "the surface must use the system palette; action foregrounds can use white")
    }

    /// Regular keys and modifier keys must remain visually distinct in dark mode,
    /// and pressed state must not pin its text color. Repointed from the deleted
    /// vendored theme to the live plate and key-face definitions.
    func testKeyboardThemeKeepsDarkSurfaceAndKeysDistinct() throws {
        let plates = try source("DictusKeyboard/KeyboardKeyStyle.swift")
        let keyStyle = try source("DictusKeyboard/KeyboardKeyStyle.swift")
        let chrome = try source("DictusKeyboard/KeyboardChrome.swift")

        XCTAssertTrue(keyStyle.contains("case .input, .control: return .tertiarySystemBackground"),
                      "keys and commands must use opaque semantic plates")
        XCTAssertFalse(plates.contains("UIColor.label.withAlphaComponent(0.035)"),
                       "key shapes must remain visible at rest")
        XCTAssertTrue(chrome.contains("role.solidFill()"),
                      "the shared chrome fill must stay semantic")
        XCTAssertFalse(keyStyle.contains("activeText: .white"),
                       "pressed-key text must adapt to the current appearance")
    }

    func testKeyboardHeightProviderDoesNotForceAUniversalPortraitHeight() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let provider = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/Vendored/Models/KeyboardHeightProvider.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(provider.contains("portrait: 216"),
                      "the iPhone provider must retain the native compact portrait height")
        XCTAssertFalse(provider.contains("return (portrait: 291, landscape: 216)"),
                       "the provider must not force every iPhone to a taller custom surface")
    }
}
