import SwiftUI
import UIKit
import DictusCore
/// Observable bridge from a UIKit touch owner to the SwiftUI face drawn beside
/// it.
///
/// WHY this exists: the press state used to live only on the UIKit control. The
/// visible key face is a *sibling* of that control, so it never observed
/// `isHighlighted` and could not animate — the key registered a touch while the
/// face stayed inert. The owner now publishes here and the face reads it.
final class KeyboardPressState: ObservableObject {
    @Published var isPressed = false
}

/// Pairs a key face with the UIKit control that owns its touch and binds the
/// face's pressed appearance to that control's published state.
///
/// This is the single place the two layers meet. Before it existed the control
/// and the face were independent siblings, so a key could register a tap while
/// showing nothing at all.
struct PressLinkedKeyFace<Face: View>: View {
    @StateObject private var pressState = KeyboardPressState()
    private let face: (Bool) -> Face
    private let hit: CGSize
    private let highlightSize: CGSize
    private let action: () -> Void

    init(
        face: @escaping (Bool) -> Face,
        hit: CGSize,
        highlightSize: CGSize,
        action: @escaping () -> Void
    ) {
        self.face = face
        self.hit = hit
        self.highlightSize = highlightSize
        self.action = action
    }

    var body: some View {
        ZStack {
            face(pressState.isPressed)
            ImmediateKeyButton(
                onTouchDown: {
                    HapticFeedback.playInputClick()
                    action()
                },
                onTouchUp: {},
                highlightCornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
                highlightSize: highlightSize,
                pressState: pressState
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: hit.width, height: hit.height)
        .contentShape(Rectangle())
    }
}

/// Tap/hold adapter used by every non-variant key surface.
struct ImmediateKeyButton: UIViewRepresentable {
    let onTouchDown: () -> Void
    let onTouchUp: () -> Void
    var highlightCornerRadius: CGFloat = 13
    var highlightSize: CGSize?
    var holdDuration: TimeInterval? = nil
    var onHold: (() -> Void)? = nil
    /// Optional sink so a sibling face can animate from this control's press.
    var pressState: KeyboardPressState? = nil

    func makeUIView(context: Context) -> KeyboardKeyTouchControl {
        let control = KeyboardKeyTouchControl()
        update(control)
        return control
    }

    func updateUIView(_ control: KeyboardKeyTouchControl, context: Context) {
        update(control)
    }

    private func update(_ control: KeyboardKeyTouchControl) {
        control.highlightCornerRadius = highlightCornerRadius
        control.highlightSize = highlightSize
        control.holdDuration = holdDuration
        control.onHold = onHold
        control.pressState = pressState
        control.onBegan = { _ in
            if holdDuration == nil { onTouchDown() }
        }
        control.onMoved = { _ in }
        control.onEnded = { _ in
            onTouchUp()
        }
    }
}

/// Drag-tracking adapter for accent and punctuation variants, backed by the
/// same UIKit control and release lifecycle as ordinary tap keys.
struct ImmediateVariantKey: UIViewRepresentable {
    let onBegan: (CGPoint) -> Void
    let onMoved: (CGPoint) -> Void
    let onEnded: (Bool) -> Void
    /// Optional sink so a sibling face can animate from this control's press.
    var pressState: KeyboardPressState? = nil

    func makeUIView(context: Context) -> KeyboardKeyTouchControl {
        let control = KeyboardKeyTouchControl()
        update(control)
        return control
    }

    func updateUIView(_ control: KeyboardKeyTouchControl, context: Context) {
        update(control)
    }

    private func update(_ control: KeyboardKeyTouchControl) {
        control.holdDuration = nil
        control.onHold = nil
        // Variant keys never set a highlight size, which used to suppress the
        // control's own highlight entirely. Default to the control bounds so
        // every key has visible press feedback.
        control.highlightSize = nil
        control.pressState = pressState
        control.onBegan = onBegan
        control.onMoved = onMoved
        control.onEnded = { cancelled in
            onEnded(cancelled)
        }
    }
}

/// Stable native target with local press feedback and release-safe tracking.
/// UIKit chooses this control once on touch-down; key ownership cannot change
/// because a prediction or visual-material update changes another key's frame.
final class KeyboardKeyTouchControl: UIControl {
    var highlightCornerRadius: CGFloat = 13 {
        didSet { setNeedsLayout() }
    }
    var highlightSize: CGSize? {
        didSet { setNeedsLayout() }
    }
    var holdDuration: TimeInterval?
    var onBegan: ((CGPoint) -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var onEnded: ((Bool) -> Void)?
    var onHold: (() -> Void)?
    /// Sink for a sibling SwiftUI face. See `KeyboardPressState`.
    var pressState: KeyboardPressState?

    private let highlightLayer = CALayer()
    private var activeTouches: [ObjectIdentifier: UITouch] = [:]
    /// The touch that opened this key's interaction. Its release commits the
    /// action even if other fingers are still resting on the key — otherwise a
    /// second finger parked on the same key swallows the first finger's action
    /// and the key looks completely dead.
    private var primaryTouchID: ObjectIdentifier?
    private var activeMove: ((CGPoint) -> Void)?
    private var activeEnd: ((Bool) -> Void)?
    private var activeHold: (() -> Void)?
    private var activeHoldDuration: TimeInterval?
    private var holdTimer: Timer?
    private var holdRecognized = false
    /// Event timestamp of the interaction currently in flight, used to correlate
    /// this control's trace lines with the input view and overlay stages. It is a
    /// timestamp only, never key content.
    private var lastEventTimestamp: TimeInterval = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        layer.addSublayer(highlightLayer)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastEventTimestamp = event?.timestamp ?? lastEventTimestamp
        if activeTouches.isEmpty {
            activeMove = onMoved
            activeEnd = onEnded
            activeHold = onHold
            activeHoldDuration = holdDuration.flatMap { $0 > 0 ? $0 : nil }
            holdRecognized = false
            isHighlighted = true
            if let activeHoldDuration {
                let timer = Timer(timeInterval: activeHoldDuration, repeats: false) { [weak self] _ in
                    guard let self, !self.activeTouches.isEmpty else { return }
                    self.holdRecognized = true
                    self.activeHold?()
                }
                holdTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }

        for touch in touches {
            let id = ObjectIdentifier(touch)
            activeTouches[id] = touch
            if primaryTouchID == nil { primaryTouchID = id }
            onBegan?(touch.location(in: self))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastEventTimestamp = event?.timestamp ?? lastEventTimestamp
        guard let touch = activeTouches.values.first(where: { touches.contains($0) })
                ?? activeTouches.values.first else { return }
        activeMove?(touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastEventTimestamp = event?.timestamp ?? lastEventTimestamp
        var primaryEnded = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            activeTouches.removeValue(forKey: id)
            if id == primaryTouchID {
                primaryEnded = true
                primaryTouchID = nil
            }
        }
        // Commit on the primary finger's release. Waiting for every finger to
        // lift meant one stray second finger made the key silently do nothing.
        if primaryEnded {
            finish(cancelled: false)
            return
        }
        guard activeTouches.isEmpty else { return }
        finish(cancelled: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastEventTimestamp = event?.timestamp ?? lastEventTimestamp
        // `touchesCancelled` is terminal for the touches it carries: UIKit has
        // already taken them away and will never deliver another event for them.
        //
        // This used to re-derive liveness from `event.allTouches` and keep any
        // touch that was not in that set. That was wrong: a touch which drifted
        // a single point off the key is still present in the event's touch list
        // with phase `.moved` and `view === self`, so it was treated as alive,
        // `finish` never ran, and the character was silently skipped. Exact-bounds
        // hit testing makes a one-point drift enough to trigger this, which is
        // why it showed up specifically as dropped characters during fast
        // two-finger typing.
        var primaryCancelled = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            activeTouches.removeValue(forKey: id)
            if id == primaryTouchID {
                primaryCancelled = true
                primaryTouchID = nil
            }
        }
        if primaryCancelled {
            finish(cancelled: true)
            return
        }
        guard activeTouches.isEmpty else { return }
        finish(cancelled: true)
    }

    private func finish(cancelled: Bool) {
        holdTimer?.invalidate()
        holdTimer = nil
        let end = activeEnd
        let shouldEnd = activeHoldDuration == nil || holdRecognized
        activeTouches.removeAll()
        primaryTouchID = nil
        activeMove = nil
        activeEnd = nil
        activeHold = nil
        activeHoldDuration = nil
        holdRecognized = false
        isHighlighted = false
        if shouldEnd { end?(cancelled) }
    }

    override var isHighlighted: Bool {
        didSet {
            pressState?.isPressed = isHighlighted
            // The layer is the control's own feedback. Animate it so a press
            // reads as a press; the old path disabled implicit animation, which
            // is why every key felt like it had no response.
            let wantsFill = isHighlighted
            CATransaction.begin()
            CATransaction.setAnimationDuration(wantsFill ? 0.08 : 0.14)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            highlightLayer.backgroundColor = wantsFill
                ? UIColor.label.withAlphaComponent(0.12).cgColor
                : UIColor.clear.cgColor
            highlightLayer.borderWidth = 0
            highlightLayer.borderColor = nil
            highlightLayer.cornerRadius = highlightCornerRadius
            CATransaction.commit()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = highlightSize ?? bounds.size
        highlightLayer.frame = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        highlightLayer.cornerRadius = highlightCornerRadius
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}
