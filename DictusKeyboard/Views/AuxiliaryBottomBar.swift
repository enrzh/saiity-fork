// DictusKeyboard/Views/AuxiliaryBottomBar.swift
import SwiftUI
import DictusCore

enum KeyHitTarget {
    /// Visual plates are independent from this persistent control.
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

            // The return's target is bounded by its neighbours, not by a constant.
            //
            // `actionHitSize` is 88pt wide, which is more than twice the 40pt plate it
            // gets centred on. Centred, it grew in both directions at once: 12pt of it
            // landed past the right edge of the keyboard, where nothing can press it,
            // and 20pt of it landed on the period key to the left. The return is added
            // to this stack after the period, so it sat above it and won the hit test
            // there — which is why the period "did nothing". It was not inert, it was
            // inserting a newline over the right half of its own plate.
            let returnHit = returnHitRect(previous: periodFrame, surface: surface)
            if fieldKeys.returnTitle == HostFieldPolicy.LetterFieldKeys.standard.returnTitle {
                wideControl(systemName: "return", label: "Return", action: onReturn,
                            hitWidth: returnHit.width, hitHeight: returnHit.height)
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

    /// The return key's press target: the platform's generous width where it fits,
    /// and no more.
    ///
    /// A key's target may be larger than its plate — that is the point of a target —
    /// but only into space that is on the keyboard and belongs to nobody else. The
    /// return sits in the rightmost slot, so growing it symmetrically spends half the
    /// extra width off the edge of the screen and the other half on the period key.
    /// Both are waste; the second is worse than waste, because it is a working key
    /// silently overwritten by its neighbour.
    ///
    /// So the growth is one-sided and bounded: into the gap on the left, stopping at
    /// the previous key's edge. With the period key present that leaves the return its
    /// own 40pt, which is what the layout can actually give it. Widening the return's
    /// plate to the platform's ~93pt is a proportion question and a separate change;
    /// this only stops one key from eating another.
    private func returnHitRect(previous: CGRect, surface: CGRect) -> CGRect {
        let plate = layout.chromeReturnFrame
        let leftLimit = previous.isEmpty
            ? surface.minX
            : previous.maxX + VoiceOnlyKeyboardPolicy.railSpacing
        let room = max(0, plate.maxX - leftLimit)
        let width = min(VoiceOnlyKeyboardPolicy.actionHitSize.width,
                        max(plate.width, room))
        return CGRect(x: plate.maxX - width, y: plate.minY,
                      width: width, height: plate.height)
    }

    private func periodKey(source: CGRect, bounds: CGSize, topOverflow: CGFloat) -> some View {
        let visual = VoiceOnlyKeyboardPolicy.commandVisualSize(
            for: CGSize(width: source.width, height: source.height)
        )
        let plateWidth = min(VoiceOnlyKeyboardPolicy.periodKeyPlateWidth, source.width)
        return ZStack {
            // WHY a VStack and not two independently aligned Texts: the old layout
            // pinned the comma to the bottom of a `plateHeight` box and *then*
            // stretched that box to the full hit height, so the plate no longer
            // matched the box the glyphs were laid out against and the hint drifted
            // outside the key. One stack, one frame, one plate: the period sits
            // directly above its comma hint and both stay inside the container.
            VStack(spacing: 0) {
                Text(".")
                    .font(.system(size: 19, weight: .light))
                Text(",")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: true)
            .frame(width: plateWidth, height: visual.height)
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
            .frame(width: source.width, height: source.height)
        }
        .frame(width: source.width, height: source.height)
        .contentShape(Rectangle())
        .accessibilityIdentifier("period-key")
        .accessibilityLabel("Period")
        .accessibilityHint("Hold for punctuation options.")
        .accessibilityAddTraits(.isButton)
    }

    private func periodBegan(at _: CGPoint, source: CGRect, bounds: CGSize, topOverflow: CGFloat) {
        PersistentLog.log(.keyboardPeriodKeyProbe(details:
            "began frame=\(Int(source.minX)),\(Int(source.minY)),"
            + "\(Int(source.width))x\(Int(source.height))"))
        HapticFeedback.playInputClick()
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
        PersistentLog.log(.keyboardPeriodKeyProbe(details:
            "ended cancelled=\(cancelled) options=\(session?.options.count ?? 0)"
            + " selected=\(session?.selectedIndex ?? -1)"))
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
                    HapticFeedback.playInputClick()
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

/// What the space bar is doing under the finger, published so the face can show it.
///
/// The tracking control is UIKit and the face is SwiftUI, and until this existed
/// nothing crossed between them: the caret moved and the key looked untouched. On
/// the system keyboard a held space bar stops saying "space" and shows a horizontal
/// arrow that leans with the drag — the only cue that the finger is steering the
/// caret rather than pressing a key.
final class SpaceDragState: ObservableObject {
    /// True from the moment cursor tracking starts until the finger lifts.
    @Published private(set) var isTracking = false
    /// Horizontal travel since tracking began, in points, already clamped.
    @Published private(set) var offset: CGFloat = 0
    /// How far the arrow may lean before it stops. Past the edge of the plate a
    /// larger travel would read as the glyph escaping the key.
    static let travel: CGFloat = 22

    private var originX: CGFloat = 0

    func begin(atX x: CGFloat) {
        originX = x
        offset = 0
        isTracking = true
    }

    func update(toX x: CGFloat) {
        guard isTracking else { return }
        let raw = x - originX
        let clamped = min(max(raw, -Self.travel), Self.travel)
        // Skip the publish when nothing moved. This fires on every touch sample, and
        // a redundant `objectWillChange` redraws the whole bar mid-gesture.
        guard clamped != offset else { return }
        offset = clamped
    }

    func end() {
        isTracking = false
        offset = 0
    }
}

/// Shared spacebar gesture for every SwiftUI keyboard page. A quick tap inserts
/// a space; a held press tracks finger travel like the native spacebar.
struct SpaceBarControl: View {
    let onTap: () -> Void
    let onCursorBegan: () -> Void
    let onCursorMoved: (KeyboardCursorStep) -> Void
    let onCursorEnded: () -> Void
    @StateObject private var drag = SpaceDragState()

    var body: some View {
        ZStack {
            CommandKeyFace(
                text: "space",
                plateHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize),
                // The space bar is one of the two wide keys, and the platform draws
                // those as full pills. It is not a command button, so it does not
                // take the command radius.
                cornerRadius: CommandKeyStyle.pillRadius(
                    forHeight: CGFloat(VoiceOnlyKeyboardPolicy.utilityVisualSize)
                ),
                isPressed: drag.isTracking
            )
            // The label hands over to a steering arrow, the way the platform's does,
            // and the arrow leans with the finger.
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: CommandKeyStyle.glyphSize, weight: .semibold))
                .foregroundStyle(.primary)
                .offset(x: drag.offset)
                .opacity(drag.isTracking ? CommandKeyStyle.pressOpacity : 0)
                .allowsHitTesting(false)
            SpaceTrackingButton(
                drag: drag,
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
    let drag: SpaceDragState
    let onTap: () -> Void
    let onCursorBegan: () -> Void
    let onCursorMoved: (KeyboardCursorStep) -> Void
    let onCursorEnded: () -> Void

    func makeUIView(context: Context) -> TrackingControl {
        let control = TrackingControl()
        control.drag = drag
        control.onTap = onTap
        control.onCursorBegan = onCursorBegan
        control.onCursorMoved = onCursorMoved
        control.onCursorEnded = onCursorEnded
        return control
    }

    func updateUIView(_ uiView: TrackingControl, context: Context) {
        uiView.drag = drag
        uiView.onTap = onTap
        uiView.onCursorBegan = onCursorBegan
        uiView.onCursorMoved = onCursorMoved
        uiView.onCursorEnded = onCursorEnded
    }

    final class TrackingControl: UIControl {
        /// The drag state the SwiftUI face renders. The view owns it; this only writes.
        var drag: SpaceDragState?
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
            if isCursorTracking { drag?.update(toX: point.x) }
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
                drag?.end()
            }
            if isCursorTracking {
                onCursorEnded?()
            } else if !wasCancelled {
                HapticFeedback.playInputClick()
                onTap?()
            }
        }

        private func activateCursorTracking() {
            guard !isCursorTracking, startedAt != nil else { return }
            isCursorTracking = true
            if let origin = joystickOrigin {
                joystickSampler = KeyboardCursorJoystickSampler(origin: origin)
                // The arrow starts under the finger, not under the key's centre.
                drag?.begin(atX: origin.x)
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
    /// Publishes the touch owner's press to the sibling key face.
    @StateObject private var pressState = KeyboardPressState()
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
                cornerRadius: visualCornerRadius,
                isPressed: pressState.isPressed
            )
            DeleteRepeatControl(
                onDelete: onDelete,
                onDeleteWord: onDeleteWord,
                pressState: pressState
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
    /// Sink for the sibling key face. See `KeyboardPressState`.
    var pressState: KeyboardPressState? = nil

    func makeUIView(context: Context) -> KeyboardDeleteRepeatControl {
        let control = KeyboardDeleteRepeatControl()
        control.pressState = pressState
        control.onDelete = onDelete
        control.onDeleteWord = onDeleteWord
        return control
    }

    func updateUIView(_ uiView: KeyboardDeleteRepeatControl, context: Context) {
        uiView.pressState = pressState
        uiView.onDelete = onDelete
        uiView.onDeleteWord = onDeleteWord
    }
}

/// UIKit delete owner shared by SwiftUI keys and the dictation-board overlay.
final class KeyboardDeleteRepeatControl: UIControl {
    var onDelete: (() -> Void)?
    var onDeleteWord: (() -> Void)?
    /// Sink for a sibling SwiftUI face. The control draws nothing itself, so
    /// without this the delete key registered every press while looking inert.
    var pressState: KeyboardPressState?

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

    override var isHighlighted: Bool {
        didSet { pressState?.isPressed = isHighlighted }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
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

private extension AuxiliaryBottomBar {
    private var commandHitSize: CGSize {
        CGSize(width: VoiceOnlyKeyboardPolicy.controlSize, height: VoiceOnlyKeyboardPolicy.bottomActionHitHeight)
    }

    private var commandVisual: CGSize {
        VoiceOnlyKeyboardPolicy.commandVisualSize(for: commandHitSize)
    }

    private func roundControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        chromeControl(label: label, action: action, hit: commandHitSize, highlightSize: commandVisual) { pressed in
            CommandKeyFace(
                systemName: systemName,
                plateWidth: commandVisual.width,
                plateHeight: commandVisual.height,
                isPressed: pressed
            )
        }
    }

    private func roundControl(
        text: String,
        label: String,
        textPointSize: CGFloat = 14,
        action: @escaping () -> Void
    ) -> some View {
        chromeControl(label: label, action: action, hit: commandHitSize, highlightSize: commandVisual) { pressed in
            CommandKeyFace(
                text: text,
                plateWidth: commandVisual.width,
                plateHeight: commandVisual.height,
                textPointSize: textPointSize,
                isPressed: pressed
            )
        }
    }

    private func chromeControl<Face: View>(
        label: String,
        action: @escaping () -> Void,
        hit: CGSize,
        highlightSize: CGSize,
        @ViewBuilder face: @escaping (Bool) -> Face
    ) -> some View {
        // The UIKit control owns the touch; the face is its sibling. Publishing
        // the press state through KeyboardPressState is what lets the visible
        // key react at all — previously the control highlighted invisibly.
        PressLinkedKeyFace(face: face, hit: hit, highlightSize: highlightSize, action: action)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private func wideControl(
        systemName: String,
        label: String,
        action: @escaping () -> Void,
        hitWidth: CGFloat = VoiceOnlyKeyboardPolicy.actionHitSize.width,
        hitHeight: CGFloat = VoiceOnlyKeyboardPolicy.actionHitSize.height
    ) -> some View {
        let hit = CGSize(width: hitWidth, height: hitHeight)
        let plate = widePlateSize(hitWidth: hit.width, hitHeight: hit.height)
        return chromeControl(label: label, action: action, hit: hit, highlightSize: hit) { pressed in
            CommandKeyFace(
                systemName: systemName,
                plateWidth: plate.width,
                plateHeight: plate.height,
                isPressed: pressed
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
        ) { pressed in
            CommandKeyFace(
                text: text,
                plateWidth: plate.width,
                plateHeight: plate.height,
                isPressed: pressed
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
