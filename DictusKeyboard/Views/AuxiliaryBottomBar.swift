// DictusKeyboard/Views/AuxiliaryBottomBar.swift
import SwiftUI
import DictusCore

/// Shared native-style bottom control row for auxiliary keyboard surfaces.
/// Letter mode uses the same row for emoji, 123, space, back-to-dictation and return.
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
    var onLetters: (() -> Void)?

    var body: some View {
        let left = layout.leftUtilityFrames
        let surface = layout.surfaceFrame
        let surfaceWidth = CGFloat(surface.width)
        let localX: (CGRect) -> CGFloat = { frame in
            CGFloat(frame.midX - surface.minX)
        }
        ZStack(alignment: .topLeading) {
            if let onLetters {
                roundControl(text: "ABC", label: "Open letter keyboard", action: onLetters)
                    .position(x: localX(left.emoji), y: 22)
                roundControl(systemName: "face.smiling", label: "Emoji", action: onEmoji)
                    .position(x: localX(layout.auxiliaryMicrophoneFrame), y: 22)
            } else {
                roundControl(systemName: "face.smiling", label: "Emoji", action: onEmoji)
                    .position(x: localX(left.emoji), y: 22)
            }
            if showsSymbolsControl {
                roundControl(text: "123", label: "Open symbols keyboard", action: onSymbols)
                    .position(x: localX(layout.auxiliaryMicrophoneFrame), y: 22)
            } else if onLetters == nil && (backFrame == nil || backFrame?.isEmpty == true) {
                roundControl(systemName: "mic.fill", label: "Return to voice keyboard", action: onVoice)
                    .position(x: localX(layout.auxiliaryMicrophoneFrame), y: 22)
            }
            if let backFrame, !backFrame.isEmpty {
                roundControl(systemName: "mic.fill", label: "Back to dictation board", action: onVoice)
                    .position(x: localX(backFrame), y: 22)
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
    @State private var gestureStartDate: Date?

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
        // Global coordinates keep the gesture alive as the finger travels past
        // the capsule's visual edge, matching the native keyboard trackpad.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                if gestureStartDate == nil {
                    gestureStartDate = Date()
                }
                guard let gestureStartDate,
                      Date().timeIntervalSince(gestureStartDate) >= KeyboardDeletion.cursorHoldDuration else {
                    return
                }
                beginCursorTrackingIfNeeded()
                // One character per eight points keeps the control usable on both
                // narrow phones and wider iPads without flooding the proxy.
                let offset = Int((drag.translation.width / 8).rounded(.towardZero))
                let delta = offset - lastCursorOffset
                if delta != 0 {
                    lastCursorOffset = offset
                    onCursorMoved(delta)
                }
            }
            .onEnded { _ in
                let wasHeld = gestureStartDate.map {
                    Date().timeIntervalSince($0) >= KeyboardDeletion.cursorHoldDuration
                } ?? false
                defer {
                    cursorTracking = false
                    lastCursorOffset = 0
                    gestureStartDate = nil
                }
                if cursorTracking || wasHeld {
                    // A stationary long press enters cursor mode but does not
                    // insert a space on release, matching the native keyboard.
                    if !cursorTracking {
                        onCursorBegan()
                    }
                    onCursorEnded()
                } else {
                    HapticFeedback.keyTapped()
                    onTap()
                }
            }
    }

    private func beginCursorTrackingIfNeeded() {
        guard !cursorTracking else { return }
        cursorTracking = true
        lastCursorOffset = 0
        HapticFeedback.trackpadActivated()
        onCursorBegan()
    }
}

struct KeyboardDeleteButton: View {
    let onDelete: () -> Void
    let onDeleteWord: () -> Void
    let visualWidth: CGFloat
    let visualHeight: CGFloat
    let visualCornerRadius: CGFloat
    let hitWidth: CGFloat
    let hitHeight: CGFloat

    @State private var deleteRepeatTimer: Timer?
    @State private var deleteHoldTriggered = false
    @State private var deleteStartedAt = Date.distantPast

    init(
        onDelete: @escaping () -> Void,
        onDeleteWord: @escaping () -> Void,
        visualWidth: CGFloat = 80,
        visualHeight: CGFloat = 36,
        visualCornerRadius: CGFloat = 18,
        hitWidth: CGFloat = VoiceOnlyKeyboardPolicy.actionHitSize.width,
        hitHeight: CGFloat = VoiceOnlyKeyboardPolicy.actionHitSize.height
    ) {
        self.onDelete = onDelete
        self.onDeleteWord = onDeleteWord
        self.visualWidth = visualWidth
        self.visualHeight = visualHeight
        self.visualCornerRadius = visualCornerRadius
        self.hitWidth = hitWidth
        self.hitHeight = hitHeight
    }

    var body: some View {
        ZStack {
            Image(systemName: "delete.backward")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: visualWidth, height: visualHeight)
                .keyboardGlass(in: RoundedRectangle(cornerRadius: visualCornerRadius, style: .continuous))
            ImmediateTouchButton(
                onTouchDown: startDeleteRepeat,
                onTouchUp: {
                    stopDeleteRepeat()
                    deleteHoldTriggered = false
                }
            )
        }
        .frame(width: hitWidth, height: hitHeight)
        .contentShape(Rectangle())
        .accessibilityLabel("Delete backward")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onDelete() }
        .onDisappear {
            stopDeleteRepeat()
            deleteHoldTriggered = false
        }
    }

    private func startDeleteRepeat() {
        guard !deleteHoldTriggered else { return }
        stopDeleteRepeat()
        deleteHoldTriggered = true
        // One confirmation is enough. Repeating haptics at the deletion rate makes
        // a long hold feel like input noise and can be mistaken for repeated taps.
        HapticFeedback.keyTapped()
        onDelete()
        deleteStartedAt = Date()
        let timer = Timer(timeInterval: KeyboardDeletion.repeatInterval, repeats: true) { _ in
            switch KeyboardDeletion.repeatAction(after: Date().timeIntervalSince(deleteStartedAt)) {
            case .word:
                onDeleteWord()
            case .character:
                onDelete()
            }
        }
        timer.fireDate = Date().addingTimeInterval(KeyboardDeletion.repeatDelay)
        deleteRepeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }
}

/// UIKit forwards touchDown synchronously, which avoids the delayed first
/// deletion SwiftUI can introduce while resolving a drag gesture.
private struct ImmediateTouchButton: UIViewRepresentable {
    let onTouchDown: () -> Void
    let onTouchUp: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTouchDown: onTouchDown, onTouchUp: onTouchUp) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.backgroundColor = .clear
        button.addTarget(context.coordinator, action: #selector(Coordinator.touchDown), for: .touchDown)
        button.addTarget(context.coordinator, action: #selector(Coordinator.touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.onTouchDown = onTouchDown
        context.coordinator.onTouchUp = onTouchUp
    }

    final class Coordinator: NSObject {
        var onTouchDown: () -> Void
        var onTouchUp: () -> Void

        init(onTouchDown: @escaping () -> Void, onTouchUp: @escaping () -> Void) {
            self.onTouchDown = onTouchDown
            self.onTouchUp = onTouchUp
        }

        @objc func touchDown() { onTouchDown() }
        @objc func touchUp() { onTouchUp() }
    }
}

/// Lightweight UIKit touch routing for ordinary keyboard keys.
/// SwiftUI buttons wait for their gesture resolver before invoking the action;
/// this adapter prepares feedback on contact and delivers the action directly
/// from UIKit's touch-up-inside event.
struct ImmediateKeyButton: UIViewRepresentable {
    let onTouchDown: () -> Void
    let onTouchUp: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTouchDown: onTouchDown, onTouchUp: onTouchUp)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = ImmediateKeyControl(type: .custom)
        button.backgroundColor = .clear
        // Consecutive fingers overlap during fast typing. Exclusive touch drops
        // the second key while the first finger is still down.
        button.isExclusiveTouch = false
        button.addTarget(context.coordinator, action: #selector(Coordinator.touchDown), for: .touchDown)
        button.addTarget(context.coordinator, action: #selector(Coordinator.touchUp), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.onTouchDown = onTouchDown
        context.coordinator.onTouchUp = onTouchUp
    }

    final class Coordinator: NSObject {
        var onTouchDown: () -> Void
        var onTouchUp: () -> Void

        init(onTouchDown: @escaping () -> Void, onTouchUp: @escaping () -> Void) {
            self.onTouchDown = onTouchDown
            self.onTouchUp = onTouchUp
        }

        @objc func touchDown() { onTouchDown() }
        @objc func touchUp() { onTouchUp() }
    }
}

private final class ImmediateKeyControl: UIButton {
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.label.withAlphaComponent(0.12)
                : .clear
            layer.borderWidth = isHighlighted ? 1 : 0
            layer.borderColor = isHighlighted
                ? UIColor.label.withAlphaComponent(0.16).cgColor
                : nil
            layer.cornerRadius = 13
        }
    }
}

/// A single UIKit tracking owner delivers accent-key input without waiting for
/// SwiftUI's drag recognizer. Movement continues outside the original key.
struct ImmediateVariantKey: UIViewRepresentable {
    let onBegan: (CGPoint) -> Void
    let onMoved: (CGPoint) -> Void
    let onEnded: (Bool) -> Void

    func makeUIView(context: Context) -> TrackingKey { TrackingKey() }

    func updateUIView(_ view: TrackingKey, context: Context) {
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
    }

    final class TrackingKey: UIControl {
        var onBegan: ((CGPoint) -> Void)?
        var onMoved: ((CGPoint) -> Void)?
        var onEnded: ((Bool) -> Void)?
        private var activeMove: ((CGPoint) -> Void)?
        private var activeEnd: ((Bool) -> Void)?

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            activeMove = onMoved
            activeEnd = onEnded
            backgroundColor = UIColor.label.withAlphaComponent(0.12)
            layer.cornerRadius = 13
            onBegan?(touch.location(in: self))
            return true
        }

        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            activeMove?(touch.location(in: self))
            return true
        }

        override func endTracking(_ touch: UITouch?, with event: UIEvent?) { finish(cancelled: false) }
        override func cancelTracking(with event: UIEvent?) { finish(cancelled: true) }

        private func finish(cancelled: Bool) {
            let completion = activeEnd
            activeEnd = nil
            activeMove = nil
            backgroundColor = .clear
            completion?(cancelled)
        }
    }
}

private extension AuxiliaryBottomBar {
    private func roundControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.keyTapped()
            action()
        } label: {
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
        Button {
            HapticFeedback.keyTapped()
            action()
        } label: {
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
        Button {
            HapticFeedback.keyTapped()
            action()
        } label: {
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
