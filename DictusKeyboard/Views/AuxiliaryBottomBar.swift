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

enum KeyHitTarget {
    /// Hit testing is owned by `point(inside:)`. The control stays clear so the
    /// expanded hit target is not drawn as a box behind the glyph.
    static func prepare(_ control: UIControl) {
        control.backgroundColor = .clear
        control.isMultipleTouchEnabled = true
        control.isExclusiveTouch = false
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
    var periodFrame: CGRect = .zero
    var onPeriod: (String) -> Void = { _ in }
    let onSpace: () -> Void
    let onSpaceCursorBegan: () -> Void
    let onSpaceCursorMoved: (KeyboardCursorStep) -> Void
    let onSpaceCursorEnded: () -> Void
    let onReturn: () -> Void
    var showsNumbersControl: Bool = true
    var showsLettersControl: Bool = true
    var showsEmojiControl: Bool = true
    var showsPeriodKey: Bool = false
    var fieldKeys: HostFieldPolicy.LetterFieldKeys = .standard
    var onSymbolInsert: (String) -> Void = { _ in }

    @State private var periodVariantSession: KeyVariantSession?
    @State private var periodPreviewSession: KeyPreviewSession?
    @State private var periodHoldToken: UUID?

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
        let periodSourceFrame = CGRect(
            x: periodFrame.minX - surface.minX,
            y: periodFrame.minY - barOriginY,
            width: periodFrame.width,
            height: periodFrame.height
        )
        let barBounds = CGSize(width: surfaceWidth, height: rowHeight)
        let popupTopOverflow = max(0, barOriginY - CGFloat(surface.minY))
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
            if let insert = fieldKeys.leftInsert {
                roundControl(
                    text: insert,
                    label: insert,
                    textPointSize: insert.count > 1 ? 12 : 14,
                    action: { onSymbolInsert(insert) }
                )
                .position(x: localX(layout.chromeLettersFrame), y: localY(layout.chromeLettersFrame))
            } else if showsEmojiControl {
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
            if let insert = fieldKeys.rightInsert, !periodFrame.isEmpty {
                roundControl(
                    text: insert,
                    label: insert,
                    textPointSize: insert.count > 1 ? 12 : 14,
                    action: { onSymbolInsert(insert) }
                )
                .position(x: localX(periodFrame), y: localY(periodFrame))
            } else if showsPeriodKey && !periodFrame.isEmpty {
                periodKey(source: periodSourceFrame, bounds: barBounds, topOverflow: popupTopOverflow)
                    .frame(width: periodSourceFrame.width, height: periodSourceFrame.height)
                    .offset(x: periodSourceFrame.minX, y: periodSourceFrame.minY)
            }
            if fieldKeys.returnTitle == HostFieldPolicy.LetterFieldKeys.standard.returnTitle {
                wideControl(systemName: "return", label: "Return", action: onReturn)
                    .position(x: localX(returnFrame), y: localY(returnFrame))
            } else {
                wideControl(
                    text: fieldKeys.returnTitle,
                    label: fieldKeys.returnTitle,
                    action: onReturn,
                    hitWidth: returnFrame.width,
                    hitHeight: returnFrame.height
                )
                .position(x: localX(returnFrame), y: localY(returnFrame))
            }

            if let session = periodVariantSession {
                KeyVariantPopup(
                    options: session.options,
                    selectedIndex: session.selectedIndex,
                    isEmoji: false
                )
                .frame(width: session.popupFrame.width, height: session.popupFrame.height)
                .position(x: session.popupFrame.midX, y: session.popupFrame.midY)
                .allowsHitTesting(false)
                .zIndex(20)
            } else if periodPreviewSession != nil {
                KeyPressPreviewHost(session: $periodPreviewSession)
                    .zIndex(20)
            }
        }
        .frame(width: surfaceWidth, height: rowHeight, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func periodKey(source: CGRect, bounds: CGSize, topOverflow: CGFloat) -> some View {
        let plateHeight = VoiceOnlyKeyboardPolicy.commandVisualSize(
            for: CGSize(width: source.width, height: source.height)
        ).height
        return ZStack {
            VStack(spacing: 1) {
                Text(".")
                    .font(.system(size: 22, weight: .light))
                Text(",")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(
                width: min(VoiceOnlyKeyboardPolicy.periodKeyPlateWidth, source.width),
                height: plateHeight
            )
            .letterKeyPlate()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            ImmediateVariantKey(
                onBegan: { point in
                    periodBegan(at: point, source: source, bounds: bounds, topOverflow: topOverflow)
                },
                onMoved: { point in
                    periodMoved(to: CGPoint(x: source.minX + point.x, y: source.minY + point.y))
                },
                onEnded: { cancelled in
                    periodEnded(cancelled: cancelled)
                }
            )
        }
        .frame(width: source.width, height: source.height)
        .contentShape(Rectangle())
        .accessibilityLabel("Period")
        .accessibilityHint("Hold for punctuation options.")
        .accessibilityAddTraits(.isButton)
    }

    private func periodBegan(at _: CGPoint, source: CGRect, bounds: CGSize, topOverflow: CGFloat) {
        HapticFeedback.prepareForNextTap()
        HapticFeedback.keyTapped()
        periodPreviewSession = KeyPreviewSession(
            text: ".",
            sourceFrame: source,
            popupFrame: KeyPressPreviewHost.frame(
                for: source,
                in: bounds,
                topOverflow: topOverflow
            ),
            cornerRadius: VoiceOnlyKeyboardPolicy.keyCornerRadius
        )

        let token = UUID()
        periodHoldToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardDeletion.holdRecognitionDuration) {
            guard periodHoldToken == token, periodVariantSession == nil else { return }
            periodPreviewSession = nil
            let options = SymbolKeyVariants.options(for: ".")
            guard options.count > 1 else { return }
            let popupFrame = KeyVariantPopup.frame(
                for: source,
                optionCount: options.count,
                isEmoji: false,
                in: bounds,
                topOverflow: topOverflow
            )
            periodVariantSession = KeyVariantSession(
                options: options,
                sourceFrame: source,
                popupFrame: popupFrame,
                isEmoji: false,
                selectedIndex: 0
            )
            HapticFeedback.variantPopupPresented()
        }
    }

    private func periodMoved(to point: CGPoint) {
        guard var session = periodVariantSession else { return }
        let index = KeyVariantPopup.selectedIndex(
            at: point,
            popupFrame: session.popupFrame,
            optionCount: session.options.count
        )
        guard session.selectedIndex != index else { return }
        session.selectedIndex = index
        periodVariantSession = session
        HapticFeedback.variantHighlightChanged()
    }

    private func periodEnded(cancelled: Bool) {
        periodHoldToken = nil
        let session = periodVariantSession
        periodVariantSession = nil
        periodPreviewSession = nil
        guard !cancelled else { return }
        if let session, session.options.indices.contains(session.selectedIndex) {
            onPeriod(session.options[session.selectedIndex])
        } else {
            onPeriod(".")
        }
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
            CommandKeyFace(
                text: "space",
                plateHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize)
            )
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
            KeyHitTarget.prepare(self)
            installCursorPanRecognizer()
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            if startedAt != nil { return true }
            return bounds.insetBy(dx: -2, dy: -2).contains(point)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            KeyHitTarget.prepare(self)
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
        visualCornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
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
            CommandKeyFace(
                systemName: "delete.backward",
                plateWidth: visualWidth,
                plateHeight: visualHeight,
                cornerRadius: visualCornerRadius
            )
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
        KeyHitTarget.prepare(self)
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
    var holdDuration: TimeInterval? = nil
    var onHold: (() -> Void)? = nil

    func makeUIView(context: Context) -> UIView {
        let button = ImmediateKeyControl(frame: .zero)
        button.highlightCornerRadius = highlightCornerRadius
        button.highlightSize = highlightSize
        button.isMultipleTouchEnabled = true
        button.isExclusiveTouch = false
        button.hitExpansion = 6
        button.adaptiveTouchScopeID = adaptiveTouchScopeID
        button.adaptiveKeyID = adaptiveKeyID
        button.holdDuration = holdDuration
        button.onHold = onHold
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
        uiView.holdDuration = holdDuration
        uiView.onHold = onHold
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
    var holdDuration: TimeInterval? = nil
    var onHold: (() -> Void)? = nil
    private var holdTimer: Timer?
    private var holdActive = false
    private var holdRecognized = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        KeyHitTarget.prepare(self)
        layer.addSublayer(highlightLayer)
    }

    deinit {
        if let adaptiveKeyID {
            AdaptiveTouchControlRegistry.shared.unregister(adaptiveKeyID, control: self)
        }
        holdTimer?.invalidate()
    }

    private func registerAdaptiveKey() {
        guard let adaptiveKeyID, let adaptiveTouchScopeID else { return }
        AdaptiveTouchControlRegistry.shared.register(
            self, for: adaptiveKeyID, scopeID: adaptiveTouchScopeID
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        KeyHitTarget.prepare(self)
        layer.addSublayer(highlightLayer)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        self.point(inside: point, with: event) ? self : nil
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -hitExpansion, dy: -hitExpansion).contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isHighlighted = true
        if let holdDuration {
            guard !holdActive else { return }
            holdActive = true
            holdRecognized = false
            let timer = Timer(timeInterval: holdDuration, repeats: false) { [weak self] _ in
                guard let self, self.holdActive else { return }
                self.holdRecognized = true
                self.onHold?()
            }
            holdTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            for _ in touches {
                onTouchDown?()
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateHighlight(using: event)
        if !hasActiveTouches(in: event) {
            finishHoldIfNeeded()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateHighlight(using: event)
        if !hasActiveTouches(in: event) {
            finishHoldIfNeeded()
        }
    }

    private func finishHoldIfNeeded() {
        guard holdDuration != nil else {
            onTouchUp?()
            return
        }
        holdTimer?.invalidate()
        holdTimer = nil
        let recognized = holdRecognized
        holdActive = false
        holdRecognized = false
        if recognized {
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
            // A press may darken an explicit visual plate. It must not stroke
            // the expanded hit bounds, which read as a hitbox hint.
            let paintsPlate = isHighlighted && highlightSize != nil
            highlightLayer.backgroundColor = paintsPlate
                ? UIColor.label.withAlphaComponent(0.12).cgColor
                : UIColor.clear.cgColor
            highlightLayer.borderWidth = 0
            highlightLayer.borderColor = nil
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
        // highlightSize is only for the press chrome. Returning it here shrinks
        // the UIKit control inside SwiftUI frames and leaves dead gaps around
        // command plates (shift/delete/123/etc).
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
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
            KeyHitTarget.prepare(self)
        }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            self.point(inside: point, with: event) ? self : nil
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            bounds.insetBy(dx: -hitExpansion, dy: -hitExpansion).contains(point)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            KeyHitTarget.prepare(self)
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
                // The control fills the hit target. Painting that rect, or
                // stroking it, shows the hitbox. Press feedback stays on the glyph.
                backgroundColor = .clear
                layer.borderWidth = 0
                layer.borderColor = nil
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
        chromeControl(label: label, action: action, hit: commandHitSize, highlightSize: commandVisual) {
            CommandKeyFace(
                systemName: systemName,
                plateWidth: commandVisual.width,
                plateHeight: commandVisual.height
            )
        }
    }

    private func roundControl(
        text: String,
        label: String,
        textPointSize: CGFloat = 14,
        action: @escaping () -> Void
    ) -> some View {
        chromeControl(label: label, action: action, hit: commandHitSize, highlightSize: commandVisual) {
            CommandKeyFace(
                text: text,
                plateWidth: commandVisual.width,
                plateHeight: commandVisual.height,
                textPointSize: textPointSize
            )
        }
    }

    private func chromeControl<Face: View>(
        label: String,
        action: @escaping () -> Void,
        hit: CGSize,
        highlightSize: CGSize,
        @ViewBuilder face: () -> Face
    ) -> some View {
        ZStack {
            face()
            ImmediateKeyButton(
                onTouchDown: {
                    HapticFeedback.keyTapped()
                    action()
                },
                onTouchUp: {},
                highlightCornerRadius: VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
                highlightSize: highlightSize
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: hit.width, height: hit.height)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private func wideControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        let hit = VoiceOnlyKeyboardPolicy.actionHitSize
        let plate = widePlateSize(hitWidth: hit.width, hitHeight: hit.height)
        return chromeControl(label: label, action: action, hit: hit, highlightSize: hit) {
            CommandKeyFace(
                systemName: systemName,
                plateWidth: plate.width,
                plateHeight: plate.height
            )
        }
    }

    private func wideControl(
        text: String,
        label: String,
        action: @escaping () -> Void,
        hitWidth: CGFloat,
        hitHeight: CGFloat
    ) -> some View {
        let plate = widePlateSize(hitWidth: hitWidth, hitHeight: hitHeight)
        return chromeControl(
            label: label,
            action: action,
            hit: CGSize(width: hitWidth, height: hitHeight),
            highlightSize: CGSize(width: hitWidth, height: hitHeight)
        ) {
            CommandKeyFace(
                text: text,
                plateWidth: plate.width,
                plateHeight: plate.height
            )
        }
    }

    private func widePlateSize(hitWidth: CGFloat, hitHeight: CGFloat) -> CGSize {
        CGSize(
            width: max(36, hitWidth - VoiceOnlyKeyboardPolicy.commandVisualInset),
            height: VoiceOnlyKeyboardPolicy.commandVisualSize(for: CGSize(width: hitWidth, height: hitHeight)).height
        )
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
        // Plates are visual. A hittable solid fill sits behind the clear key
        // control and swallows the tap; glass does not, which is why solid
        // mode felt dead.
        plate(content)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func plate(_ content: Content) -> some View {
        if !KeyboardInteractionPreferences.liquidGlassEnabled {
            if role == .board {
                content
            } else {
                content.background { shape.fill(solidFill).allowsHitTesting(false) }
            }
        } else if reduceTransparency || accessibilityContrast == .increased {
            content.background {
                shape.fill(Color(uiColor: accessibilityContrast == .increased ? .systemFill : .secondarySystemFill)).allowsHitTesting(false)
            }
        } else if #available(iOS 26, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content.background { shape.fill(.regularMaterial).allowsHitTesting(false) }
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
    func commandKeyPlate(cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius) -> some View {
        keyboardGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Symbol or short label on a command plate. The hit target stays on the caller.
struct CommandKeyFace: View {
    private let systemName: String?
    private let text: String?
    private let textWeight: Font.Weight
    private let symbolPointSize: CGFloat
    private let textPointSize: CGFloat
    private let plateWidth: CGFloat?
    private let plateHeight: CGFloat
    private let cornerRadius: CGFloat

    init(
        systemName: String,
        plateWidth: CGFloat? = nil,
        plateHeight: CGFloat,
        cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
        symbolPointSize: CGFloat = 16
    ) {
        self.systemName = systemName
        self.text = nil
        self.textWeight = .semibold
        self.symbolPointSize = symbolPointSize
        self.textPointSize = 14
        self.plateWidth = plateWidth
        self.plateHeight = plateHeight
        self.cornerRadius = cornerRadius
    }

    init(
        text: String,
        plateWidth: CGFloat? = nil,
        plateHeight: CGFloat,
        cornerRadius: CGFloat = VoiceOnlyKeyboardPolicy.commandKeyCornerRadius,
        textPointSize: CGFloat = 14,
        textWeight: Font.Weight = .semibold
    ) {
        self.systemName = nil
        self.text = text
        self.textWeight = textWeight
        self.symbolPointSize = 16
        self.textPointSize = textPointSize
        self.plateWidth = plateWidth
        self.plateHeight = plateHeight
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: symbolPointSize, weight: .semibold))
            } else if let text {
                Text(text)
                    .font(.system(size: textPointSize, weight: textWeight))
            }
        }
        .foregroundStyle(.primary)
        .frame(
            minWidth: plateWidth,
            maxWidth: plateWidth ?? .infinity,
            minHeight: plateHeight,
            maxHeight: plateHeight
        )
        .commandKeyPlate(cornerRadius: cornerRadius)
    }
}

private struct LetterKeyPlateModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if KeyboardInteractionPreferences.keyContainersEnabled {
            // Visual only — interactive glass must not compete with ImmediateKeyButton.
            content.keyboardGlass(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                interactive: false
            )
        } else {
            content
        }
    }
}
