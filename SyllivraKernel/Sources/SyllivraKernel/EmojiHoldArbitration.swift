import CoreGraphics
import Foundation

/// State machine for the emoji skin-tone hold.
///
/// The collection view's pan waits until this recognizer fails. An ineligible
/// touch (blank Recents, a glyph with no tones) must fail immediately. Once a
/// hold has begun, movement keeps that ownership until release or cancellation.
public enum EmojiHoldPhase: String, Equatable, Sendable {
    case possible
    case began
    case changed
    case failed
    case ended
    case cancelled
}

public struct EmojiHoldArbitration: Equatable, Sendable {
    public var phase: EmojiHoldPhase
    public private(set) var isTracking: Bool
    public let movementAllowance: CGFloat

    public init(movementAllowance: CGFloat, phase: EmojiHoldPhase = .possible) {
        self.phase = phase
        self.isTracking = false
        self.movementAllowance = movementAllowance
    }

    /// A touch the hold cannot own. Failing here is what lets the pager pan start.
    public mutating func beginTouch(eligible: Bool) {
        guard phase == .possible, !isTracking else { return }
        guard eligible else {
            phase = .failed
            return
        }
        isTracking = true
    }

    public mutating func move(distance: CGFloat) {
        switch phase {
        case .began, .changed:
            phase = .changed
        case .possible where isTracking:
            if distance > movementAllowance {
                isTracking = false
                phase = .failed
            }
        case .possible:
            // The began path never tracked this touch, so a later move must
            // still release the pan instead of leaving the hold possible.
            phase = .failed
        case .failed, .ended, .cancelled:
            break
        }
    }

    /// The hold timer fired while the finger was still within the allowance.
    public mutating func recognize() {
        guard phase == .possible, isTracking else { return }
        phase = .began
    }

    public mutating func endTouch() {
        switch phase {
        case .began, .changed:
            isTracking = false
            phase = .ended
        case .possible:
            isTracking = false
            phase = .failed
        case .failed, .ended, .cancelled:
            break
        }
    }

    public mutating func cancelTouch() {
        switch phase {
        case .failed, .ended, .cancelled:
            break
        case .possible, .began, .changed:
            isTracking = false
            phase = .cancelled
        }
    }
}
