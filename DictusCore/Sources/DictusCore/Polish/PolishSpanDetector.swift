// DictusCore/Sources/DictusCore/Polish/PolishSpanDetector.swift
import Foundation
import NaturalLanguage

/// One sentence-level slice of a dictation, tagged for polish vs passthrough.
///
/// Mixed-script and low-confidence slices stay passthrough so a language-agnostic
/// model cannot fold them into one language. Adjacent slices with the same
/// decision and language are merged before the engine runs.
public struct PolishSpan: Equatable, Sendable {
    public let text: String
    /// Raw `NLLanguage` code when detection is confident, otherwise `nil`.
    public let languageCode: String?
    public let polishable: Bool

    public init(text: String, languageCode: String?, polishable: Bool) {
        self.text = text
        self.languageCode = languageCode
        self.polishable = polishable
    }
}

public enum PolishSpanDetector {
    public static let minPolishableCharacters = 12
    public static let confidenceThreshold = PolishPipeline.defaultConfidenceThreshold

    /// Split `text` into sentence spans. Empty input yields no spans.
    public static func spans(in text: String) -> [PolishSpan] {
        let trimmedProbe = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProbe.isEmpty else { return [] }

        let sentences = sentenceSlices(in: text)
        let classified = sentences.map(classify)
        return mergeAdjacent(classified)
    }

    /// Translation needs coherent clauses even within one ASR audio region.
    /// Every slice owns its original separators; joining never deduplicates speech.
    public static func translationSpans(in text: String, sourceHint: String? = nil) -> [PolishSpan] {
        sentenceSlices(in: text).flatMap { sentence -> [PolishSpan] in
            var clauses: [String] = []
            var current = ""
            let characters = Array(sentence)
            for (index, character) in characters.enumerated() {
                current.append(character)
                if ",，;；\n".contains(character),
                   !(index > 0 && index + 1 < characters.count && characters[index - 1].isNumber && characters[index + 1].isNumber) {
                    clauses.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { clauses.append(current) }
            return clauses.flatMap { clause -> [PolishSpan] in
                let probe = SpeechLanguageEvidence.languageProbe(clause)
                if probe.filter(\.isLetter).count < SpeechLanguageEvidence.minimumValidatedCharacterCount {
                    return [PolishSpan(text: clause, languageCode: nil, polishable: false)]
                }
                if let boundary = languageSwitchBoundary(in: clause) {
                    return translationSpans(in: String(clause[..<boundary]), sourceHint: sourceHint)
                        + translationSpans(in: String(clause[boundary...]), sourceHint: sourceHint)
                }
                if let source = SpeechLanguageEvidence.sourceLanguage(in: clause, hint: sourceHint) {
                    if let pattern = commandJoinPattern(language: source),
                       let expression = try? NSRegularExpression(pattern: pattern) {
                        let joins = expression.matches(in: clause, range: NSRange(clause.startIndex..., in: clause))
                        if !joins.isEmpty {
                            var start = clause.startIndex
                            var parts: [PolishSpan] = []
                            for join in joins {
                                guard let range = Range(join.range, in: clause) else { continue }
                                parts.append(PolishSpan(text: String(clause[start..<range.lowerBound]), languageCode: source, polishable: false))
                                start = range.lowerBound
                            }
                            parts.append(PolishSpan(text: String(clause[start...]), languageCode: source, polishable: false))
                            return parts
                        }
                    }
                    return [PolishSpan(text: clause, languageCode: source, polishable: false)]
                }
                var parts: [String] = []
                var run = ""
                var script: SpeechLanguageEvidence.Script?
                for character in clause {
                    let next = character.unicodeScalars.compactMap(SpeechLanguageEvidence.script(for:)).first
                    if let next, let previous = script, next != previous,
                       SpeechLanguageEvidence.isMixedLanguageScript([next, previous]) {
                        parts.append(run)
                        run = ""
                    }
                    if let next { script = next }
                    run.append(character)
                }
                if !run.isEmpty { parts.append(run) }
                return parts.map {
                    PolishSpan(text: $0, languageCode: SpeechLanguageEvidence.sourceLanguage(in: $0, hint: sourceHint), polishable: false)
                }
            }
        }
    }

    private static func commandJoinPattern(language: String) -> String? {
        // Explicit parallel instructions get independent translation results.
        switch SpeechLanguageEvidence.baseCode(language) {
        case "en": return #"(?i)[ \t]+(?:and|then)[ \t]+(?=(?:send|cancel|confirm|delete|call|check|pay)\b)"#
        case "fr": return #"(?i)[ \t]+(?:et|puis|ensuite)[ \t]+(?=(?:envoyer|annuler|confirmer|supprimer|appeler|vérifier|payer)\b)"#
        case "de": return #"(?i)[ \t]+(?:und|dann)[ \t]+(?=(?:senden|stornieren|bestätigen|löschen|prüfen|bezahlen)\b)"#
        case "es": return #"(?i)[ \t]+(?:y|luego)[ \t]+(?=(?:envía|cancela|confirma|elimina|llama|verifica|paga)\b)"#
        default: return nil
        }
    }

    static func languageSwitchBoundary(in text: String) -> String.Index? {
        let scripts = Set(SpeechLanguageEvidence.languageProbe(text).unicodeScalars.compactMap(SpeechLanguageEvidence.script(for:)))
        guard scripts == [.latin] else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 6 else { return nil }
        var best: (index: String.Index, score: Double)?
        // Bound the text-classifier work on long dictations; uncertain remainder
        // still reaches automatic translation, never a guessed word language.
        let candidates = Array(3...(words.count - 3))
        let strideSize = max(1, candidates.count / 24)
        for offset in stride(from: 0, to: candidates.count, by: strideSize) {
            let position = words[candidates[offset]].startIndex
            let left = SpeechLanguageEvidence.languageProbe(String(text[..<position]))
            let right = SpeechLanguageEvidence.languageProbe(String(text[position...]))
            guard left.filter(\.isLetter).count >= minPolishableCharacters,
                  right.filter(\.isLetter).count >= minPolishableCharacters,
                  let lhs = SpeechLanguageEvidence.hypotheses(in: left).max(by: { $0.value < $1.value }),
                  let rhs = SpeechLanguageEvidence.hypotheses(in: right).max(by: { $0.value < $1.value }),
                  lhs.key != rhs.key, lhs.value >= 0.95, rhs.value >= 0.95 else { continue }
            let score = lhs.value * rhs.value
            if score > (best?.score ?? 0) { best = (position, score) }
        }
        return best?.index
    }

    private static func sentenceSlices(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var slices: [String] = []
        var cursor = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if cursor < range.lowerBound {
                let gap = String(text[cursor..<range.lowerBound])
                slices.append(gap + String(text[range]))
            } else {
                slices.append(String(text[range]))
            }
            cursor = range.upperBound
            return true
        }
        if cursor < text.endIndex {
            let trailing = String(text[cursor...])
            if let last = slices.popLast() {
                slices.append(last + trailing)
            } else {
                slices.append(trailing)
            }
        }
        if slices.isEmpty {
            return [text]
        }
        return slices
    }

    private static func classify(_ text: String) -> PolishSpan {
        if looksMixedScript(text) {
            return PolishSpan(text: text, languageCode: nil, polishable: false)
        }
        let letterCount = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letterCount >= minPolishableCharacters else {
            return PolishSpan(text: text, languageCode: nil, polishable: false)
        }
        guard let code = SpeechLanguageEvidence.sourceLanguage(in: text) else {
            return PolishSpan(text: text, languageCode: nil, polishable: false)
        }
        return PolishSpan(text: text, languageCode: code, polishable: true)
    }

    /// Latin letters plus CJK in the same slice are a code-switch the model
    /// historically rewrites into one language. Keep those slices on the floor.
    public static func looksMixedScript(_ text: String) -> Bool {
        let scripts = Set(SpeechLanguageEvidence.languageProbe(text).unicodeScalars.compactMap(SpeechLanguageEvidence.script(for:)))
        return SpeechLanguageEvidence.isMixedLanguageScript(scripts)
    }

    private static func mergeAdjacent(_ spans: [PolishSpan]) -> [PolishSpan] {
        guard var current = spans.first else { return [] }
        var merged: [PolishSpan] = []
        for span in spans.dropFirst() {
            if span.polishable == current.polishable, span.languageCode == current.languageCode {
                current = PolishSpan(
                    text: current.text + span.text,
                    languageCode: current.languageCode,
                    polishable: current.polishable
                )
            } else {
                merged.append(current)
                current = span
            }
        }
        merged.append(current)
        return merged
    }

    static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        SpeechLanguageEvidence.script(for: scalar) == .latin
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        [.han, .kana, .hangul].contains(SpeechLanguageEvidence.script(for: scalar))
    }
}
