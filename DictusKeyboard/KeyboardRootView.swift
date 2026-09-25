// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import UIKit
import Foundation
import DictusCore

/// Root SwiftUI view for the voice-only keyboard surface.
struct KeyboardRootView: View {
    let controllerID: String
    /// The UIKit letter grid. It is mounted on the input view by the controller and
    /// is handed down rather than created here, so there is exactly one instance
    /// and no process-wide registry for it to be registered in.
    let letterGridView: LetterKeyGridView?
    let routeText: (String) -> Void
    let routeCommand: (KeyboardCommand) -> Void
    let routeWordDeletion: () -> Void
    let routeCursorMovement: (KeyboardCursorStep) -> Void
    let routeCursorEnded: () -> Void
    let routePaste: () -> Void
    let routeDismiss: () -> Void
    @ObservedObject var state = KeyboardState.shared
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
        // Pages owned by the rebuilt UIKit grid render only the shared bottom bar
        // here.
        //
        // The grid draws its own keys in a real `UIView` mounted on the input view,
        // and `NextKeyboardHost.gridFrame` gives it a rect that stops above the bar
        // lane. So the two describe disjoint regions — nothing is drawn twice and
        // nothing overlaps, which is what let the SwiftUI layer stay non-interactive
        // over the rows. That matters: leaving SwiftUI hit-testable on top of the
        // grid is what swallowed every touch in the first place.
        if KeyboardViewController.nextKeyboardModes.contains(state.areaMode) {
            sharedBottomBar(layout: layout, surfaceFrame: surfaceFrame)
        } else {
            surfaceContent(layout: layout, surfaceFrame: surfaceFrame)
        }
    }

    /// The one bottom bar, mounted in the lane the grid leaves free.
    ///
    /// Deliberately the same component the emoji picker, symbol surface and legacy
    /// letter surface use, so a bar change lands on every page at once. The grid
    /// pages used to carry their own, which is how the same keyboard ended up with
    /// two different bars depending on which page you were on.
    @ViewBuilder
    private func sharedBottomBar(
        layout: VoiceOnlyKeyboardPolicy.Layout,
        surfaceFrame: CGRect
    ) -> some View {
        let lane = CGFloat(VoiceOnlyKeyboardPolicy.chromeCommandRowGap)
            + CGFloat(VoiceOnlyKeyboardPolicy.spacebarHeight)
            + CGFloat(VoiceOnlyKeyboardPolicy.chromeBottomInset)
        let barHeight = CGFloat(VoiceOnlyKeyboardPolicy.spacebarHeight)
        let isLetterPage = state.areaMode == .letters
        // The number pad has no bar. The system pad is 1-9 then a centred 0 and a
        // delete, and it runs the full height; mounting a bar under it would both
        // differ from that and take 54pt the pad's keys need.
        let isPad = state.areaMode == .numberPad
        if isPad {
            Color.clear
                .frame(width: surfaceFrame.width, height: surfaceFrame.height)
                .allowsHitTesting(false)
        } else {
        VStack(spacing: 0) {
            // The grid's share. Transparent and untouchable: it only reserves the
            // space so the bar lands in the lane the host left for it.
            Color.clear
                .frame(width: surfaceFrame.width, height: max(0, surfaceFrame.height - lane))
                .allowsHitTesting(false)
            Color.clear
                .frame(height: CGFloat(VoiceOnlyKeyboardPolicy.chromeCommandRowGap))
                .allowsHitTesting(false)
            // Flag-for-flag the same call `LetterKeyboardSurface` and
            // `SymbolKeyboardSurface` make. The letter page is the only one with a
            // period key and the only one that hides its own layer control; the
            // symbol page hides 123 because it carries a #+/123 toggle of its own.
            AuxiliaryBottomBar(
                layout: layout,
                numbersTitle: "123",
                onNumbers: { state.presentNumbersArea() },
                onLetters: { state.presentArea(.letters) },
                onEmoji: { state.presentArea(.emoji) },
                spaceFrame: isLetterPage ? layout.letterSpaceFrame : layout.chromeWideSpaceFrame,
                returnFrame: layout.chromeReturnFrame,
                periodFrame: isLetterPage ? layout.letterPeriodFrame : .zero,
                onPeriod: { routeText($0) },
                onSpace: { routeProxyCommand(.space) },
                onSpaceCursorBegan: {},
                onSpaceCursorMoved: routeCursorMovement,
                onSpaceCursorEnded: routeCursorEnded,
                onReturn: { routeProxyCommand(.returnKey) },
                showsNumbersControl: true,
                showsLettersControl: !isLetterPage,
                showsEmojiControl: true,
                showsPeriodKey: isLetterPage,
                fieldKeys: state.hostLetterFieldKeys,
                onSymbolInsert: { routeText($0) }
            )
            .frame(width: surfaceFrame.width, height: barHeight)
            Color.clear
                .frame(height: CGFloat(VoiceOnlyKeyboardPolicy.chromeBottomInset))
                .allowsHitTesting(false)
        }
        .frame(width: surfaceFrame.width, height: surfaceFrame.height, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func surfaceContent(
        layout: VoiceOnlyKeyboardPolicy.Layout,
        surfaceFrame: CGRect
    ) -> some View {
        switch state.areaMode {
        case .keys:
            centerSurface(layout: layout)
        case .letters:
            LetterKeyboardSurface(
                surfaceLayout: layout,
                availableWidth: surfaceFrame.width,
                availableHeight: surfaceFrame.height,
                gridView: letterGridView,
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
            EmojiKeyboardSurface(
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
            SymbolKeyboardSurface(
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
            NumberKeyboardSurface(
                style: state.hostNumberPadStyle,
                availableWidth: surfaceFrame.width,
                availableHeight: surfaceFrame.height,
                popupTopOverflow: CGFloat(layout.surfaceFrame.minY),
                onInsert: { text in routeProxyText(text) },
                onDelete: { routeProxyCommand(.delete) },
                onDeleteWord: routeWordDeletion,
                onKeyboard: { state.presentArea(.letters) },
                // The shared UIKit touch owner is mounted on the input view, so the
                // pad must publish its geometry in that space, not its own.
                surfaceOrigin: surfaceFrame.origin,
            )
            .frame(width: surfaceFrame.width, height: surfaceFrame.height)
            .accessibilityIdentifier("number-pad-surface")
        }
    }

    func routeProxyText(_ text: String) {
        routeText(text)
    }

    func routeProxyCommand(_ command: KeyboardCommand) {
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
            systemName: "text.bubble",
            label: "Return to dictation board",
            laneSize: accessoryHitSize,
            action: { state.closeArea() }
        )
        .accessibilityIdentifier("return-to-dictation-board")
    }


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
                HapticFeedback.playInputClick()
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
                    HapticFeedback.playInputClick()
                    state.selectTranslation(target)
                }
            )
        }
        return outputActions
    }

    final class Coordinator {}
}
