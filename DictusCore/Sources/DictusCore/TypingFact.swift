// DictusCore/Sources/DictusCore/TypingFact.swift
import Foundation

/// Tokens the typist or the speaker already decided: amounts, clock times,
/// invoice codes, and names. Prediction may use them as context. It must not
/// rewrite them, and a missing word-pair must not invent a common word in
/// their place.
public enum TypingFact {

    /// One fact and where it sits in the original text, in UTF-16 so it lines
    /// up with a correction marker found by a regular expression.
    public struct SpokenFact: Equatable {
        public let token: String
        public let utf16Offset: Int

        public init(token: String, utf16Offset: Int) {
            self.token = token
            self.utf16Offset = utf16Offset
        }
    }

    /// A committed token whose spelling is the fact. Ordinary words return false.
    public static func shouldLeaveUntouched(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .punctuationCharacters)
        guard !trimmed.isEmpty else { return false }
        if trimmed.range(of: #"^\d{1,2}(?::\d{2})?(?:am|pm)$"#,
                         options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if trimmed.range(of: #"^[A-Za-z]{1,12}[-/]\d{2,}$"#, options: .regularExpression) != nil
            || trimmed.range(of: #"^\d{2,}[-/][A-Za-z]{1,12}$"#, options: .regularExpression) != nil {
            return true
        }
        let hasDigit = trimmed.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
        guard hasDigit else { return false }
        if trimmed.contains(where: \.isLetter) { return true }
        return trimmed.contains(".") || trimmed.contains(",") || trimmed.contains(":")
    }

    /// The token is still being typed and already looks like a fact, so the
    /// next-letter prior stays neutral.
    public static func isOpenPrefix(_ partial: String) -> Bool {
        if shouldLeaveUntouched(partial) { return true }
        if partial.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) {
            return true
        }
        return partial.range(of: #"^[A-Z]{1,12}[-/]$"#, options: .regularExpression) != nil
    }

    /// Drops fact tokens so the word before a code or an amount remains the
    /// language context. An all-fact window returns an empty list.
    public static func contextWords(from words: [String]) -> [String] {
        words.filter { !shouldLeaveUntouched($0) && !isOpenPrefix($0) }
    }

    /// Extra weight for the next letter of a name or learned spelling that
    /// continues `prefix`. Empty when the prefix is a fact or has no continuation.
    public static func recallWeights(prefix: String, tokens: [String]) -> [String: Double] {
        let normalized = prefix.lowercased()
        guard !normalized.isEmpty, !isOpenPrefix(prefix) else { return [:] }
        var weights: [String: Double] = [:]
        for token in tokens {
            let lowered = token.lowercased()
            guard lowered.hasPrefix(normalized), lowered.count > normalized.count else { continue }
            let nextIndex = lowered.index(lowered.startIndex, offsetBy: normalized.count)
            let next = String(lowered[nextIndex])
            guard next.count == 1, next.allSatisfy(\.isLetter) else { continue }
            weights[next, default: 0] += 36
        }
        return weights
    }

    /// Mid-sentence given names and acronyms, in reading order. A capitalized
    /// word that only exists because it opens a sentence is not included.
    public static func anchoredNames(in text: String) -> [String] {
        scannedWords(in: text).compactMap { word, sentenceStart, _ in
            if ignoredAcronyms.contains(word) { return nil }
            if isAcronym(word) { return word }
            if isGivenName(word), !sentenceStart { return word }
            return nil
        }
    }

    /// The first word when it is a capitalized name rather than a lowercase
    /// sentence opener that cleanup later capitalizes.
    public static func openingName(in text: String) -> String? {
        guard let first = scannedWords(in: text).first, first.sentenceStart, isGivenName(first.word) else {
            return nil
        }
        guard !sentenceOpeners.contains(first.word.lowercased()) else { return nil }
        return first.word
    }

    public static func openingWord(in text: String) -> String? {
        scannedWords(in: text).first?.word
    }

    /// Clock times and letter-digit codes, normalized and in reading order.
    /// `4 a.m.` and `4am` compare equal. Amounts made only of digits stay on
    /// the number check.
    public static func atomicFacts(in text: String) -> [String] {
        atomicFactSpans(in: text).map(\.token)
    }

    public static func atomicFactSpans(in text: String) -> [SpokenFact] {
        spans(in: text, pattern: #"(?i)\b(?:\d{1,2}(?::\d{2})?\s*[ap]\s*\.?\s*m\.?|[A-Za-z]{1,12}-\d{2,}|\d{2,}-[A-Za-z]{1,12})\b"#)
            .map { SpokenFact(token: normalizeAtomic($0.token), utf16Offset: $0.utf16Offset) }
    }

    /// Names and acronyms with their position, including a capitalized name
    /// that opens the text. Sentence openers such as "Please" are not names.
    public static func nameSpans(in text: String) -> [SpokenFact] {
        scannedWords(in: text).enumerated().compactMap { index, word in
            if ignoredAcronyms.contains(word.word) { return nil }
            let fact = SpokenFact(token: word.word, utf16Offset: word.utf16Offset)
            if isAcronym(word.word) { return fact }
            guard isGivenName(word.word) else { return nil }
            if !word.sentenceStart { return fact }
            guard index == 0, !sentenceOpeners.contains(word.word.lowercased()) else { return nil }
            return fact
        }
    }

    /// UTF-16 offset of the last spoken correction, when the text has one.
    public static func lastCorrectionMarkerOffset(in text: String) -> Int? {
        let pattern = #"(?i)\b(?:oh\s+sorry|sorry|actually|i mean|wait|rather)\b"#
        return spans(in: text, pattern: pattern).last?.utf16Offset
    }

    /// `polished` may collapse an immediate duplicate. It may not invent a
    /// token. Dropping a superseded fact requires `preservesSpokenFacts`,
    /// which knows where the speaker corrected themselves.
    public static func keepsFacts(_ polished: [String], from raw: [String]) -> Bool {
        if raw == polished { return true }
        guard isSubsequence(polished, of: raw) else { return false }
        return collapsingConsecutiveDuplicates(raw) == polished
    }

    /// A correction may drop facts that sit before the marker when a later
    /// fact replaces them. Facts at or after the marker stay. A cue with no
    /// replacement fact does not license deleting the only amount or name.
    public static func preservesSpokenFacts(
        polishedTokens: [String],
        rawFacts: [SpokenFact],
        correctionMarkerUTF16: Int?
    ) -> Bool {
        let rawTokens = rawFacts.map(\.token)
        if keepsFacts(polishedTokens, from: rawTokens) { return true }
        guard isSubsequence(polishedTokens, of: rawTokens) else { return false }
        guard let marker = correctionMarkerUTF16 else { return false }
        let kept = collapsingConsecutiveDuplicates(
            rawFacts.filter { $0.utf16Offset >= marker }.map(\.token)
        )
        guard !kept.isEmpty else { return false }
        return isSubsequence(kept, of: polishedTokens)
    }

    private static let ignoredAcronyms: Set<String> = ["AM", "PM"]

    /// Words that are capitalized because they open a sentence, not because
    /// they are a name. A real name at the start of a sentence stays protected.
    private static let sentenceOpeners: Set<String> = [
        "the", "this", "that", "these", "those", "what", "when", "where", "why", "how",
        "please", "send", "meet", "hey", "hello", "hi", "dear", "thanks", "thank",
        "can", "could", "would", "should", "have", "has", "had", "will", "just", "also",
        "and", "but", "for", "not", "yes", "yeah", "so", "we", "our", "you", "your",
        "they", "their", "his", "her", "she", "its", "from", "with", "about", "after",
        "before", "into", "over", "then", "than", "there", "here", "good", "great",
        "sure", "well", "now", "today", "tomorrow", "yesterday", "let", "make", "take",
        "get", "got", "need", "want", "like", "know", "think", "see", "look", "come",
        "sorry", "wait", "actually", "really", "very", "still", "already", "maybe",
        "ich", "der", "die", "das", "ein", "eine", "und", "aber", "wir", "sie", "mit",
        "für", "nicht", "auch", "bitte", "hallo", "guten", "heute", "morgen",
        "je", "tu", "il", "elle", "on", "nous", "vous", "les", "des", "une", "pas",
        "pour", "avec", "dans", "sur", "mais", "bonjour", "merci", "salut",
        "yo", "el", "la", "los", "las", "un", "una", "por", "para", "con", "hoy",
        "hola", "gracias", "buenos"
    ]

    private static func normalizeAtomic(_ token: String) -> String {
        token.lowercased().filter { !$0.isWhitespace && $0 != "." }
    }

    private static func isGivenName(_ word: String) -> Bool {
        guard word.count >= 3, let first = word.first, first.isUppercase else { return false }
        return word.dropFirst().allSatisfy { $0.isLowercase || $0 == "'" || $0 == "’" || $0 == "-" }
    }

    private static func isAcronym(_ word: String) -> Bool {
        word.count >= 2 && word.allSatisfy(\.isUppercase)
    }

    private static func spans(in text: String, pattern: String) -> [SpokenFact] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            SpokenFact(token: source.substring(with: match.range), utf16Offset: match.range.location)
        }
    }

    private static func scannedWords(in text: String) -> [(word: String, sentenceStart: Bool, utf16Offset: Int)] {
        var words: [(String, Bool, Int)] = []
        var sentenceStart = true
        var word = ""
        var wordOffset: Int?
        var utf16 = 0
        func flush() {
            let cleaned = word.trimmingCharacters(in: CharacterSet(charactersIn: "-'’"))
            let offset = wordOffset
            word = ""
            wordOffset = nil
            guard !cleaned.isEmpty, let offset else { return }
            words.append((cleaned, sentenceStart, offset))
            sentenceStart = false
        }
        for character in text {
            if character.isNewline {
                flush()
                sentenceStart = true
            } else if character.isWhitespace {
                flush()
            } else if ".!?…".contains(character) {
                flush()
                sentenceStart = true
            } else if ",;:".contains(character) || character.isNumber {
                flush()
            } else if character.isLetter || character == "'" || character == "’" || character == "-" {
                if word.isEmpty { wordOffset = utf16 }
                word.append(character)
            } else {
                flush()
            }
            utf16 += character.utf16.count
        }
        flush()
        return words
    }

    private static func isSubsequence(_ sub: [String], of full: [String]) -> Bool {
        var index = 0
        for token in full where index < sub.count && token == sub[index] {
            index += 1
        }
        return index == sub.count
    }

    private static func collapsingConsecutiveDuplicates(_ tokens: [String]) -> [String] {
        tokens.reduce(into: [String]()) { result, token in
            if result.last != token { result.append(token) }
        }
    }
}
