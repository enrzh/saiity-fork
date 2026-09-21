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
        guard let code = PolishPipeline.detectLanguageCode(
            in: text,
            confidenceThreshold: confidenceThreshold
        ) else {
            return PolishSpan(text: text, languageCode: nil, polishable: false)
        }
        return PolishSpan(text: text, languageCode: code, polishable: true)
    }

    /// Latin letters plus CJK in the same slice are a code-switch the model
    /// historically rewrites into one language. Keep those slices on the floor.
    public static func looksMixedScript(_ text: String) -> Bool {
        var latin = 0
        var cjk = 0
        for scalar in text.unicodeScalars {
            guard CharacterSet.letters.contains(scalar) else { continue }
            if isCJK(scalar) {
                cjk += 1
            } else if isLatin(scalar) {
                latin += 1
            }
        }
        return latin >= 2 && cjk >= 2
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
        let value = scalar.value
        return (0x0041...0x005A).contains(value)
            || (0x0061...0x007A).contains(value)
            || (0x00C0...0x024F).contains(value)
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value)
            || (0x3400...0x4DBF).contains(value)
            || (0x3040...0x30FF).contains(value)
            || (0xAC00...0xD7AF).contains(value)
    }
}
