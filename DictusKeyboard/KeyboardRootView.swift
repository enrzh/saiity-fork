// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import UIKit
import Foundation
import DictusCore

/// Root SwiftUI view for the voice-only keyboard surface.
struct KeyboardRootView: View {
    let controllerID: String
    let routeText: (String) -> Void
    let routeCommand: (KeyboardCommand) -> Void
    let routeWordDeletion: () -> Void
    let routeCursorMovement: (KeyboardCursorStep) -> Void
    let routeCursorEnded: () -> Void
    let routePaste: () -> Void
    let routeDismiss: () -> Void
    @ObservedObject private var state = KeyboardState.shared
    @Environment(\.openURL) private var openURL
    @State private var symbolPage: KeyboardPage = .symbols1
    @State private var emojiSelectedCategoryID = "recents"
    @State private var emojiCategoryJump: EmojiScrollRequest?
    @State private var lastAppliedEmojiCategoryToken: UUID?

    var body: some View {
        GeometryReader { proxy in
            let surfaceHeight = max(proxy.size.height, 1)
            let layout = VoiceOnlyKeyboardPolicy.layout(
                for: proxy.size.width,
                surfaceHeight: Double(surfaceHeight),
                controlOrder: KeyboardAccessoryOrder.current,
                topAccessoryHeight: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
            )
            let surfaceFrame = layout.surfaceFrame
            ZStack(alignment: .topLeading) {
                // Keep the hosting canvas transparent so the native UIInputView
                // backdrop is the only layer behind the inset surface.
                Color.clear
                    .allowsHitTesting(false)
                embeddedSurface(
                    areaSurface(layout: layout, contentFrame: surfaceFrame),
                    frame: surfaceFrame
                )
                    .position(x: surfaceFrame.midX, y: surfaceFrame.midY)
                    // Popups may extend into the suggestion lane. Keep the
                    // entire surface above that lane's controls so the popup
                    // is visible without changing the controls' hit targets.
                    .zIndex(3)

                if state.areaMode == .keys || state.areaMode == .recording {
                    if layout.leftRailWidth > 0 {
                        voiceBoardChrome(text: "123", label: "Open symbols keyboard") {
                            state.presentNumbersArea()
                        }
                            .position(x: CGFloat(layout.chromeNumbersFrame.midX), y: CGFloat(layout.chromeNumbersFrame.midY))
                            .zIndex(4)
                        voiceBoardChrome(text: "ABC", label: "Open letter keyboard") {
                            state.presentArea(.letters)
                        }
                            .position(x: CGFloat(layout.chromeLettersFrame.midX), y: CGFloat(layout.chromeLettersFrame.midY))
                            .zIndex(4)
                        voiceBoardChrome(
                            systemName: "face.smiling",
                            label: "Emoji",
                            visualWidth: VoiceOnlyKeyboardPolicy.commandVisualSize(
                                for: CGSize(
                                    width: VoiceOnlyKeyboardPolicy.controlSize,
                                    height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight
                                )
                            ).width,
                            visualHeight: VoiceOnlyKeyboardPolicy.commandVisualSize(
                                for: CGSize(
                                    width: VoiceOnlyKeyboardPolicy.controlSize,
                                    height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight
                                )
                            ).height,
                            visualCornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius
                        ) {
                            state.presentArea(.emoji)
                        }
                            .position(x: CGFloat(layout.chromeEmojiFrame.midX), y: CGFloat(layout.chromeEmojiFrame.midY))
                            .zIndex(4)
                    }

                    if layout.rightRailWidth > 0 {
                        KeyboardDeleteButton(
                            onDelete: { routeProxyCommand(.delete) },
                            onDeleteWord: routeWordDeletion,
                            visualWidth: layout.commandKeyVisualSize.width,
                            visualHeight: layout.commandKeyVisualSize.height,
                            hitWidth: layout.boardDeleteFrame.width,
                            hitHeight: layout.boardDeleteFrame.height
                        )
                            .position(x: CGFloat(layout.boardDeleteFrame.midX), y: CGFloat(layout.boardDeleteFrame.midY))
                            .allowsHitTesting(!voiceBoardUsesUIKitHits)
                            .zIndex(4)
                        voiceBoardChrome(
                            systemName: "return",
                            label: "Return",
                            width: VoiceOnlyKeyboardPolicy.actionHitSize.width,
                            height: VoiceOnlyKeyboardPolicy.actionHitSize.height,
                            visualWidth: VoiceOnlyKeyboardPolicy.commandVisualSize(for: VoiceOnlyKeyboardPolicy.actionHitSize).width,
                            visualHeight: VoiceOnlyKeyboardPolicy.commandVisualSize(for: VoiceOnlyKeyboardPolicy.actionHitSize).height,
                            visualCornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius
                        ) {
                            routeProxyCommand(.returnKey)
                        }
                            .position(x: CGFloat(layout.boardReturnFrame.midX), y: CGFloat(layout.boardReturnFrame.midY))
                            .zIndex(4)
                    }
                }

                if state.areaMode == .emoji {
                    EmojiCategoryBar(
                        sections: CategoryInfo.emojiBarSections,
                        selectedCategoryID: emojiSelectedCategoryID,
                        isExpanded: state.emojiCategoryBarExpanded,
                        contentOffset: Binding(
                            get: { state.emojiCategoryBarOffset },
                            set: { state.setEmojiCategoryBarOffset($0) }
                        )
                    )
                    .frame(
                        width: CGFloat(layout.floatingEmojiCategoryFrame.width),
                        height: CGFloat(layout.floatingEmojiCategoryFrame.height)
                    )
                    .position(
                        x: CGFloat(layout.floatingEmojiCategoryFrame.midX),
                        y: CGFloat(layout.floatingEmojiCategoryFrame.midY)
                    )
                    .allowsHitTesting(false)
                    .zIndex(4)

                    KeyboardDeleteButton(
                        onDelete: { routeProxyCommand(.delete) },
                        onDeleteWord: routeWordDeletion,
                        visualWidth: layout.commandKeyVisualSize.width,
                        visualHeight: layout.commandKeyVisualSize.height,
                        hitWidth: layout.boardDeleteFrame.width,
                        hitHeight: layout.boardDeleteFrame.height
                    )
                    .position(
                        x: CGFloat(layout.boardDeleteFrame.midX),
                        y: CGFloat(layout.boardDeleteFrame.midY)
                    )
                    .zIndex(4)
                }

                accessoryBar(width: proxy.size.width, layout: layout)
                    .position(x: proxy.size.width / 2, y: VoiceOnlyKeyboardPolicy.suggestionLaneHeight / 2)
                    .zIndex(2)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background(Color.clear)
            .onChange(of: state.areaMode) { _, mode in
                if mode == .panel {
                    symbolPage = .symbols1
                }
            }
            .onChange(of: state.hostPrefersNumberPad) { _, prefers in
                if prefers {
                    symbolPage = .symbols1
                }
            }
        }
        .onAppear {
            // Keep the SwiftUI URL action available as the fallback when the
            // extension context declines a recovery handoff.
            state.openContainingApp = { url, completion in
                openURL(url, completion: completion)
            }
            HapticFeedback.refreshEnabledState()
            HapticFeedback.warmUp()
            bindEmojiCategoryScrubber()
            state.startClipboardMonitoring()
            state.refreshTypingLanguage()
        }
        .onChange(of: state.areaMode) { _, _ in
            bindEmojiCategoryScrubber()
        }
        .onChange(of: state.emojiCategoryJumpToken) { _, _ in
            applyEmojiCategory(at: state.emojiCategoryJumpIndex)
        }
    }

    private func bindEmojiCategoryScrubber() {
        state.onSelectEmojiCategory = { index in
            applyEmojiCategory(at: index)
        }
    }

    private func applyEmojiCategory(at index: Int) {
        let token = state.emojiCategoryJumpToken
        if lastAppliedEmojiCategoryToken == token { return }
        lastAppliedEmojiCategoryToken = token
        let sections = CategoryInfo.emojiBarSections
        guard sections.indices.contains(index) else { return }
        let id = sections[index].id
        if emojiSelectedCategoryID != id {
            HapticFeedback.variantHighlightChanged()
        }
        emojiSelectedCategoryID = id
        emojiCategoryJump = EmojiScrollRequest(id: id, animated: false)
    }

    @ViewBuilder
    private func accessoryBar(width: CGFloat, layout: VoiceOnlyKeyboardPolicy.Layout) -> some View {
        let categoryFrame = layout.accessoryEmojiCategoryFrame
        ZStack(alignment: .topLeading) {
            languageIndicator
                .position(
                    x: CGFloat(VoiceOnlyKeyboardPolicy.accessoryEdgeInset + VoiceOnlyKeyboardPolicy.languageVisualWidth / 2),
                    y: VoiceOnlyKeyboardPolicy.suggestionLaneHeight / 2
                )
            HStack(spacing: CGFloat(VoiceOnlyKeyboardPolicy.railSpacing)) {
                pasteButton
                Spacer(minLength: 0)
            }
            .frame(width: max(0, categoryFrame.width + layout.accessoryDictationBoardFrame.width), height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight)
            .position(
                x: categoryFrame.minX + max(0, categoryFrame.width + layout.accessoryDictationBoardFrame.width) / 2,
                y: VoiceOnlyKeyboardPolicy.suggestionLaneHeight / 2
            )
            if state.areaMode == .letters || state.areaMode == .panel || state.areaMode == .numberPad || state.areaMode == .emoji {
                dictationBoardButton
                    .position(
                        x: layout.accessoryDictationBoardFrame.midX,
                        y: layout.accessoryDictationBoardFrame.midY
                    )
            }
            dismissAccessoryButton
                .position(
                    x: layout.accessoryDismissFrame.midX,
                    y: layout.accessoryDismissFrame.midY
                )
        }
        .frame(width: width, height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight, alignment: .topLeading)
    }

    // This literal is validated by URL at construction time. The file URL is an
    // unreachable fail-closed fallback for an unexpected Foundation parser change.
    private let preparationURL = URL(
        string: "saiity://dictate?source=keyboard&intent=prepare"
    ) ?? URL(fileURLWithPath: "/")

    @ViewBuilder
    private func areaSurface(layout: VoiceOnlyKeyboardPolicy.Layout, contentFrame: CGRect) -> some View {
        let surfaceFrame = contentFrame
        switch state.areaMode {
        case .keys:
            centerSurface(layout: layout)
        case .letters:
            LetterKeyboardPageView(
                surfaceLayout: layout,
                availableWidth: surfaceFrame.width,
                availableHeight: surfaceFrame.height,
                onInsert: routeProxyText,
                onDelete: { routeProxyCommand(.delete) },
                onDeleteWord: routeWordDeletion,
                onReturn: { routeProxyCommand(.returnKey) },
                onSpace: { routeProxyCommand(.space) },
                onBackToVoice: { state.closeArea() },
                onSymbols: { state.presentNumbersArea() },
                onEmoji: { state.presentArea(.emoji) },
                showsSymbolsControl: true,
                fieldKeys: state.hostLetterFieldKeys,
                onSpaceCursorBegan: {},
                onSpaceCursorMoved: routeCursorMovement,
                onSpaceCursorEnded: routeCursorEnded,
            )
            .frame(width: surfaceFrame.width, height: surfaceFrame.height)
            .accessibilityIdentifier("letter-keyboard-surface")
        case .recording:
            centerSurface(layout: layout)
        case .emoji:
            EmojiPickerView(
                onEmojiInsert: { emoji in
                    routeText(emoji)
                },
                onBackToVoice: { state.closeArea() },
                onLetters: { state.presentArea(.letters) },
                onSymbols: { state.presentNumbersArea() },
                onSpace: { routeProxyCommand(.space) },
                onReturn: { routeProxyCommand(.returnKey) },
                onSpaceCursorBegan: {},
                onSpaceCursorMoved: routeCursorMovement,
                onSpaceCursorEnded: routeCursorEnded,
                onDelete: { routeProxyCommand(.delete) },
                onDeleteWord: routeWordDeletion,
                surfaceLayout: layout,
                availableWidth: surfaceFrame.width,
                availableHeight: surfaceFrame.height,
                selectedCategoryID: $emojiSelectedCategoryID,
                scrollRequest: $emojiCategoryJump
            )
            .frame(width: surfaceFrame.width, height: surfaceFrame.height)
            .accessibilityIdentifier("emoji-picker-surface")
        case .panel:
            LiquidSymbolPageView(
                page: symbolPage,
                surfaceLayout: layout,
                availableWidth: surfaceFrame.width,
                availableHeight: surfaceFrame.height,
                onInsert: { text in routeProxyText(text) },
                onDelete: { routeProxyCommand(.delete) },
                onDeleteWord: routeWordDeletion,
                onReturn: { routeProxyCommand(.returnKey) },
                onSpace: { routeProxyCommand(.space) },
                onTogglePage: { nextPage in symbolPage = nextPage },
                onClose: { state.closeArea() },
                onBackToVoice: { state.closeArea() },
                onEmoji: { state.presentArea(.emoji) },
                onKeyboard: { state.presentArea(.letters) },
                onSpaceCursorBegan: {},
                onSpaceCursorMoved: routeCursorMovement,
                onSpaceCursorEnded: routeCursorEnded,
            )
            .frame(width: surfaceFrame.width, height: surfaceFrame.height)
            .accessibilityIdentifier("number-layer-surface")
        case .numberPad:
            LiquidNumberPadView(
                style: state.hostNumberPadStyle,
                availableWidth: surfaceFrame.width,
                availableHeight: surfaceFrame.height,
                popupTopOverflow: CGFloat(layout.surfaceFrame.minY),
                onInsert: { text in routeProxyText(text) },
                onDelete: { routeProxyCommand(.delete) },
                onDeleteWord: routeWordDeletion,
                onKeyboard: { state.presentArea(.letters) },
            )
            .frame(width: surfaceFrame.width, height: surfaceFrame.height)
            .accessibilityIdentifier("number-pad-surface")
        }
    }

    private func routeProxyText(_ text: String) {
        routeText(text)
    }

    private func routeProxyCommand(_ command: KeyboardCommand) {
        routeCommand(command)
    }

    private var accessoryHitSize: CGSize {
        CGSize(
            width: VoiceOnlyKeyboardPolicy.accessoryControlSize,
            height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
        )
    }

    private var languageIndicator: some View {
        let visualHeight = VoiceOnlyKeyboardPolicy.commandVisualSize(for: accessoryHitSize).height
        return ZStack {
            appleControlSurface(
                    Text(languageIndicatorTitle)
                    .font(.caption2.weight(.semibold))
                    // The keyboard control has a fixed frame; preserve a complete
                    // label while allowing text growth through standard sizes.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.languageVisualWidth), height: visualHeight),
                in: Capsule()
            )
            LanguageMenuButton()
        }
        .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.languageVisualWidth), height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight)
        .tint(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Output language")
        .accessibilityValue(languageIndicatorTitle)
        .accessibilityHint("Opens the translation menu.")
        .accessibilityAddTraits(.isButton)
    }

    private var languageIndicatorTitle: String {
        if let target = state.selectedTranslationTarget {
            return target.shortCode
        }
        return "AUTO"
    }

    private var dismissAccessoryButton: some View {
        SuggestionBarIconButton(
            systemName: "keyboard.chevron.compact.down",
            label: "Dismiss keyboard",
            laneSize: accessoryHitSize,
            action: routeDismiss
        )
        .accessibilityIdentifier("dismiss-keyboard")
    }

    private var pasteButton: some View {
        SuggestionBarIconButton(
            systemName: state.isOneTimeCodeField ? "number.square" : "doc.on.clipboard",
            label: state.isOneTimeCodeField ? "Paste verification code" : "Paste from clipboard",
            laneSize: accessoryHitSize,
            action: routePaste
        )
        .accessibilityHint("Inserts the current clipboard text.")
    }

    private var dictationBoardButton: some View {
        SuggestionBarIconButton(
            systemName: "mic.fill",
            label: "Return to dictation board",
            laneSize: accessoryHitSize,
            action: { state.closeArea() }
        )
        .accessibilityIdentifier("return-to-dictation-board")
    }

    @ViewBuilder
    private func centerSurface(layout: VoiceOnlyKeyboardPolicy.Layout) -> some View {
        if !layout.dictateFrame.isEmpty {
            let dictateFrame = layout.dictateFrame
                let errorFrame = layout.dictationErrorFrame
            ZStack(alignment: .topLeading) {
                dictateButton(frame: dictateFrame)
                    .frame(width: dictateFrame.width, height: dictateFrame.height)
                    .position(x: dictateButtonLocalX(for: dictateFrame, in: layout),
                              y: CGFloat(dictateFrame.midY - layout.surfaceFrame.minY))
                if !layout.spaceFrame.isEmpty {
                    spaceBar(frame: layout.spaceFrame)
                        .position(
                            x: CGFloat(layout.spaceFrame.midX - layout.surfaceFrame.minX),
                            y: CGFloat(layout.spaceFrame.midY - layout.surfaceFrame.minY)
                        )
                }
                if !dictationErrorMessage.isEmpty && !errorFrame.isEmpty {
                    Text(dictationErrorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .frame(width: max(CGFloat.zero, errorFrame.width - 8), height: errorFrame.height)
                        .position(x: CGFloat(errorFrame.midX - layout.surfaceFrame.minX),
                                  y: CGFloat(errorFrame.midY - layout.surfaceFrame.minY))
                        .accessibilityIdentifier("dictation-error")
                }
            }
            .frame(maxWidth: .infinity, minHeight: CGFloat(layout.surfaceFrame.height), maxHeight: CGFloat(layout.surfaceFrame.height))
        } else {
            Color.clear.allowsHitTesting(false)
        }
    }

    private func dictateButtonLocalX(for frame: CGRect, in layout: VoiceOnlyKeyboardPolicy.Layout) -> CGFloat {
        CGFloat(frame.midX - layout.surfaceFrame.minX)
    }

    private func dictateButton(frame: CGRect) -> some View {
        let appNeedsAppAction = state.appNeedsAppAction
        let isCancellationStage = state.dictationStatus == .requested
            || state.dictationStatus == .transcribing
            || state.dictationStatus == .processing
        return ZStack {
            dictationControlVisual(frame: frame)
                .allowsHitTesting(false)
            ImmediateKeyButton(
                onTouchDown: {
                    if appNeedsAppAction || state.appNeedsAppAction {
                        state.openDictusForRecovery()
                    } else if isCancellationStage
                        || state.dictationStatus == .requested
                        || state.dictationStatus == .transcribing
                        || state.dictationStatus == .processing {
                        state.cancelActiveDictation()
                    }
                },
                onTouchUp: {
                    let statusIsCancellationStage = state.dictationStatus == .requested
                        || state.dictationStatus == .transcribing
                        || state.dictationStatus == .processing
                    guard !appNeedsAppAction
                        && !state.appNeedsAppAction
                        && !isCancellationStage
                        && !statusIsCancellationStage else { return }
                    state.handleMicPressEnded()
                },
                highlightCornerRadius: frame.height / 2,
                highlightSize: CGSize(width: frame.width, height: frame.height),
                holdDuration: appNeedsAppAction || isCancellationStage
                    ? nil
                    : KeyboardDeletion.dictationHoldRecognitionDuration,
                onHold: appNeedsAppAction || isCancellationStage
                    ? nil
                    : { state.handleMicPressBegan() }
            )
            .frame(width: frame.width, height: frame.height)
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Capsule())
        .accessibilityLabel(state.appNeedsAppAction ? "Open sAiity to prepare dictation" : state.dictationActionLabel)
        .accessibilityAddTraits(.isButton)
    }

    private func dictationControlVisual(frame: CGRect) -> some View {
        let capsuleHeight = frame.height
        return ZStack(alignment: .center) {
            VStack(spacing: 1) {
                dictationIcon
                Text(dictationTitle)
                    .font(.caption2.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: frame.width, height: capsuleHeight)
        .background {
            ZStack {
                if KeyboardInteractionPreferences.liquidGlassEnabled {
                    appleControlSurface(Color.clear, in: Capsule(), role: .control)
                    Capsule().fill(dictationButtonBackground.opacity(dictationButtonIsCancellation ? 0.94 : 0.86))
                } else {
                    Capsule().fill(dictationButtonBackground)
                }
            }
        }
        .clipShape(Capsule())
        .contentShape(Capsule())
        .foregroundStyle(dictationButtonForeground)
        .accessibilityIdentifier("dictate-button")
        .accessibilityLabel(state.dictationActionLabel)
        .accessibilityValue(dictationTitle)
    }

    @ViewBuilder
    private var dictationIcon: some View {
        if state.dictationStatus == .recording && !state.isFinishingRecording {
            ListeningWaveIcon(color: dictationButtonForeground)
        } else {
            Image(systemName: dictationSymbol)
                .font(.system(size: 20, weight: .semibold))
        }
    }

    private var dictationButtonIsCancellation: Bool {
        switch state.dictationStatus {
        case .requested, .transcribing, .processing:
            return true
        case .idle, .recording, .ready, .failed:
            return false
        }
    }

    private var dictationButtonBackground: Color {
        dictationButtonIsCancellation ? .dictusRecording : .white
    }

    private var dictationButtonForeground: Color {
        dictationButtonIsCancellation ? .white : .black
    }

    private func spaceBar(frame: CGRect) -> some View {
        ZStack {
            appleControlSurface(
                Text("space")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: frame.width, height: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize)),
                in: Capsule()
            )
            if !voiceBoardUsesUIKitHits {
                SpaceBarControl(
                    onTap: { routeProxyCommand(.space) },
                    onCursorBegan: {},
                    onCursorMoved: routeCursorMovement,
                    onCursorEnded: routeCursorEnded
                )
            }
        }
        .frame(width: frame.width, height: frame.height)
        .allowsHitTesting(!voiceBoardUsesUIKitHits)
        .accessibilityHidden(voiceBoardUsesUIKitHits)
    }

    private var dictationTitle: String {
        switch state.dictationStatus {
        case .idle, .ready:
            if state.isOpeningForDictation { return "Opening sAiity…" }
            return state.appNeedsAppAction ? "Open sAiity" : "Hold to dictate"
        case .requested: return "Getting ready..."
        case .recording: return state.isFinishingRecording ? "Finishing..." : "Listening..."
        case .transcribing: return "Cancel transcription"
        case .processing: return "Cancel cleanup"
        case .failed: return "Hold to dictate"
        }
    }

    private var dictationSymbol: String {
        switch state.dictationStatus {
        case .recording: return state.isFinishingRecording ? "ellipsis" : "waveform"
        case .requested: return "ellipsis"
        case .transcribing, .processing: return "xmark"
        case .failed: return "mic.fill"
        case .idle, .ready:
            if state.isOpeningForDictation { return "ellipsis" }
            return state.appNeedsAppAction ? "arrow.up.right.square.fill" : "mic.fill"
        }
    }

    private var dictationErrorMessage: String {
        if let message = state.statusMessage { return message }
        if state.appNeedsAppAction { return "If the link is blocked, open sAiity from the Home Screen." }
        guard state.dictationStatus == .failed else { return "" }
        return state.statusMessage ?? "Dictation could not be completed."
    }

    private let surfaceCornerRadius: CGFloat = 24

    private func embeddedSurface<Content: View>(
        _ content: Content,
        frame: CGRect,
        withoutGlassRim: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
        // The content normally remains unclipped so key popups can rise above
        // the top row. Emoji glyphs are the exception: their rectangular grid
        // must stop at the same rounded edge as the Liquid Glass inset.
        return ZStack(alignment: .topLeading) {
            appleControlSurface(
                Color.clear.frame(width: frame.width, height: frame.height),
                in: shape,
                usesGlass: !withoutGlassRim,
                role: .board
            )
            .clipShape(shape)
            if state.areaMode == .emoji {
                content
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                    // Keep emoji glyphs behind the glass edge. A full-size
                    // clip still lets the rectangular collection view paint
                    // over the inset rim at the rounded corners.
                    .clipShape(shape.inset(by: 2))
            } else {
                content
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            }
        }
        .frame(width: frame.width, height: frame.height)
    }

    private var voiceBoardUsesUIKitHits: Bool {
        // Material is visual only. UIKit owns the same voice-board hit layer for
        // both glass and solid chrome so changing the preference cannot strand
        // an old transparent overlay over the SwiftUI controls.
        state.areaMode == .keys || state.areaMode == .recording
    }

    @ViewBuilder
    private func appleControlSurface<Content: View, S: Shape>(
        _ content: Content,
        in shape: S,
        usesGlass: Bool = true,
        role: KeyboardChromeRole = .control
    ) -> some View {
        if usesGlass {
            content.keyboardGlass(in: shape, role: role)
        } else if role == .board {
            content
        } else {
            content
                .background(shape.fill(Color(uiColor: .tertiarySystemFill)))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func commandChromeFace<Face: View>(
        label: String,
        hit: CGSize,
        cornerRadius: CGFloat,
        action: @escaping () -> Void,
        @ViewBuilder face: () -> Face
    ) -> some View {
        Group {
            if voiceBoardUsesUIKitHits {
                face()
            } else {
                ZStack {
                    face()
                    ImmediateKeyButton(
                        onTouchDown: {
                            HapticFeedback.keyTapped()
                            action()
                        },
                        onTouchUp: {},
                        highlightCornerRadius: cornerRadius
                    )
                }
                .contentShape(Rectangle())
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
            }
        }
        .frame(width: hit.width, height: hit.height)
        .allowsHitTesting(!voiceBoardUsesUIKitHits)
        .accessibilityHidden(voiceBoardUsesUIKitHits)
        .zIndex(4)
    }

    @ViewBuilder
    private func voiceBoardChrome(
        text: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let hit = CGSize(
            width: VoiceOnlyKeyboardPolicy.controlSize,
            height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight
        )
        let plate = VoiceOnlyKeyboardPolicy.commandVisualSize(for: hit)
        commandChromeFace(
            label: label,
            hit: hit,
            cornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
            action: action
        ) {
            CommandKeyFace(
                text: text,
                plateWidth: plate.width,
                plateHeight: plate.height
            )
        }
    }

    @ViewBuilder
    private func voiceBoardChrome(
        systemName: String,
        label: String,
        width: Double = VoiceOnlyKeyboardPolicy.controlSize,
        height: Double = VoiceOnlyKeyboardPolicy.bottomActionHitHeight,
        visualWidth: Double? = nil,
        visualHeight: Double? = nil,
        visualCornerRadius: Double = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
        action: @escaping () -> Void
    ) -> some View {
        let hit = CGSize(width: CGFloat(width), height: CGFloat(height))
        let fallback = VoiceOnlyKeyboardPolicy.commandVisualSize(for: hit)
        let plate = CGSize(
            width: visualWidth ?? fallback.width,
            height: visualHeight ?? fallback.height
        )
        commandChromeFace(
            label: label,
            hit: hit,
            cornerRadius: CGFloat(visualCornerRadius),
            action: action
        ) {
            CommandKeyFace(
                systemName: systemName,
                plateWidth: plate.width,
                plateHeight: plate.height,
                cornerRadius: CGFloat(visualCornerRadius)
            )
        }
    }

}

/// Compact live waveform used only while the dictation control is listening.
/// The static fallback keeps the control calm when Reduce Motion is enabled.
private struct ListeningWaveIcon: View {
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                bars(phase: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    bars(phase: timeline.date.timeIntervalSinceReferenceDate * 5.5)
                }
            }
        }
        .frame(width: 24, height: 22)
        .accessibilityHidden(true)
    }

    private func bars(phase: Double) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<5, id: \.self) { index in
                let level = (sin(phase + Double(index) * 0.85) + 1.0) * 0.5
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: 6 + CGFloat(level) * 14)
            }
        }
    }
}

/// SwiftUI-owned letter page. It consumes the same `KeyboardLayouts` definitions
/// as the former UIKit grid, while sharing the auxiliary bottom bar with symbols.
private struct LetterKeyboardPageView: View {
    let surfaceLayout: VoiceOnlyKeyboardPolicy.Layout
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let onReturn: () -> Void
    let onSpace: () -> Void
    let onBackToVoice: () -> Void
    let onSymbols: () -> Void
    let onEmoji: () -> Void
    let showsSymbolsControl: Bool
    var fieldKeys: HostFieldPolicy.LetterFieldKeys = .standard
    let onSpaceCursorBegan: () -> Void
    let onSpaceCursorMoved: (KeyboardCursorStep) -> Void
    let onSpaceCursorEnded: () -> Void

    @State private var page: KeyboardPage = .normal
    @State private var variantSession: KeyVariantSession?
    @State private var previewSession: KeyPreviewSession?
    @State private var variantHoldToken: UUID?
    @State private var variantTouchOrigin: CGPoint?
    @State private var variantTouchCancelled = false
    @State private var activeVariantKeyID: String?
    @State private var nonPopupVariantTouchIDs: Set<String> = []
    @State private var adaptiveTouchScopeID = UUID()
    @ObservedObject private var suggestionState = SuggestionState.shared
    @AppStorage(SharedKeys.language, store: AppGroup.defaults) private var languageCode = SupportedLanguage.active.rawValue

    private var shiftSymbolName: String {
        page == .capslock ? "capslock.fill" : page == .shifted ? "shift.fill" : "capslock"
    }

    private let bottomBarHeight: CGFloat = 44
    private let chromeBottomInset: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeBottomInset)
    private let commandRowGap: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeCommandRowGap)

    var body: some View {
        let _ = (onBackToVoice, showsSymbolsControl)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let gridSize = CGSize(width: proxy.size.width, height: proxy.size.height)
                let frames = positionedKeys(in: gridSize)
                ZStack(alignment: .topLeading) {
                    ForEach(frames) { positioned in
                        letterKey(
                            positioned.key,
                            keyID: positioned.id,
                            frame: positioned.frame,
                            visualFrame: positioned.visualFrame,
                            bounds: gridSize
                        )
                            .frame(width: positioned.frame.width, height: positioned.frame.height)
                            .position(x: positioned.frame.midX, y: positioned.frame.midY)
                    }
                    // Typed-text language detection now drives next-letter priors.
                    // Adaptive redirects only fire on confident edge priors; gap
                    // absorption still owns the geometry between plates.
                    AdaptiveLetterTouchRouter(
                        keys: adaptiveTouchKeys(from: frames),
                        probabilities: variantSession == nil ? suggestionState.adaptiveTouchPrediction : nil,
                        scopeID: adaptiveTouchScopeID.uuidString
                    )
                    .frame(width: gridSize.width, height: gridSize.height)
                    .accessibilityHidden(true)
                    .zIndex(10)
                    if let session = variantSession {
                        KeyVariantPopup(
                            options: session.options,
                            selectedIndex: session.selectedIndex,
                            isEmoji: false
                        )
                        .frame(width: session.popupFrame.width, height: session.popupFrame.height)
                        .position(x: session.popupFrame.midX, y: session.popupFrame.midY)
                        .allowsHitTesting(false)
                        .zIndex(20)
                    } else if previewSession != nil {
                        KeyPressPreviewHost(session: $previewSession)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .coordinateSpace(name: "letterKeyboard")
            }
            Color.clear.frame(height: commandRowGap)
            AuxiliaryBottomBar(
                layout: surfaceLayout,
                numbersTitle: "123",
                onNumbers: onSymbols,
                onLetters: {},
                onEmoji: onEmoji,
                spaceFrame: surfaceLayout.letterSpaceFrame,
                returnFrame: surfaceLayout.chromeReturnFrame,
                periodFrame: surfaceLayout.letterPeriodFrame,
                onPeriod: onInsert,
                onSpace: onSpace,
                onSpaceCursorBegan: onSpaceCursorBegan,
                onSpaceCursorMoved: onSpaceCursorMoved,
                onSpaceCursorEnded: onSpaceCursorEnded,
                onReturn: onReturn,
                showsLettersControl: false,
                showsPeriodKey: true,
                fieldKeys: fieldKeys,
                onSymbolInsert: onInsert
            )
            .frame(width: availableWidth, height: bottomBarHeight)
            Color.clear.frame(height: chromeBottomInset)
        }
        .frame(width: availableWidth, height: availableHeight)
        .onChange(of: LayoutType.active) { _, _ in
            resetLetterPageTransientState()
        }
        .onChange(of: languageCode) { _, _ in
            resetLetterPageTransientState()
        }
        .onChange(of: page) { _, _ in
            suggestionState.clearAdaptiveTouchPrediction()
        }
        .onDisappear {
            suggestionState.clearAdaptiveTouchPrediction()
            variantHoldToken = nil
            variantTouchOrigin = nil
            variantTouchCancelled = false
            variantSession = nil
            previewSession = nil
            activeVariantKeyID = nil
            nonPopupVariantTouchIDs.removeAll()
        }
    }

    private func resetLetterPageTransientState() {
        page = .normal
        suggestionState.clearAdaptiveTouchPrediction()
        variantSession = nil
        previewSession = nil
        variantHoldToken = nil
        variantTouchOrigin = nil
        variantTouchCancelled = false
        KeyboardState.shared.lastShiftTapDate = .distantPast
        activeVariantKeyID = nil
        nonPopupVariantTouchIDs.removeAll()
    }

    private var rows: [[KeyDefinition]] {
        let _ = languageCode
        guard let layout = KeyboardLayouts.current().currentDeviceLayout else { return [] }
        let pageRows: [[KeyDefinition]]
        switch page {
        case .normal:
            pageRows = layout.normal
        case .shifted, .capslock:
            pageRows = layout.shifted
        case .symbols1, .symbols2:
            pageRows = layout.normal
        }
        // The common bottom bar owns emoji, symbols, space and return. Keeping
        // those definitions out of this grid prevents a second shifting row.
        return Array(pageRows.dropLast())
    }

    private func positionedKeys(in size: CGSize) -> [PositionedLetterKey] {
        let geometry = VoiceOnlyKeyboardPolicy.scaledKeyGeometry(for: Double(size.width))
        let edgeInset = geometry.keyGridInset
        let rowSpacing = geometry.keyRowSpacing
        let keySpacing = geometry.keySpacing
        let currentRows = rows
        let weights = currentRows.map { row in row.map { CGFloat($0.size.width) } }
        let lastRowHeight = VoiceOnlyKeyboardPolicy.SymbolGrid.letterAlignedLastRowHeight(
            in: size.height,
            rowSpacing: rowSpacing
        )
        var frames = VoiceOnlyKeyboardPolicy.SymbolGrid.framesWithPinnedLastRow(
            for: weights,
            in: size,
            spacing: keySpacing,
            inset: edgeInset,
            rowSpacing: rowSpacing,
            lastRowHeight: lastRowHeight,
            maxRowHeight: geometry.letterKeyHeight
        )
        if let row = frames.last, let first = row.first {
            frames[frames.count - 1] = VoiceOnlyKeyboardPolicy.SymbolGrid.fixedEdgeCommandRowFrames(
                itemCount: row.count,
                rowFrame: CGRect(x: edgeInset, y: first.minY,
                                 width: max(0, size.width - edgeInset * 2),
                                 height: lastRowHeight),
                spacing: CGFloat(VoiceOnlyKeyboardPolicy.railSpacing),
                commandWidth: surfaceLayout.boardDeleteFrame.width
            )
        }
        let deleteFrame = CGRect(
            x: surfaceLayout.boardDeleteFrame.minX - surfaceLayout.surfaceFrame.minX,
            y: surfaceLayout.boardDeleteFrame.minY - surfaceLayout.surfaceFrame.minY,
            width: surfaceLayout.boardDeleteFrame.width,
            height: surfaceLayout.boardDeleteFrame.height
        )
        if let lastRow = frames.indices.last, currentRows.indices.contains(lastRow) {
            frames[lastRow] = frames[lastRow].map {
                CGRect(x: $0.minX, y: deleteFrame.minY, width: $0.width, height: deleteFrame.height)
            }
            for (index, key) in currentRows[lastRow].enumerated() {
                if case .backspace = key.type, frames[lastRow].indices.contains(index) {
                    frames[lastRow][index] = deleteFrame
                }
            }
        }
        // Absorb inter-key gaps into hit targets so taps between frosted plates
        // still land on a key. Plates fill the same cells as hit targets (no visible gaps).
        let hitFrames = VoiceOnlyKeyboardPolicy.SymbolGrid.expandFramesAbsorbingGaps(
            frames,
            horizontalSpacing: keySpacing,
            verticalSpacing: rowSpacing
        )
        return currentRows.indices.flatMap { rowIndex -> [PositionedLetterKey] in
            let row = currentRows[rowIndex]
            let rowHits = hitFrames[rowIndex]
            return row.indices.map { columnIndex in
                PositionedLetterKey(
                    id: "\(adaptiveTouchScopeID.uuidString)-letter-\(rowIndex)-\(columnIndex)",
                    key: row[columnIndex],
                    frame: rowHits[columnIndex],
                    visualFrame: rowHits[columnIndex],
                    row: rowIndex,
                    column: columnIndex
                )
            }
        }
    }

    private func adaptiveTouchKeys(from positioned: [PositionedLetterKey]) -> [AdaptiveTouchKey] {
        positioned.map { item in
            guard case .input(let value, _) = item.key.type,
                  value.count == 1,
                  value != KeyboardLayouts.emojiKeyGlyph else {
                return AdaptiveTouchKey(
                    id: item.id,
                    label: "",
                    frame: item.frame,
                    row: item.row,
                    column: item.column,
                    isCommand: true,
                    hasVariants: false
                )
            }
            return AdaptiveTouchKey(
                id: item.id,
                label: value,
                frame: item.frame,
                row: item.row,
                column: item.column,
                isCommand: false,
                hasVariants: alternateVariants(for: item.key).count > 1
            )
        }
    }

    @ViewBuilder
    private func letterKey(
        _ key: KeyDefinition,
        keyID: String,
        frame: CGRect,
        visualFrame: CGRect,
        bounds: CGSize
    ) -> some View {
        let variants = alternateVariants(for: key)
        let hitExpansion: CGFloat = 6
        Group {
            switch key.type {
            case .spacer:
                Color.clear.accessibilityHidden(true)
            case .shift:
                ZStack {
                    letterKeyLabel(for: key, frame: visualFrame)
                    ImmediateKeyButton(
                        onTouchDown: {
                            HapticFeedback.prepareForNextTap()
                            handleShiftTap()
                        },
                        onTouchUp: {},
                        highlightCornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
                        highlightSize: surfaceLayout.commandKeyVisualSize
                    )
                }
                    .contentShape(Rectangle().inset(by: -hitExpansion))
                    .accessibilityLabel("Caps Lock")
                    .accessibilityAddTraits(.isButton)
            case .backspace:
                let visual = surfaceLayout.commandKeyVisualSize
                KeyboardDeleteButton(
                    onDelete: onDelete,
                    onDeleteWord: onDeleteWord,
                    visualWidth: visual.width,
                    visualHeight: visual.height,
                    visualCornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
                    hitWidth: frame.width,
                    hitHeight: frame.height
                )
                .frame(width: frame.width, height: frame.height)
            default:
                if variants.count > 1 {
                    // A Button and a high-priority long-press both receive the
                    // same touch-up on some keyboard hosts. That race inserts the
                    // base letter and the selected accent. Variant keys therefore
                    // have exactly one gesture owner: short release inserts the
                    // base key, long release commits one popup option.
                    letterKeyLabel(for: key, frame: visualFrame)
                        .contentShape(Rectangle().inset(by: -hitExpansion))
                        .overlay {
                            ImmediateVariantKey(
                                onBegan: { point in
                                    handleLetterVariantBegan(
                                        key: key, keyID: keyID, point: point,
                                        frame: visualFrame, bounds: bounds
                                    )
                                },
                                onMoved: { point in
                                    handleLetterVariantMoved(keyID: keyID, point: point, frame: frame)
                                },
                                onEnded: { cancelled in
                                    handleLetterVariantEnded(key: key, keyID: keyID, cancelled: cancelled)
                                },
                                adaptiveKeyID: keyID,
                                adaptiveTouchScopeID: adaptiveTouchScopeID.uuidString
                            )
                        }
                        .accessibilityLabel(
                            key.accessibilityLabel(for: page) ?? "Keyboard key"
                        )
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { commit(key) }
                } else {
                    ZStack {
                        letterKeyLabel(for: key, frame: visualFrame)
                        ImmediateKeyButton(
                                onTouchDown: {
                                    handleLetterKeyBegan(key: key, frame: visualFrame, bounds: bounds)
                                },
                                onTouchUp: {
                                    dismissKeyPreview()
                                },
                                adaptiveKeyID: keyID,
                                adaptiveTouchScopeID: adaptiveTouchScopeID.uuidString
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .contentShape(Rectangle().inset(by: -hitExpansion))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        key.type == .backspace
                            ? "Delete backward"
                            : key.accessibilityLabel(for: page) ?? "Keyboard key"
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { commit(key) }
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
    }

    private func letterKeyLabel(for key: KeyDefinition, frame: CGRect) -> some View {
        Group {
            if case .shift = key.type {
                let visual = surfaceLayout.commandKeyVisualSize
                CommandKeyFace(
                    systemName: shiftSymbolName,
                    plateWidth: visual.width,
                    plateHeight: visual.height
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                letterGlyph(for: key)
                    .frame(width: max(0, frame.width), height: max(0, frame.height))
                    .letterKeyPlate()
            }
        }
    }

    @ViewBuilder
    private func letterGlyph(for key: KeyDefinition) -> some View {
        switch key.type {
        case .input(let value, _):
            Text(value)
                .font(.system(size: 22, weight: .light))
        case .shift:
            Image(systemName: shiftSymbolName)
                .font(.system(size: 16, weight: .semibold))
        case .symbols:
            Text("123")
                .font(.system(size: 14, weight: .medium))
        case .returnkey(let name):
            Text(name)
                .font(.system(size: 14, weight: .medium))
        case .backspace:
            Image(systemName: "delete.backward")
                .font(.system(size: 16, weight: .semibold))
        default:
            EmptyView()
        }
    }

    private func commit(_ key: KeyDefinition) {
        switch key.type {
        case .input(let value, _):
            if value == KeyboardLayouts.emojiKeyGlyph {
                onEmoji()
            } else {
                onInsert(value)
                if page == .shifted { page = .normal }
            }
        case .shift:
            page = page == .capslock ? .normal : (page == .shifted ? .normal : .shifted)
        case .symbols:
            onSymbols()
        case .returnkey:
            onReturn()
        case .spacebar:
            onSpace()
        default:
            break
        }
    }

    private func commitTap(_ key: KeyDefinition) {
        HapticFeedback.keyTapped()
        if case .backspace = key.type {
            onDelete()
        } else {
            commit(key)
        }
    }

    private func handleShiftTap() {
        let now = Date()
        let isSecondTap = now.timeIntervalSince(KeyboardState.shared.lastShiftTapDate) <= KeyboardShiftState.doubleTapWindow
        let currentState: KeyboardShiftState
        switch page {
        case .capslock: currentState = .capsLock
        case .shifted: currentState = .shifted
        default: currentState = .normal
        }
        let nextState = currentState.state(afterTapIsWithinDoubleTapWindow: isSecondTap)
        switch nextState {
        case .normal: page = .normal
        case .shifted: page = .shifted
        case .capsLock: page = .capslock
        }
        KeyboardState.shared.lastShiftTapDate = nextState == .shifted ? now : .distantPast
        HapticFeedback.keyTapped()
    }

    private func alternateVariants(for key: KeyDefinition) -> [String] {
        guard case .input(let value, _) = key.type,
              value.count == 1,
              let accents = AccentedCharacters.accents(for: value),
              !accents.isEmpty else {
            return []
        }

        let transformedAccents = (page == .shifted || page == .capslock)
            ? accents.map(KeyCaseTransform.uppercased)
            : accents
        return [value] + transformedAccents
    }

    private func handleLetterKeyBegan(key: KeyDefinition, frame: CGRect, bounds: CGSize) {
        HapticFeedback.prepareForNextTap()
        HapticFeedback.keyTapped()
        presentKeyPreview(text: previewText(for: key), source: frame, bounds: bounds)
        commit(key)
    }

    private func handleLetterVariantBegan(
        key: KeyDefinition,
        keyID: String,
        point: CGPoint,
        frame: CGRect,
        bounds: CGSize
    ) {
        let variants = alternateVariants(for: key)
        guard !variants.isEmpty else {
            handleLetterKeyBegan(key: key, frame: frame, bounds: bounds)
            return
        }
        HapticFeedback.prepareForNextTap()
        // A held accent key must not block a second finger from typing another
        // accent/base key. Only one popup is shown, while concurrent touches
        // commit their base key independently on touch-down.
        guard activeVariantKeyID == nil else {
            nonPopupVariantTouchIDs.insert(keyID)
            HapticFeedback.keyTapped()
            commit(key)
            return
        }
        activeVariantKeyID = keyID
        variantSession = nil
        presentKeyPreview(text: previewText(for: key), source: frame, bounds: bounds)
        variantTouchOrigin = CGPoint(x: frame.minX + point.x, y: frame.minY + point.y)
        variantTouchCancelled = false
        HapticFeedback.keyTapped()
        scheduleLetterVariantPopup(variants, source: frame, bounds: bounds)
    }

    private func handleLetterVariantMoved(keyID: String, point: CGPoint, frame: CGRect) {
        guard activeVariantKeyID == keyID else { return }
        moveLetterVariant(to: CGPoint(x: frame.minX + point.x, y: frame.minY + point.y))
    }

    private func handleLetterVariantEnded(key: KeyDefinition, keyID: String, cancelled: Bool) {
        if nonPopupVariantTouchIDs.remove(keyID) != nil {
            return
        }
        guard activeVariantKeyID == keyID else {
            if !cancelled { commit(key) }
            return
        }
        activeVariantKeyID = nil
        variantHoldToken = nil
        variantTouchOrigin = nil
        defer {
            variantTouchCancelled = false
            variantSession = nil
            previewSession = nil
        }
        guard !cancelled, !variantTouchCancelled else { return }
        if variantSession != nil { commitLetterVariantSession() }
        else { commit(key) }
    }

    private func moveLetterVariant(to point: CGPoint) {
        if var session = variantSession {
            let index = KeyVariantPopup.selectedIndex(at: point, popupFrame: session.popupFrame,
                                                     optionCount: session.options.count)
            if session.selectedIndex != index {
                session.selectedIndex = index
                variantSession = session
                HapticFeedback.variantHighlightChanged()
            }
        }
    }

    private func scheduleLetterVariantPopup(_ variants: [String], source: CGRect, bounds: CGSize) {
        guard KeyboardInteractionPreferences.accentVariantsEnabled else { return }
        let token = UUID()
        variantHoldToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardDeletion.holdRecognitionDuration) {
            guard variantHoldToken == token,
                  variantSession == nil,
                  !variantTouchCancelled else { return }
            previewSession = nil
            variantSession = makeLetterVariantSession(variants, source: source, in: bounds)
        }
    }

    private func previewText(for key: KeyDefinition) -> String? {
        guard case .input(let value, _) = key.type,
              value != KeyboardLayouts.emojiKeyGlyph else { return nil }
        return value
    }

    private func presentKeyPreview(text: String?, source: CGRect, bounds: CGSize) {
        guard KeyboardInteractionPreferences.keyPopupsEnabled, let text, !text.isEmpty else { return }
        previewSession = KeyPreviewSession(
            text: text,
            sourceFrame: source,
            popupFrame: KeyPressPreviewHost.frame(
                for: source,
                in: bounds,
                topOverflow: CGFloat(surfaceLayout.surfaceFrame.minY)
            ),
            cornerRadius: VoiceOnlyKeyboardPolicy.keyCornerRadius
        )
    }

    private func dismissKeyPreview() {
        previewSession = nil
    }

    private func makeLetterVariantSession(_ options: [String], source: CGRect, in bounds: CGSize) -> KeyVariantSession {
        HapticFeedback.variantPopupPresented()
        let popupFrame = KeyVariantPopup.frame(
            for: source,
            optionCount: options.count,
            isEmoji: false,
            in: bounds,
            topOverflow: CGFloat(surfaceLayout.surfaceFrame.minY)
        )
        return KeyVariantSession(
            options: options,
            sourceFrame: source,
            popupFrame: popupFrame,
            isEmoji: false,
            selectedIndex: 0
        )
    }

    private func commitLetterVariantSession() {
        guard let session = variantSession,
              session.options.indices.contains(session.selectedIndex) else {
            variantSession = nil
            previewSession = nil
            return
        }
        onInsert(session.options[session.selectedIndex])
        if page == .shifted {
            page = .normal
        }
        variantSession = nil
        previewSession = nil
    }
}

private struct PositionedLetterKey: Identifiable {
    let id: String
    let key: KeyDefinition
    /// Continuous hit target (gaps absorbed).
    let frame: CGRect
    /// Original drawn plate/glyph rect (inset inside `frame`).
    let visualFrame: CGRect
    let row: Int
    let column: Int
}

/// UIKit owns only the narrow adaptive boundary zones. Returning false from
/// `point(inside:)` leaves all ordinary touches with the existing SwiftUI key.
private struct AdaptiveLetterTouchRouter: UIViewRepresentable {
    let keys: [AdaptiveTouchKey]
    let probabilities: NextCharacterProbabilities?
    let scopeID: String

    func makeUIView(context: Context) -> RoutingView {
        let view = RoutingView()
        update(view)
        return view
    }

    func updateUIView(_ uiView: RoutingView, context: Context) {
        update(uiView)
    }

    private func update(_ view: RoutingView) {
        view.keys = keys
        view.probabilities = probabilities
        view.scopeID = scopeID
    }

    final class RoutingView: UIView {
        var keys: [AdaptiveTouchKey] = []
        var probabilities: NextCharacterProbabilities?
        var scopeID = ""

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
            isAccessibilityElement = false
            accessibilityElementsHidden = true
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            targetControl(at: point) != nil
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            targetControl(at: point)
        }

        private func targetControl(at point: CGPoint) -> UIView? {
            guard isUserInteractionEnabled, !isHidden, alpha > 0.01,
                  bounds.contains(point),
                  !UIAccessibility.isVoiceOverRunning,
                  !UIAccessibility.isSwitchControlRunning,
                  let window,
                  let probabilities,
                  let targetID = AdaptiveTouchResolver.redirectedKey(
                    at: point, keys: keys, probabilities: probabilities
                  ) else {
                return nil
            }
            return AdaptiveTouchControlRegistry.shared.control(
                for: targetID, in: window, scopeID: scopeID
            )
        }
    }
}

private struct LiquidNumberPadView: View {
    let style: HostFieldPolicy.NumberPadStyle
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let popupTopOverflow: CGFloat
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let onKeyboard: () -> Void

    @State private var lettersHoldToken: UUID?
    @State private var openedLettersFromHold = false
    @State private var previewSession: KeyPreviewSession?

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let frames = positionedKeys(in: proxy.size)
                ZStack(alignment: .topLeading) {
                    ForEach(frames) { item in
                        padKey(item.key, frame: item.frame, bounds: proxy.size)
                            .frame(width: item.frame.width, height: item.frame.height)
                            .position(x: item.frame.midX, y: item.frame.midY)
                    }
                    if previewSession != nil {
                        KeyPressPreviewHost(session: $previewSession)
                    }
                }
            }
        }
        .frame(width: availableWidth, height: availableHeight)
    }

    private var rows: [[KeyboardNumberPadLayout.Key]] {
        KeyboardNumberPadLayout.rows(
            for: style,
            decimalSeparator: Locale.current.decimalSeparator ?? "."
        )
    }

    private func positionedKeys(in size: CGSize) -> [PositionedNumberPadKey] {
        let edge = VoiceOnlyKeyboardPolicy.numberPadEdgeInset
        let content = CGSize(
            width: max(0, size.width - edge * 2),
            height: max(0, size.height - edge * 2)
        )
        let weights = rows.map { row in row.map { CGFloat($0.width) } }
        let frames = VoiceOnlyKeyboardPolicy.SymbolGrid.frames(
            for: weights,
            in: content,
            spacing: VoiceOnlyKeyboardPolicy.numberPadKeySpacing,
            inset: 0,
            rowSpacing: VoiceOnlyKeyboardPolicy.numberPadRowSpacing
        ).map { row in
            row.map { $0.offsetBy(dx: edge, dy: edge) }
        }
        return zip(rows, frames).enumerated().flatMap { rowIndex, pair in
            zip(pair.0, pair.1).enumerated().map { columnIndex, item in
                PositionedNumberPadKey(
                    id: "\(style.rawValue)-\(rowIndex)-\(columnIndex)",
                    key: item.0,
                    frame: item.1
                )
            }
        }
    }

    @ViewBuilder
    private func padKey(_ key: KeyboardNumberPadLayout.Key, frame: CGRect, bounds: CGSize) -> some View {
        switch key.kind {
        case .spacer:
            Color.clear.accessibilityHidden(true)
        case .letters:
            ZStack {
                CommandKeyFace(
                    text: "ABC",
                    plateWidth: frame.width,
                    plateHeight: frame.height,
                    cornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius,
                    textPointSize: 16
                )
                ImmediateKeyButton(
                    onTouchDown: {
                        HapticFeedback.keyTapped()
                        onKeyboard()
                    },
                    onTouchUp: {},
                    highlightCornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius,
                    highlightSize: frame.size
                )
            }
            .frame(width: frame.width, height: frame.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open letter keyboard")
            .accessibilityAddTraits(.isButton)
        case .delete:
            KeyboardDeleteButton(
                onDelete: onDelete,
                onDeleteWord: onDeleteWord,
                visualWidth: frame.width,
                visualHeight: frame.height,
                visualCornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius,
                hitWidth: frame.width,
                hitHeight: frame.height
            )
        case .insert(let value, let holdLetters):
            ZStack {
                VStack(spacing: 1) {
                    Text(value)
                        .font(.system(size: 22, weight: .light))
                    if holdLetters {
                        Text("ABC")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .letterKeyPlate(cornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius)
                if holdLetters {
                    ImmediateVariantKey(
                        onBegan: { _ in
                            openedLettersFromHold = false
                            let token = UUID()
                            lettersHoldToken = token
                            HapticFeedback.keyTapped()
                            DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardDeletion.holdRecognitionDuration) {
                                guard lettersHoldToken == token else { return }
                                openedLettersFromHold = true
                                lettersHoldToken = nil
                                HapticFeedback.variantPopupPresented()
                                onKeyboard()
                            }
                        },
                        onMoved: { _ in },
                        onEnded: { cancelled in
                            lettersHoldToken = nil
                            defer { openedLettersFromHold = false }
                            guard !cancelled, !openedLettersFromHold else { return }
                            onInsert(value)
                        }
                    )
                } else {
                    ImmediateKeyButton(
                        onTouchDown: {
                            HapticFeedback.keyTapped()
                            presentPadPreview(text: value, source: frame, bounds: bounds)
                            onInsert(value)
                        },
                        onTouchUp: { previewSession = nil }
                    )
                }
            }
            .contentShape(Rectangle().inset(by: -2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value)
            .accessibilityHint(holdLetters ? "Hold to open the letter keyboard." : "")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func presentPadPreview(text: String, source: CGRect, bounds: CGSize) {
        guard KeyboardInteractionPreferences.keyPopupsEnabled, !text.isEmpty else { return }
        previewSession = KeyPreviewSession(
            text: text,
            sourceFrame: source,
            popupFrame: KeyPressPreviewHost.frame(
                for: source,
                in: bounds,
                topOverflow: popupTopOverflow
            ),
            cornerRadius: VoiceOnlyKeyboardPolicy.numberPadKeyCornerRadius
        )
    }
}

private struct PositionedNumberPadKey: Identifiable {
    let id: String
    let key: KeyboardNumberPadLayout.Key
    let frame: CGRect
}

private struct LiquidSymbolPageView: View {
    let page: KeyboardPage
    let surfaceLayout: VoiceOnlyKeyboardPolicy.Layout
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    let onInsert: (String) -> Void
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let onReturn: () -> Void
    let onSpace: () -> Void
    let onTogglePage: (KeyboardPage) -> Void
    // Symbols use the dictation-board emoji control instead of an ABC control.
    let onClose: () -> Void
    let onBackToVoice: () -> Void
    let onEmoji: () -> Void
    let onKeyboard: () -> Void
    let onSpaceCursorBegan: () -> Void
    let onSpaceCursorMoved: (KeyboardCursorStep) -> Void
    let onSpaceCursorEnded: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast
    @State private var variantSession: KeyVariantSession?
    @State private var previewSession: KeyPreviewSession?
    @State private var variantHoldToken: UUID?
    @State private var variantTouchOrigin: CGPoint?
    @State private var variantTouchCancelled = false
    @State private var activeVariantKeyID: String?
    @State private var nonPopupVariantTouchIDs: Set<String> = []

    private let bottomBarHeight: CGFloat = 44
    private let chromeBottomInset: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeBottomInset)
    private let commandRowGap: CGFloat = CGFloat(VoiceOnlyKeyboardPolicy.chromeCommandRowGap)

    var body: some View {
        let _ = (onClose, onBackToVoice)
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let gridSize = CGSize(width: proxy.size.width, height: proxy.size.height)
                let frames = positionedKeys(in: gridSize)
                ZStack(alignment: .topLeading) {
                    ForEach(frames) { positionedKey in
                        symbolKey(
                            positionedKey.key,
                            keyID: positionedKey.id,
                            frame: positionedKey.frame,
                            visualFrame: positionedKey.visualFrame,
                            bounds: gridSize
                        )
                            .frame(width: positionedKey.frame.width, height: positionedKey.frame.height)
                            .position(x: positionedKey.frame.midX, y: positionedKey.frame.midY)
                    }
                    .frame(width: gridSize.width, height: gridSize.height)
                    if let session = variantSession {
                        variantOverlay(session, in: gridSize)
                            .zIndex(20)
                    } else if previewSession != nil {
                        KeyPressPreviewHost(session: $previewSession)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .coordinateSpace(name: "symbolPage")
                // Each key owns its touch; a second grid drag used to race
                // long-press selection and could delete again on release.
                .accessibilityElement(children: .contain)
            }
            Color.clear.frame(height: commandRowGap)
            AuxiliaryBottomBar(
                layout: surfaceLayout,
                numbersTitle: "123",
                onNumbers: {},
                onLetters: onKeyboard,
                onEmoji: onEmoji,
                spaceFrame: surfaceLayout.chromeWideSpaceFrame,
                returnFrame: surfaceLayout.chromeReturnFrame,
                onSpace: onSpace,
                onSpaceCursorBegan: onSpaceCursorBegan,
                onSpaceCursorMoved: onSpaceCursorMoved,
                onSpaceCursorEnded: onSpaceCursorEnded,
                onReturn: onReturn,
                showsNumbersControl: false
            )
            .frame(width: availableWidth, height: bottomBarHeight)
            Color.clear.frame(height: chromeBottomInset)
        }
        .frame(width: availableWidth, height: availableHeight)
        .onChange(of: page) { _, _ in
            variantSession = nil
            previewSession = nil
            variantHoldToken = nil
            variantTouchOrigin = nil
            variantTouchCancelled = false
            activeVariantKeyID = nil
            nonPopupVariantTouchIDs.removeAll()
        }
        .onDisappear {
            variantHoldToken = nil
            variantTouchOrigin = nil
            variantTouchCancelled = false
            variantSession = nil
            previewSession = nil
            activeVariantKeyID = nil
            nonPopupVariantTouchIDs.removeAll()
        }
    }

    private var rows: [[LiquidSymbolKey]] {
        switch page {
        case .symbols2:
            return KeyboardSymbolsLayout.symbols.enumerated().map { rowIndex, row in
                row.enumerated().map { columnIndex, key in
                    LiquidSymbolKey(id: "\(page)-\(rowIndex)-\(columnIndex)", key: key, page: page)
                }
            }
        case .symbols1:
            return KeyboardSymbolsLayout.numbers.enumerated().map { rowIndex, row in
                row.enumerated().map { columnIndex, key in
                    LiquidSymbolKey(id: "\(page)-\(rowIndex)-\(columnIndex)", key: key, page: page)
                }
            }
        default:
            return []
        }
    }

    private func positionedKeys(in size: CGSize) -> [PositionedLiquidSymbolKey] {
        guard !rows.isEmpty else { return [] }
        let geometry = VoiceOnlyKeyboardPolicy.scaledKeyGeometry(for: Double(size.width))
        let edgeInset = geometry.keyGridInset
        let rowSpacing = geometry.keyRowSpacing
        let keySpacing = geometry.keySpacing
        let rowWeights = rows.map { row in row.map(\.width) }
        let lastRowHeight = VoiceOnlyKeyboardPolicy.SymbolGrid.letterAlignedLastRowHeight(
            in: size.height,
            rowSpacing: rowSpacing
        )
        var frames = VoiceOnlyKeyboardPolicy.SymbolGrid.framesWithPinnedLastRow(
            for: rowWeights,
            in: size,
            spacing: keySpacing,
            inset: edgeInset,
            rowSpacing: rowSpacing,
            lastRowHeight: lastRowHeight,
            maxRowHeight: geometry.letterKeyHeight
        )
        if let row = frames.last, let first = row.first {
            frames[frames.count - 1] = VoiceOnlyKeyboardPolicy.SymbolGrid.fixedEdgeCommandRowFrames(
                itemCount: row.count,
                rowFrame: CGRect(
                    x: edgeInset,
                    y: first.minY,
                    width: max(0, size.width - edgeInset * 2),
                    height: first.height
                ),
                spacing: CGFloat(VoiceOnlyKeyboardPolicy.railSpacing),
                commandWidth: surfaceLayout.boardDeleteFrame.width
            )
        }
        let deleteFrame = CGRect(
            x: surfaceLayout.boardDeleteFrame.minX - surfaceLayout.surfaceFrame.minX,
            y: surfaceLayout.boardDeleteFrame.minY - surfaceLayout.surfaceFrame.minY,
            width: surfaceLayout.boardDeleteFrame.width,
            height: surfaceLayout.boardDeleteFrame.height
        )
        if let lastRow = frames.indices.last, rows.indices.contains(lastRow) {
            frames[lastRow] = frames[lastRow].map {
                CGRect(x: $0.minX, y: deleteFrame.minY, width: $0.width, height: deleteFrame.height)
            }
            for (index, key) in rows[lastRow].enumerated() {
                if case .delete = key.action, frames[lastRow].indices.contains(index) {
                    frames[lastRow][index] = deleteFrame
                }
            }
        }
        let hitFrames = VoiceOnlyKeyboardPolicy.SymbolGrid.expandFramesAbsorbingGaps(
            frames,
            horizontalSpacing: keySpacing,
            verticalSpacing: rowSpacing
        )
        return rows.indices.flatMap { rowIndex -> [PositionedLiquidSymbolKey] in
            let row = rows[rowIndex]
            let rowHits = hitFrames[rowIndex]
            return row.indices.map { columnIndex in
                PositionedLiquidSymbolKey(
                    key: row[columnIndex],
                    frame: rowHits[columnIndex],
                    visualFrame: rowHits[columnIndex]
                )
            }
        }
    }

    private func key(at point: CGPoint, in frames: [PositionedLiquidSymbolKey]) -> LiquidSymbolKey? {
        if let direct = frames.first(where: {
            $0.frame.contains(point) && !$0.key.isSpacer
        }) {
            return direct.key
        }
        return nil
    }

    @ViewBuilder
    private func symbolKey(
        _ key: LiquidSymbolKey,
        keyID: String,
        frame: CGRect,
        visualFrame: CGRect,
        bounds: CGSize
    ) -> some View {
        if key.isSpacer {
            Color.clear
                .accessibilityHidden(true)
        } else if case .delete = key.action {
            let visual = surfaceLayout.commandKeyVisualSize
            KeyboardDeleteButton(
                onDelete: onDelete, onDeleteWord: onDeleteWord,
                visualWidth: visual.width,
                visualHeight: visual.height,
                hitWidth: frame.width, hitHeight: frame.height
            )
                .frame(width: frame.width, height: frame.height)
        } else {
            let variants = insertVariants(for: key)
            if variants.count > 1 {
                ZStack {
                    keyContent(key, frame: visualFrame)
                    ImmediateVariantKey(
                        onBegan: { point in
                            HapticFeedback.prepareForNextTap()
                            guard activeVariantKeyID == nil else {
                                nonPopupVariantTouchIDs.insert(keyID)
                                HapticFeedback.keyTapped()
                                commitSymbolFromTap(key, emitsHaptic: false)
                                return
                            }
                            activeVariantKeyID = keyID
                            HapticFeedback.keyTapped()
                            variantTouchOrigin = CGPoint(x: frame.minX + point.x, y: frame.minY + point.y)
                            variantTouchCancelled = false
                            if case .insert(let value) = key.action {
                                presentSymbolPreview(text: value, source: visualFrame, bounds: bounds)
                            }
                            scheduleSymbolVariantPopup(variants, source: visualFrame, bounds: bounds)
                        },
                        onMoved: { point in
                            let absolutePoint = CGPoint(x: frame.minX + point.x, y: frame.minY + point.y)
                            if var session = variantSession {
                                let index = KeyVariantPopup.selectedIndex(
                                    at: absolutePoint,
                                    popupFrame: session.popupFrame,
                                    optionCount: session.options.count
                                )
                                if session.selectedIndex != index {
                                    session.selectedIndex = index
                                    variantSession = session
                                    HapticFeedback.variantHighlightChanged()
                                }
                            }
                        },
                        onEnded: { cancelled in
                            if nonPopupVariantTouchIDs.remove(keyID) != nil {
                                return
                            }
                            guard activeVariantKeyID == keyID else {
                                if !cancelled { commitSymbolFromTap(key, emitsHaptic: false) }
                                return
                            }
                            let sessionWasPresented = variantSession != nil
                            let touchWasCancelled = cancelled || variantTouchCancelled
                            activeVariantKeyID = nil
                            variantHoldToken = nil
                            variantTouchOrigin = nil
                            variantTouchCancelled = false
                            if touchWasCancelled {
                                variantSession = nil
                                previewSession = nil
                            } else if sessionWasPresented {
                                commitVariantSession()
                            } else {
                                previewSession = nil
                                commitSymbolFromTap(key, emitsHaptic: false)
                            }
                        }
                    )
                }
                .frame(width: frame.width, height: frame.height)
                .foregroundStyle(.primary)
                .contentShape(Rectangle().inset(by: -6))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(key.accessibilityLabel)
                .accessibilityAddTraits(.isButton)
            } else {
                ZStack {
                    keyContent(key, frame: visualFrame)
                    ImmediateKeyButton(
                        onTouchDown: {
                            if case .insert(let value) = key.action {
                                presentSymbolPreview(text: value, source: visualFrame, bounds: bounds)
                            }
                            commit(key)
                        },
                        onTouchUp: {
                            previewSession = nil
                        },
                        highlightCornerRadius: key.isRoundCommand ? 18 : 13,
                        highlightSize: key.isRoundCommand ? surfaceLayout.commandKeyVisualSize : nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .foregroundStyle(.primary)
                .frame(width: frame.width, height: frame.height)
                // Keep the full rectangular frame tappable, including edge keys.
                .contentShape(Rectangle().inset(by: -6))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(key.accessibilityLabel)
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func insertVariants(for key: LiquidSymbolKey) -> [String] {
        guard case .insert(let value) = key.action else { return [] }
        return SymbolKeyVariants.options(for: value)
    }

    @ViewBuilder
    private func variantOverlay(_ session: KeyVariantSession, in _: CGSize) -> some View {
        KeyVariantPopup(
            options: session.options,
            selectedIndex: session.selectedIndex,
            isEmoji: session.isEmoji
        )
        .frame(width: session.popupFrame.width, height: session.popupFrame.height)
        .position(x: session.popupFrame.midX, y: session.popupFrame.midY)
        .allowsHitTesting(false)
    }

    private func scheduleSymbolVariantPopup(_ variants: [String], source: CGRect, bounds: CGSize) {
        guard KeyboardInteractionPreferences.accentVariantsEnabled else { return }
        let token = UUID()
        variantHoldToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardDeletion.holdRecognitionDuration) {
            guard variantHoldToken == token,
                  variantSession == nil,
                  !variantTouchCancelled else { return }
            previewSession = nil
            variantSession = makeVariantSession(variants, source: source, in: bounds)
        }
    }

    private func presentSymbolPreview(text: String, source: CGRect, bounds: CGSize) {
        guard KeyboardInteractionPreferences.keyPopupsEnabled, !text.isEmpty else { return }
        previewSession = KeyPreviewSession(
            text: text,
            sourceFrame: source,
            popupFrame: KeyPressPreviewHost.frame(
                for: source,
                in: bounds,
                topOverflow: CGFloat(surfaceLayout.surfaceFrame.minY)
            ),
            cornerRadius: VoiceOnlyKeyboardPolicy.keyCornerRadius
        )
    }

    private func makeVariantSession(_ options: [String], source: CGRect, in bounds: CGSize) -> KeyVariantSession {
        HapticFeedback.variantPopupPresented()
        let popupFrame = KeyVariantPopup.frame(
            for: source,
            optionCount: options.count,
            isEmoji: false,
            in: bounds,
            topOverflow: CGFloat(surfaceLayout.surfaceFrame.minY)
        )
        return KeyVariantSession(
            options: options,
            sourceFrame: source,
            popupFrame: popupFrame,
            isEmoji: false,
            selectedIndex: 0
        )
    }

    private func commitVariantSession() {
        guard let session = variantSession,
              session.options.indices.contains(session.selectedIndex) else {
            variantSession = nil
            previewSession = nil
            return
        }
        onInsert(session.options[session.selectedIndex])
        variantSession = nil
        previewSession = nil
    }

    private func commitSymbolFromTap(_ key: LiquidSymbolKey, emitsHaptic: Bool = true) {
        commit(key, emitsHaptic: emitsHaptic)
    }

    @ViewBuilder
    private func keyContent(_ key: LiquidSymbolKey, frame: CGRect) -> some View {
        switch key.action {
        case .togglePage:
            let visual = surfaceLayout.commandKeyVisualSize
            CommandKeyFace(
                text: key.label,
                plateWidth: visual.width,
                plateHeight: visual.height,
                textWeight: .medium
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .delete:
            let visual = surfaceLayout.commandKeyVisualSize
            CommandKeyFace(
                systemName: "delete.backward",
                plateWidth: visual.width,
                plateHeight: visual.height
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .insert:
            Text(key.label)
                .font(.system(size: 22, weight: .light))
                .frame(width: max(0, frame.width), height: max(0, frame.height))
                .letterKeyPlate()
        case .close:
            Text(key.label)
                .font(.system(size: 22, weight: .light))
                .frame(width: max(0, frame.width), height: max(0, frame.height))
        }
    }

    private func commit(_ key: LiquidSymbolKey, emitsHaptic: Bool = true) {
        guard !key.isSpacer else { return }
        if emitsHaptic {
            HapticFeedback.keyTapped()
        }
        switch key.action {
        case .insert(let value): onInsert(value)
        case .delete: onDelete()
        case .togglePage:
            switch VoiceOnlyKeyboardPolicy.SymbolPageTransition.forToggle(
                from: page == .symbols1 ? .symbols1 : .symbols2
            ) {
            case .symbols1ToSymbols2:
                onTogglePage(.symbols2)
            case .symbols2ToSymbols1:
                onTogglePage(.symbols1)
            }
        case .close: onClose()
        }
    }
}

private struct LiquidSymbolKey: Identifiable {
    enum Action {
        case insert(String)
        case delete
        case togglePage
        case close
    }

    let id: String
    let label: String
    let width: CGFloat
    let action: Action
    let isSpacer: Bool

    init(id: String, key: KeyboardSymbolsLayout.Key, page: KeyboardPage) {
        self.id = id
        self.width = CGFloat(key.width)
        switch key.kind {
        case .insert(let value):
            label = value
            action = .insert(value)
            isSpacer = false
        case .pageToggle:
            label = page == .symbols1 ? "#+=" : "123"
            action = .togglePage
            isSpacer = false
        case .delete:
            label = ""
            action = .delete
            isSpacer = false
        case .emoji, .voice, .space, .returnKey, .spacer:
            label = ""
            action = .close
            isSpacer = true
        }
    }

    var accessibilityLabel: String {
        switch action {
        case .insert: return label
        case .delete: return "Delete backward"
        case .togglePage: return label == "#+=" ? "More symbols" : "Return to numbers keyboard"
        case .close: return "Close"
        }
    }

    var isPageToggle: Bool {
        if case .togglePage = action { return true }
        return false
    }

    var isRoundCommand: Bool {
        switch action {
        case .togglePage, .delete:
            return true
        case .insert, .close:
            return false
        }
    }
}

private struct PositionedLiquidSymbolKey: Identifiable {
    let key: LiquidSymbolKey
    /// Continuous hit target (gaps absorbed).
    let frame: CGRect
    /// Original drawn plate/glyph rect.
    let visualFrame: CGRect
    var id: String { key.id }
}

private struct OptionalLongPressModifier<G: Gesture>: ViewModifier {
    let enabled: Bool
    let gesture: G

    func body(content: Content) -> some View {
        if enabled {
            content.highPriorityGesture(gesture)
        } else {
            content
        }
    }
}

private struct SymbolGlowButtonStyle: ButtonStyle {
    let isActive: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isActive
        configuration.label
            .background {
                if pressed {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                        }
                        .padding(4)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: pressed)
    }
}

/// UIKit owns the language menu. SwiftUI Menu rebuilds whenever KeyboardState
/// publishes clipboard or translation-status updates, which dismissed the
/// dropdown. `UIDeferredMenuElement` builds items only when the user opens it.
struct LanguageMenuButton: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
        button.backgroundColor = .clear
        button.accessibilityElementsHidden = true
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { completion in
                completion(Self.menuItems())
            }
        ])
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        // Keep the same deferred menu instance so a KeyboardState publish cannot
        // tear down an open dropdown.
    }

    static func menuItems() -> [UIMenuElement] {
        let state = KeyboardState.shared
        var outputActions: [UIMenuElement] = [
            UIAction(
                title: "AUTO",
                subtitle: "Keep spoken language",
                image: UIImage(systemName: state.selectedTranslationTarget == nil ? "checkmark.circle.fill" : "waveform"),
                state: state.selectedTranslationTarget == nil ? .on : .off
            ) { _ in
                HapticFeedback.keyTapped()
                state.selectTranscription()
            }
        ]
        for target in state.translationTargets {
            let targetStatus = state.translationTargetStatus(target)
            let selected = state.selectedTranslationTarget == target
            var attributes: UIMenuElement.Attributes = []
            if targetStatus == .unavailable { attributes.insert(.disabled) }
            outputActions.append(
                UIAction(
                    title: state.translationTargetMenuLabel(target),
                    subtitle: target.displayName,
                    image: UIImage(systemName: selected ? "checkmark.circle.fill"
                                    : targetStatus == .supportedNeedsDownload ? "arrow.down.circle"
                                    : targetStatus == .checking ? "ellipsis.circle" : "character.bubble"),
                    attributes: attributes,
                    state: selected ? .on : .off
                ) { _ in
                    HapticFeedback.keyTapped()
                    state.selectTranslation(target)
                }
            )
        }
        return outputActions
    }

    final class Coordinator {}
}
