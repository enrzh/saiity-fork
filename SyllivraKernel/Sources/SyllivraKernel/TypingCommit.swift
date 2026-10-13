// SyllivraKernel/Sources/SyllivraKernel/TypingCommit.swift
import Foundation

/// Which prepared corrections space is allowed to insert.
///
/// A commit is a small change: an accent, an apostrophe, a one-character
/// split, or a one-letter slip. Facts and distant rewrites stay as typed.
public enum TypingCommit {
    public static func accepts(typed: String, correction: String) -> Bool {
        let original = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, !replacement.isEmpty else { return false }
        guard original.caseInsensitiveCompare(replacement) != .orderedSame else { return false }
        if TypingFact.shouldLeaveUntouched(original) || TypingFact.isOpenPrefix(original) {
            return false
        }
        if isAccentOnly(original, replacement) || isApostropheRepair(original, replacement) {
            return true
        }
        if replacement.contains(" ") {
            let joined = replacement.replacingOccurrences(of: " ", with: "")
            return editDistance(folded(original), folded(joined)) <= 1
        }
        return editDistance(folded(original), folded(replacement)) <= 1
    }

    private static func isAccentOnly(_ typed: String, _ correction: String) -> Bool {
        let left = folded(typed)
        let right = folded(correction)
        return left == right && typed.caseInsensitiveCompare(correction) != .orderedSame
    }

    private static func isApostropheRepair(_ typed: String, _ correction: String) -> Bool {
        let left = withoutApostrophes(typed)
        let right = withoutApostrophes(correction)
        guard left == right, !left.isEmpty else { return false }
        return typed.contains("'") || typed.contains("’")
            || correction.contains("'") || correction.contains("’")
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func withoutApostrophes(_ text: String) -> String {
        folded(text)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
    }

    /// Adjacent transposition counts as one change, so `teh` can become `the`.
    private static func editDistance(_ a: String, _ b: String) -> Int {
        let left = Array(a)
        let right = Array(b)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }
        var older = Array(repeating: 0, count: right.count + 1)
        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(
                    current[j - 1] + 1,
                    previous[j] + 1,
                    previous[j - 1] + cost
                )
                if i > 1, j > 1,
                   left[i - 1] == right[j - 2],
                   left[i - 2] == right[j - 1] {
                    current[j] = min(current[j], older[j - 2] + 1)
                }
            }
            older = previous
            previous = current
        }
        return previous[right.count]
    }
}
