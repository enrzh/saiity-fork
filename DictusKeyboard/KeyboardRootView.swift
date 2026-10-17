// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import UIKit
import Foundation
import SyllivraKernel

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
    let installOpenURL: (@escaping (URL, @escaping (Bool) -> Void) -> Void) -> Void
    @ObservedObject var state = KeyboardState.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { proxy in
            let surfaceHeight = max(proxy.size.height, 1)
            let layout = VoiceOnlyKeyboardPolicy.layout(
                for: proxy.size.width,
                surfaceHeight: Double(surfaceHeight),
                controlOrder: KeyboardAccessoryOrder.current,
                topAccessoryHeight: KeyboardInteractionPreferences.topBarHeight(for: state.areaMode),
                compactChrome: !KeyboardInteractionPreferences.topBarEnabled
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

                if !voiceBoardUsesUIKitHits && (state.areaMode == .keys || state.areaMode == .recording) {
                    if layout.leftRailWidth > 0 {
                        voiceBoardChrome(text: "123", label: "Open symbols keyboard") {
                            state.presentNumbersArea()
                        }
                            .position(x: CGFloat(layout.chromeNumbersFrame.midX), y: CGFloat(layout.chromeNumbersFrame.midY))
                            .zIndex(4)
                        voiceBoardChrome(text: "ABC", label: "Open letter keyboard") {
                            state.presentArea(.letters)
                        }
                            .position(x: CGFloat(layout.chromeEmojiFrame.midX), y: CGFloat(layout.chromeEmojiFrame.midY))
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
                            .position(x: CGFloat(layout.chromeLettersFrame.midX), y: CGFloat(layout.chromeLettersFrame.midY))
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

                // Accessory faces are children of their native controls.
                // The retained SwiftUI accessory renderer is not live here.
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .background(Color.clear)
        }
        .environment(\.keyboardLiquidGlassEnabled, KeyboardInteractionPreferences.liquidGlassEnabled)
        .allowsHitTesting(false)
        .onAppear {
            // Keep the SwiftUI URL action available as the fallback when the
            // extension context declines a recovery handoff.
            installOpenURL { url, completion in
                openURL(url, completion: completion)
            }
            HapticFeedback.refreshEnabledState()
            HapticFeedback.warmUp()
            state.startClipboardMonitoring()
            state.refreshTypingLanguage()
        }
    }

    @ViewBuilder
    private func areaSurface(layout: VoiceOnlyKeyboardPolicy.Layout, contentFrame: CGRect) -> some View {
        let surfaceFrame = contentFrame
        // The UIKit grid and bottom bar own letters, symbols, emoji, and the pad.
        // SwiftUI stays clear there so it cannot swallow their touches.
        if KeyboardViewController.nextKeyboardModes.contains(state.areaMode) || state.areaMode == .emoji {
            Color.clear
                .frame(width: surfaceFrame.width, height: surfaceFrame.height)
                .allowsHitTesting(false)
        } else {
            surfaceContent(layout: layout, surfaceFrame: surfaceFrame)
        }
    }

    /// Letters, symbols, emoji, and the number pad are drawn by the UIKit grid.
    /// This view only hosts the dictation board.
    @ViewBuilder
    private func surfaceContent(
        layout: VoiceOnlyKeyboardPolicy.Layout,
        surfaceFrame: CGRect
    ) -> some View {
        switch state.areaMode {
        case .keys, .recording:
            centerSurface(layout: layout)
        case .letters, .panel, .emoji, .numberPad:
            Color.clear
                .frame(width: surfaceFrame.width, height: surfaceFrame.height)
                .allowsHitTesting(false)
        }
    }

    func routeProxyText(_ text: String) {
        routeText(text)
    }

    func routeProxyCommand(_ command: KeyboardCommand) {
        routeCommand(command)
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
