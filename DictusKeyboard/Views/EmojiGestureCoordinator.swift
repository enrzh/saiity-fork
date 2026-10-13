import UIKit
import SyllivraKernel

/// Long-press owner for emoji variants.
///
/// `UILongPressGestureRecognizer` can be cancelled by a scroll view after it
/// begins. The letter keyboard uses a touch-tracking owner instead: the hold
/// timer decides when it begins, and movement is never a cancellation path
/// after that point. Keep the same contract for emoji variants.
final class EmojiGestureCoordinator: UIGestureRecognizer {
    private let holdSession = KeyboardHoldSession()
    private let allowableMovement: CGFloat
    private var holdToken: UUID?
    private var initialPoint = CGPoint.zero
    private weak var trackedTouch: UITouch?
    private var arbitration: EmojiHoldArbitration

    init(target: Any?, action: Selector?, minimumPressDuration: TimeInterval,
         allowableMovement: CGFloat) {
        self.allowableMovement = allowableMovement
        self.arbitration = EmojiHoldArbitration(movementAllowance: allowableMovement)
        super.init(target: target, action: action)
        // A failed hold must not cancel the pager's blank-area swipe. The
        // button tap is suppressed explicitly once a variant popup begins.
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    /// When non-nil, returning false fails the hold immediately so the pager
    /// pan is not blocked for the full recognition duration on ordinary taps.
    var shouldBeginHold: ((CGPoint) -> Bool)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard state == .possible, trackedTouch == nil else { return }
        guard let touch = touches.first, let view else {
            state = .failed
            return
        }
        let point = touch.location(in: view)
        let eligible = shouldBeginHold?(point) ?? true
        arbitration.beginTouch(eligible: eligible)
        applyArbitration()
        guard arbitration.isTracking else { return }
        trackedTouch = touch
        initialPoint = point
        let token = UUID()
        holdToken = token
        holdSession.begin(after: KeyboardDeletion.holdRecognitionDuration) { [weak self] in
            guard let self, self.holdToken == token, self.arbitration.phase == .possible else { return }
            self.arbitration.recognize()
            self.applyArbitration()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard arbitration.isTracking else { return }
        guard let trackedTouch, touches.contains(where: { $0 === trackedTouch }) else { return }
        let distance: CGFloat
        if let view {
            let point = trackedTouch.location(in: view)
            distance = hypot(point.x - initialPoint.x, point.y - initialPoint.y)
        } else {
            distance = allowableMovement + 1
        }
        arbitration.move(distance: distance)
        if arbitration.phase == .failed { holdToken = nil }
        applyArbitration()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let trackedTouch, !touches.contains(where: { $0 === trackedTouch }) { return }
        holdToken = nil
        holdSession.cancel()
        arbitration.endTouch()
        applyArbitration()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let trackedTouch, !touches.contains(where: { $0 === trackedTouch }) { return }
        holdToken = nil
        holdSession.cancel()
        arbitration.cancelTouch()
        applyArbitration()
    }

    private func applyArbitration() {
        switch arbitration.phase {
        case .possible:
            break
        case .began:
            self.state = .began
        case .changed:
            state = .changed
        case .failed:
            state = .failed
        case .ended:
            state = .ended
        case .cancelled:
            state = .cancelled
        }
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Once the popup is visible, a scroll view or ancestor recognizer must
        // not cancel the active variant session while the finger is sliding.
        if state == .began || state == .changed { return false }
        return super.canBePrevented(by: preventingGestureRecognizer)
    }

    override func reset() {
        holdToken = nil
        holdSession.cancel()
        trackedTouch = nil
        initialPoint = .zero
        arbitration = EmojiHoldArbitration(movementAllowance: allowableMovement)
        super.reset()
    }
}
