import XCTest
@testable import DictusCore

final class VoiceOnlyKeyboardContractTests: XCTestCase {

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

        XCTAssertTrue(root.contains("state.startRecording()"))
        XCTAssertFalse(root.contains("advanceToNextInputMode()"))
        XCTAssertTrue(root.contains("DragGesture(minimumDistance: 0)"))
        XCTAssertTrue(root.contains(".onEnded"))
        XCTAssertTrue(root.contains("state.requestStop()"))
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

    func testLatestVoiceLayoutUsesThreeLeftTargetsAndBottomDismiss() {
        for width in [320.0, 375, 390, 430] {
            let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 216)
            XCTAssertEqual(VoiceOnlyKeyboardPolicy.leftRailControlCount, 3)
            XCTAssertEqual(layout.leftUtilityFrames.at.width, 44)
            XCTAssertEqual(layout.leftUtilityFrames.emoji.minX, layout.leftUtilityFrames.at.maxX)
            XCTAssertEqual(layout.leftUtilityFrames.number.minX, layout.leftUtilityFrames.emoji.maxX)
            XCTAssertEqual(layout.leftUtilityFrames.number.minY, layout.leftUtilityFrames.emoji.minY)
            XCTAssertEqual(layout.dismissFrame.size, VoiceOnlyKeyboardPolicy.actionHitSize)
            XCTAssertEqual(layout.dismissFrame.maxY, 216, accuracy: 0.001)
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
        XCTAssertEqual(layout.centerAreaWidth, 150)
        XCTAssertTrue(root.contains("availableWidth: width"))
        XCTAssertTrue(controller.contains("numberKeyboardView.frame = layout.alternateContentFrame"))
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
