// SyllivraKernel/Sources/SyllivraKernel/DictationErrorChannel.swift
// The one current reason a dictation failed, shared across the two processes (#320).
import Foundation

public enum DictationFailureDisposition: String, Codable, Sendable {
    case recoverableRetry
    case requiresApp
}

public enum DictationFailureAction: Equatable, Sendable {
    case retry
    case openApp

    public enum RecoveryTransition: Equatable, Sendable {
        case resetAndRetry
        case openApp
        case retainFailed
    }

    public static func forDisposition(_ disposition: DictationFailureDisposition?) -> Self {
        disposition == .requiresApp ? .openApp : .retry
    }

    public static func recoveryTransition(
        for disposition: DictationFailureDisposition?, urlOpened: Bool
    ) -> RecoveryTransition {
        switch forDisposition(disposition) {
        case .retry:
            return .resetAndRetry
        case .openApp:
            return urlOpened ? .openApp : .retainFailed
        }
    }

    public static func fallbackMayOpen(
        expectedSessionID: String?, currentSessionID: String?,
        expectedGeneration: Int, currentGeneration: Int,
        status: DictationStatus
    ) -> Bool {
        expectedSessionID == currentSessionID
            && expectedGeneration == currentGeneration
            && status == .requested
    }
}

/// Why the last dictation failed, written by the app and read by whichever surface the
/// user happens to be looking at.
///
/// WHY this exists as a named contract rather than three `UserDefaults` calls:
/// the key itself never changed, but the *read* did, and the read is the whole bug.
/// It used to be destructive — the keyboard took the message and removed it in the
/// same breath — so the app's failure screen could never see it and fell back to a
/// hardcoded sentence about the model download, naming the one subsystem that was
/// working. Putting the three operations behind one type is what keeps a future
/// reader from re-adding a `removeObject` next to a `string(forKey:)` without seeing
/// the rule it breaks.
///
/// The rule, in one line: **reading does not consume; only a new dictation invalidates.**
///
/// WHY the next attempt and nothing else is the invalidation event (#320):
/// a TTL would have to guess how long a user takes to switch apps, a timestamp would
/// have to be compared against a clock two processes agree on, and per-surface
/// acknowledgement flags would need one flag per surface and a migration each time a
/// surface is added. None of them answer a question the status does not already
/// answer: a `.failed` status with no newer attempt behind it means the stored reason
/// is still the true one, however many minutes ago it was written.
///
/// Each surface owns its own presentation instead — the keyboard's three-second
/// toolbar message, the app's failure screen — and clears that, never the key.
public enum DictationErrorChannel {

    /// Store the reason the current dictation failed. Overwrites any previous one:
    /// this channel holds one reason, not a history.
    public static func record(_ message: String, disposition: DictationFailureDisposition = .recoverableRetry) {
        let defaults = AppGroup.defaults
        defaults.set(message, forKey: SharedKeys.lastError)
        defaults.set(disposition.rawValue, forKey: SharedKeys.failureDisposition)
        defaults.synchronize()
    }

    /// The stored reason, or nil when none was recorded since the last dictation started.
    ///
    /// Non-destructive by contract. Both processes read this, and neither can know
    /// whether the other has read it yet.
    public static var current: String? {
        AppGroup.defaults.string(forKey: SharedKeys.lastError)
    }

    public static var currentDisposition: DictationFailureDisposition? {
        guard let raw = AppGroup.defaults.string(forKey: SharedKeys.failureDisposition) else { return nil }
        return DictationFailureDisposition(rawValue: raw)
    }

    /// Drop the stored reason. Called when a dictation starts, and from nowhere else:
    /// a new attempt is what makes the previous attempt's error stale.
    public static func clear() {
        let defaults = AppGroup.defaults
        defaults.removeObject(forKey: SharedKeys.lastError)
        defaults.removeObject(forKey: SharedKeys.failureDisposition)
        defaults.synchronize()
    }
}
