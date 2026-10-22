import SwiftUI
import UIKit
import Foundation
import SyllivraKernel

extension KeyboardRootView {
    func embeddedSurface<Content: View>(
        _ content: Content,
        frame: CGRect
    ) -> some View {
        let surfaceCornerRadius: CGFloat = 0
        let shape = RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
        // The content normally remains unclipped so key popups can rise above
        // the top row. Emoji glyphs are the exception: their grid stops just
        // inside the surface edge.
        return ZStack(alignment: .topLeading) {
            if state.areaMode == .emoji {
                content
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                    .clipShape(shape.inset(by: 2))
            } else {
                content
                    .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            }
        }
        .frame(width: frame.width, height: frame.height)
    }

    var voiceBoardUsesUIKitHits: Bool {
        // UIKit owns the voice-board hit layer, so no transparent SwiftUI
        // overlay can claim touches over the native controls.
        state.areaMode == .keys || state.areaMode == .recording
    }

    func appleControlSurface<Content: View, S: Shape>(
        _ content: Content,
        in shape: S,
        role: KeyboardChromeRole = .control
    ) -> some View {
        content.keyboardGlass(in: shape, role: role)
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
                            HapticFeedback.playInputClick()
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
    func voiceBoardChrome(
        text: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let hit = CGSize(
            width: VoiceOnlyKeyboardPolicy.controlSize,
            height: VoiceOnlyKeyboardPolicy.spacebarHeight
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
    func voiceBoardChrome(
        systemName: String,
        label: String,
        width: Double = VoiceOnlyKeyboardPolicy.controlSize,
        height: Double = VoiceOnlyKeyboardPolicy.spacebarHeight,
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
