import Foundation

/// One successful dictation kept for the Home recents list.
public struct RecentDictation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: TimeInterval
    public var originalText: String?

    public init(id: UUID = UUID(), text: String, createdAt: TimeInterval = Date().timeIntervalSince1970,
                originalText: String? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.originalText = originalText
    }
}

/// Bounded transcript recents. Newest first. Not the diagnostic issue-report slot.
public enum RecentDictations {
    public static let retentionLimit = 30
    public static let maxTextCharacters = 8_000

    public static func append(_ text: String, in defaults: UserDefaults, at date: Date = Date(), originalText: String? = nil) {
        guard defaults.object(forKey: SharedKeys.historyEnabled) as? Bool ?? true else {
            ensureTombstone(in: defaults)
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let clamped = String(trimmed.prefix(maxTextCharacters))
        var items = load(from: defaults)
        items.removeAll { $0.text == clamped }
        items.insert(RecentDictation(text: clamped, createdAt: date.timeIntervalSince1970,
            originalText: originalText.map { String($0.prefix(maxTextCharacters)) }), at: 0)
        if items.count > retentionLimit {
            items = Array(items.prefix(retentionLimit))
        }
        store(items, in: defaults)
    }

    public static func load(from defaults: UserDefaults) -> [RecentDictation] {
        guard let data = defaults.data(forKey: SharedKeys.recentDictations),
              let items = try? JSONDecoder().decode([RecentDictation].self, from: data) else {
            return migratedSingleSlot(from: defaults)
        }
        return Array(items.prefix(retentionLimit))
    }

    public static func clear(in defaults: UserDefaults) {
        store([], in: defaults)
    }

    /// Disabling history must not erase existing entries, but an empty slot prevents
    /// a legacy single-result value from being migrated after the preference is re-enabled.
    public static func disable(in defaults: UserDefaults) {
        ensureTombstone(in: defaults)
        LastDictationIssueReport.removeTranscriptFields(in: defaults)
    }

    public static func remove(_ id: UUID, from defaults: UserDefaults) {
        store(load(from: defaults).filter { $0.id != id }, in: defaults)
    }

    public static func update(_ item: RecentDictation, in defaults: UserDefaults) {
        var items = load(from: defaults)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        items[index] = RecentDictation(
            id: item.id,
            text: String(text.prefix(maxTextCharacters)),
            createdAt: item.createdAt,
            originalText: items[index].originalText
        )
        store(items, in: defaults)
    }


    private static func store(_ items: [RecentDictation], in defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(items), forKey: SharedKeys.recentDictations)
    }

    private static func ensureTombstone(in defaults: UserDefaults) {
        guard defaults.object(forKey: SharedKeys.recentDictations) == nil else { return }
        store([], in: defaults)
    }

    /// First launch after this feature: keep the last in-memory/App Group transcript.
    private static func migratedSingleSlot(from defaults: UserDefaults) -> [RecentDictation] {
        guard defaults.object(forKey: SharedKeys.historyEnabled) as? Bool ?? true else { return [] }
        let text = defaults.string(forKey: SharedKeys.lastTranscription)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return [] }
        let timestamp = defaults.object(forKey: SharedKeys.lastTranscriptionTimestamp) as? Double
            ?? Date().timeIntervalSince1970
        let item = RecentDictation(
            text: String(text.prefix(maxTextCharacters)),
            createdAt: timestamp
        )
        store([item], in: defaults)
        return [item]
    }
}
