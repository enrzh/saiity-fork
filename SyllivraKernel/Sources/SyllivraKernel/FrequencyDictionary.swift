// SyllivraKernel/Sources/SyllivraKernel/FrequencyDictionary.swift
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
    private var prefixWords: [UInt8: [String]] = [:]
    private var fallbackWords: [String] = []

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
            // Preserve dictionary order within each bucket, including ranking ties.
            prefixWords.removeAll(keepingCapacity: true)
            for word in counts.keys {
                guard let first = word.utf8.first, first < 128 else { continue }
                prefixWords[first, default: []].append(word)
            }
            fallbackWords = rankedCompletions(Array(counts.keys.filter { $0.count >= 2 }), limit: 3)
        } catch {
            print("[FrequencyDictionary] Failed to decode frequency data: \(error)")
            self = FrequencyDictionary()
        }
    }

    /// Loads frequency data for the given language from a JSON file in the specified bundle.
    /// Looks for `{language}_frequency.json` (e.g., `fr_frequency.json`).
    /// If the file is missing, prints a warning and leaves counts empty.
    public mutating func load(language: String, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "\(language)_frequency", withExtension: "json") else {
            print("[FrequencyDictionary] Missing \(language)_frequency.json in bundle")
            self = FrequencyDictionary()
            return
        }
        do {
            let data = try Data(contentsOf: url)
            load(from: data)
        } catch {
            print("[FrequencyDictionary] Failed to read \(language)_frequency.json: \(error)")
            self = FrequencyDictionary()
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
        if count <= 3 { return Array(fallbackWords.prefix(count)) }
        let eligible = counts.keys.filter { $0.count >= 2 }
        return rankedCompletions(Array(eligible), limit: count)
    }

    /// Highest-frequency dictionary words that continue `prefix`.
    /// Used for next-letter priors from typed keyboard input.
    public func prefixCompletions(prefix: String, limit: Int) -> [String] {
        let needle = prefix.lowercased()
        guard let first = needle.first, limit > 0 else { return [] }
        let candidates: [String]
        if let byte = first.asciiValue {
            candidates = prefixWords[byte] ?? []
        } else {
            // Keep canonical-equivalent Unicode initials on the original path.
            candidates = Array(counts.keys)
        }
        let prefixLength = needle.count
        let matches = candidates.filter { $0.hasPrefix(needle) && $0.count > prefixLength }
        return rankedCompletions(Array(matches), limit: limit)
    }

    /// Ranked dictionary words that a swipe path can produce.
    public func swipeCandidates(path: String, limit: Int = 3) -> [String] {
        let sampled = SwipeTypingDecoder.sampledLetters(from: path)
        guard SwipeTypingDecoder.shouldCommit(path: sampled), limit > 0 else { return [] }
        let matches = counts.keys.filter { SwipeTypingDecoder.matches($0, path: sampled) }
        return rankedCompletions(matches, limit: limit)
    }

    /// Ranked dictionary words for a timed swipe using key geometry.
    /// Spatial score breaks ties that frequency alone cannot.
    public func swipeCandidates(
        touches: [SwipeTypingDecoder.Touch],
        keys: [SwipeTypingDecoder.Key],
        limit: Int = 3
    ) -> [String] {
        let sampled = SwipeTypingDecoder.sampledLetters(from: touches, keys: keys)
        guard SwipeTypingDecoder.shouldCommit(path: sampled), limit > 0 else { return [] }
        let matches = counts.keys.filter { SwipeTypingDecoder.matches($0, path: sampled) }
        let ranked = matches.compactMap { word -> (String, Double, Int)? in
            guard let score = SwipeTypingDecoder.spatialScore(word: word, touches: touches, keys: keys) else {
                return nil
            }
            return (word, score, counts[word] ?? 0)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.2 > rhs.2
        }
        return Array(ranked.prefix(limit).map(\.0))
    }
}
