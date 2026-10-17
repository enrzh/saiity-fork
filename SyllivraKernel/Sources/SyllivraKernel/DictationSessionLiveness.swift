import Foundation

public enum DictationSessionLiveness: String, Equatable, Sendable {
    case notActive
    case live
    case unproven
    case orphaned
}

public enum DictationSessionLivenessPolicy {
    // Recording beats every second and must be reconciled before the five-second waveform watchdog.
    public static let recordingStaleThreshold: TimeInterval = 4
    // Transcription/processing use the idle audio heartbeat, which arrives every three seconds.
    public static let transcribingStaleThreshold: TimeInterval = 8

    public static func isActive(_ status: DictationStatus) -> Bool {
        switch status {
        case .idle, .ready, .failed: return false
        case .requested, .recording, .transcribing, .processing: return true
        }
    }

    public static func staleThreshold(for status: DictationStatus) -> TimeInterval? {
        switch status {
        case .recording: return recordingStaleThreshold
        case .transcribing, .processing: return transcribingStaleThreshold
        case .requested, .idle, .ready, .failed: return nil
        }
    }

    public static func evaluate(status: DictationStatus?, heartbeat: TimeInterval?,
                                localSessionStartedAt: TimeInterval? = nil,
                                now: TimeInterval) -> DictationSessionLiveness {
        guard let status, isActive(status) else { return .notActive }
        // A request awaiting app preparation has no heartbeat to judge yet.
        guard let limit = staleThreshold(for: status), let heartbeat,
              heartbeat.isFinite, heartbeat > 0, now.isFinite else { return .unproven }
        if let start = localSessionStartedAt {
            guard start.isFinite, heartbeat > start else { return .unproven }
        }
        // Clock rollback is not evidence that the recording process died.
        return now - heartbeat > limit ? .orphaned : .live
    }
}
