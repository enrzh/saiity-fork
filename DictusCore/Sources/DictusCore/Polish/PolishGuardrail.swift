// DictusCore/Sources/DictusCore/Polish/PolishGuardrail.swift
import Foundation
import NaturalLanguage

/// Runtime sanity check on every polish output.
///
/// Two complementary checks:
/// 1. `accepts(raw:polished:mode:)` — character-length ratio. Catches catastrophic
///    over- or under-generation (empty output, runaway generation).
/// 2. `detectedLanguageMatches(polished:target:)` — language detection on the
///    polished output. Catches chat-reply contamination where Apple FM responds
///    conversationally in a different language (e.g. "I'll polish it for you"
///    when the user dictated French).
public enum PolishGuardrail {

    /// Returns `true` when `polished` is within the allowed ratio band for `mode`.
    /// Natural: `[0.5, 2.0]`. Repair: `[0.3, 3.0]`. Auto (#239): same band as
    /// Natural — the auto prompt is light-corrections-only, so anything outside
    /// the Natural band is over/under-generation. Empty raw → only empty
    /// polished accepted.
    public static func accepts(raw: String, polished: String, mode: PolishMode) -> Bool {
        guard !raw.isEmpty else { return polished.isEmpty }
        let ratio = Double(polished.count) / Double(raw.count)
        switch mode {
        case .natural, .auto: return (0.5...2.0).contains(ratio)
        case .repair:         return (0.3...3.0).contains(ratio)
        }
    }

    /// Keeps list and line structure intact for light cleanup modes.
    ///
    /// A language model can produce a plausible paragraph while silently
    /// dropping line breaks or list markers. That is a destructive change for
    /// dictated notes, so the deterministic floor should win instead. Repair
    /// mode is intentionally excluded because repair is allowed to rebuild
    /// malformed structure.
    public static func preservesStructure(raw: String,
                                          polished: String,
                                          mode: PolishMode) -> Bool {
        guard mode != .repair else { return true }

        let rawLines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        let polishedLines = polished.split(separator: "\n", omittingEmptySubsequences: false)
        guard rawLines.count <= 1 || polishedLines.count >= rawLines.count else {
            return false
        }

        let rawMarkers = listMarkerCount(in: rawLines)
        guard rawMarkers > 0 else { return true }
        return listMarkerCount(in: polishedLines) >= rawMarkers
    }

    /// Returns `true` when the top language hypothesis of `polished` matches `target`
    /// with confidence ≥ 0.5. Short outputs (< 12 characters) and low-confidence
    /// detections pass through — `NLLanguageRecognizer` is unreliable on either.
    ///
    /// The intended failure to catch is the Apple FM chat-reply pattern: target=fr
    /// but the engine emitted English. The char-ratio guardrail misses this when
    /// the chat reply happens to be similar length to the raw input.
    public static func detectedLanguageMatches(polished: String,
                                               target: SupportedLanguage) -> Bool {
        matches(polished: polished, expectedCode: target.rawValue)
    }

    /// Auto-mode variant (#239): there is no target language, but the INPUT's
    /// detected language is known — the polished output must be in the same
    /// one. This is the runtime enforcement of the auto prompt's
    /// never-translate contract: it catches translation drift (e.g. English
    /// speech polished into the keyboard language) that the char-ratio check
    /// cannot see. `inputLanguageCode` is an `NLLanguage` raw value (BCP-47ish:
    /// "en", "it", "zh-Hans", …) from `PolishPipeline.detectLanguageCode`,
    /// compared against the same recognizer's verdict on the output — so both
    /// sides share one namespace.
    public static func detectedLanguageMatches(polished: String,
                                               inputLanguageCode: String) -> Bool {
        matches(polished: polished, expectedCode: inputLanguageCode)
    }

    /// Shared core: `true` when the top language hypothesis of `polished`
    /// equals `expectedCode` — or when the check cannot be trusted (short
    /// output, low confidence), which passes through.
    private static func matches(polished: String, expectedCode: String) -> Bool {
        let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        guard let top = hypotheses.max(by: { $0.value < $1.value }),
              top.value >= 0.5 else {
            return true
        }
        return top.key.rawValue == expectedCode
    }

    private static func listMarkerCount(in lines: [Substring]) -> Int {
        lines.reduce(into: 0) { count, line in
            let text = String(line)
            if text.range(of: #"^[ \t]*(?:[-*•]|[0-9]+[.)])[ \t]+"#, options: .regularExpression) != nil {
                count += 1
            }
        }
    }
}
