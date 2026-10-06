// DictusKeyboard/Views/AuxiliaryBottomBar.swift
import SwiftUI
import UIKit
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
    var onDelete: () -> Void = {}
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
    @State private var periodInserted = false

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
                    // The native mounting bridge converts this exact placement,
                    // so the visible face and its target cannot drift apart.
                    .position(x: periodSourceFrame.midX, y: periodSourceFrame.midY)
                    .zIndex(10)
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
                    .position(x: localX(returnHit), y: localY(returnHit))
            } else {
                wideControl(
                    text: fieldKeys.returnTitle,
                    label: fieldKeys.returnTitle,
                    action: onReturn,
                    hitWidth: returnHit.width,
                    hitHeight: returnHit.height
                )
                .position(x: localX(returnHit), y: localY(returnHit))
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
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
        .frame(width: surfaceWidth, height: rowHeight, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .center)
        .onChange(of: showsPeriodKey) { _, visible in
            if !visible {
                periodHoldToken = nil
                periodInserted = false
                periodVariantSession = nil
                periodPreviewSession = nil
            }
        }
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
        KeyboardBottomBarView.returnHitRect(layout: layout, previous: previous)
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
                    .font(.system(size: 19, weight: .regular))
                Text(",")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(uiColor: KeyboardChromeRole.secondaryForeground))
            }
            .fixedSize(horizontal: true, vertical: true)
            .frame(width: plateWidth, height: visual.height)
            .keyboardGlass(in: RoundedRectangle(cornerRadius: VoiceOnlyKeyboardPolicy.keyCornerRadius),
                           interactive: false, role: .input)
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
                },
                nativeMode: .letters,
                highlightSize: CGSize(width: plateWidth, height: visual.height)
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
        guard !periodInserted else { return }
        PersistentLog.log(.keyboardPeriodKeyProbe(details:
            "began frame=\(Int(source.minX)),\(Int(source.minY)),"
            + "\(Int(source.width))x\(Int(source.height))"))
        HapticFeedback.playInputClick()
        periodInserted = true
        onPeriod(".")
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
        let inserted = periodInserted
        periodInserted = false
        let session = periodVariantSession
        periodVariantSession = nil
        periodPreviewSession = nil
        PersistentLog.log(.keyboardPeriodKeyProbe(details:
            "ended cancelled=\(cancelled) options=\(session?.options.count ?? 0)"
            + " selected=\(session?.selectedIndex ?? -1)"))
        guard !cancelled, inserted,
              let session, session.options.indices.contains(session.selectedIndex) else { return }
        let variant = session.options[session.selectedIndex]
        guard variant != "." else { return }
        onDelete()
        onPeriod(variant)
    }

}

/// Live bottom bar. Its touch owners survive material/preview updates and the
/// period belongs to this row, not to an independent input-view overlay.
final class KeyboardBottomBarView: UIView {
    let period = KeyboardPeriodKeyView()
    let firstControl = KeyboardKeyTouchControl()
    let secondControl = KeyboardKeyTouchControl()
    let fieldControl = KeyboardKeyTouchControl()
    let returnControl = KeyboardKeyTouchControl()
    let spaceControl = SpaceTrackingButton.TrackingControl()
    var onNumbers: (() -> Void)?
    var onLetters: (() -> Void)?
    var onEmoji: (() -> Void)?
    var onDictation: (() -> Void)?
    var onInsert: ((String) -> Void)?
    var onReturn: (() -> Void)?
    private let spaceDrag = SpaceDragState()
    private var mode: KeyboardAreaMode = .letters
    private var fieldKeys = HostFieldPolicy.LetterFieldKeys.standard

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isHidden = true
        for control in [firstControl, secondControl, fieldControl, returnControl] {
            control.isAccessibilityElement = true
            control.accessibilityTraits = .button
            addSubview(control)
        }
        spaceControl.drag = spaceDrag
        spaceControl.isAccessibilityElement = true
        spaceControl.accessibilityLabel = "Space"
        firstControl.accessibilityIdentifier = "bottom-layer-switch"
        secondControl.accessibilityIdentifier = "bottom-secondary-switch"
        returnControl.accessibilityIdentifier = "bottom-return"
        fieldControl.accessibilityIdentifier = "bottom-field-insert"
        spaceControl.accessibilityIdentifier = "bottom-space"
        spaceControl.accessibilityTraits = .button
        addSubview(spaceControl)
        addSubview(period)
        firstControl.configurePageSwitch(tap: { [weak self] in
            guard let self else { return }
            if self.mode == .panel { self.onLetters?() } else { self.onNumbers?() }
        }, hold: { [weak self] in self?.onDictation?() }, holdLabel: "Open dictation board")
        secondControl.onBegan = { [weak self] _ in
            guard let self else { return }
            HapticFeedback.playInputClick()
            if let text = self.fieldKeys.leftInsert { self.onInsert?(text) }
            else if self.mode == .emoji { self.onLetters?() }
            else { self.onEmoji?() }
        }
        fieldControl.onBegan = { [weak self] _ in
            guard let self, let text = self.fieldKeys.rightInsert else { return }
            HapticFeedback.playInputClick()
            self.onInsert?(text)
        }
        returnControl.onBegan = { [weak self] _ in
            HapticFeedback.playInputClick()
            self?.onReturn?()
        }
    }

    required init?(coder: NSCoder) { nil }

    func show(_ mode: KeyboardAreaMode, layout: VoiceOnlyKeyboardPolicy.Layout,
              inputHeight: CGFloat, fieldKeys: HostFieldPolicy.LetterFieldKeys) {
        if self.mode != mode { cancelInteractions() }
        self.mode = mode
        self.fieldKeys = fieldKeys
        if mode != .letters {
            self.fieldKeys.leftInsert = nil
            self.fieldKeys.rightInsert = nil
        }
        isHidden = mode != .letters && mode != .panel && mode != .emoji
        if isHidden { cancelInteractions(); return }
        let bar = CGRect(x: layout.surfaceFrame.minX, y: layout.chromeBottomBarOriginY,
                         width: layout.surfaceFrame.width, height: VoiceOnlyKeyboardPolicy.spacebarHeight)
        let nextFrame = layout.inputFrame(bar, inputViewHeight: inputHeight)
        if frame != nextFrame { cancelInteractions() }
        frame = nextFrame
        func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -bar.minX, dy: -bar.minY) }
        firstControl.frame = local(layout.chromeNumbersFrame)
        secondControl.frame = local(layout.chromeLettersFrame)
        spaceControl.frame = local(mode == .letters ? layout.letterSpaceFrame : layout.chromeWideSpaceFrame)
        let previous = mode == .letters ? layout.letterPeriodFrame : .zero
        period.frame = local(previous)
        period.isHidden = mode != .letters || self.fieldKeys.rightInsert != nil
        if period.isHidden { period.cancelInteraction() }
        fieldControl.frame = local(previous)
        fieldControl.isHidden = mode != .letters || self.fieldKeys.rightInsert == nil
        returnControl.frame = local(Self.returnHitRect(layout: layout, previous: previous))
        firstControl.accessibilityLabel = mode == .panel ? "Open letter keyboard" : "Open symbols keyboard"
        secondControl.accessibilityLabel = self.fieldKeys.leftInsert ?? (mode == .emoji ? "Open letter keyboard" : "Emoji")
        fieldControl.accessibilityLabel = self.fieldKeys.rightInsert
        returnControl.accessibilityLabel = self.fieldKeys.returnTitle
        updateChrome()
        period.refreshAppearance()
    }

    static func returnHitRect(layout: VoiceOnlyKeyboardPolicy.Layout, previous: CGRect) -> CGRect {
        let plate = layout.chromeReturnFrame
        let leftLimit = previous.isEmpty ? layout.surfaceFrame.minX
            : previous.maxX + VoiceOnlyKeyboardPolicy.bottomBarSpacing
        let room = max(0, plate.maxX - leftLimit)
        let width = min(VoiceOnlyKeyboardPolicy.actionHitSize.width, max(plate.width, room))
        return CGRect(x: plate.maxX - width, y: plate.minY, width: width, height: plate.height)
    }

    private func updateChrome() {
        firstControl.holdDuration = KeyboardDeletion.holdRecognitionDuration
        let circle = CGSize(width: VoiceOnlyKeyboardPolicy.bottomBarVisualHeight,
                            height: VoiceOnlyKeyboardPolicy.bottomBarVisualHeight)
        firstControl.keyboardFace.configure(text: mode == .panel ? "ABC" : "123",
            visualSize: circle, radius: circle.height / 2,
            holdSymbol: KeyboardInteractionPreferences.topBarEnabled ? nil : "mic.fill")
        let second = fieldKeys.leftInsert ?? (mode == .emoji ? "ABC" : nil)
        secondControl.keyboardFace.configure(text: second, symbol: second == nil ? "face.smiling" : nil,
            visualSize: circle, radius: circle.height / 2)
        fieldControl.keyboardFace.configure(text: fieldKeys.rightInsert,
            visualSize: VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: fieldControl.bounds.size),
            textPointSize: (fieldKeys.rightInsert?.count ?? 0) > 3 ? 12 : CommandKeyStyle.textSize)
        let title = fieldKeys.returnTitle == HostFieldPolicy.LetterFieldKeys.standard.returnTitle
            ? nil : fieldKeys.returnTitle
        returnControl.keyboardFace.configure(text: title, symbol: title == nil ? "return" : nil,
            visualSize: VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: returnControl.bounds.size),
            tint: title == nil ? nil : .saiityAction, foreground: title == nil ? .label : .saiityOnAction,
            textPointSize: (title?.count ?? 0) > 3 ? 12 : CommandKeyStyle.textSize)
        spaceControl.keyboardFace.configure(text: "space",
            visualSize: CGSize(width: spaceControl.bounds.width, height: VoiceOnlyKeyboardPolicy.bottomBarVisualHeight),
            radius: CommandKeyStyle.cornerRadius, textWeight: .regular, role: .input)
    }

    func refreshAppearance() {
        period.refreshAppearance()
        if !isHidden { updateChrome() }
    }

    func cancelInteractions() {
        [firstControl, secondControl, fieldControl, returnControl].forEach { $0.cancelInteraction() }
        spaceControl.cancelInteraction()
        period.cancelInteraction()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01,
              bounds.contains(point) else { return nil }
        for owner in [period, fieldControl, returnControl, spaceControl,
                      secondControl, firstControl] as [UIView] {
            guard !owner.isHidden, owner.isUserInteractionEnabled, owner.alpha > 0.01 else { continue }
            if let hit = owner.hitTest(owner.convert(point, from: self), with: event) { return hit }
        }
        return nil
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
                plateHeight: CGFloat(VoiceOnlyKeyboardPolicy.bottomBarVisualHeight),
                cornerRadius: CommandKeyStyle.cornerRadius,
                textWeight: .regular,
                isPressed: drag.isTracking,
                role: .input
            )
            // No steering arrow. The caret moving is the feedback, and an arrow that
            // leans with the finger reads as a control the user is meant to operate
            // rather than a cursor they are already steering.
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
struct SpaceTrackingButton: UIViewRepresentable {
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
        override var isHighlighted: Bool {
            didSet { existingKeyboardFace?.setPressed(isHighlighted) }
        }
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
        private let cursorHold = KeyboardHoldSession()

        override init(frame: CGRect) {
            super.init(frame: frame)
            KeyHitTarget.prepare(self)
            installCursorPanRecognizer()
        }

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
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
            isHighlighted = true
            HapticFeedback.playInputClick()
            startedAt = Date()
            trackingCoordinateView = window ?? superview ?? self
            let point = trackingPoint(for: touch)
            joystickOrigin = point
            joystickSampler = nil
            latestTouchPoint = point
            isCursorTracking = false
            stopJoystickClock()
            cursorHold.begin(after: KeyboardDeletion.cursorHoldDuration) { [weak self] in
                self?.activateCursorTracking()
            }
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
            isHighlighted = false
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
                onTap?()
            }
        }

        func cancelInteraction() {
            finish(wasCancelled: true)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { cancelInteraction() }
        }

        override func accessibilityActivate() -> Bool {
            guard !isHidden, isEnabled, isUserInteractionEnabled else { return false }
            HapticFeedback.playInputClick()
            onTap?()
            return true
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
            cursorHold.cancel()
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
                systemName: CommandKeyStyle.deleteSymbolName,
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
    private let deleteRepeat = KeyboardDeleteRepeatSession()

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
        didSet {
            pressState?.isPressed = isHighlighted
            existingKeyboardFace?.setPressed(isHighlighted)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isDeleting else { return }
        isDeleting = true
        isHighlighted = true
        HapticFeedback.keyTapped()
        onDelete?()

        deleteRepeat.begin { [weak self] action in
            guard let self, self.isDeleting else { return }
            switch action {
            case .word: self.onDeleteWord?()
            case .character: self.onDelete?()
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish()
    }

    func cancelInteraction() {
        finish()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { finish() }
    }

    override func accessibilityActivate() -> Bool {
        guard !isHidden, isEnabled, isUserInteractionEnabled, alpha > 0.01 else { return false }
        HapticFeedback.keyTapped()
        onDelete?()
        return true
    }

    private func finish() {
        guard isDeleting else { return }
        deleteRepeat.cancel()
        isDeleting = false
        isHighlighted = false
    }

}

private extension AuxiliaryBottomBar {
    private var commandHitSize: CGSize {
        CGSize(width: VoiceOnlyKeyboardPolicy.bottomBarControlWidth, height: VoiceOnlyKeyboardPolicy.spacebarHeight)
    }

    private var commandVisual: CGSize {
        CGSize(width: VoiceOnlyKeyboardPolicy.bottomBarVisualHeight, height: VoiceOnlyKeyboardPolicy.bottomBarVisualHeight)
    }

    private func roundControl(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        chromeControl(label: label, action: action, hit: commandHitSize, highlightSize: commandVisual) { pressed in
            CommandKeyFace(
                systemName: systemName,
                plateWidth: commandVisual.width,
                plateHeight: commandVisual.height,
                cornerRadius: commandVisual.height / 2,
                isPressed: pressed
            )
        }
    }

    private func roundControl(
        text: String,
        label: String,
        textPointSize: CGFloat = CommandKeyStyle.textSize,
        action: @escaping () -> Void
    ) -> some View {
        chromeControl(label: label, action: action, hit: commandHitSize, highlightSize: commandVisual) { pressed in
            CommandKeyFace(
                text: text,
                plateWidth: commandVisual.width,
                plateHeight: commandVisual.height,
                cornerRadius: commandVisual.height / 2,
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
                isPressed: pressed,
                accented: true
            )
        }
    }

    private func widePlateSize(hitWidth: CGFloat, hitHeight: CGFloat) -> CGSize {
        VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: CGSize(width: hitWidth, height: hitHeight))
    }

}
