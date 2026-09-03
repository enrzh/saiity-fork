// DictusKeyboard/Views/AuxiliaryBottomBar.swift
import SwiftUI
import DictusCore

/// Shared bottom control row for the Emoji and 123/symbols pages:
/// emoji, microphone, space, delete, return.
struct AuxiliaryBottomBar: View {
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
            roundControl(systemName: "face.smiling", label: "Emoji", action: onEmoji)
            roundControl(systemName: "mic.fill", label: "Return to voice keyboard", action: onVoice)

            Button(action: onSpace) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .overlay {
                        Text("space")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
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
