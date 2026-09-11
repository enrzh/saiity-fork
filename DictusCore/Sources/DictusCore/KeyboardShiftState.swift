import Foundation

/// The three states used by the letter keyboard's shift key.
///
/// Keeping the transition independent from the view makes the caps-lock
/// behavior deterministic and testable without synthesizing touch events.
public enum KeyboardShiftState: String, Equatable, Sendable {
    case normal
    case shifted
    case capsLock

    /// Returns the state after one completed shift-key tap.
    ///
    /// A second tap only promotes a temporary shift to caps lock. Once caps
    /// lock is active, every tap turns it off, including a fast tap.
    public func state(afterTapIsWithinDoubleTapWindow: Bool) -> KeyboardShiftState {
        switch self {
        case .normal:
            return .shifted
        case .shifted:
            return afterTapIsWithinDoubleTapWindow ? .capsLock : .normal
        case .capsLock:
            return .normal
        }
    }
}
