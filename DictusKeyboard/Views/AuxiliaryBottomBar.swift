// DictusKeyboard/Views/AuxiliaryBottomBar.swift
import SwiftUI
import DictusCore

/// Shared bottom control row for the 123/symbols page:
/// emoji, microphone, space, delete, return — order of the first two follows
/// `KeyboardAccessoryOrder` so Settings changes every page.
struct AuxiliaryBottomBar: View {
    var controlOrder: KeyboardAccessoryOrder = .emojiFirst
    let onEmoji: () -> Void
    let onVoice: () -> Void
    let onSpace: () -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void

    @State private var deleteRepeatTimer: Timer?
    @State private var deleteRepeatStarted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            switch controlOrder {
            case .emojiFirst:
                roundControl(systemName: "face.smiling", label: "Emoji", action: onEmoji)
                roundControl(systemName: "mic.fill", label: "Return to voice keyboard", action: onVoice)
            case .numberFirst:
                roundControl(systemName: "mic.fill", label: "Return to voice keyboard", action: onVoice)
                roundControl(systemName: "face.smiling", label: "Emoji", action: onEmoji)
            }

            Button(action: onSpace) {
                Text("space")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize), maxHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize))
                    .keyboardGlass(in: Capsule())
                    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Space")

            deleteControl
            roundControl(systemName: "return", label: "Return", action: onReturn)
        }
        .padding(.horizontal, CGFloat(VoiceOnlyKeyboardPolicy.horizontalPadding))
        .frame(minHeight: 44, maxHeight: 44)
        .onDisappear { stopDeleteRepeat() }
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

    private var deleteControl: some View {
        Button {
            if deleteRepeatStarted {
                deleteRepeatStarted = false
                return
            }
            onDelete()
        } label: {
            Image(systemName: "delete.backward")
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
        .accessibilityLabel("Delete backward")
        .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
            if pressing {
                startDeleteRepeat()
            } else {
                stopDeleteRepeat()
            }
        }, perform: {})
    }

    private func startDeleteRepeat() {
        stopDeleteRepeat()
        deleteRepeatStarted = true
        onDelete()
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            onDelete()
        }
        deleteRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
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
