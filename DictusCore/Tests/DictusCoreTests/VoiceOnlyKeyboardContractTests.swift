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

        XCTAssertTrue(controller.contains("let auxiliaryControlsHidden = isAuxiliary"))
        XCTAssertTrue(controller.contains("$0.isEnabled = !isAuxiliary"))
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = !isAuxiliary && !$0.isHidden"))
        XCTAssertTrue(controller.contains("atButton?.isHidden = auxiliaryControlsHidden"))
        XCTAssertTrue(controller.contains("dismissButton?.isHidden = isAuxiliary || !rightRailVisible"))
    }


    func testMicrophoneUIKitHitTargetUsesPolicyFrameAndOwnsTouchLifecycle() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("micButton = makeKeyboardActionButton"))
        XCTAssertTrue(controller.contains("micButton?.frame = layout.dictateFrame"))
        XCTAssertTrue(controller.contains(".touchDown"))
        XCTAssertTrue(controller.contains(".touchUpInside"))
        XCTAssertTrue(controller.contains(".touchUpOutside"))
        XCTAssertTrue(controller.contains(".touchCancel"))
        XCTAssertTrue(controller.contains("state.startRecording()"))
        XCTAssertTrue(controller.contains("state.requestStop()"))
    }

    func testMicrophoneTouchDownGuardsBusyStatuses() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("guard state.dictationStatus == .idle || state.dictationStatus == .ready || state.dictationStatus == .failed else { return }"))
    }

    func testMicrophoneVisualRemainsSwiftUIOnlyAndDoesNotInstallGestureStartStop() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains(".background(Capsule().fill(Color.white))"))
        XCTAssertTrue(root.contains("case .idle, .ready: return \"mic.fill\""))
        XCTAssertFalse(root.contains("DragGesture(minimumDistance: 0)"))
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
        XCTAssertEqual(layout.surfaceFrame.minX, 6)
        XCTAssertEqual(layout.surfaceFrame.minY, 4)
    }

    func testAlternatePagesLeaveTheInsetSurfaceAndUseTheNativeCanvas() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(root.contains("? layout.auxiliaryContentFrame"),
                      "alternate content must begin below the accessory row")
        XCTAssertTrue(controller.contains("KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)"),
                      "the UIKit input view must provide the native adaptive backdrop")
        XCTAssertFalse(controller.contains("kbInputView.backgroundColor"),
                       "a transparent input view leaks the host wallpaper behind the keyboard")
        XCTAssertTrue(controller.contains("max(nativeHeight, CGFloat(VoiceOnlyKeyboardPolicy.alternateMinimumHeight))"),
                      "alternate pages must reserve enough height for three real symbol-content rows plus one accessory row")
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
        XCTAssertTrue(emoji.contains("return max(1, Int(gridSpace / rowWithSpacing))"),
                      "emoji rows must be limited to complete rows that fit above the category bar")
        XCTAssertFalse(emoji.contains("return max(3, Int(gridSpace / rowWithSpacing))"),
                       "a forced third row is clipped when the category bar is visible")
        XCTAssertFalse(emoji.contains("Text(selectedCategoryName)"),
                       "the removed search/header lane must not leave a second offset")
    }

    func testEmojiGridUsesOnePointerHighlightInsteadOfPerCellGlass() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let gridStart = try XCTUnwrap(picker.range(of: "LazyVGrid(columns: gridColumns"))
        let categoryStart = try XCTUnwrap(picker.range(of: "EmojiCategoryBar("))
        let gridBody = String(picker[gridStart.lowerBound..<categoryStart.lowerBound])

        XCTAssertFalse(gridBody.contains(".keyboardGlassEffect()"),
                       "emoji cells must not own individual glass containers")
        XCTAssertTrue(picker.contains("private var emojiPointerHighlight"),
                      "the picker must render one shared touch highlight")
        XCTAssertTrue(picker.contains("pressedEmojiIndex"),
                      "the shared highlight must follow the active emoji target")
        XCTAssertTrue(picker.contains("ZStack"),
                      "the highlight must be layered behind the emoji grid")
    }

    func testEmojiPointerUsesSharedGridGeometryAndReleaseContract() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains("private let emojiColumnCount: Int = 8"),
                      "grid geometry must define one shared column count")
        XCTAssertTrue(picker.contains("private let gridHorizontalPadding: CGFloat = 2"),
                      "grid geometry must define one shared horizontal padding")
        XCTAssertTrue(picker.contains("count: emojiColumnCount"),
                      "the LazyVGrid columns must use the shared column count")
        XCTAssertTrue(picker.contains("availableWidth - gridHorizontalPadding * 2"),
                      "cell width must use the shared horizontal padding")
        XCTAssertTrue(picker.contains("x: gridHorizontalPadding +"),
                      "the shared highlight must include the grid horizontal padding")
        XCTAssertTrue(picker.contains("(point.x - gridHorizontalPadding)"),
                      "pointer mapping must use the shared horizontal padding")
        XCTAssertTrue(picker.contains("column < emojiColumnCount"),
                      "pointer mapping must use the shared column count")

        let gesture = try XCTUnwrap(picker.range(of: ".gesture("))
        let gestureBody = String(picker[gesture.lowerBound...])
        XCTAssertTrue(gestureBody.contains("DragGesture(minimumDistance: 0"),
                      "emoji grid must use the zero-distance drag gesture")
        XCTAssertTrue(gestureBody.contains(".onChanged { value in"),
                      "pointer tracking must update during onChanged")
        XCTAssertTrue(gestureBody.contains(".onEnded { value in"),
                      "pointer tracking must handle release in onEnded")
        XCTAssertTrue(gestureBody.contains("guard let index = emojiIndex(at: value.location), currentCategoryEmojis.indices.contains(index) else"),
                      "release must have one legal insertion guard")
        XCTAssertEqual(gestureBody.components(separatedBy: "insertEmoji(currentCategoryEmojis[index].emoji)").count - 1, 1,
                       "release must insert at most once")
        XCTAssertTrue(gestureBody.contains("pressedEmojiIndex = nil"),
                      "release must clear the pressed state")
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
        XCTAssertTrue(root.contains("LiquidSymbolPageView("),
                      "SwiftUI must provide the symbols surface")
        XCTAssertTrue(root.contains(".frame(width: contentFrame.width, height: contentFrame.height)"),
                      "the symbols surface must fill the content frame")
    }

    func testAuxiliaryContentStartsBelowUIKitAccessoryRow() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(root.contains("layout.auxiliaryContentFrame"))
        XCTAssertTrue(root.contains("layout.auxiliaryContentFrame"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertTrue(controller.contains("configureAuxiliaryAccessoryControls"))
    }

    func testAuxiliaryAccessoryIsOwnedByNativeInputViewInsteadOfSwiftUISurface() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(root.contains("alternateAccessoryRow(layout:"),
                       "the alternate accessory row must not be rendered inside SwiftUI")
        XCTAssertTrue(controller.contains("configureAuxiliaryAccessoryControls"),
                      "UIKit must own the alternate accessory controls and their hit targets")
    }

    func testAuxiliaryLayoutRaisesUIKitControlsAboveEveryAuxiliarySubview() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("if let controls = actionControlsView, let inputView {\n            inputView.bringSubviewToFront(controls)\n        }"),
                      "layout must explicitly restore the UIKit hit layer above the symbols view")
    }

    func testAuxiliaryAccessoryUsesUIKitNativeVisualsWithoutSwiftUIActions() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("imageName: \"arrow.uturn.backward\""))
        XCTAssertTrue(controller.contains("micConfiguration.image = UIImage(systemName: \"mic.fill\""))
        XCTAssertTrue(controller.contains("imageName: \"delete.left\""))
        XCTAssertTrue(controller.contains("imageName: \"return\""))
        XCTAssertTrue(controller.contains("UIButton.Configuration.filled()"))
        XCTAssertTrue(controller.contains("baseBackgroundColor = .white"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertTrue(root.contains("background(Capsule().fill(Color.white))"),
                      "the voice page keeps its own white microphone capsule")
        XCTAssertFalse(root.contains("state.startRecording()"))
        XCTAssertFalse(root.contains("state.requestStop()"))
    }

    func testAuxiliaryModeOwnsOnlyRevertMicDeleteAndReturnControls() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(controller.contains("atButton?.isHidden = auxiliaryControlsHidden || !leftRailVisible"))
        XCTAssertTrue(controller.contains("emojiButton?.isHidden = auxiliaryControlsHidden || !leftRailVisible"))
        XCTAssertTrue(controller.contains("dismissButton?.isHidden = isAuxiliary || !rightRailVisible"))
        XCTAssertTrue(controller.contains("micButton?.isHidden = auxiliaryControlsHidden ||"))
        XCTAssertTrue(controller.contains("configureAuxiliaryAccessoryControls(for: mode)"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertTrue(controller.contains("configureAuxiliaryAccessoryControls(for: mode)"))
    }

    func testAuxiliaryControlsHideWhenAccessoryRowIsUnavailable() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("numberButton?.isHidden = auxiliaryControlsHidden || !leftRailVisible"))
        XCTAssertTrue(controller.contains("micButton?.isHidden = auxiliaryControlsHidden ||"))
        XCTAssertTrue(controller.contains("deleteButton?.isHidden = auxiliaryControlsHidden"))
        XCTAssertTrue(controller.contains("returnButton?.isHidden = auxiliaryControlsHidden"))
    }

    func testReturningToVoiceRemovesAuxiliaryGlassBackgrounds() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let configurationStart = try XCTUnwrap(controller.range(of: "private func configureAuxiliaryAccessoryControls"))
        let visualsStart = try XCTUnwrap(controller.range(of: "private func setAuxiliaryUtilityVisuals"))
        let configurationBody = String(controller[configurationStart.lowerBound..<visualsStart.lowerBound])

        XCTAssertTrue(configurationBody.contains("viewWithTag(Self.glassBackgroundTag)"),
                      "voice mode must find the glass layer created by auxiliary mode")
        XCTAssertTrue(configurationBody.contains("removeFromSuperview()"),
                      "voice mode must remove the auxiliary glass layer before reusing the button")
    }

    func testAuxiliaryUIKitAccessoryRowFailsClosedWithItsGeometry() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("auxiliaryFramesAvailable"),
                      "auxiliary UIKit controls must be hidden when their geometry is invalid")
    }

    func testUIKitBackdropAndPressedRadiusUseActualFrames() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let inputView = try source("DictusKeyboard/InputView.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(inputView.contains("inputViewStyle: .keyboard"))
        XCTAssertTrue(inputView.contains("backgroundColor = .clear"))
        XCTAssertTrue(inputView.contains("isOpaque = false"))
        XCTAssertTrue(controller.contains("$0.layer.cornerRadius = $0.bounds.height / 2"))
        XCTAssertTrue(controller.contains("micButton?.layer.cornerRadius = (micButton?.bounds.height ?? 0) / 2"))
        XCTAssertFalse(root.contains("Color(uiColor: .systemBackground)"))
    }

    func testAuxiliaryReturnUsesSharedAppleControlSurfaceSemantics() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertTrue(controller.contains("layer.cornerCurve = .continuous"))
        XCTAssertTrue(controller.contains("imageName: \"return\""))
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
        XCTAssertTrue(root.contains("layout.auxiliaryContentFrame"))
        XCTAssertTrue(controller.contains("let height = max(1, controls.bounds.height)"))
        XCTAssertTrue(controller.contains("handleDeleteHold"))
        XCTAssertTrue(controller.contains("RunLoop.main.add(timer, forMode: .common)"))
        XCTAssertTrue(layouts.contains("KeyDefinition(type: .shiftSymbols"))
        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 3"))
    }

    func testRuntimeSurfaceUsesOneSharedLayoutContract() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(controller.contains("controlOrder: KeyboardAccessoryOrder.current"))
        XCTAssertTrue(root.contains("layout.auxiliaryContentFrame"))
        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.layout("))
        XCTAssertTrue(root.contains("surfaceHeight: Double(surfaceHeight)"))
    }

    func testEmojiPickerReceivesTheInsetContentHeight() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let emoji = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(root.contains("availableHeight: contentFrame.height"),
                      "emoji picker height must match the inset content/surface frame")
        XCTAssertTrue(emoji.contains("private let categoryBarHeight: CGFloat = 44"),
                      "emoji geometry must use the actual category-bar height")
        XCTAssertFalse(root.contains("availableHeight: surfaceHeight"),
                       "the outer keyboard height includes the surface inset")
    }

    func testSymbolsReserveTheBottomRowForTheTopmostABCControlGeometryOnly() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 3"))
        XCTAssertTrue(root.contains("LiquidSymbolPageView("),
                      "SwiftUI must own the symbols page content")
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"),
                      "the UIKit mode control must remain above the symbols surface")
    }

    func testBothAuxiliaryModeControlsUseOnlyTheirSmallUtilityHitFrame() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertEqual(controller.components(separatedBy: "numberButton?.frame = layout.leftUtilityFrames.number").count - 1, 1,
                       "both auxiliary modes must share one compact frame assignment")
    }

    func testAuxiliaryModeControlUpdatesAccessibilitySemantics() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("numberButton?.accessibilityLabel = isAuxiliary"),
                      "the mode control label must describe its current action")
        XCTAssertTrue(controller.contains("numberButton?.accessibilityHint = isAuxiliary"),
                      "the mode control hint must describe its current action")
        XCTAssertTrue(controller.contains("Open symbols keyboard"),
                      "normal mode must announce opening symbols")
        XCTAssertTrue(controller.contains("Return to voice keyboard"),
                      "auxiliary mode must announce returning to voice keyboard")
        XCTAssertTrue(controller.contains("if KeyboardState.shared.areaMode == .emoji")
            && controller.contains("KeyboardState.shared.closeArea()"),
                      "emoji ABC action must return to the voice keyboard")
        XCTAssertTrue(controller.contains("else if KeyboardState.shared.areaMode == .panel")
            && controller.contains("closeNumberPanel()"),
                      "symbols ABC action must return to the voice keyboard")
        XCTAssertTrue(controller.contains("self.presentArea(.panel)"),
                      "normal 123 action must open the symbols keyboard")
    }

    func testAuxiliaryKeyboardUsesFullSurfaceAndActionControlsStayOnTop() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controlOrder: KeyboardAccessoryOrder.current"))
        XCTAssertTrue(controller.contains("actionControlsView = controls"))
        XCTAssertTrue(controller.contains("if let controls = actionControlsView"))
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"))
    }

    func testBothAuxiliaryPagesKeepModeControlAvailableToReturnToNormal() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("numberButton?.isHidden = auxiliaryControlsHidden || !leftRailVisible"),
                      "UIKit must release the auxiliary hit target to SwiftUI")
        XCTAssertTrue(controller.contains("layoutVoiceActionControls()"),
                      "mode visibility must be refreshed after each layout transition")
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"),
                      "UIKit action controls must be restored above auxiliary content")
    }

    func testAuxiliaryAccessoryUsesUIKitRevertControlInsteadOfVoiceABCVisual() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(root.contains("utilityGlyph(text: state.areaMode.modeControlTitle)"))
        XCTAssertTrue(root.contains("layout.leftUtilityFrames.number.midX"))
        XCTAssertTrue(controller.contains("imageName: \"arrow.uturn.backward\""))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
    }

    func testDeleteRepeatStopsOnCancelAndEnd() throws {
        let keyboardView = try source("DictusKeyboard/Vendored/Views/KeyboardView.swift")

        XCTAssertTrue(keyboardView.contains("func stopKeyRepeat()"))
        XCTAssertTrue(keyboardView.contains("stopKeyRepeat()"))
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
        XCTAssertFalse(root.contains("suggestionState"))
        XCTAssertFalse(root.contains("fullAreaToolbar"))
        XCTAssertFalse(root.contains("togglePanel"))
        XCTAssertFalse(root.contains("keyboard-controls"))
        XCTAssertTrue(root.contains("keyboard.chevron.compact.down"))
        XCTAssertTrue(root.contains("usesInteractiveSurface: false"))
        XCTAssertTrue(root.contains("onEmoji: { state.presentArea(.emoji) }"))
        XCTAssertFalse(root.contains("private func utilityButton("))
        XCTAssertFalse(root.contains("LazyVGrid"))
        XCTAssertTrue(root.contains("allowsHitTesting(false)"))
        XCTAssertTrue(controller.contains("identifier: \"number-layer\""))
        XCTAssertTrue(controller.contains("KeyboardState.shared.closeArea()"))
        XCTAssertTrue(controller.contains("identifier: \"at-key\""))
        XCTAssertTrue(controller.contains("identifier: \"emoji-picker\""))
        XCTAssertTrue(controller.contains("identifier: \"number-layer\""))
        XCTAssertEqual(controller.components(separatedBy: "identifier: \"dismiss-keyboard\"").count - 1, 1)
        XCTAssertEqual(root.components(separatedBy: "usesInteractiveSurface: false").count - 1, 1)
        XCTAssertFalse(root.contains("openURL"))
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
        XCTAssertFalse(root.contains("identifier: \"dismiss-keyboard\""))
        XCTAssertTrue(controller.contains("makeKeyboardActionButton"))
        XCTAssertFalse(controller.contains("handleInputModeList(from: sender, with: event)"))
        XCTAssertFalse(controller.contains("nextInputModeButton"))
        XCTAssertFalse(root.contains("utilityGlyph(systemName: \"globe\")"))
        XCTAssertTrue(root.contains("state.areaMode.modeControlTitle"))
        XCTAssertFalse(root.contains("Text(\"AUTO\")"))
        XCTAssertTrue(root.contains("languageIndicatorTitle"))
        XCTAssertTrue(root.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(root.contains("Text(dictationTitle)"))
        XCTAssertFalse(root.contains("onDelete: onDelete"))
        XCTAssertFalse(root.contains("onDismiss: onDismiss"))
        XCTAssertFalse(controller.contains("hostingController?.view.isHidden = true"))
        XCTAssertFalse(controller.contains("setVoiceActionControlsHidden(mode == .emoji)"))
        XCTAssertTrue(root.contains("layout.leftUtilityFrames"))
        XCTAssertTrue(root.contains("layout.languageFrame"))
        XCTAssertTrue(controller.contains("dismissKeyboard()"))
        XCTAssertTrue(root.contains("KeyboardLayouts.current"))
        XCTAssertTrue(root.contains("LiquidSymbolPageView("))
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
        XCTAssertTrue(root.contains("utilityGlyph(systemName: \"delete.backward\", width: VoiceOnlyKeyboardPolicy.actionHitSize.width, height: VoiceOnlyKeyboardPolicy.actionHitSize.height"))
        XCTAssertTrue(root.contains("utilityGlyph(systemName: \"return\", width: VoiceOnlyKeyboardPolicy.actionHitSize.width, height: VoiceOnlyKeyboardPolicy.actionHitSize.height"))
        XCTAssertTrue(root.contains("utilityGlyph(systemName: \"keyboard.chevron.compact.down\", width: VoiceOnlyKeyboardPolicy.actionHitSize.width, height: VoiceOnlyKeyboardPolicy.actionHitSize.height"))
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
        XCTAssertFalse(controller.contains("case .keyboard"))
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
        XCTAssertTrue(root.contains(".foregroundStyle(.primary)"))
        XCTAssertTrue(root.contains("dictateFrame"))
        XCTAssertTrue(root.contains("let capsuleHeight = frame.height"))
        XCTAssertTrue(root.contains("height: capsuleHeight"))
        XCTAssertTrue(root.contains("surfaceFrame.midX"))
        XCTAssertTrue(root.contains("availableWidth: availableWidth"),
                      "emoji content must receive the complete embedded surface width")
        XCTAssertTrue(root.contains("auxiliaryContentFrame"))
    }

    func testLatestVoiceLayoutUsesThreeLeftTargetsAndBottomDismiss() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 216)
            XCTAssertEqual(VoiceOnlyKeyboardPolicy.leftRailControlCount, 3)
            XCTAssertEqual(layout.leftUtilityFrames.at.width, 44)
            XCTAssertEqual(layout.leftUtilityFrames.at.minY, 116)
            XCTAssertEqual(layout.leftUtilityFrames.at.maxY, layout.leftUtilityFrames.emoji.minY)
            XCTAssertEqual(layout.leftUtilityFrames.emoji.minX, layout.leftUtilityFrames.at.minX)
            XCTAssertEqual(layout.leftUtilityFrames.number.minX, layout.leftUtilityFrames.emoji.maxX + 4)
            XCTAssertEqual(layout.leftUtilityFrames.number.minY, layout.leftUtilityFrames.emoji.minY)
            XCTAssertEqual(layout.dismissFrame.size, VoiceOnlyKeyboardPolicy.actionHitSize)
            XCTAssertEqual(layout.dismissFrame.maxY, layout.surfaceFrame.maxY - 8, accuracy: 0.001)
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

        XCTAssertTrue(root.contains("visualWidth: 80, visualHeight: 36, visualCornerRadius: 18"))
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
        XCTAssertEqual(layout.centerAreaWidth, 150)
        XCTAssertTrue(root.contains("availableWidth: availableWidth"))
        XCTAssertTrue(root.contains("layout.auxiliaryContentFrame"))
    }

    func testMicUIKitTargetIsHiddenOutsideKeysAndRecordingAndOwnsAccessibility() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(controller.contains("micButton?.isHidden = auxiliaryControlsHidden ||"))
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = !isAuxiliary && !$0.isHidden"))
        XCTAssertTrue(controller.contains("identifier: \"dictate-button\", label: \"Hold to dictate\""))
        XCTAssertTrue(root.contains(".accessibilityHidden(true)"))
    }

    func testFailedMicUsesRecoveryOnlyWhenRequiredAndRetriesOtherwise() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        XCTAssertTrue(controller.contains("if state.dictationStatus == .failed, state.failedRequiresApp"))
        XCTAssertTrue(controller.contains("else {"))
        XCTAssertTrue(controller.contains("state.startRecording()"))
    }

    func testMicVisualUsesReadableSemanticForegroundAndIdleGlyph() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(root.contains(".foregroundStyle(.black)"))
        XCTAssertTrue(root.contains("case .idle, .ready: return \"mic.fill\""))
    }

    func testLanguageIndicatorIsRestrictedToKeysAndRecordingModes() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardRootView.swift"), encoding: .utf8)

        XCTAssertTrue(root.contains("if (state.areaMode == .keys || state.areaMode == .recording) && layout.showsLanguageIndicator") ||
                      root.contains("if layout.showsLanguageIndicator && (state.areaMode == .keys || state.areaMode == .recording)"),
                      "language indicator must not be rendered for emoji or panel modes")
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
        XCTAssertTrue(root.contains("layout.auxiliaryContentFrame"),
                      "symbols mode must use the live native surface bounds below the accessory row")
        XCTAssertTrue(root.contains("LiquidSymbolPageView("),
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
