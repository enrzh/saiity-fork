import XCTest
@testable import DictusCore

final class VoiceOnlyKeyboardContractTests: XCTestCase {

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

    func testMicrophoneVisualRemainsSwiftUIOnlyAndDoesNotInstallGestureStartStop() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains(".background(Capsule().fill(Color.white))"))
        XCTAssertTrue(root.contains("case .idle, .ready: return \"mic.fill\""))
        XCTAssertFalse(root.contains("DragGesture(minimumDistance: 0)"))
        XCTAssertFalse(root.contains("state.startRecording()"))
        XCTAssertFalse(root.contains("state.requestStop()"))
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
        let keyboardView = try source("DictusKeyboard/Vendored/Views/KeyboardView.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")

        XCTAssertTrue(controller.contains("numberKeyboardView?.page = .symbols2"))
        XCTAssertTrue(controller.contains("numberKeyboardView?.page = .symbols1"))
        XCTAssertTrue(controller.contains("numberKeyboardView?.page = .normal"))
        XCTAssertTrue(keyboardView.contains("keyRepeatTimer?.invalidate()"))
        XCTAssertTrue(controller.contains("KeyboardHeightProvider.height"))
        XCTAssertTrue(controller.contains("numberKeyboardView.frame = layout.alternateContentFrame"))
        XCTAssertTrue(controller.contains("let height = max(1, controls.bounds.height)"))
        XCTAssertTrue(controller.contains("handleDeleteHold"))
        XCTAssertTrue(controller.contains("RunLoop.main.add(timer, forMode: .common)"))
        XCTAssertTrue(controller.contains("numberKeyboardView.clipsToBounds = true"))
        XCTAssertTrue(layouts.contains("KeyDefinition(type: .shiftSymbols"))
        XCTAssertTrue(layouts.contains("blankRow()"))
        XCTAssertFalse(layouts.contains("bottomRow("))
    }

    func testRuntimeSurfaceUsesOneSharedLayoutContract() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(controller.contains("let layout = VoiceOnlyKeyboardPolicy.layout(for: Double(width), surfaceHeight: Double(height))"))
        XCTAssertTrue(controller.contains("numberKeyboardView.frame = layout.alternateContentFrame"))
        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.layout("))
        XCTAssertTrue(root.contains("surfaceHeight: Double(surfaceHeight)"))
    }

    func testEmojiPickerReceivesTheInsetContentHeight() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("availableHeight: contentFrame.height"),
                      "emoji picker height must match the inset content/surface frame")
        XCTAssertFalse(root.contains("availableHeight: surfaceHeight"),
                       "the outer keyboard height includes the surface inset")
    }

    func testSymbolsReserveTheBottomRowForTheTopmostABCControlGeometryOnly() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")

        XCTAssertTrue(layouts.contains("// Row 4 is reserved for the UIKit-owned public actions."))
        XCTAssertTrue(layouts.contains("private static func blankRow()"))
        XCTAssertFalse(controller.contains("numberButton?.frame = layout.symbolsReservedRowFrame"),
                       "the runtime button must not claim the full reserved row")
        XCTAssertTrue(controller.contains("controls.superview?.bringSubviewToFront(controls)"),
                      "the UIKit mode control must remain above the symbols surface")
    }

    func testBothAuxiliaryModeControlsUseOnlyTheirSmallUtilityHitFrame() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(controller.contains("numberButton?.frame = layout.symbolsReservedRowFrame"))
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

        XCTAssertTrue(controller.contains("numberKeyboardView.frame = layout.alternateContentFrame"))
        XCTAssertTrue(controller.contains("actionControlsView = controls"))
        XCTAssertTrue(controller.contains("if let controls = actionControlsView"))
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"))
    }

    func testBothAuxiliaryPagesKeepModeControlAvailableToReturnToNormal() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("numberButton?.isHidden = !leftRailVisible"),
                      "the mode control must remain reachable on both symbols and emoji pages")
        XCTAssertTrue(controller.contains("layoutVoiceActionControls()"),
                      "mode visibility must be refreshed after each layout transition")
        XCTAssertTrue(controller.contains("controls.superview?.bringSubviewToFront(controls)"),
                      "UIKit action controls must be restored above auxiliary content")
    }

    func testAuxiliaryRootDrawsTheSharedABCModeControlGlyph() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("utilityGlyph(text: state.areaMode.modeControlTitle)"))
        XCTAssertTrue(root.contains("layout.leftUtilityFrames.number.midX"))
        XCTAssertTrue(root.contains("if state.areaMode != .panel && state.areaMode != .emoji"))
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
        XCTAssertFalse(root.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)"))
        XCTAssertFalse(root.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)"))
        XCTAssertTrue(root.contains("keyboard.chevron.compact.down"))
        XCTAssertTrue(root.contains("usesInteractiveSurface: false"))
        XCTAssertFalse(root.contains("state.presentArea(.emoji)"))
        XCTAssertFalse(root.contains("state.presentArea(.panel)"))
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
        XCTAssertTrue(root.contains("Color(uiColor: .secondarySystemBackground)"))
        XCTAssertTrue(root.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(root.contains("Text(dictationTitle)"))
        XCTAssertFalse(root.contains("onDelete: onDelete"))
        XCTAssertFalse(root.contains("onDismiss: onDismiss"))
        XCTAssertFalse(controller.contains("hostingController?.view.isHidden = true"))
        XCTAssertFalse(controller.contains("setVoiceActionControlsHidden(mode == .emoji)"))
        XCTAssertTrue(root.contains("layout.leftUtilityFrames"))
        XCTAssertTrue(root.contains("layout.languageFrame"))
        XCTAssertTrue(controller.contains("dismissKeyboard()"))
        XCTAssertTrue(controller.contains("KeyboardLayouts.current"))
        XCTAssertTrue(controller.contains("numberKeyboardView?.page = .symbols1"))
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
        XCTAssertTrue(root.contains("surfaceFrame.midX"))
        XCTAssertTrue(root.contains("availableWidth: availableWidth"),
                      "emoji content must receive the complete embedded surface width")
        XCTAssertTrue(root.contains("alternateContentFrame"))
    }

    func testLatestVoiceLayoutUsesThreeLeftTargetsAndBottomDismiss() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 216)
            XCTAssertEqual(VoiceOnlyKeyboardPolicy.leftRailControlCount, 3)
            XCTAssertEqual(layout.leftUtilityFrames.at.width, 44)
            XCTAssertEqual(layout.leftUtilityFrames.at.minY, 112)
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
        let controller = try String(contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"), encoding: .utf8)

        let layout = VoiceOnlyKeyboardPolicy.layout(for: 390)
        XCTAssertEqual(layout.centerAreaWidth, 146)
        XCTAssertTrue(root.contains("availableWidth: availableWidth"))
        XCTAssertTrue(controller.contains("numberKeyboardView.frame = layout.alternateContentFrame"))
    }

    func testMicUIKitTargetIsHiddenOutsideKeysAndRecordingAndOwnsAccessibility() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(controller.contains("micButton?.isHidden = mode != .keys && mode != .recording"))
        XCTAssertTrue(controller.contains("micButton?.isUserInteractionEnabled = !(micButton?.isHidden ?? true)"))
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
        XCTAssertTrue(emoji.contains("let language = SupportedLanguage.active.rawValue"))
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
        XCTAssertTrue(controller.contains("keyboard.frame = layout.alternateContentFrame"),
                      "symbols mode must use the live native surface bounds above the bottom actions")
        XCTAssertTrue(controller.contains("keyboard.autoresizingMask = [.flexibleWidth, .flexibleHeight]"),
                      "symbols mode must follow native surface size changes")
        XCTAssertTrue(root.contains("let surfaceHeight = max(proxy.size.height, 1)"),
                      "voice and symbols surfaces must consume the runtime native surface height")
    }

    func testVendoredKeyboardInvalidatesGridAfterAuxiliarySurfaceResizes() throws {
        let keyboardView = try source("DictusKeyboard/Vendored/Views/KeyboardView.swift")

        XCTAssertTrue(keyboardView.contains("private var lastLaidOutBounds"),
                      "the vendored grid must remember the bounds used for its cached cell sizes")
        XCTAssertTrue(keyboardView.contains("collectionView.collectionViewLayout.invalidateLayout()"),
                      "a native keyboard height transition must invalidate cached symbol cell frames")
    }

    func testSymbolsReturnRestoresTheVendoredKeyboardPage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = try String(
            contentsOf: repository.appending(path: "DictusKeyboard/KeyboardViewController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(controller.contains("numberKeyboardView?.page = .normal"),
                      "leaving the symbols surface must reset the vendored keyboard page")
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
