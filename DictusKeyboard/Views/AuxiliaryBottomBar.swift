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
    let onSymbols: () -> Void
    let showsSymbolsControl: Bool
    let spaceFrame: CGRect
    let returnFrame: CGRect
    let onSpace: () -> Void
    let onSpaceCursorBegan: () -> Void
    let onSpaceCursorMoved: (Int) -> Void
    let onSpaceCursorEnded: () -> Void
    let onReturn: () -> Void
    let backFrame: CGRect?

    var body: some View {
        let left = layout.leftUtilityFrames
        let surface = layout.surfaceFrame
        let surfaceWidth = CGFloat(surface.width)
        let localX: (CGRect) -> CGFloat = { frame in
            CGFloat(frame.midX - surface.minX)
        }
        ZStack(alignment: .topLeading) {
            roundControl(systemName: "face.smiling", label: "Emoji", action: onEmoji)
                .position(x: localX(left.emoji), y: 22)
            if let backFrame, !backFrame.isEmpty {
                roundControl(systemName: "mic.fill", label: "Back to dictation board", action: onVoice)
                    .position(x: localX(backFrame), y: 22)
            } else {
                Group {
                    if showsSymbolsControl {
                        roundControl(text: "123", label: "Open symbols keyboard", action: onSymbols)
                    } else {
                        roundControl(systemName: "mic.fill", label: "Return to voice keyboard", action: onVoice)
                    }
                }
                    .position(x: localX(layout.auxiliaryMicrophoneFrame), y: 22)
            }
            SpaceBarControl(
                onTap: onSpace,
                onCursorBegan: onSpaceCursorBegan,
                onCursorMoved: onSpaceCursorMoved,
                onCursorEnded: onSpaceCursorEnded
            )
                .frame(width: CGFloat(spaceFrame.width), height: 44)
                .position(x: localX(spaceFrame), y: 22)
            wideControl(systemName: "return", label: "Return", action: onReturn)
                .position(x: localX(returnFrame), y: 22)
        }
        .frame(width: surfaceWidth, height: 44)
    }

}

/// Shared spacebar gesture for every SwiftUI keyboard page. A quick tap inserts
/// a space; a held horizontal drag routes character offsets to the host field.
struct SpaceBarControl: View {
    let onTap: () -> Void
    let onCursorBegan: () -> Void
    let onCursorMoved: (Int) -> Void
    let onCursorEnded: () -> Void

    @State private var cursorTracking = false
    @State private var lastCursorOffset = 0

    var body: some View {
        Text("space")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize), maxHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize))
            .keyboardGlass(in: Capsule())
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Space")
            .gesture(cursorGesture)
    }

    private var cursorGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if !cursorTracking {
                    cursorTracking = true
                    lastCursorOffset = 0
                    onCursorBegan()
                }
                // One character per eight points keeps the control usable on both
                // narrow phones and wider iPads without flooding the proxy.
                let offset = Int((drag.translation.width / 8).rounded(.towardZero))
                let delta = offset - lastCursorOffset
                if delta != 0 {
                    lastCursorOffset = offset
                    onCursorMoved(delta)
                }
            }
            .onEnded { value in
                defer {
                    cursorTracking = false
                    lastCursorOffset = 0
                }
                if case .second(true, _) = value {
                    onCursorEnded()
                } else {
                    onTap()
                }
            }
    }
}

struct KeyboardDeleteButton: View {
    let onDelete: () -> Void

    @State private var deleteRepeatTimer: Timer?
    @State private var deleteRepeatStarted = false

    var body: some View {
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
                .frame(width: 80, height: 36)
                .keyboardGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(width: VoiceOnlyKeyboardPolicy.actionHitSize.width,
                       height: VoiceOnlyKeyboardPolicy.actionHitSize.height)
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
        .onDisappear { stopDeleteRepeat() }
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

private extension AuxiliaryBottomBar {
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

    private func roundControl(text: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
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

    private func wideControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 80, height: 36)
                .keyboardGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(width: VoiceOnlyKeyboardPolicy.actionHitSize.width,
                       height: VoiceOnlyKeyboardPolicy.actionHitSize.height)
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
