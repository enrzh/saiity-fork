import Foundation

/// Dispatch uptime is boot-relative on the same device, including across the
/// app and keyboard processes. Dates are deliberately excluded from durations.
public struct DictationRuntimeMetrics: Codable, Sendable, Equatable {
    public let sessionID: String
    public let stopUptimeNanoseconds: UInt64
    public private(set) var stagesMs: [String: Double] = [:]
    public private(set) var context: [String: String] = [:]

    public init(sessionID: String, stopUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        self.sessionID = sessionID
        self.stopUptimeNanoseconds = stopUptimeNanoseconds
    }

    private enum CodingKeys: String, CodingKey { case sessionID, stopUptimeNanoseconds, stagesMs, context }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        stopUptimeNanoseconds = try values.decode(UInt64.self, forKey: .stopUptimeNanoseconds)
        stagesMs = try values.decodeIfPresent([String: Double].self, forKey: .stagesMs) ?? [:]
        context = try values.decodeIfPresent([String: String].self, forKey: .context) ?? [:]
    }

    public mutating func mark(_ stage: String, now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        guard now >= stopUptimeNanoseconds else { return }
        stagesMs[stage] = Double(now - stopUptimeNanoseconds) / 1_000_000
    }

    public mutating func setContext(_ key: String, value: String) {
        context[key] = value
    }

    public func log(outcome: String = "inserted") {
        let stages = stagesMs.keys.sorted().map { "\($0)=\(String(format: "%.2f", stagesMs[$0] ?? 0))ms" }
        let metadata = context.keys.sorted().map { "\($0)=\(context[$0] ?? "unknown")" }
        PersistentLog.log(.diagnosticProbe(component: "DictationTiming", instanceID: sessionID,
            action: "stopToProxy", details: (["outcome=\(outcome)"] + metadata + stages).joined(separator: " ")))
    }

    public static func elapsedMilliseconds(since start: UInt64) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        return now >= start ? Int((now - start) / 1_000_000) : 0
    }
}
