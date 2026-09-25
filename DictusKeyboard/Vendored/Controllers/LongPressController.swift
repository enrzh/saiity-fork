// DictusKeyboard/Vendored/Controllers/LongPressController.swift
// Vendored from giellakbd-ios Keyboard/Controllers/LongPressController.swift
// Stripped: Bundle.top reference replaced with Bundle.main for image loading

import UIKit
import DictusCore

protocol LongPressCursorMovementDelegate: AnyObject {
    func longpress(movedCursor step: KeyboardCursorStep)
    func longpressDidCancel()
}

protocol LongPressBehaviorProvider {
    func touchesBegan(_ point: CGPoint)
    func touchesMoved(_ point: CGPoint)
    func touchesEnded(_ point: CGPoint)
}

final class LongPressCursorMovementController: NSObject, LongPressBehaviorProvider {
    public weak var delegate: LongPressCursorMovementDelegate?

    /// Press location used to seed the shared delta sampler. A stationary
    /// finger never produces synthetic cursor movement.
    private var joystickOrigin: CGPoint?
    private var joystickSampler: KeyboardCursorJoystickSampler?
    private var latestTouchPoint: CGPoint?

    public func touchesBegan(_ point: CGPoint) {
        if joystickOrigin == nil {
            joystickOrigin = point
            joystickSampler = KeyboardCursorJoystickSampler(origin: point)
        }
        latestTouchPoint = point
        emitJoystickStep(force: true)
    }

    public func touchesMoved(_ point: CGPoint) {
        latestTouchPoint = point
        emitJoystickStep()
    }

    public func touchesEnded(_ point: CGPoint) {
        stopJoystick()
        delegate?.longpressDidCancel()
    }

    deinit {
        stopJoystick()
    }

    private func stopJoystick() {
        joystickOrigin = nil
        joystickSampler = nil
        latestTouchPoint = nil
    }

    private func emitJoystickStep(force: Bool = false) {
        guard let origin = joystickOrigin, let point = latestTouchPoint else { return }
        if joystickSampler == nil {
            joystickSampler = KeyboardCursorJoystickSampler(origin: origin)
        }
        var sampler = joystickSampler ?? KeyboardCursorJoystickSampler(origin: origin)
        let step = sampler.tick(
            to: point,
            now: Date.timeIntervalSinceReferenceDate,
            force: force
        )
        joystickSampler = sampler
        guard !step.isEmpty else { return }
        delegate?.longpress(movedCursor: step)
    }
}
