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
        let keyboardStart = try XCTUnwrap(settings.range(of: "settingsPanel(\"Keyboard\""))
        let nextSection = try XCTUnwrap(settings.range(of: "settingsPanel(\"More\"", range: keyboardStart.upperBound..<settings.endIndex))
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

        XCTAssertTrue(controller.contains("controls.isHidden = false"))
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = true"))
        XCTAssertTrue(controller.contains("$0.isEnabled = !$0.isHidden"))
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
    }

    func testAuxiliaryModeSkipsAllUIKitFrameAndZOrderUpdates() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let start = try XCTUnwrap(controller.range(of: "private func layoutVoiceActionControls(surfaceHeight: CGFloat? = nil)"))
        let end = try XCTUnwrap(controller.range(of: "@objc private func handleMicTouchDown"))
        let body = String(controller[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(body.contains("let isAuxiliary = mode == .panel || mode == .emoji || mode == .letters || mode == .numberPad"))
        XCTAssertTrue(body.contains("micButton?.frame = .zero"), "a stale mic frame is cleared during relayout")
        XCTAssertTrue(body.contains("keyboardModeButton?.frame ="))
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

        XCTAssertTrue(controller.contains("micButton?.frame = .zero"))
        XCTAssertTrue(controller.contains("micButton?.isUserInteractionEnabled = false"))
        XCTAssertTrue(root.contains("ImmediateKeyButton("))
        XCTAssertTrue(root.contains("highlightSize: CGSize(width: frame.width, height: frame.height)"))
        XCTAssertTrue(root.contains(".frame(width: frame.width, height: frame.height)"))
        XCTAssertFalse(root.contains("Link(destination:"))
        XCTAssertTrue(root.contains("onTouchDown: { state.handleMicPressBegan() }"))
        XCTAssertTrue(root.contains("onTouchUp: { state.handleMicPressEnded() }"))
        XCTAssertFalse(root.contains("HoldToSpeakButton("))
        XCTAssertFalse(controller.contains("layout.dictateFrame.insetBy(dx: -8, dy: -8)"))
        XCTAssertFalse(controller.contains("#selector(handleMicTap)"))
    }

    func testMicrophoneTouchDownGuardsBusyStatuses() throws {
        let state = try source("DictusKeyboard/KeyboardState.swift")

        XCTAssertTrue(state.contains("case .transcribing, .processing:"))
        XCTAssertTrue(state.contains("abandonStuckCleanup()"))
        XCTAssertTrue(state.contains("case .requested, .recording:"))
    }

    func testMicrophoneVisualRemainsSwiftUIOnlyAndDoesNotInstallGestureStartStop() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("appleControlSurface("))
        XCTAssertTrue(root.contains("Color.white.opacity(0.86)"))
        XCTAssertTrue(root.contains("state.appNeedsAppAction ? \"arrow.up.right.square.fill\" : \"mic.fill\""))
        XCTAssertTrue(root.contains("voiceBoardUsesUIKitHits"))
        XCTAssertTrue(root.contains("KeyboardInteractionPreferences.liquidGlassEnabled"))
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

    func testMainTabsKeepSpeakAndSettingsAndOpenModelsFromSettings() throws {
        let mainTabs = try source("DictusApp/Views/MainTabView.swift")
        let settings = try source("DictusApp/Views/SettingsView.swift")

        XCTAssertFalse(mainTabs.contains("Label(\"Models\", systemImage:"),
                       "Models is a Settings destination, not a root tab")
        XCTAssertTrue(settings.contains("NavigationLink { ModelManagerView(modelManager: modelManager) } label:"),
                       "Models opens from Settings")
    }

    func testDictationErrorsRenderOutsideTheMicButton() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let dictateButton = try XCTUnwrap(root.range(of: "private func dictateButton"))
        let dictationTitle = try XCTUnwrap(root.range(of: "private var dictationTitle"))
        let buttonBody = String(root[dictateButton.lowerBound..<dictationTitle.lowerBound])

        XCTAssertTrue(root.contains("private var dictationErrorMessage"))
        XCTAssertTrue(root.contains("Text(dictationErrorMessage)"))
        XCTAssertTrue(root.contains(".foregroundStyle(.red)"))
        XCTAssertTrue(root.contains("layout.dictationErrorFrame"),
                      "the error must have its own bounded layout lane")
        XCTAssertTrue(root.contains("accessibilityIdentifier(\"dictation-error\")"),
                      "the error line must remain independently targetable")
        XCTAssertFalse(buttonBody.contains("statusMessage"),
                       "the mic capsule must remain reserved for its action state")
        XCTAssertTrue(root.contains("case .failed: return \"Hold to dictate\""),
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
        XCTAssertTrue(root.contains("ImmediateVariantKey("),
                      "letter variants use the immediate native touch owner")
        XCTAssertTrue(root.contains("onMoved: { point in"),
                      "variant tracking must update selection while the finger moves")
        XCTAssertTrue(root.contains("guard !cancelled, !variantTouchCancelled else { return }"),
                      "cancelled or escaped touches must not commit a key")
        XCTAssertTrue(root.contains("activeVariantKeyID"),
                      "multi-key tracking must only let the active key finish the touch")
        XCTAssertFalse(root.contains("letterTouchActive"))
        XCTAssertFalse(root.contains(".nativeKeyboardKeySurface()"))
        let buttons = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        XCTAssertTrue(buttons.contains("SpaceTrackingButton("))
        XCTAssertTrue(buttons.contains("DeleteRepeatControl("))
        XCTAssertTrue(buttons.contains("timer.fireDate = Date().addingTimeInterval(KeyboardDeletion.repeatDelay)"))
        XCTAssertTrue(buttons.contains("KeyboardDeletion.repeatInterval"))
        XCTAssertTrue(buttons.contains("KeyboardDeletion.repeatAction"))
        let repeatStart = try XCTUnwrap(buttons.range(of: "private func repeatDelete()"))
        let repeatEnd = try XCTUnwrap(buttons.range(of: "private func finish()", range: repeatStart.upperBound..<buttons.endIndex))
        let repeatBody = String(buttons[repeatStart.lowerBound..<repeatEnd.lowerBound])
        XCTAssertTrue(repeatBody.contains("HapticFeedback.keyTapped()"),
                      "a held delete key must click on every repeat tick")
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
        XCTAssertTrue(picker.contains("private let gridHorizontalPadding: CGFloat = VoiceOnlyKeyboardPolicy.keyGridInset"),
                      "grid geometry must use the same inset as letter and symbol keys")
        XCTAssertTrue(picker.contains("emojiGridWidth - gridHorizontalPadding * 2"),
                      "cell width must use the shared horizontal padding")
        XCTAssertTrue(picker.contains("private var emojiGridWidth: CGFloat"),
                      "the scrolling viewport must use one full-width geometry")
        XCTAssertTrue(picker.contains("max(0, availableWidth)"),
                      "the emoji grid may render beneath the fixed delete target")
        XCTAssertTrue(picker.contains("override var isHighlighted: Bool"),
                      "the highlight must be owned by the native emoji button")
        XCTAssertTrue(picker.contains("UICollectionView"), "categories use native paging")
        XCTAssertTrue(picker.contains("EmojiNavigation.scrollResolution("),
                      "category-bar jumps must use the first page containing the category")
        XCTAssertFalse(picker.contains("TabView("))
        XCTAssertFalse(picker.contains("ScrollView(.vertical"))
        XCTAssertTrue(picker.contains("UILongPressGestureRecognizer"),
                      "skin-tone extras use the unified tap/hold gesture owner")
        XCTAssertFalse(picker.contains("emojiDragAxis"),
                       "horizontal scrolling owns drag; there is no second drag-select axis")
        XCTAssertTrue(picker.contains("UIButton"),
                      "emoji taps must remain native button interactions")
        XCTAssertTrue(picker.contains("onTap?(item.emoji)"),
                      "emoji release must call the tap insertion callback")
        let ownerStart = try XCTUnwrap(picker.range(of: "private final class EmojiPagerCollectionView"))
        let ownerEnd = try XCTUnwrap(picker.range(of: "private final class EmojiPageCell"))
        let owner = String(picker[ownerStart.lowerBound..<ownerEnd.lowerBound])
        XCTAssertEqual(picker.components(separatedBy: "UILongPressGestureRecognizer(target:").count - 1, 1,
                       "one stable pager recognizer survives cell reuse and category changes")
        XCTAssertTrue(owner.contains("addGestureRecognizer(hold)"))
        XCTAssertTrue(owner.contains("hold.cancelsTouchesInView = true"),
                      "a recognized hold must cancel the UIButton base tap")
        XCTAssertTrue(owner.contains("hold.allowableMovement = 10_000"),
                      "emoji holds must tolerate normal finger jitter before recognition")
        XCTAssertTrue(owner.contains("hypot(translation.x, translation.y) < 16"),
                      "a still hold must beat scrolling; a swipe still pages")
        XCTAssertTrue(owner.contains("shouldRecognizeSimultaneouslyWith otherGestureRecognizer") &&
                      owner.contains("false"),
                      "the hold must not share the pan with scrolling")
        XCTAssertTrue(owner.contains("button.convert(button.bounds, to: self)"))
        XCTAssertTrue(owner.contains("frame.offsetBy(dx: bounds.minX, dy: bounds.minY)"),
                      "source and popup must share scrolled content coordinates")
        XCTAssertTrue(owner.contains("addSubview(popup)"),
                      "the gesture owner presents synchronously without a SwiftUI state round trip")
        XCTAssertTrue(owner.contains("updateVariantSelection(at: recognizer.location(in: self))"))
        XCTAssertTrue(owner.contains("guard selectedIndex >= 0 else { return }"),
                      "a brief excursion outside the popup must retain the last valid tone")
        XCTAssertTrue(owner.contains("panGestureRecognizer.isEnabled = false"),
                      "only a recognized hold may suspend scrolling while choosing a tone")
        XCTAssertTrue(owner.contains("panGestureRecognizer.isEnabled = true"))
        XCTAssertTrue(owner.contains("case .cancelled, .failed:\n            cancelVariantSelection()"))
        XCTAssertTrue(picker.contains("!view.hasVariantSelection"),
                      "a content reload must not dismantle a held selection")
        XCTAssertTrue(picker.contains("accessibilityCustomActions = EmojiSkinToneVariants.options"),
                      "VoiceOver must retain direct access to every tone")
        XCTAssertFalse(picker.contains(".simultaneousGesture(emojiGesture)"),
                      "the hold recognizer must not take ownership of horizontal scrolling")
        XCTAssertTrue(picker.contains("minimumPressDuration = KeyboardDeletion.holdRecognitionDuration"),
                      "scrolling must cancel a pending emoji hold")
        XCTAssertTrue(picker.contains("scrollViewDidScroll"),
                      "category highlight follows the selected native page")
        let insertStart = try XCTUnwrap(picker.range(of: "private func insertEmoji"))
        let insertEnd = try XCTUnwrap(picker.range(of: "// MARK: - Scroll canvas"))
        let insertBody = String(picker[insertStart.lowerBound..<insertEnd.lowerBound])
        XCTAssertTrue(insertBody.contains("RecentEmojis.add(emoji, limit:"))
        XCTAssertFalse(insertBody.contains("recentEmojis = RecentEmojis.load("),
                       "inserting an emoji must not rebuild the grid from recents")
    }

    func testEmojiPagerUsesStablePagesAndNativePagingWithoutTouchReloads() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains("@State private var pageRevision = 0"))
        XCTAssertTrue(picker.contains("pageRevision: pageRevision"),
                      "the coordinator must detect page changes without rebuilding emoji signatures")
        XCTAssertTrue(picker.contains("private func reloadIfIdle"))
        XCTAssertTrue(picker.contains("context.coordinator.reloadWhenIdle(uiView)"))
        XCTAssertTrue(picker.contains("isPagingEnabled = true"),
                      "empty recents and later categories page horizontally")
        XCTAssertTrue(picker.contains("decelerationRate = .fast"))
        XCTAssertFalse(picker.contains("scrollViewWillEndDragging"),
                       "free-scroll must not snap to a page on release")
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
        XCTAssertTrue(root.contains("LiquidSymbolPageView("))
        XCTAssertTrue(root.contains("LiquidNumberPadView("),
                      "SwiftUI must provide the symbols surface")
        XCTAssertTrue(root.contains(".frame(width: surfaceFrame.width, height: surfaceFrame.height)"),
                      "the symbols surface must fill the shared inset surface")
    }

    func testAuxiliaryContentUsesTheCompleteSurfaceWithoutUIKitAccessoryRow() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"))
        XCTAssertTrue(root.contains("areaSurface(layout: layout, contentFrame: surfaceFrame)"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = true"))
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"))
    }

    func testAuxiliaryControlsAreOwnedBySwiftUISurface() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(root.contains("alternateAccessoryRow(layout:"),
                       "the alternate accessory row must not be rendered inside SwiftUI")
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"),
                       "UIKit must not install an alternate accessory row")
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = true"),
                      "UIKit keeps the container live while hidden controls pass through")
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
        XCTAssertTrue(root.contains("Color.white.opacity(0.86)"),
                      "the voice page keeps its own white microphone capsule")
        XCTAssertFalse(root.contains("state.startRecording()"))
        XCTAssertFalse(root.contains("state.requestStop()"))
    }

    func testAuxiliaryModeOwnsOnlyRevertMicDeleteAndReturnControls() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = false"))
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = true"))
        XCTAssertTrue(controller.contains("micButton?.frame = .zero"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"))
    }

    func testAuxiliaryControlsHideWhenAccessoryRowIsUnavailable() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = false"))
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

        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = true"))
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
        XCTAssertTrue(root.contains("onBackToVoice: { state.closeArea() }"))
        XCTAssertFalse(controller.contains("imageName: \"arrow.uturn.backward\""))
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

        XCTAssertTrue(root.contains("LiquidSymbolPageView("))
        XCTAssertTrue(root.contains("page: symbolPage"))
        XCTAssertTrue(root.contains("onTogglePage: { nextPage in symbolPage = nextPage }"))
        XCTAssertTrue(root.contains("symbolPage = .symbols1"))
        XCTAssertTrue(controller.contains("KeyboardHeightProvider.height"))
        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"))
        XCTAssertTrue(controller.contains("let resolvedHeight = surfaceHeight ?? computeKeyboardHeight(for: mode)"))
        XCTAssertTrue(controller.contains("surfaceHeight: Double(max(1, resolvedHeight))"))
        let bottomBar = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        XCTAssertTrue(bottomBar.contains("DeleteRepeatControl("))
        XCTAssertTrue(bottomBar.contains("RunLoop.main.add(timer, forMode: .common)"))
        XCTAssertTrue(layouts.contains("KeyDefinition(type: .shiftSymbols"))
        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 3"))
    }

    func testLetterKeyboardUsesVendoredRendererAndSharedBottomRow() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")
        let policy = try source("DictusCore/Sources/DictusCore/VoiceOnlyKeyboardPolicy.swift")

        XCTAssertTrue(controller.contains("GiellaKeyboardView("))
        XCTAssertTrue(controller.contains("keyboard.delegate = self"))
        XCTAssertTrue(controller.contains("case .keyboardMode:"))
        XCTAssertTrue(controller.contains("case .symbols:"))
        XCTAssertTrue(controller.contains("didMoveCursor"))
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

        XCTAssertTrue(root.contains("availableHeight: surfaceFrame.height"),
                      "emoji picker height must match the inset content/surface frame")
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
        XCTAssertTrue(root.contains("LiquidSymbolPageView("))
        XCTAssertTrue(root.contains("LiquidNumberPadView("),
                      "SwiftUI must own the symbols page content")
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"),
                      "the UIKit mode control must remain above the symbols surface")
    }

    func testBothAuxiliaryModeControlsUseOnlyTheirSmallUtilityHitFrame() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertEqual(controller.components(separatedBy: "numberButton?.frame = layout.chromeNumbersFrame").count - 1, 1,
                       "both auxiliary modes must share one compact frame assignment")
    }

    func testAuxiliaryModeControlUpdatesAccessibilitySemantics() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("onBackToVoice: { state.closeArea() }"),
                      "the SwiftUI voice-return control must describe its action")
        XCTAssertTrue(root.contains("case .togglePage: return label == \"#+=\" ? \"More symbols\" : \"Return to numbers keyboard\""),
                      "the SwiftUI page toggle must describe its action")
        XCTAssertTrue(controller.contains("Open symbols keyboard"),
                      "normal mode must announce opening symbols")
        XCTAssertTrue(root.contains("onBackToVoice: { state.closeArea() }"),
                      "auxiliary mode must announce returning to voice keyboard")
        XCTAssertTrue(controller.contains("if KeyboardState.shared.areaMode == .panel")
            && controller.contains("closeNumberPanel()"),
                      "symbols 123 action must return to the voice keyboard")
        XCTAssertTrue(controller.contains("self.presentNumbersArea()"),
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
        XCTAssertTrue(controller.contains("micButton?.frame = .zero"))
        XCTAssertTrue(root.contains("onSpaceCursorMoved: routeCursorMovement"))
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
        XCTAssertFalse(controller.contains("HapticFeedback.cursorMoved()"),
                       "spacebar cursor steps must not play per-character haptics")
        XCTAssertTrue(controller.contains("KeyboardCursorTrackpad.visualOffset("),
                      "cursor drag must jump to a 2D layout position, not walk the string")
        XCTAssertTrue(controller.contains("spaceCursorPressOrigin"),
                      "dictation spacebar joystick origin must be the original press")
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

        XCTAssertTrue(root.contains("showsSymbolsControl: true"),
                      "letter mode must expose an explicit 123 control")
        XCTAssertTrue(root.contains("onSpace: { routeProxyCommand(.space) }"),
                      "letter mode must route its spacebar through the keyboard command")
        XCTAssertTrue(root.contains("case .spacebar:\n            onSpace()"),
                      "letter mode's space fallback must share the keyboard command route")
        XCTAssertTrue(root.contains("case .backspace:"),
                      "letter mode must render the layout's delete key")
        XCTAssertTrue(root.contains("Image(systemName: \"delete.backward\")"),
                      "letter mode's delete key must have a visible glyph")
        XCTAssertTrue(root.contains("onDelete: { routeProxyCommand(.delete) }"),
                      "letter mode's delete key must route to the text proxy")
        XCTAssertTrue(bar.contains("roundControl(text: numbersTitle"),
                      "the shared bottom row must render 123 as a real button")
        XCTAssertTrue(bar.contains("HapticFeedback.keyTapped()"),
                      "bottom-row actions must provide optional haptic feedback")
    }

    func testBothAuxiliaryPagesKeepModeControlAvailableToReturnToNormal() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = false"))
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

        XCTAssertTrue(picker.contains("floatingEmojiCategoryFrame"),
                      "category bookmarks float over the emoji grid with delete")
        XCTAssertTrue(picker.contains("gridHeight: emojiGridHeight"),
                      "emoji scrolling stays on a compact 4-row inset instead of stretching the glass")
        XCTAssertTrue(picker.contains("usable / rows"))
        XCTAssertTrue(picker.contains("UICollectionView"),
                      "emoji categories keep a stable native collection surface")
        XCTAssertFalse(picker.contains("TabView("))
        XCTAssertFalse(picker.contains("ScrollView(.vertical"))
        XCTAssertTrue(picker.contains("AuxiliaryBottomBar("))
        XCTAssertTrue(picker.contains("KeyboardDeleteButton("))
        XCTAssertTrue(picker.contains("boardDeleteFrame"))
        XCTAssertTrue(picker.contains(".zIndex(4)"))
        XCTAssertTrue(picker.contains("EmojiCategoryBar("))
        XCTAssertFalse(root.contains("EmojiCategoryBar("),
                       "category bookmarks float over the emoji grid, not the accessory lane")
        XCTAssertFalse(picker.contains("systemName: \"mic.fill\""))
    }

    func testSymbolsReserveTheBottomLeftControlFootprintAcrossLastTwoRows() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertFalse(root.contains("bottomControlReservedUnits"))
        XCTAssertFalse(root.contains("leadingReservedWidths"))
        XCTAssertFalse(root.contains("positionedKeys(in: gridSize).filter"),
                       "functional symbol keys must remain available")
    }

    func testDeleteRepeatStopsOnCancelAndEnd() throws {
        let keyboardView = try source("DictusKeyboard/Vendored/Views/KeyboardView.swift")

        XCTAssertTrue(keyboardView.contains("func stopKeyRepeat()"))
        XCTAssertTrue(keyboardView.contains("stopKeyRepeat()"))
    }

    func testPredictedLetterWinsOverlappingExpandedHitTargets() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("ImmediateVariantKey("),
                      "keyboard keys must use the direct UIKit touch owner")
        XCTAssertTrue(root.contains("let hitExpansion: CGFloat = 6"),
                      "keyboard keys must keep a small stable hit expansion")
        let buttons = try source("DictusKeyboard/Views/AuxiliaryBottomBar.swift")
        XCTAssertFalse(buttons.contains("hitExpansion = 3"),
                       "UIKit key hit slop must not overlap the 5pt key gap")
        XCTAssertFalse(buttons.contains("insetBy(dx: -3, dy: -3)"),
                       "delete must not steal neighboring letter taps")
        XCTAssertTrue(buttons.contains("hitExpansion = 6"))
        XCTAssertTrue(buttons.contains("var hitExpansion: CGFloat = 6"))
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
        let project = try String(contentsOf: repository.appending(path: "Dictus.xcodeproj/project.pbxproj"), encoding: .utf8)
        let bridge = repository.appending(path: "DictusKeyboard/DictusKeyboardBridge.swift")

        XCTAssertFalse(controller.contains("DictusKeyboardBridge"))
        XCTAssertFalse(controller.contains("suggestionState"))
        XCTAssertFalse(root.contains("DictusKeyboardBridge"))
        XCTAssertFalse(root.contains("legacyBody"))
        XCTAssertTrue(root.contains("suggestionState.adaptiveTouchPrediction"),
                      "local prediction is used only for invisible touch routing")
        XCTAssertFalse(root.contains("fullAreaToolbar"))
        XCTAssertFalse(root.contains("togglePanel"))
        XCTAssertFalse(root.contains("keyboard-controls"))
        XCTAssertTrue(root.contains("keyboard.chevron.compact.down"))
        XCTAssertFalse(root.contains("usesInteractiveSurface: false"))
        XCTAssertTrue(root.contains("onEmoji: { state.presentArea(.emoji) }"))
        XCTAssertFalse(root.contains("private func utilityButton("))
        XCTAssertFalse(root.contains("LazyVGrid"))
        XCTAssertTrue(root.contains("allowsHitTesting(false)"))
        XCTAssertTrue(controller.contains("identifier: \"number-layer\""))
        XCTAssertTrue(controller.contains("KeyboardState.shared.closeArea()"))
        XCTAssertTrue(controller.contains("identifier: \"letter-mode\""))
        XCTAssertTrue(controller.contains("identifier: \"emoji-picker\""))
        XCTAssertTrue(controller.contains("identifier: \"number-layer\""))
        XCTAssertEqual(controller.components(separatedBy: "identifier: \"dismiss-keyboard\"").count - 1, 1)
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
        XCTAssertTrue(state.contains("extensionContext.open(url, completionHandler: completion)"))
        XCTAssertTrue(state.contains("openDictusURL(url)"))

        XCTAssertFalse(root.contains("state.startRecording()"))
        XCTAssertFalse(root.contains("advanceToNextInputMode()"))
        XCTAssertFalse(root.contains("DragGesture(minimumDistance: 0)"))
        XCTAssertFalse(root.contains("state.requestStop()"))
        XCTAssertFalse(root.contains("Button(\"ABC\")"))
        XCTAssertFalse(root.contains("identifier: \"delete-backward\""))
        XCTAssertFalse(root.contains("identifier: \"return-key\""))
        XCTAssertTrue(root.contains(".accessibilityIdentifier(\"dismiss-keyboard\")"))
        XCTAssertTrue(controller.contains("makeKeyboardActionButton"))
        XCTAssertFalse(controller.contains("handleInputModeList(from: sender, with: event)"))
        XCTAssertFalse(controller.contains("nextInputModeButton"))
        XCTAssertFalse(root.contains("utilityGlyph(systemName: \"globe\")"))
        XCTAssertTrue(root.contains("voiceBoardChrome(text: \"123\""))
        XCTAssertTrue(root.contains("case .letters:"))
        XCTAssertTrue(controller.contains("keyboardModeButton"))
        XCTAssertFalse(root.contains("dictateButton(frame: layout.letterMicFrame)"),
                       "letter mode must not render the dictation button")
        XCTAssertFalse(controller.contains("micButton?.frame = layout.letterMicFrame"),
                       "letter mode must not install the dictation hit target")
        XCTAssertTrue(root.contains("showsSymbolsControl: true"))
        XCTAssertFalse(root.contains("Text(\"AUTO\")"))
        XCTAssertTrue(root.contains("languageIndicatorTitle"))
        XCTAssertTrue(root.contains("return \"AUTO\""))
        XCTAssertTrue(root.contains("state.selectTranscription()"))
        XCTAssertFalse(root.contains("state.selectAutomaticTypingLanguage()"))
        XCTAssertFalse(root.contains("state.selectKeyboardLayout(layout)"))
        XCTAssertTrue(root.contains("title: \"AUTO\""))
        XCTAssertTrue(root.contains("\"Keep spoken language\""))
        XCTAssertTrue(root.contains("LanguageMenuButton()"))
        XCTAssertFalse(root.contains("suggestionState.suggestions"),
                       "prediction must not reintroduce a visible suggestion list")
        XCTAssertFalse(root.contains("TypingSuggestionLane()"))
        XCTAssertFalse(root.contains("liveSuggestions"))
        XCTAssertFalse(root.contains("acceptLiveSuggestion(at:"))
        XCTAssertFalse(root.contains("Insert suggestion:"))
        XCTAssertFalse(root.contains("postDictationSuggestions"))
        XCTAssertFalse(root.contains("acceptPostDictationSuggestion"))
        XCTAssertFalse(state.contains("PostDictationSuggestionPolicy"))
        XCTAssertFalse(state.contains("clearPostDictationSuggestions"))
        XCTAssertFalse(state.contains("acceptLiveSuggestion"))
        XCTAssertTrue(root.contains("KeyboardShiftState.doubleTapWindow"))
        XCTAssertTrue(controller.contains("SuggestionState.shared.handleSpace(proxy:"))
        XCTAssertFalse(controller.contains("refreshTypingSuggestions()"))
        XCTAssertTrue(root.contains("UIDeferredMenuElement"))
        XCTAssertTrue(root.contains("pasteButton"))
        XCTAssertTrue(root.contains("doc.on.clipboard"))
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
        XCTAssertTrue(state.contains("HostInputTraits.prefersNumberPad(for:"))
        XCTAssertTrue(state.contains("presentPreferredOpeningArea()"))
        XCTAssertTrue(state.contains("hostPrefersNumberPad"))
        XCTAssertTrue(root.contains("state.hostPrefersNumberPad"))
        XCTAssertTrue(root.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(root.contains("Text(dictationTitle)"))
        XCTAssertTrue(root.contains("onDelete: { routeProxyCommand(.delete) }"))
        XCTAssertFalse(root.contains("onDismiss: onDismiss"))
        XCTAssertFalse(controller.contains("hostingController?.view.isHidden = true"))
        XCTAssertTrue(controller.contains("setVoiceActionControlsHidden(mode == .panel || mode == .letters || mode == .numberPad)"))
        XCTAssertTrue(root.contains("layout.chromeLettersFrame"))
        XCTAssertTrue(root.contains("private var languageIndicator"))
        XCTAssertTrue(controller.contains("dismissKeyboard()"))
        XCTAssertTrue(controller.contains("routeDismiss: { [weak self] in self?.dismissKeyboard() }"),
                      "the controller must own dismissal through the SwiftUI callback")
        XCTAssertTrue(root.contains("SuggestionBarIconButton("))
        XCTAssertTrue(root.contains("action: routeDismiss"))
        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.layout("))
        XCTAssertTrue(root.contains("LiquidSymbolPageView("))
        XCTAssertTrue(root.contains("LiquidNumberPadView("))
        XCTAssertTrue(root.contains("case .numberPad:"))
        XCTAssertTrue(state.contains("hostNumberPadStyle"))
        XCTAssertTrue(state.contains("presentArea(.numberPad, registerUserDismissal: false)"))
        XCTAssertTrue(state.contains("func presentNumbersArea()"))
        XCTAssertTrue(root.contains("number-pad-surface"))
        XCTAssertTrue(root.contains("Locale.current.decimalSeparator"))
        XCTAssertTrue(root.contains("state.presentNumbersArea()"))
        XCTAssertTrue(controller.contains("identifier: \"number-layer\""))
        XCTAssertTrue(controller.contains("self.presentNumbersArea()"))
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

        XCTAssertTrue(root.contains("width: CGFloat(width), height: CGFloat(height)"))
        XCTAssertTrue(root.contains("KeyboardDeleteButton("))
        XCTAssertTrue(root.contains("systemName: \"return\""))
        XCTAssertTrue(root.contains("width: VoiceOnlyKeyboardPolicy.actionHitSize.width"))
        XCTAssertTrue(root.contains("height: VoiceOnlyKeyboardPolicy.actionHitSize.height"))
        XCTAssertTrue(root.contains("SuggestionBarIconButton("))
        XCTAssertTrue(root.contains("keyboard.chevron.compact.down"))
    }

    func testKeyboardHasNoGlobeGenerationOrRenderingPath() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let systemKeys = try source("DictusKeyboard/Vendored/Models/SystemKeys.swift")
        let keyView = try source("DictusKeyboard/Vendored/Views/KeyView.swift")
        let soundPolicy = try source("DictusKeyboard/KeySoundPolicy.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertFalse(systemKeys.contains("type: .keyboard,"))
        XCTAssertFalse(keyView.contains("globe"))
        XCTAssertFalse(soundPolicy.contains(".keyboard,"))
        XCTAssertFalse(controller.contains("case .keyboard:"))
        XCTAssertTrue(try String(contentsOf: repository.appending(path: "DictusKeyboard/InputView.swift"), encoding: .utf8).contains("inputViewStyle: .keyboard"))
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
        XCTAssertTrue(rootView.contains(".tint(.primary)"),
                      "the SwiftUI translation menu must use the system label color")
    }

    func testKeyboardRootUsesEmbeddedGlassSurfaceAndStableMicPlacement() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)"))
        XCTAssertTrue(root.contains("glassEffect(.regular"))
        XCTAssertTrue(root.contains(".regularMaterial"))
        XCTAssertTrue(root.contains("Color.white"))
        XCTAssertTrue(root.contains("Intentional white liquid-glass primary control"))
        XCTAssertTrue(root.contains(".foregroundStyle(.primary)"))
        XCTAssertTrue(root.contains("dictateFrame"))
        XCTAssertTrue(root.contains("let capsuleHeight = frame.height"))
        XCTAssertTrue(root.contains("height: capsuleHeight"))
        XCTAssertTrue(root.contains("surfaceFrame.midX"))
        XCTAssertTrue(root.contains("availableWidth: surfaceFrame.width"),
                      "emoji content must receive the complete embedded surface width")
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
            XCTAssertEqual(layout.dismissFrame.size, VoiceOnlyKeyboardPolicy.actionHitSize)
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
        XCTAssertTrue(root.contains("visualCornerRadius: 18"))
        XCTAssertTrue(root.contains("RoundedRectangle(cornerRadius: CGFloat(visualCornerRadius), style: .continuous)"))
        XCTAssertTrue(root.contains(".frame(width: CGFloat(visualWidth), height: CGFloat(visualHeight))"))
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
        XCTAssertTrue(root.contains("availableWidth: surfaceFrame.width"))
        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"))
    }

    func testMicUIKitTargetIsHiddenOutsideKeysAndRecordingAndOwnsAccessibility() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(controller.contains("uikitOwnsVoiceChrome"),
                      "the UIKit mic target owns glass dictation-board recovery")
        XCTAssertFalse(root.contains("accessoryDictationLabel"))
        XCTAssertFalse(controller.contains("micButton?.frame = isAuxiliary ? layout.accessoryMicrophoneFrame"))
        XCTAssertTrue(controller.contains("micButton?.frame = .zero"),
                      "a stale mic frame must never remain after relayout")
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
        XCTAssertTrue(controller.contains("identifier: \"dictate-button\", label: \"Hold to dictate\""))
        XCTAssertTrue(controller.contains("dismissButton?.isHidden = false"))
        XCTAssertTrue(root.contains(".accessibilityHidden(true)"))
    }

    func testFailedMicUsesRecoveryOnlyWhenRequiredAndRetriesOtherwise() throws {
        let state = try source("DictusKeyboard/KeyboardState.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(state.contains("case .failed:"))
        XCTAssertTrue(state.contains("if failedRequiresApp"))
        XCTAssertTrue(state.contains("openDictusForRecovery()"))
        XCTAssertTrue(state.contains("startRecording()"))
        XCTAssertTrue(controller.contains("state.handleMicPressBegan()"))
        XCTAssertTrue(controller.contains("KeyboardState.shared.handleMicPressEnded()"))
    }

    func testMicVisualUsesReadableSemanticForegroundAndIdleGlyph() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(root.contains(".foregroundStyle(.black)"))
        XCTAssertTrue(root.contains("state.appNeedsAppAction ? \"arrow.up.right.square.fill\" : \"mic.fill\""))
    }

    func testLanguageIndicatorIsPresentOnEveryKeyboardPage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"), encoding: .utf8)

        XCTAssertFalse(root.contains("if isBoard && layout.showsLanguageIndicator"),
                       "AUTO must remain in the shared lane on every page")
        XCTAssertTrue(root.contains("languageIndicator"))
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

    func testDarkKeyboardUsesSemanticBackgroundOrMaterial() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(contentsOf: repository.appending(path: "DictusKeyboard/Vendored/Models/Theme.swift"), encoding: .utf8)

        XCTAssertTrue(theme.contains(".systemGroupedBackground") ||
                      theme.contains(".secondarySystemBackground") ||
                      theme.contains(".regularMaterial"),
                      "dark keyboard background must use a semantic system color or material")
        XCTAssertFalse(theme.contains("backgroundColor: .black"),
                       "dark keyboard background must not be a fixed black color")
    }

    func testNumberPadDigitsHaveNoGlassKeycaps() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let padStart = try XCTUnwrap(root.range(of: "private struct LiquidNumberPadView"))
        let padEnd = try XCTUnwrap(root.range(of: "private struct PositionedNumberPadKey"))
        let pad = String(root[padStart.lowerBound..<padEnd.lowerBound])
        let insertStart = try XCTUnwrap(pad.range(of: "case .insert(let value, let holdLetters):"))
        let insertBody = String(pad[insertStart.lowerBound...])

        XCTAssertTrue(insertBody.contains("letterKeyPlate"),
                       "number-pad digits match letter keys with optional inset key plates")
        XCTAssertTrue(insertBody.contains("VoiceOnlyKeyboardPolicy.keyCornerRadius") || insertBody.contains("letterKeyPlate()"),
                      "digit plates reuse the shared letter-key radius")
        XCTAssertTrue(insertBody.contains(".font(.system(size: 22, weight: .light))"))
        XCTAssertTrue(insertBody.contains("Text(\"ABC\")"),
                      "the decimal/phone separator must show an ABC hold hint")
        XCTAssertTrue(insertBody.contains(".foregroundStyle(.secondary)"))
        XCTAssertTrue(insertBody.contains("ImmediateVariantKey("),
                      "the decimal/phone separator must open ABC on hold")
        XCTAssertTrue(insertBody.contains("KeyboardDeletion.holdRecognitionDuration"))
        XCTAssertTrue(pad.contains("case .letters:"))
        XCTAssertTrue(pad.contains("commandKeyPlate"),
                      "ABC on the pad keeps a command plate independent of letter containers")
        XCTAssertTrue(root.contains("state.presentNumbersArea()"))
        XCTAssertFalse(root.contains("accessoryLettersButton"),
                       "ABC must not sit in the suggestion bar on the number pad")
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
        XCTAssertTrue(root.contains("LiquidSymbolPageView("))
        XCTAssertTrue(root.contains("LiquidNumberPadView("),
                      "symbols mode must be rendered by SwiftUI")
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

        XCTAssertTrue(root.contains("onClose: { state.closeArea() }"),
                      "leaving the symbols surface must return through SwiftUI")
        XCTAssertTrue(controller.contains("layoutVoiceActionControls()"),
                      "leaving the symbols surface must immediately restore the native action hit areas")
    }

    func testKeyboardThemeResolvesSemanticColorsForBothAppearances() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/Vendored/Models/Theme.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(theme.contains("traits.userInterfaceStyle == .dark"),
                      "theme selection must follow the current system appearance")
        XCTAssertTrue(theme.contains("case .dark") && theme.contains("case .light"),
                      "the theme factory must define both appearance branches")
        XCTAssertTrue(theme.contains("UIColor.systemGroupedBackground"),
                      "keyboard background must use a semantic system color")
        XCTAssertTrue(theme.contains("UIColor.label") && theme.contains("UIColor.secondaryLabel"),
                      "keyboard foreground colors must remain semantic in light and dark mode")
        XCTAssertFalse(theme.contains("background: UIColor.white"),
                       "light-mode background must not be hardcoded white")
    }

    func testKeyboardThemeKeepsDarkSurfaceAndKeysDistinct() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let theme = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/Vendored/Models/Theme.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(theme.contains("let regularKey = style.isLegacy") &&
                      theme.contains(": UIColor.tertiarySystemGroupedBackground"),
                      "dark regular keys need a distinct semantic elevated surface")
        XCTAssertTrue(theme.contains("let specialKey = style.isLegacy") &&
                      theme.contains(": UIColor.secondarySystemBackground"),
                      "dark modifier keys need a distinct semantic surface")
        XCTAssertFalse(theme.contains("activeText: .white"),
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
