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
        let keyboardStart = try XCTUnwrap(settings.range(of: "Section(\"Keyboard\")"))
        let nextSection = try XCTUnwrap(settings.range(of: "Section(\"Translation & Cleanup\")"))
        let keyboardSection = String(settings[keyboardStart.lowerBound..<nextSection.lowerBound])

        XCTAssertTrue(keyboardSection.contains("Picker(selection: keyboardAccessoryOrderBinding, label: Text(\"Control order\"))"))
        XCTAssertTrue(keyboardSection.contains("KeyboardAccessoryOrder.emojiFirst"))
        XCTAssertTrue(keyboardSection.contains(".numberFirst"))
        XCTAssertTrue(keyboardSection.contains("NavigationLink { ModelManagerView(modelManager: modelManager) } label:"))
        XCTAssertTrue(keyboardSection.contains("Label(\"Models\", systemImage: \"square.stack.3d.up.fill\")"))
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

        XCTAssertTrue(controller.contains("controls.isHidden = isAuxiliary"))
        XCTAssertTrue(controller.contains("$0.isEnabled = false"))
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = false"))
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = !isAuxiliary"),
                      "the UIKit overlay must pass through SwiftUI auxiliary pages")
        XCTAssertTrue(controller.contains("guard !isAuxiliary else {"))
        XCTAssertTrue(controller.contains("$0.isHidden = true"))
    }

    func testAuxiliaryModeSkipsAllUIKitFrameAndZOrderUpdates() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let start = try XCTUnwrap(controller.range(of: "private func layoutVoiceActionControls(surfaceHeight: CGFloat? = nil)"))
        let end = try XCTUnwrap(controller.range(of: "@objc private func handleMicTouchDown"))
        let body = String(controller[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(body.contains("guard !isAuxiliary else {"),
                      "auxiliary pages must leave UIKit frame ownership to SwiftUI")
        XCTAssertFalse(body.contains("if isAuxiliary {"),
                       "auxiliary mode must not assign substitute UIKit frames")
        let guardOffset = try XCTUnwrap(body.range(of: "guard !isAuxiliary else {")?.lowerBound)
        let frameOffset = try XCTUnwrap(body.range(of: "atButton?.frame =")?.lowerBound)
        let zOrderOffset = try XCTUnwrap(body.range(of: "inputView.bringSubviewToFront(controls)")?.lowerBound)
        XCTAssertLessThan(guardOffset, frameOffset)
        XCTAssertLessThan(guardOffset, zOrderOffset)
    }

    func testCurrentSymbolPagesHaveFourRowsAndNonOverlappingBottomFunctions() throws {
        for page in [KeyboardSymbolsLayout.numbers, KeyboardSymbolsLayout.symbols] {
            XCTAssertEqual(page.count, 4)
            XCTAssertTrue(page.flatMap { $0 }.contains { $0.kind == .insert(".") })
            XCTAssertTrue(page[3].contains { $0.kind == .delete })
            XCTAssertTrue(page[3].contains { $0.kind == .returnKey })
            XCTAssertTrue(page[2].contains { $0.kind == .pageToggle })
            XCTAssertEqual(page[3].map(\.width).reduce(0, +), 10)
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
                        case .insert, .pageToggle, .emoji, .voice, .delete, .returnKey: return frame
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

    func testMainTabsHideModelsWhileSettingsKeepsModelsNavigation() throws {
        let mainTabs = try source("DictusApp/Views/MainTabView.swift")
        let settings = try source("DictusApp/Views/SettingsView.swift")

        XCTAssertFalse(mainTabs.contains("Label(\"Models\", systemImage:"),
                       "Models must not be a root tab")
        XCTAssertTrue(settings.contains("NavigationLink { ModelManagerView(modelManager: modelManager) } label:"),
                      "Settings must retain the Models navigation")
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
        XCTAssertTrue(picker.contains("stroke(Color.primary.opacity(0.16)"),
                      "the shared highlight must remain readable in both appearances")
    }

    func testEmojiPointerUsesSharedGridGeometryAndReleaseContract() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")

        XCTAssertTrue(picker.contains("private var emojiColumnCount: Int"),
                      "grid geometry must compute one shared column count")
        XCTAssertTrue(picker.contains("Int((availableWidth - gridHorizontalPadding * 2) / minimumEmojiTargetWidth)"),
                      "the column count must preserve the minimum emoji target width")
        XCTAssertTrue(picker.contains("minimumEmojiTargetWidth: CGFloat = 44"),
                      "emoji targets must be at least 44pt")
        XCTAssertTrue(picker.contains("max(1, "),
                      "narrow widths must still produce a valid positive column count")
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

        let gesture = try XCTUnwrap(picker.range(of: ".simultaneousGesture("))
        let gestureBody = String(picker[gesture.lowerBound...])
        XCTAssertTrue(gestureBody.contains("DragGesture(minimumDistance: 8"),
                      "emoji drag selection must leave ordinary taps to Buttons")
        XCTAssertTrue(gestureBody.contains(".simultaneousGesture("),
                      "emoji drag selection must coexist with the vertical ScrollView")
        XCTAssertTrue(gestureBody.contains("emojiDragAxis == .horizontal"),
                      "emoji drag selection must require horizontal intent")
        XCTAssertTrue(gestureBody.contains("!emojiCommitLocked"),
                      "emoji tap and drag must share a one-time commit lock")
        XCTAssertTrue(gestureBody.contains("resetEmojiGestureLock()"),
                      "emoji commit lock must reset after the gesture lifecycle")
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

        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 4"))
        XCTAssertFalse(numberBody.contains("blankRow()"))
        XCTAssertFalse(symbolsBody.contains("blankRow()"))
        XCTAssertFalse(controller.contains("contentFrame.size.height = max(contentFrame.height"))
        XCTAssertTrue(root.contains("LiquidSymbolPageView("),
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
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = !isAuxiliary"))
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"))
    }

    func testAuxiliaryControlsAreOwnedBySwiftUISurface() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(root.contains("alternateAccessoryRow(layout:"),
                       "the alternate accessory row must not be rendered inside SwiftUI")
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"),
                       "UIKit must not install an alternate accessory row")
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = !isAuxiliary"),
                      "UIKit must pass through auxiliary hit targets")
    }

    func testAuxiliaryLayoutRaisesUIKitControlsAboveEveryAuxiliarySubview() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = !isAuxiliary"),
                      "auxiliary content must disable the UIKit hit layer")
    }

    func testAuxiliaryAccessoryUsesUIKitNativeVisualsWithoutSwiftUIActions() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"),
                       "the removed accessory row must not have a UIKit styling path")
        XCTAssertFalse(controller.contains("installGlassBackground"),
                       "auxiliary UIKit controls must not add another glass/background layer")
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertTrue(root.contains("background(Capsule().fill(Color.white))"),
                      "the voice page keeps its own white microphone capsule")
        XCTAssertFalse(root.contains("state.startRecording()"))
        XCTAssertFalse(root.contains("state.requestStop()"))
    }

    func testAuxiliaryModeOwnsOnlyRevertMicDeleteAndReturnControls() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = isAuxiliary"))
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = !isAuxiliary"))
        XCTAssertTrue(controller.contains("guard !isAuxiliary else {"))
        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = !isAuxiliary"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"))
    }

    func testAuxiliaryControlsHideWhenAccessoryRowIsUnavailable() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = isAuxiliary"))
        XCTAssertTrue(controller.contains("$0.isHidden = true"))
        XCTAssertTrue(controller.contains("$0.isEnabled = false"))
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = false"))
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

        XCTAssertTrue(controller.contains("controls.isUserInteractionEnabled = !isAuxiliary"),
                      "auxiliary UIKit controls must fail closed and pass through")
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
        XCTAssertTrue(root.contains("case .voice: return \"Return to voice keyboard\""))
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
        XCTAssertTrue(controller.contains("handleDeleteHold"))
        XCTAssertTrue(controller.contains("RunLoop.main.add(timer, forMode: .common)"))
        XCTAssertTrue(layouts.contains("KeyDefinition(type: .shiftSymbols"))
        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 4"))
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
        XCTAssertTrue(emoji.contains("private let categoryBarHeight: CGFloat = 44"),
                      "emoji geometry must use the actual category-bar height")
        XCTAssertFalse(root.contains("availableHeight: surfaceHeight"),
                       "the outer keyboard height includes the surface inset")
    }

    func testSymbolsReserveTheBottomRowForTheTopmostABCControlGeometryOnly() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let layouts = try source("DictusKeyboard/KeyboardLayouts.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(layouts.contains("static let symbolsRowCount = 4"))
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
        let root = try source("DictusKeyboard/KeyboardRootView.swift")

        XCTAssertTrue(root.contains("case .voice: return \"Return to voice keyboard\""),
                      "the SwiftUI voice-return control must describe its action")
        XCTAssertTrue(root.contains("case .togglePage: return label == \"#+=\" ? \"More symbols\" : \"Return to numbers keyboard\""),
                      "the SwiftUI page toggle must describe its action")
        XCTAssertTrue(controller.contains("Open symbols keyboard"),
                      "normal mode must announce opening symbols")
        XCTAssertTrue(root.contains("onBackToVoice: { state.closeArea() }"),
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
        XCTAssertTrue(controller.contains("guard !isAuxiliary else {"))
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"))
    }

    func testBothAuxiliaryPagesKeepModeControlAvailableToReturnToNormal() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(controller.contains("controls.isHidden = isAuxiliary"),
                      "UIKit must release the auxiliary hit target to SwiftUI")
        XCTAssertTrue(controller.contains("layoutVoiceActionControls()"),
                      "mode visibility must be refreshed after each layout transition")
        XCTAssertTrue(controller.contains("inputView.bringSubviewToFront(controls)"),
                      "UIKit action controls must be restored above auxiliary content")
    }

    func testAuxiliaryAccessoryUsesUIKitRevertControlInsteadOfVoiceABCVisual() throws {
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")

        XCTAssertTrue(root.contains("Image(systemName: \"mic.fill\")"))
        XCTAssertTrue(root.contains("Image(systemName: \"face.smiling\")"))
        XCTAssertFalse(controller.contains("configureAuxiliaryAccessoryControls"))
        XCTAssertFalse(root.contains("alternateAccessoryRow"))
    }

    func testEmojiGridReservesTheCategoryBarLaneExplicitly() throws {
        let picker = try source("DictusKeyboard/Views/EmojiPickerView.swift")
        let normalModeStart = try XCTUnwrap(picker.range(of: "private var normalMode"))
        let normalMode = picker[normalModeStart.lowerBound...]

        XCTAssertTrue(picker.contains("let gridHeight = max(0, availableHeight - categoryBarHeight)"),
                      "emoji content must leave a real lane for the fixed category bar")
        XCTAssertTrue(picker.contains(".frame(width: availableWidth, height: gridHeight, alignment: .top)"),
                      "emoji scrolling must stop above the category bar")
        XCTAssertTrue(normalMode.contains("\n            }\n            .padding(.horizontal, gridHorizontalPadding)"),
                      "normal mode must close the grid container before applying the outer padding")
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
        XCTAssertTrue(root.contains("VoiceOnlyKeyboardPolicy.layout("))
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
        XCTAssertTrue(root.contains("Intentional white primary control"))
        XCTAssertTrue(root.contains(".foregroundStyle(.primary)"))
        XCTAssertTrue(root.contains("dictateFrame"))
        XCTAssertTrue(root.contains("let capsuleHeight = frame.height"))
        XCTAssertTrue(root.contains("height: capsuleHeight"))
        XCTAssertTrue(root.contains("surfaceFrame.midX"))
        XCTAssertTrue(root.contains("availableWidth: availableWidth"),
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
        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"))
    }

    func testMicUIKitTargetIsHiddenOutsideKeysAndRecordingAndOwnsAccessibility() throws {
        let controller = try source("DictusKeyboard/KeyboardViewController.swift")
        let root = try source("DictusKeyboard/KeyboardRootView.swift")
        XCTAssertTrue(controller.contains("micButton?.isHidden = (mode != .keys && mode != .recording)"))
        XCTAssertTrue(controller.contains("$0.isUserInteractionEnabled = !$0.isHidden"))
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
        XCTAssertFalse(root.contains("layout.auxiliaryContentFrame"),
                       "symbols mode must use the complete shared surface")
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
