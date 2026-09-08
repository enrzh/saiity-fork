// DictusKeyboard/Views/AuxiliaryBottomBar.swift
import SwiftUI
import DictusCore

/// Shared bottom control row for the 123/symbols page:
/// emoji, microphone, space, return — order of the first two follows
/// `KeyboardAccessoryOrder` so Settings changes every page.
struct AuxiliaryBottomBar: View {
    let layout: VoiceOnlyKeyboardPolicy.Layout
    let onEmoji: () -> Void
    let onVoice: () -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void

    var body: some View {
        let left = layout.leftUtilityFrames
        let space = layout.spaceFrame
        let surface = layout.surfaceFrame
        let surfaceWidth = CGFloat(surface.width)
        let localX: (CGRect) -> CGFloat = { frame in
            CGFloat(frame.midX - surface.minX)
        }
        let returnFrame = layout.dismissFrame

        ZStack(alignment: .topLeading) {
            roundControl(systemName: "face.smiling", label: "Emoji", action: onEmoji)
                .position(x: localX(left.emoji), y: 22)
            roundControl(systemName: "mic.fill", label: "Return to voice keyboard", action: onVoice)
                .position(x: localX(layout.auxiliaryMicrophoneFrame), y: 22)
            spaceControl
                .frame(width: CGFloat(space.width), height: 44)
                .position(x: localX(space), y: 22)
            roundControl(systemName: "return", label: "Return", action: onReturn)
                .position(x: localX(returnFrame), y: 22)
        }
        .frame(width: surfaceWidth, height: 44)
    }

    private var spaceControl: some View {
        Button(action: onSpace) {
            Text("space")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize), maxHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize))
                .keyboardGlass(in: Capsule())
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Space")
    }

    private func roundControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(
                    width: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize),
                    height: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize)
                )
                .keyboardGlass(in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

}

/// Liquid-glass chrome matching the voice-page utility controls.
struct KeyboardGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast

    func body(content: Content) -> some View {
        if reduceTransparency || accessibilityContrast == .increased {
            content
                .background(shape.fill(Color(uiColor: accessibilityContrast == .increased ? .systemFill : .secondarySystemFill)))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(shape.fill(.regularMaterial))
        }
    }
}

extension View {
    func keyboardGlass<S: Shape>(in shape: S) -> some View {
        modifier(KeyboardGlassSurface(shape: shape))
    }
}
