import Foundation

/// Bounded snapshot of the most recent dictation for an opt-in issue report.
///
/// One slot only: each new dictation overwrites the previous snapshot. Transcript
/// text is stored so the user can choose to include it later; export omits it
/// unless they opt in. Nothing here is sent automatically.
public struct LastDictationIssueSnapshot: Codable, Equatable, Sendable {
    public var createdAt: TimeInterval
    public var appVersion: String
    public var buildNumber: String
    public var modelIdentifier: String
    public var engineName: String
    public var outputMode: String
    public var transcriptionMode: String
    public var translationTarget: String?
    public var stage: String
    public var failureStage: String?
    public var errorSummary: String?
    public var recordingDurationMs: Int?
    public var transcribeMs: Int?
    public var polishMs: Int?
    public var rawText: String?
    public var cleanedText: String?

    public init(
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        appVersion: String,
        buildNumber: String,
        modelIdentifier: String,
        engineName: String,
        outputMode: String,
        transcriptionMode: String,
        translationTarget: String? = nil,
        stage: String,
        failureStage: String? = nil,
        errorSummary: String? = nil,
        recordingDurationMs: Int? = nil,
        transcribeMs: Int? = nil,
        polishMs: Int? = nil,
        rawText: String? = nil,
        cleanedText: String? = nil
    ) {
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.modelIdentifier = modelIdentifier
        self.engineName = engineName
        self.outputMode = outputMode
        self.transcriptionMode = transcriptionMode
        self.translationTarget = translationTarget
        self.stage = stage
        self.failureStage = failureStage
        self.errorSummary = errorSummary
        self.recordingDurationMs = recordingDurationMs
        self.transcribeMs = transcribeMs
        self.polishMs = polishMs
        self.rawText = rawText
        self.cleanedText = cleanedText
    }
}

public enum LastDictationIssueReport {
    public static let maxTextCharacters = 8_000
    public static let maxErrorCharacters = 240
    public static let retentionLimit = 1

    public static func store(_ snapshot: LastDictationIssueSnapshot, in defaults: UserDefaults) {
        var bounded = snapshot
        bounded.rawText = clamp(snapshot.rawText)
        bounded.cleanedText = clamp(snapshot.cleanedText)
        bounded.errorSummary = clamp(snapshot.errorSummary, limit: maxErrorCharacters)
        defaults.set(try? JSONEncoder().encode(bounded), forKey: SharedKeys.lastDictationIssueSnapshot)
    }

    public static func load(from defaults: UserDefaults) -> LastDictationIssueSnapshot? {
        guard let data = defaults.data(forKey: SharedKeys.lastDictationIssueSnapshot) else { return nil }
        return try? JSONDecoder().decode(LastDictationIssueSnapshot.self, from: data)
    }

    public static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: SharedKeys.lastDictationIssueSnapshot)
    }

    /// Export payload. Transcript fields are present only when `includeText` is true.
    public static func exportSnapshot(
        _ snapshot: LastDictationIssueSnapshot,
        includeText: Bool
    ) -> LastDictationIssueSnapshot {
        var exported = snapshot
        if !includeText {
            exported.rawText = nil
            exported.cleanedText = nil
        }
        return exported
    }

    public static func exportData(
        _ snapshot: LastDictationIssueSnapshot,
        includeText: Bool
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(exportSnapshot(snapshot, includeText: includeText))
    }

    public static func previewString(
        _ snapshot: LastDictationIssueSnapshot,
        includeText: Bool
    ) -> String {
        (try? String(data: exportData(snapshot, includeText: includeText), encoding: .utf8)) ?? "{}"
    }

    /// Raw transcript used by an explicit revert. Nil when the user has not
    /// kept a last snapshot or the raw slot is empty.
    public static func recoverableRawText(from defaults: UserDefaults) -> String? {
        let raw = load(from: defaults)?.rawText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    private static func clamp(_ value: String?, limit: Int = maxTextCharacters) -> String? {
        guard let value else { return nil }
        if value.count <= limit { return value }
        return String(value.prefix(limit))
    }
}
