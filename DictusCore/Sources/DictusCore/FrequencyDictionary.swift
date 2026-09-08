// DictusCore/Sources/DictusCore/FrequencyDictionary.swift
// Loads word frequency rankings from JSON and provides rank-based lookup.
import Foundation

/// A dictionary that maps words to frequency counts (higher count = more common).
///
/// WHY a struct with mutating load:
/// FrequencyDictionary is a value type holding a simple [String: Int] dictionary.
/// Load is mutating because we only load the active language (not both at once)
/// to keep memory usage low -- important for keyboard extension's ~50MB limit.
/// The `load(from:)` entry point accepts raw Data so unit tests can inject
/// JSON without needing a Bundle, keeping tests fast and deterministic.
public struct FrequencyDictionary {

    private var counts: [String: Int] = [:]

    private struct RankedCompletion {
        let word: String
        let score: Int
        let index: Int
    }

    /// Maximum words to keep in memory. Only the most frequent words are retained.
    /// This dictionary is only used for ranking UITextChecker completions —
    /// we don't need rare words for ranking purposes.
    /// 10K words ≈ 3 MiB vs 40K ≈ 6 MiB. Every MiB counts in a 50MB extension.
    private static let maxWords = 10000

    public init() {}

    /// Loads frequency data from raw JSON Data.
    /// Expected format: `{"word": count, ...}` where count is an Int (higher = more common).
    /// This is the testable entry point -- no Bundle dependency.
    public mutating func load(from data: Data) {
        do {
            let decoded = try JSONDecoder().decode([String: Int].self, from: data)
            // Keep only the top N most frequent words to save memory.
            // Words not in this dictionary get rank 0 (lowest priority in sorting),
            // which is the correct behavior for rare words.
            if decoded.count > Self.maxWords {
                let top = decoded.sorted { $0.value > $1.value }.prefix(Self.maxWords)
                counts = [:]
                counts.reserveCapacity(Self.maxWords)
                for (key, value) in top {
                    counts[key] = value
                }
            } else {
                counts = decoded
            }
        } catch {
            print("[FrequencyDictionary] Failed to decode frequency data: \(error)")
            counts = [:]
        }
    }

    /// Loads frequency data for the given language from a JSON file in the specified bundle.
    /// Looks for `{language}_frequency.json` (e.g., `fr_frequency.json`).
    /// If the file is missing, prints a warning and leaves counts empty.
    public mutating func load(language: String, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "\(language)_frequency", withExtension: "json") else {
            print("[FrequencyDictionary] Missing \(language)_frequency.json in bundle")
            counts = [:]
            return
        }
        do {
            let data = try Data(contentsOf: url)
            load(from: data)
        } catch {
            print("[FrequencyDictionary] Failed to read \(language)_frequency.json: \(error)")
            counts = [:]
        }
    }

    /// Returns the word frequency count (higher = more common).
    /// Returns 0 if the word is not in the dictionary.
    /// Lookup is case-insensitive.
    public func rank(of word: String) -> Int {
        return counts[word.lowercased()] ?? 0
    }

    /// Returns the highest-ranked completions without sorting the entire input.
    ///
    /// The keyboard only displays a few slots, so keeping a bounded ordered list
    /// avoids doing O(n log n) work on every keystroke. Ties preserve the order
    /// supplied by UITextChecker, which keeps its existing deterministic priority.
    public func rankedCompletions(_ completions: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }

        var best: [RankedCompletion] = []
        best.reserveCapacity(min(limit, completions.count))

        for (index, word) in completions.enumerated() {
            let candidate = RankedCompletion(word: word, score: rank(of: word), index: index)
            let insertionIndex = best.firstIndex { current in
                candidate.score > current.score
                    || (candidate.score == current.score && candidate.index < current.index)
            }

            if let insertionIndex {
                best.insert(candidate, at: insertionIndex)
            } else if best.count < limit {
                best.append(candidate)
            }

            if best.count > limit {
                best.removeLast()
            }
        }

        return best.map(\.word)
    }

    /// Returns the top N most frequent words, sorted by count descending.
    /// Used as fallback when n-gram predictions return no results.
    ///
    /// WHY filter short words: Single-letter words ("a", "y") and common
    /// stopwords are poor standalone predictions. We require at least 2 chars
    /// to provide useful fallback suggestions.
    public func topWords(count: Int) -> [String] {
        guard count > 0 else { return [] }
        let eligible = counts.keys.filter { $0.count >= 2 }
        return rankedCompletions(Array(eligible), limit: count)
    }
}
