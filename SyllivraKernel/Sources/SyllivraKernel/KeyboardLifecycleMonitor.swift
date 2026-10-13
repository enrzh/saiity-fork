import Foundation

/// Reads the App Group heartbeat and decides whether the writing process is gone.
public enum KeyboardLifecycleMonitor {
    public struct Reading: Equatable, Sendable {
        public let verdict: DictationSessionLiveness
        public let status: DictationStatus?
        public let heartbeatAgeMs: Int

        public init(verdict: DictationSessionLiveness, status: DictationStatus?, heartbeatAgeMs: Int) {
            self.verdict = verdict
            self.status = status
            self.heartbeatAgeMs = heartbeatAgeMs
        }
    }

    public static func reading(
        statusRaw: String?,
        heartbeat: TimeInterval?,
        localSessionStartedAt: TimeInterval?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Reading {
        let status = statusRaw.flatMap(DictationStatus.init(rawValue:))
        return Reading(
            verdict: DictationSessionLivenessPolicy.evaluate(
                status: status,
                heartbeat: heartbeat,
                localSessionStartedAt: localSessionStartedAt,
                now: now
            ),
            status: status,
            heartbeatAgeMs: heartbeat.map { Int((now - $0) * 1000) } ?? -1
        )
    }
}
