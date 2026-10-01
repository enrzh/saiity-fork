import SwiftUI
import UIKit
import DictusCore

/// Shared hold lifecycle for the grid, Period, emoji and native key controls.
/// A cancelled or superseded finger can never fire a queued hold.
final class KeyboardHoldSession {
    private var timer: Timer?
    private(set) var recognized = false

    func begin(after delay: TimeInterval, action: @escaping () -> Void) {
        cancel()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.timer = nil
            self.recognized = true
            action()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        recognized = false
    }

    deinit { timer?.invalidate() }
}

/// Every Delete owner uses the same repeat clock, word transition and haptic.
final class KeyboardDeleteRepeatSession {
    private let hold = KeyboardHoldSession()
    private var timer: Timer?
    private var startedAt = Date.distantPast
    private var onRepeat: ((KeyboardDeletion.RepeatAction) -> Void)?

    func begin(_ action: @escaping (KeyboardDeletion.RepeatAction) -> Void) {
        cancel()
        startedAt = Date()
        onRepeat = action
        hold.begin(after: KeyboardDeletion.repeatDelay) { [weak self] in
            guard let self else { return }
            self.tick()
            let timer = Timer(timeInterval: KeyboardDeletion.repeatInterval, repeats: true) { [weak self] _ in self?.tick() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func tick() {
        guard let onRepeat else { return }
        HapticFeedback.keyTapped()
        onRepeat(KeyboardDeletion.repeatAction(after: Date().timeIntervalSince(startedAt)))
    }

    func cancel() {
        hold.cancel()
        timer?.invalidate()
        timer = nil
        onRepeat = nil
    }

    deinit { timer?.invalidate() }
}

/// A control's visible face lives inside the control that receives its touch.
/// The plate and glyph are passive children; material changes never replace
/// the control or move its hit frame.
final class KeyboardNativeControlFace: UIView {
    private let plate = UIVisualEffectView(effect: nil)
    private let iconWell = UIView()
    private let image = UIImageView()
    private let label = UILabel()
    var visualSize: CGSize?
    var radius: CGFloat = CommandKeyStyle.cornerRadius
    var tint: UIColor?
    var foreground: UIColor = .label
    var isPrimary = false
    private enum Material: Equatable { case glass, solid, reduced, contrast }
    private var material: Material?
    private var displayedSymbol: String?
    private var displayedSymbolSize: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        plate.isUserInteractionEnabled = false
        plate.clipsToBounds = true
        image.contentMode = .center
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        iconWell.isUserInteractionEnabled = false
        [plate, iconWell, image, label].forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { nil }

    func configureInset(_ layout: VoiceOnlyKeyboardPolicy.Layout, inputHeight: CGFloat) {
        frame = layout.inputFrame(layout.surfaceFrame, inputViewHeight: inputHeight)
        configure(visualSize: layout.surfaceFrame.size, radius: 24)
        isHidden = !KeyboardInteractionPreferences.keyboardInsetEnabled
    }

    func configure(text: String? = nil, symbol: String? = nil,
                   visualSize: CGSize? = nil, radius: CGFloat = CommandKeyStyle.cornerRadius,
                   primary: Bool = false, tint: UIColor? = nil, foreground: UIColor = .label,
                   textPointSize: CGFloat = CommandKeyStyle.textSize) {
        self.visualSize = visualSize
        self.radius = radius
        self.isPrimary = primary
        self.tint = tint
        self.foreground = foreground
        label.text = text
        label.isHidden = text == nil
        label.textColor = foreground
        let textSize: CGFloat = primary ? 14 : textPointSize
        let font = UIFont.systemFont(ofSize: textSize, weight: .semibold)
        label.font = primary ? UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: font, maximumPointSize: 17) : font
        label.numberOfLines = primary ? 2 : 1
        label.minimumScaleFactor = primary ? min(1, 11 / label.font.pointSize) : 0.5
        label.lineBreakMode = primary ? .byWordWrapping : .byTruncatingTail
        let symbolSize: CGFloat = primary ? 20 : CommandKeyStyle.glyphSize
        if displayedSymbol != symbol || displayedSymbolSize != symbolSize || image.image == nil {
            displayedSymbol = symbol
            displayedSymbolSize = symbolSize
            image.image = symbol.flatMap {
                UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: symbolSize, weight: .semibold)) ?? UIImage(systemName: "mic.fill")
            }
            updateSymbolAnimation()
        }
        image.isHidden = symbol == nil
        image.tintColor = foreground
        iconWell.isHidden = !primary || symbol == nil
        iconWell.backgroundColor = foreground.withAlphaComponent(0.08)
        refreshAppearance()
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSymbolAnimation()
    }

    private func updateSymbolAnimation() {
        image.removeAllSymbolEffects()
        image.alpha = 1
        if window != nil, (displayedSymbol == "waveform" || displayedSymbol == "ellipsis"),
           !UIAccessibility.isReduceMotionEnabled {
            image.addSymbolEffect(.pulse, options: .repeating)
        }
    }

    func refreshAppearance() {
        // An enabled service button is an opaque green plate. Glass around a
        // tinted utility button leaves a persistent halo after release.
        let next: Material = (tint != nil && !isPrimary) || !KeyboardInteractionPreferences.liquidGlassEnabled ? .solid
            : UIAccessibility.isDarkerSystemColorsEnabled ? .contrast
            : UIAccessibility.isReduceTransparencyEnabled ? .reduced : .glass
        if material != next {
            material = next
            plate.effect = nil
            if next == .glass {
                if #available(iOS 26.0, *) { plate.effect = UIGlassEffect(style: .regular) }
                else { plate.effect = UIBlurEffect(style: .systemMaterial) }
            }
        }
        plate.backgroundColor = .clear
        plate.contentView.backgroundColor = tint.map {
            next == .glass ? $0.withAlphaComponent(0.86) : $0
        } ?? (next == .glass ? .clear : next == .contrast ? .systemFill
                : next == .reduced ? .secondarySystemFill : .tertiarySystemFill)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = visualSize ?? VoiceOnlyKeyboardPolicy.commandVisualSize(for: bounds.size)
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
        plate.frame = rect
        plate.layer.cornerRadius = radius
        if isPrimary, !image.isHidden, !label.isHidden {
            // A leading microphone badge and readable action label keep the
            // 54pt hold target unchanged, including cancel and app recovery.
            iconWell.frame = CGRect(x: rect.minX + 10, y: rect.midY - 17, width: 34, height: 34)
            iconWell.layer.cornerRadius = 17
            image.frame = iconWell.frame
            label.frame = CGRect(x: iconWell.frame.maxX + 8, y: rect.minY + 8,
                                 width: max(0, rect.maxX - iconWell.frame.maxX - 20), height: rect.height - 16)
        } else {
            image.frame = CGRect(x: rect.midX - 11, y: rect.midY - 11, width: 22, height: 22)
            label.frame = rect.insetBy(dx: 4, dy: 0)
        }
    }

    func setPressed(_ pressed: Bool) {
        guard (alpha < 1) != pressed else { return }
        let changes = {
            self.transform = pressed && !UIAccessibility.isReduceMotionEnabled
                ? CGAffineTransform(scaleX: CommandKeyStyle.pressScale, y: CommandKeyStyle.pressScale) : .identity
            self.alpha = pressed ? CommandKeyStyle.pressOpacity : 1
        }
        if pressed {
            UIView.performWithoutAnimation(changes)
        } else {
            UIView.animate(withDuration: CommandKeyStyle.pressDurationOut,
                           delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        }
    }
}

extension UIControl {
    var existingKeyboardFace: KeyboardNativeControlFace? {
        subviews.compactMap { $0 as? KeyboardNativeControlFace }.first
    }

    var keyboardFace: KeyboardNativeControlFace {
        if let face = existingKeyboardFace { return face }
        let face = KeyboardNativeControlFace(frame: bounds)
        face.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(face)
        return face
    }
}

/// Native visual hosts still need normal controller containment for trait,
/// appearance and keyboard-service lifecycle propagation.
func attachKeyboardVisualController<Content: View>(
    _ host: UIHostingController<Content>, from container: UIView
) {
    // All chrome uses the native owner's local frame. Inherited safe areas or
    // an opaque hosting canvas must not shift or cover the native controls.
    host.safeAreaRegions = []
    host.view.backgroundColor = .clear
    host.view.isOpaque = false
    host.view.isUserInteractionEnabled = false
    guard host.parent == nil else { return }
    var responder: UIResponder? = container
    while let current = responder {
        if let parent = current as? UIViewController {
            parent.addChild(host)
            container.addSubview(host.view)
            host.didMove(toParent: parent)
            return
        }
        responder = current.next
    }
    // A view can be configured before it joins the keyboard hierarchy. Its
    // next layout pass retries containment once a controller is available.
    if host.view.superview !== container { container.addSubview(host.view) }
}

func detachKeyboardVisualController(_ host: UIViewController?) {
    guard let host else { return }
    host.willMove(toParent: nil)
    host.view.removeFromSuperview()
    host.removeFromParent()
}

/// SwiftUI supplies placement; UIKit owns the mounted surface and its touches.
/// Keeping the native view outside the hosting hierarchy also makes blank areas
/// hittable, independently of SwiftUI content shapes and glass layers.
final class KeyboardNativeSurfaceHost<Surface: UIView>: UIView {
    let surface: Surface
    private let requiredMode: KeyboardAreaMode
    private let registersInput: Bool
    private let layerPosition: CGFloat

    init(surface: Surface, requiredMode: KeyboardAreaMode,
         registersInput: Bool = true, layerPosition: CGFloat = 200) {
        self.surface = surface
        self.requiredMode = requiredMode
        self.registersInput = registersInput
        self.layerPosition = layerPosition
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { unmount() } else { mount() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mount()
    }

    // The hosted keyboard's hit map must include this placement marker. Returning
    // the native sibling keeps one touch owner whichever route UIKit uses.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01,
              bounds.contains(point), let window, surface.window === window else { return nil }
        return surface.hitTest(surface.convert(point, from: self), with: event)
    }

    private func mount() {
        guard window != nil, !bounds.isEmpty else { return }
        var ancestor = superview
        while let view = ancestor, !(view is KeyboardInputView) { ancestor = view.superview }
        guard let input = ancestor as? KeyboardInputView else { return }
        input.registerNativeMount(self)
        let rect = convert(bounds, to: input)
        let changed = surface.superview !== input || surface.frame != rect
        if surface.superview !== input { input.addSubview(surface) }
        if surface.frame != rect { surface.frame = rect }
        surface.layer.zPosition = layerPosition
        surface.isHidden = KeyboardState.shared.areaMode != requiredMode
        if registersInput {
            if requiredMode == .letters { input.periodKey = surface }
            if requiredMode == .emoji { input.emojiPager = surface }
        }
        #if DEBUG
        if changed && registersInput {
            PersistentLog.log(.diagnosticProbe(
                component: "NativeKeyboardSurface", instanceID: requiredMode.rawValue,
                action: "mounted", details: "frame=\(rect) input=\(input.bounds.size)"
            ))
            DispatchQueue.main.async { [weak self, weak input] in
                guard let self, let input, !self.surface.isHidden,
                      self.surface.superview === input else { return }
                let point = self.surface.convert(
                    CGPoint(x: self.surface.bounds.midX, y: self.surface.bounds.midY), to: input
                )
                let hit = input.hitTest(point, with: nil)
                let owns = hit === self.surface || hit?.isDescendant(of: self.surface) == true
                var hostedRoot = self.superview
                while let view = hostedRoot, view.superview !== input { hostedRoot = view.superview }
                let hostedHit = hostedRoot?.hitTest(hostedRoot?.convert(point, from: input) ?? .zero, with: nil)
                let hostedOwns = hostedHit === self.surface || hostedHit?.isDescendant(of: self.surface) == true
                PersistentLog.log(.diagnosticProbe(
                    component: "NativeKeyboardSurface", instanceID: self.requiredMode.rawValue,
                    action: "routeCheck", details: "owns=\(owns) hostedOwns=\(hostedOwns) frame=\(self.surface.frame)"
                ))
            }
        }
        #endif
    }

    func unmount() {
        if let input = surface.superview as? KeyboardInputView {
            if input.periodKey === surface { input.periodKey = nil }
            if input.emojiPager === surface { input.emojiPager = nil }
        }
        surface.removeFromSuperview()
    }
}

/// Floating chrome stays above a native pager without making its clear canvas
/// an input owner. The existing SwiftUI control still owns its press lifecycle.
struct KeyboardNativeOverlay<Content: View>: UIViewRepresentable {
    let hitRect: CGRect
    let content: Content

    init(hitRect: CGRect, @ViewBuilder content: () -> Content) {
        self.hitRect = hitRect
        self.content = content()
    }

    func makeUIView(context: Context) -> KeyboardNativeSurfaceHost<KeyboardOverlayView<Content>> {
        KeyboardNativeSurfaceHost(
            surface: KeyboardOverlayView(content: content, hitRect: hitRect),
            requiredMode: .emoji, registersInput: false, layerPosition: 300
        )
    }

    func updateUIView(_ host: KeyboardNativeSurfaceHost<KeyboardOverlayView<Content>>, context: Context) {
        host.surface.hosting.rootView = content
        host.surface.hitRect = hitRect
    }

    static func dismantleUIView(_ host: KeyboardNativeSurfaceHost<KeyboardOverlayView<Content>>, coordinator: ()) {
        host.unmount()
    }
}

final class KeyboardOverlayView<Content: View>: UIView {
    let hosting: UIHostingController<Content>
    var hitRect: CGRect

    init(content: Content, hitRect: CGRect) {
        self.hosting = UIHostingController(rootView: content)
        self.hitRect = hitRect
        super.init(frame: .zero)
        backgroundColor = .clear
        hosting.safeAreaRegions = []
        hosting.view.backgroundColor = .clear
        hosting.view.isOpaque = false
        hosting.view.frame = bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(hosting.view)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01, hitRect.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

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
    var nativeMode: KeyboardAreaMode? = nil
    var highlightSize: CGSize? = nil

    func makeUIView(context: Context) -> UIView {
        let control = KeyboardKeyTouchControl()
        update(control)
        if let nativeMode {
            control.accessibilityIdentifier = "period-key"
            control.isAccessibilityElement = true
            control.accessibilityTraits = [.button]
            control.accessibilityLabel = "Period"
            control.accessibilityHint = "Hold for punctuation options."
            return KeyboardNativeSurfaceHost(surface: control, requiredMode: nativeMode)
        }
        return control
    }

    func updateUIView(_ view: UIView, context: Context) {
        if let host = view as? KeyboardNativeSurfaceHost<KeyboardKeyTouchControl> {
            update(host.surface)
        } else if let control = view as? KeyboardKeyTouchControl {
            update(control)
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        if let host = view as? KeyboardNativeSurfaceHost<KeyboardKeyTouchControl> {
            host.surface.cancelInteraction()
            host.unmount()
        }
    }

    private func update(_ control: KeyboardKeyTouchControl) {
        control.holdDuration = nil
        control.onHold = nil
        // A supplied size confines feedback to the visible face, not its wider
        // touch target. Other variants retain their full-cell feedback.
        control.highlightSize = highlightSize
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
    private let holdSession = KeyboardHoldSession()
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

    override func accessibilityActivate() -> Bool {
        guard let onBegan else { return false }
        onBegan(CGPoint(x: bounds.midX, y: bounds.midY))
        onEnded?(false)
        return true
    }

    func cancelInteraction() {
        guard !activeTouches.isEmpty else { return }
        finish(cancelled: true)
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
                holdSession.begin(after: activeHoldDuration) { [weak self] in
                    guard let self, !self.activeTouches.isEmpty else { return }
                    self.holdRecognized = true
                    self.activeHold?()
                }
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
        holdSession.cancel()
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
            existingKeyboardFace?.setPressed(isHighlighted)
            // The layer is the control's own feedback. Animate it so a press
            // reads as a press; the old path disabled implicit animation, which
            // is why every key felt like it had no response.
            let wantsFill = isHighlighted && existingKeyboardFace == nil
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
