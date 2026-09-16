// DictusKeyboard/Views/AuxiliaryBottomBar.swift
import SwiftUI
import DictusCore

/// Stable weak references used only by the invisible letter-boundary router.
/// The router forwards to these existing controls so UIKit keeps their normal
/// press, hold, cancellation, haptic, and accessibility behavior.
final class AdaptiveTouchControlRegistry {
    static let shared = AdaptiveTouchControlRegistry()

    private final class Entry {
        weak var control: UIView?
        let scopeID: String

        init(_ control: UIView, scopeID: String) {
            self.control = control
            self.scopeID = scopeID
        }
    }

    private var entries: [String: Entry] = [:]

    func register(_ control: UIView, for keyID: String, scopeID: String) {
        entries[keyID] = Entry(control, scopeID: scopeID)
    }

    func unregister(_ keyID: String, control: UIView) {
        guard entries[keyID]?.control === control else { return }
        entries.removeValue(forKey: keyID)
    }

    func control(for keyID: String, in window: UIWindow, scopeID: String) -> UIView? {
        guard let entry = entries[keyID],
              entry.scopeID == scopeID,
              let control = entry.control,
              control.window === window else {
            return nil
        }
        var view: UIView? = control
        while let current = view {
            guard !current.isHidden, current.alpha > 0 else { return nil }
            view = current.superview
        }
        return control
    }
}

/// Shared native-style bottom control row for auxiliary keyboard surfaces.
/// ABC and 123 pages use compact 123/ABC, then emoji, space, and return.
/// Emoji pages keep compact 123 + ABC and give the leftover width to space.
struct AuxiliaryBottomBar: View {
    let layout: VoiceOnlyKeyboardPolicy.Layout
    let numbersTitle: String
    let onNumbers: () -> Void
    let onLetters: () -> Void
    let onEmoji: () -> Void
    let spaceFrame: CGRect
    let returnFrame: CGRect
    let onSpace: () -> Void
    let onSpaceCursorBegan: () -> Void
    let onSpaceCursorMoved: (KeyboardCursorStep) -> Void
    let onSpaceCursorEnded: () -> Void
    let onReturn: () -> Void
    var showsNumbersControl: Bool = true
    var showsLettersControl: Bool = true
    var showsEmojiControl: Bool = true

    var body: some View {
        let surface = layout.surfaceFrame
        let surfaceWidth = CGFloat(surface.width)
        let barOriginY = CGFloat(layout.chromeBottomBarOriginY)
        let rowHeight = CGFloat(VoiceOnlyKeyboardPolicy.spacebarHeight)
        let localX: (CGRect) -> CGFloat = { frame in
            CGFloat(frame.midX - surface.minX)
        }
        let localY: (CGRect) -> CGFloat = { frame in
            CGFloat(frame.midY - barOriginY)
        }
        let compactMode = layout.chromeNumbersFrame
        ZStack(alignment: .topLeading) {
            if showsNumbersControl && showsLettersControl {
                roundControl(text: numbersTitle, label: "Open symbols keyboard", action: onNumbers)
                    .position(x: localX(layout.chromeNumbersFrame), y: localY(layout.chromeNumbersFrame))
                roundControl(text: "ABC", label: "Open letter keyboard", action: onLetters)
                    .position(x: localX(layout.chromeLettersFrame), y: localY(layout.chromeLettersFrame))
            } else if showsNumbersControl {
                roundControl(text: numbersTitle, label: "Open symbols keyboard", action: onNumbers)
                    .position(x: localX(compactMode), y: localY(compactMode))
            } else if showsLettersControl {
                roundControl(text: "ABC", label: "Open letter keyboard", action: onLetters)
                    .position(x: localX(compactMode), y: localY(compactMode))
            }
            if showsEmojiControl {
                roundControl(systemName: "face.smiling", label: "Emoji", action: onEmoji)
                    .position(x: localX(layout.chromeLettersFrame), y: localY(layout.chromeLettersFrame))
            }
            SpaceBarControl(
                onTap: onSpace,
                onCursorBegan: onSpaceCursorBegan,
                onCursorMoved: onSpaceCursorMoved,
                onCursorEnded: onSpaceCursorEnded
            )
                .frame(width: CGFloat(spaceFrame.width), height: CGFloat(spaceFrame.height))
                .position(x: localX(spaceFrame), y: localY(spaceFrame))
            wideControl(systemName: "return", label: "Return", action: onReturn)
                .position(x: localX(returnFrame), y: localY(returnFrame))
        }
        .frame(width: surfaceWidth, height: rowHeight, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .center)
    }

}

/// Circular accessory-lane control with even inset from the suggestion bar edge.
struct SuggestionBarIconButton: View {
    let systemName: String
    let label: String
    let laneSize: CGSize
    let action: () -> Void

    private var visualDiameter: CGFloat {
        min(laneSize.width, laneSize.height) - VoiceOnlyKeyboardPolicy.suggestionLaneControlInset * 2
    }

    var body: some View {
        ZStack {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: visualDiameter, height: visualDiameter)
                .keyboardGlass(in: Circle())
            ImmediateKeyButton(
                onTouchDown: {
                    HapticFeedback.keyTapped()
                    action()
                },
                onTouchUp: {},
                highlightCornerRadius: visualDiameter / 2,
                highlightSize: CGSize(width: visualDiameter, height: visualDiameter)
            )
        }
        .frame(width: laneSize.width, height: laneSize.height)
        .contentShape(Circle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

/// Shared spacebar gesture for every SwiftUI keyboard page. A quick tap inserts
/// a space; a held press tracks finger travel like the native spacebar.
struct SpaceBarControl: View {
    let onTap: () -> Void
    let onCursorBegan: () -> Void
    let onCursorMoved: (KeyboardCursorStep) -> Void
    let onCursorEnded: () -> Void

    var body: some View {
        ZStack {
            Text("space")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize), maxHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize))
                .commandKeyPlate(cornerRadius: 18)
            SpaceTrackingButton(
                onTap: onTap,
                onCursorBegan: onCursorBegan,
                onCursorMoved: onCursorMoved,
                onCursorEnded: onCursorEnded
            )
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Space")
        .accessibilityAddTraits(.isButton)
    }
}

/// UIKit tracks one finger independently from every other key control. Movement
/// deltas move the caret immediately, including after the finger leaves the
/// visible capsule; a stationary finger is inert.
private struct SpaceTrackingButton: UIViewRepresentable {
    let onTap: () -> Void
    let onCursorBegan: () -> Void
    let onCursorMoved: (KeyboardCursorStep) -> Void
    let onCursorEnded: () -> Void

    func makeUIView(context: Context) -> TrackingControl {
        let control = TrackingControl()
        control.onTap = onTap
        control.onCursorBegan = onCursorBegan
        control.onCursorMoved = onCursorMoved
        control.onCursorEnded = onCursorEnded
        return control
    }

    func updateUIView(_ uiView: TrackingControl, context: Context) {
        uiView.onTap = onTap
        uiView.onCursorBegan = onCursorBegan
        uiView.onCursorMoved = onCursorMoved
        uiView.onCursorEnded = onCursorEnded
    }

    final class TrackingControl: UIControl {
        var onTap: (() -> Void)?
        var onCursorBegan: (() -> Void)?
        var onCursorMoved: ((KeyboardCursorStep) -> Void)?
        var onCursorEnded: (() -> Void)?

        private var startedAt: Date?
        private weak var trackingCoordinateView: UIView?
        private var joystickOrigin: CGPoint?
        private var joystickSampler: KeyboardCursorJoystickSampler?
        private var latestTouchPoint: CGPoint?
        private var isCursorTracking = false
        private var cursorTimer: Timer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
            backgroundColor = .clear
            installCursorPanRecognizer()
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if startedAt != nil { return true }
            return bounds.insetBy(dx: -2, dy: -2).contains(point)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
            backgroundColor = .clear
            installCursorPanRecognizer()
        }

        /// UIControl normally keeps tracking outside its bounds, but keyboard
        /// hosting can hand the touch to an edge recognizer once the finger
        /// leaves the visual spacebar. The pan recognizer keeps receiving the
        /// same touch stream, including positions beyond the control's frame.
        private func installCursorPanRecognizer() {
            let recognizer = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleCursorPan(_:))
            )
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.minimumNumberOfTouches = 1
            recognizer.maximumNumberOfTouches = 1
            addGestureRecognizer(recognizer)

            let hold = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleCursorPan(_:))
            )
            hold.minimumPressDuration = KeyboardDeletion.cursorHoldDuration
            hold.allowableMovement = 10_000
            hold.cancelsTouchesInView = false
            hold.delaysTouchesBegan = false
            hold.delaysTouchesEnded = false
            addGestureRecognizer(hold)
        }

        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            startedAt = Date()
            trackingCoordinateView = window ?? superview ?? self
            let point = trackingPoint(for: touch)
            joystickOrigin = point
            joystickSampler = nil
            latestTouchPoint = point
            isCursorTracking = false
            HapticFeedback.prepareForNextTap()
            stopJoystickClock()
            let holdTimer = Timer(
                timeInterval: KeyboardDeletion.cursorHoldDuration,
                repeats: false
            ) { [weak self] _ in
                self?.activateCursorTracking()
            }
            RunLoop.main.add(holdTimer, forMode: .common)
            cursorTimer = holdTimer
            return true
        }

        override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            processTouch(at: trackingPoint(for: touch))
            return true
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let touch = touches.first {
                processTouch(at: trackingPoint(for: touch))
            }
            super.touchesMoved(touches, with: event)
        }

        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            if let touch {
                processTouch(at: trackingPoint(for: touch))
            }
            finish(wasCancelled: false)
        }

        override func cancelTracking(with event: UIEvent?) {
            finish(wasCancelled: true)
        }

        @objc private func handleCursorPan(_ recognizer: UIGestureRecognizer) {
            guard startedAt != nil else { return }

            switch recognizer.state {
            case .began, .changed:
                processTouch(at: trackingPoint(for: recognizer))
            case .ended, .cancelled, .failed:
                // Keep joystick mode until the finger lifts. A pan can end
                // while UIControl is still tracking that same touch.
                if !isTracking {
                    finish(wasCancelled: recognizer.state != .ended)
                }
            default:
                break
            }
        }

        private func trackingPoint(for touch: UITouch) -> CGPoint {
            touch.location(in: trackingCoordinateView ?? self)
        }

        private func trackingPoint(for recognizer: UIGestureRecognizer) -> CGPoint {
            recognizer.location(in: trackingCoordinateView ?? self)
        }

        private func processTouch(at point: CGPoint) {
            guard startedAt != nil else { return }
            latestTouchPoint = point
            if !isCursorTracking,
               Date().timeIntervalSince(startedAt ?? .distantPast) >= KeyboardDeletion.cursorHoldDuration {
                activateCursorTracking()
            }
            emitJoystickStep()
        }

        private func finish(wasCancelled: Bool) {
            guard startedAt != nil else { return }
            stopJoystickClock()
            defer {
                startedAt = nil
                trackingCoordinateView = nil
                joystickOrigin = nil
                joystickSampler = nil
                latestTouchPoint = nil
                isCursorTracking = false
            }
            if isCursorTracking {
                onCursorEnded?()
            } else if !wasCancelled {
                HapticFeedback.keyTapped()
                onTap?()
            }
        }

        private func activateCursorTracking() {
            guard !isCursorTracking, startedAt != nil else { return }
            isCursorTracking = true
            if let origin = joystickOrigin {
                joystickSampler = KeyboardCursorJoystickSampler(origin: origin)
            }
            onCursorBegan?()
            emitJoystickStep(force: true)
        }

        private func stopJoystickClock() {
            cursorTimer?.invalidate()
            cursorTimer = nil
        }

        private func emitJoystickStep(force: Bool = false) {
            guard isCursorTracking,
                  let origin = joystickOrigin,
                  let point = latestTouchPoint else { return }
            if joystickSampler == nil {
                joystickSampler = KeyboardCursorJoystickSampler(origin: origin)
            }
            guard var sampler = joystickSampler else { return }
            let step = sampler.tick(
                to: point,
                now: Date.timeIntervalSinceReferenceDate,
                force: force
            )
            joystickSampler = sampler
            guard !step.isEmpty else { return }
            onCursorMoved?(step)
        }

        deinit {
            stopJoystickClock()
        }
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
                .commandKeyPlate(cornerRadius: visualCornerRadius)
            DeleteRepeatControl(
                onDelete: onDelete,
                onDeleteWord: onDeleteWord
            )
        }
        .frame(width: hitWidth, height: hitHeight)
        .contentShape(Rectangle())
        .accessibilityLabel("Delete backward")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onDelete() }
    }
}

/// UIKit owns the full delete lifecycle. Keeping the repeat timer beside the
/// touch owner prevents a SwiftUI state update from recreating the control while
/// a finger is still down.
private struct DeleteRepeatControl: UIViewRepresentable {
    let onDelete: () -> Void
    let onDeleteWord: () -> Void

    func makeUIView(context: Context) -> KeyboardDeleteRepeatControl {
        let control = KeyboardDeleteRepeatControl()
        control.onDelete = onDelete
        control.onDeleteWord = onDeleteWord
        return control
    }

    func updateUIView(_ uiView: KeyboardDeleteRepeatControl, context: Context) {
        uiView.onDelete = onDelete
        uiView.onDeleteWord = onDeleteWord
    }
}

/// UIKit delete owner shared by SwiftUI keys and the dictation-board overlay.
final class KeyboardDeleteRepeatControl: UIControl {
    var onDelete: (() -> Void)?
    var onDeleteWord: (() -> Void)?

    private var isDeleting = false
    private var startedAt = Date.distantPast
    private var repeatTimer: Timer?

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
        accessibilityIdentifier = "board-delete"
        accessibilityLabel = "Delete backward"
        accessibilityTraits = .button
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -2, dy: -2).contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isDeleting else { return }
        isDeleting = true
        startedAt = Date()
        isHighlighted = true
        HapticFeedback.keyTapped()
        onDelete?()

        let timer = Timer(timeInterval: KeyboardDeletion.repeatInterval, repeats: true) { [weak self] _ in
            self?.repeatDelete()
        }
        timer.fireDate = Date().addingTimeInterval(KeyboardDeletion.repeatDelay)
        repeatTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish()
    }

    private func repeatDelete() {
        guard isDeleting else { return }
        HapticFeedback.prepareForNextTap()
        HapticFeedback.keyTapped()
        switch KeyboardDeletion.repeatAction(after: Date().timeIntervalSince(startedAt)) {
        case .word:
            onDeleteWord?()
        case .character:
            onDelete?()
        }
    }

    private func finish() {
        guard isDeleting else { return }
        repeatTimer?.invalidate()
        repeatTimer = nil
        isDeleting = false
        startedAt = .distantPast
        isHighlighted = false
    }

    deinit {
        repeatTimer?.invalidate()
    }
}

/// Lightweight UIKit touch routing for ordinary keyboard keys.
/// SwiftUI buttons wait for their gesture resolver before invoking the action;
/// this adapter delivers the action directly from the control's touch-down.
struct ImmediateKeyButton: UIViewRepresentable {
    let onTouchDown: () -> Void
    let onTouchUp: () -> Void
    var highlightCornerRadius: CGFloat = 13
    var highlightSize: CGSize?
    var adaptiveKeyID: String?
    var adaptiveTouchScopeID: String?

    func makeUIView(context: Context) -> UIView {
        let button = ImmediateKeyControl(frame: .zero)
        button.highlightCornerRadius = highlightCornerRadius
        button.highlightSize = highlightSize
        button.isMultipleTouchEnabled = true
        button.isExclusiveTouch = false
        button.hitExpansion = 6
        button.adaptiveTouchScopeID = adaptiveTouchScopeID
        button.adaptiveKeyID = adaptiveKeyID
        button.onTouchDown = onTouchDown
        button.onTouchUp = onTouchUp
        return button
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let uiView = uiView as? ImmediateKeyControl else { return }
        uiView.highlightCornerRadius = highlightCornerRadius
        uiView.highlightSize = highlightSize
        uiView.isMultipleTouchEnabled = true
        uiView.isExclusiveTouch = false
        uiView.hitExpansion = 6
        uiView.adaptiveTouchScopeID = adaptiveTouchScopeID
        uiView.adaptiveKeyID = adaptiveKeyID
        uiView.onTouchDown = onTouchDown
        uiView.onTouchUp = onTouchUp
    }
}

private final class ImmediateKeyControl: UIControl {
    var highlightCornerRadius: CGFloat = 13
    var highlightSize: CGSize? {
        didSet {
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
    }
    private let highlightLayer = CALayer()
    var hitExpansion: CGFloat = 6
    var adaptiveTouchScopeID: String? {
        willSet {
            guard adaptiveKeyID != nil, adaptiveTouchScopeID != newValue,
                  let adaptiveKeyID else { return }
            AdaptiveTouchControlRegistry.shared.unregister(adaptiveKeyID, control: self)
        }
        didSet { registerAdaptiveKey() }
    }
    var adaptiveKeyID: String? {
        willSet {
            if let adaptiveKeyID, adaptiveKeyID != newValue {
                AdaptiveTouchControlRegistry.shared.unregister(adaptiveKeyID, control: self)
            }
        }
        didSet { registerAdaptiveKey() }
    }
    var onTouchDown: (() -> Void)?
    var onTouchUp: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
        layer.addSublayer(highlightLayer)
    }

    deinit {
        if let adaptiveKeyID {
            AdaptiveTouchControlRegistry.shared.unregister(adaptiveKeyID, control: self)
        }
    }

    private func registerAdaptiveKey() {
        guard let adaptiveKeyID, let adaptiveTouchScopeID else { return }
        AdaptiveTouchControlRegistry.shared.register(
            self, for: adaptiveKeyID, scopeID: adaptiveTouchScopeID
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
        layer.addSublayer(highlightLayer)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -hitExpansion, dy: -hitExpansion).contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = true
        for _ in touches {
            onTouchDown?()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateHighlight(using: event)
        if !hasActiveTouches(in: event) {
            onTouchUp?()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateHighlight(using: event)
        if !hasActiveTouches(in: event) {
            onTouchUp?()
        }
    }

    private func hasActiveTouches(in event: UIEvent?) -> Bool {
        event?.touches(for: self)?.contains { touch in
            switch touch.phase {
            case .began, .moved, .stationary: return true
            default: return false
            }
        } ?? false
    }

    private func updateHighlight(using event: UIEvent?) {
        isHighlighted = hasActiveTouches(in: event)
    }

    override var isHighlighted: Bool {
        didSet {
            // Keep feedback local to this control. The parent SwiftUI view does
            // not need to redraw every key when another finger lands.
            highlightLayer.backgroundColor = isHighlighted
                ? UIColor.label.withAlphaComponent(0.12).cgColor
                : UIColor.clear.cgColor
            highlightLayer.borderWidth = isHighlighted ? 1 : 0
            highlightLayer.borderColor = isHighlighted
                ? UIColor.label.withAlphaComponent(0.16).cgColor
                : nil
            highlightLayer.cornerRadius = highlightCornerRadius
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = highlightSize ?? bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.frame = CGRect(x: bounds.midX - size.width / 2,
                                      y: bounds.midY - size.height / 2,
                                      width: size.width, height: size.height)
        CATransaction.commit()
    }

    override var intrinsicContentSize: CGSize {
        highlightSize ?? super.intrinsicContentSize
    }
}

/// A single UIKit tracking owner delivers accent-key input without waiting for
/// SwiftUI's drag recognizer. Movement continues outside the original key.
struct ImmediateVariantKey: UIViewRepresentable {
    let onBegan: (CGPoint) -> Void
    let onMoved: (CGPoint) -> Void
    let onEnded: (Bool) -> Void
    var adaptiveKeyID: String?
    var adaptiveTouchScopeID: String?

    func makeUIView(context: Context) -> TrackingKey {
        let view = TrackingKey()
        view.adaptiveTouchScopeID = adaptiveTouchScopeID
        view.adaptiveKeyID = adaptiveKeyID
        return view
    }

    func updateUIView(_ view: TrackingKey, context: Context) {
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        view.adaptiveTouchScopeID = adaptiveTouchScopeID
        view.adaptiveKeyID = adaptiveKeyID
    }

    final class TrackingKey: UIControl {
        var onBegan: ((CGPoint) -> Void)?
        var onMoved: ((CGPoint) -> Void)?
        var onEnded: ((Bool) -> Void)?
        var hitExpansion: CGFloat = 6
        var adaptiveTouchScopeID: String? {
            willSet {
                guard adaptiveKeyID != nil, adaptiveTouchScopeID != newValue,
                      let adaptiveKeyID else { return }
                AdaptiveTouchControlRegistry.shared.unregister(adaptiveKeyID, control: self)
            }
            didSet { registerAdaptiveKey() }
        }
        var adaptiveKeyID: String? {
            willSet {
                if let adaptiveKeyID, adaptiveKeyID != newValue {
                    AdaptiveTouchControlRegistry.shared.unregister(adaptiveKeyID, control: self)
                }
            }
            didSet { registerAdaptiveKey() }
        }
        private var activeMove: ((CGPoint) -> Void)?
        private var activeEnd: ((Bool) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            bounds.insetBy(dx: -hitExpansion, dy: -hitExpansion).contains(point)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
        }

        deinit {
            if let adaptiveKeyID {
                AdaptiveTouchControlRegistry.shared.unregister(adaptiveKeyID, control: self)
            }
        }

        private func registerAdaptiveKey() {
            guard let adaptiveKeyID, let adaptiveTouchScopeID else { return }
            AdaptiveTouchControlRegistry.shared.register(
                self, for: adaptiveKeyID, scopeID: adaptiveTouchScopeID
            )
        }

        private var activeTouches: [ObjectIdentifier: UITouch] = [:]

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                let id = ObjectIdentifier(touch)
                guard activeTouches[id] == nil else { continue }
                activeTouches[id] = touch
                if activeTouches.count == 1 {
                    activeMove = onMoved
                    activeEnd = onEnded
                    isHighlighted = true
                    layer.cornerRadius = 13
                }
                onBegan?(touch.location(in: self))
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let primary = activeTouches.values.first else { return }
            activeMove?(primary.location(in: self))
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                activeTouches.removeValue(forKey: ObjectIdentifier(touch))
            }
            if activeTouches.isEmpty {
                finish(cancelled: false)
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                activeTouches.removeValue(forKey: ObjectIdentifier(touch))
            }
            if activeTouches.isEmpty {
                finish(cancelled: true)
            }
        }

        private func finish(cancelled: Bool) {
            let completion = activeEnd
            activeEnd = nil
            activeMove = nil
            activeTouches.removeAll()
            isHighlighted = false
            completion?(cancelled)
        }

        override var isHighlighted: Bool {
            didSet {
                backgroundColor = isHighlighted
                    ? UIColor.label.withAlphaComponent(0.12)
                    : .clear
                layer.borderWidth = isHighlighted ? 1 : 0
                layer.borderColor = isHighlighted
                    ? UIColor.label.withAlphaComponent(0.16).cgColor
                    : nil
            }
        }
    }
}

private extension AuxiliaryBottomBar {
    private var commandHitSize: CGSize {
        CGSize(width: VoiceOnlyKeyboardPolicy.controlSize, height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight)
    }

    private var commandVisual: CGSize {
        VoiceOnlyKeyboardPolicy.commandVisualSize(for: commandHitSize)
    }

    private func roundControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        chromeControl(label: label, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private func roundControl(text: String, label: String, action: @escaping () -> Void) -> some View {
        chromeControl(label: label, action: action) {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private func chromeControl<Glyph: View>(
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        ZStack {
            glyph()
                .frame(width: commandVisual.width, height: commandVisual.height)
                .commandKeyPlate(cornerRadius: 18)
            ImmediateKeyButton(
                onTouchDown: {
                    HapticFeedback.keyTapped()
                    action()
                },
                onTouchUp: {},
                highlightCornerRadius: 18,
                highlightSize: commandVisual
            )
        }
        .frame(width: commandHitSize.width, height: commandHitSize.height)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private func wideControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        wideControl(
            label: label,
            action: action,
            hitWidth: VoiceOnlyKeyboardPolicy.actionHitSize.width,
            hitHeight: VoiceOnlyKeyboardPolicy.actionHitSize.height
        ) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private func wideControl(
        text: String,
        label: String,
        action: @escaping () -> Void,
        hitWidth: CGFloat,
        hitHeight: CGFloat
    ) -> some View {
        wideControl(label: label, action: action, hitWidth: hitWidth, hitHeight: hitHeight) {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private func wideControl<Glyph: View>(
        label: String,
        action: @escaping () -> Void,
        hitWidth: CGFloat,
        hitHeight: CGFloat,
        @ViewBuilder glyph: () -> Glyph
    ) -> some View {
        ZStack {
            glyph()
                .frame(width: max(36, hitWidth - VoiceOnlyKeyboardPolicy.commandVisualInset), height: VoiceOnlyKeyboardPolicy.commandVisualSize(for: CGSize(width: hitWidth, height: hitHeight)).height)
                .commandKeyPlate(cornerRadius: 18)
            ImmediateKeyButton(
                onTouchDown: {
                    HapticFeedback.keyTapped()
                    action()
                },
                onTouchUp: {},
                highlightCornerRadius: 18
            )
        }
        .frame(width: hitWidth, height: hitHeight)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

}

/// Whether keyboard chrome is a floating control or the large board behind it.
enum KeyboardChromeRole {
    case control
    case board
}

/// Liquid-glass chrome matching the voice-page utility controls.
struct KeyboardGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var interactive: Bool = true
    var role: KeyboardChromeRole = .control
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var accessibilityContrast: ColorSchemeContrast

    func body(content: Content) -> some View {
        if !KeyboardInteractionPreferences.liquidGlassEnabled {
            if role == .board {
                content
            } else {
                content
                    .background(shape.fill(solidFill))
            }
        } else if reduceTransparency || accessibilityContrast == .increased {
            content
                .background(shape.fill(Color(uiColor: accessibilityContrast == .increased ? .systemFill : .secondarySystemFill)))
        } else if #available(iOS 26, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content
                .background(shape.fill(.regularMaterial))
        }
    }

    private var solidFill: Color {
        Color(uiColor: .tertiarySystemFill)
    }
}

extension View {
    func keyboardGlass<S: Shape>(
        in shape: S,
        interactive: Bool = true,
        role: KeyboardChromeRole = .control
    ) -> some View {
        modifier(KeyboardGlassSurface(shape: shape, interactive: interactive, role: role))
    }

    /// Optional per-key plate. Off by default so letters sit on the shared inset.
    func letterKeyPlate(cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.keyCornerRadius) -> some View {
        modifier(LetterKeyPlateModifier(cornerRadius: cornerRadius))
    }

    /// Always-on plate for 123 / ABC / emoji / shift / delete / space / return.
    func commandKeyPlate(cornerRadius: CGFloat = 18) -> some View {
        keyboardGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct LetterKeyPlateModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if KeyboardInteractionPreferences.keyContainersEnabled {
            content.keyboardGlass(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
        }
    }
}
