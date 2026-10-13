import Foundation

/// Explicitly approved spellings, separate from automatic typing observations.
/// The task-local snapshot follows one dictation through ASR and cleanup.
public enum DictationVocabulary {
    public static let maxTerms = 32
    public static let maxTermCharacters = 64
    @TaskLocal public static var currentHints: [String] = []

    public static func stored(in defaults: UserDefaults) -> [String] {
        var seen = Set<String>()
        return Array((defaults.stringArray(forKey: SharedKeys.dictationVocabulary) ?? [])
            .filter { isValid($0) && seen.insert($0.lowercased()).inserted }.prefix(maxTerms))
    }

    public static func hints(in defaults: UserDefaults) -> [String] {
        guard defaults.object(forKey: SharedKeys.vocabularyEnabled) as? Bool ?? true else { return [] }
        return stored(in: defaults)
    }

    public static func isValid(_ term: String) -> Bool {
        !term.isEmpty && term == term.trimmingCharacters(in: .whitespacesAndNewlines)
            && term.count <= maxTermCharacters && term.split(whereSeparator: \.isWhitespace).count <= 6
            && term.unicodeScalars.contains(where: CharacterSet.letters.contains)
            && !term.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    @discardableResult
    public static func approve(_ term: String, in defaults: UserDefaults) -> Bool {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(term) else { return false }
        var terms = stored(in: defaults)
        let existing = terms.firstIndex { $0.caseInsensitiveCompare(term) == .orderedSame }
        if let existing { terms[existing] = term }
        else {
            guard terms.count < maxTerms else { return false }
            terms.append(term)
        }
        defaults.set(terms, forKey: SharedKeys.dictationVocabulary)
        return true
    }

    public static func remove(_ term: String, in defaults: UserDefaults) {
        defaults.set(stored(in: defaults).filter { $0.caseInsensitiveCompare(term) != .orderedSame },
                     forKey: SharedKeys.dictationVocabulary)
    }

    public static func clear(in defaults: UserDefaults) {
        defaults.set([String](), forKey: SharedKeys.dictationVocabulary)
    }

    public static var recognitionPrompt: String { currentHints.joined(separator: ", ") }

    /// Optional server processing receives no unrelated personal vocabulary.
    public static func serverHints(for transcript: String) -> [String] {
        currentHints.filter { term in
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: term) + "(?![\\p{L}\\p{N}_])"
            return transcript.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}
