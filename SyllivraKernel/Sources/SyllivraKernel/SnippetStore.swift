import Foundation

/// A user-created typed expansion, shared between the app and keyboard.
public struct TextSnippet: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var shortcut: String
    public var expansion: String

    public init(id: UUID = UUID(), shortcut: String, expansion: String) {
        self.id = id
        self.shortcut = shortcut
        self.expansion = expansion
    }
}

/// Small bounded store for text replacements created in earlier versions of the app.
/// New replacements come from iOS; these keep working until the user deletes them.
public enum SnippetStore {
    public static let retentionLimit = 100
    public static let maxShortcutCharacters = 64
    public static let maxExpansionCharacters = 4_000

    public static func load(from defaults: UserDefaults) -> [TextSnippet] {
        guard let data = defaults.data(forKey: SharedKeys.textSnippets),
              let snippets = try? JSONDecoder().decode([TextSnippet].self, from: data) else {
            return []
        }
        return Array(snippets.prefix(retentionLimit))
    }

    public static func save(_ snippets: [TextSnippet], to defaults: UserDefaults) {
        let normalized = snippets.compactMap(normalize).prefix(retentionLimit)
        guard let data = try? JSONEncoder().encode(Array(normalized)) else { return }
        defaults.set(data, forKey: SharedKeys.textSnippets)
    }

    @discardableResult
    public static func upsert(shortcut: String,
                              expansion: String,
                              in defaults: UserDefaults) -> TextSnippet? {
        guard let normalized = normalize(TextSnippet(shortcut: shortcut, expansion: expansion)) else {
            return nil
        }
        var snippets = load(from: defaults)
        snippets.removeAll { canonical($0.shortcut) == canonical(normalized.shortcut) }
        snippets.insert(normalized, at: 0)
        save(snippets, to: defaults)
        return normalized
    }

    public static func remove(_ id: UUID, from defaults: UserDefaults) {
        save(load(from: defaults).filter { $0.id != id }, to: defaults)
    }

    public static func expansion(for shortcut: String, from defaults: UserDefaults) -> String? {
        let key = canonical(shortcut)
        guard !key.isEmpty else { return nil }
        return load(from: defaults).first { canonical($0.shortcut) == key }?.expansion
    }

    private static func normalize(_ snippet: TextSnippet) -> TextSnippet? {
        let shortcut = snippet.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        let expansion = snippet.expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shortcut.isEmpty,
              !expansion.isEmpty,
              shortcut.count <= maxShortcutCharacters,
              expansion.count <= maxExpansionCharacters,
              !shortcut.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            return nil
        }
        return TextSnippet(id: snippet.id, shortcut: shortcut, expansion: expansion)
    }

    static func canonical(_ shortcut: String) -> String {
        shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// The user's iOS Text Replacements, as the keyboard's supplementary lexicon lists them.
public struct SystemTextReplacements: Equatable, Sendable {
    private var expansions: [String: String] = [:]

    public init() {}

    /// The lexicon also lists contact names, whose input and text are identical;
    /// only entries that change the typed text are replacements.
    public init(entries: [(userInput: String, documentText: String)]) {
        for entry in entries {
            let shortcut = entry.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shortcut.isEmpty, !entry.documentText.isEmpty,
                  shortcut != entry.documentText,
                  !shortcut.contains(where: { $0.isWhitespace || $0.isNewline }) else { continue }
            let key = SnippetStore.canonical(shortcut)
            if expansions[key] == nil { expansions[key] = entry.documentText }
        }
    }

    public var count: Int { expansions.count }

    public func expansion(for word: String) -> String? {
        expansions[SnippetStore.canonical(word)]
    }
}
