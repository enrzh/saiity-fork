import Foundation
import NaturalLanguage

/// Script evidence used to keep a weak Whisper language token from controlling
/// an entire mixed-language recording.
public struct SpeechLanguageEvidence: Equatable, Sendable {
    public static let minimumValidatedCharacterCount = 8
    public static let minimumValidatedScore = 0.75

    public enum Script: String, CaseIterable, Sendable {
        case latin
        case cyrillic
        case arabic
        case han
        case kana
        case hangul
        case devanagari
        case hebrew, bengali, tamil, thai, greek
        case other
    }

    public let detectedLanguage: String?
    public let observedScripts: Set<Script>
    public let expectedScript: Script?
    public let score: Double
    public let isMixedScript: Bool
    public let meaningfulCharacterCount: Int
    let hasLanguageSwitch: Bool
    private let resolvedLanguage: String?

    public init(detectedLanguage: String?,
                observedScripts: Set<Script>,
                expectedScript: Script?,
                score: Double,
                isMixedScript: Bool,
                meaningfulCharacterCount: Int = 0,
                resolvedLanguage: String? = nil,
                hasLanguageSwitch: Bool = false) {
        self.detectedLanguage = detectedLanguage
        self.observedScripts = observedScripts
        self.expectedScript = expectedScript
        self.score = score
        self.isMixedScript = isMixedScript
        self.meaningfulCharacterCount = meaningfulCharacterCount
        self.hasLanguageSwitch = hasLanguageSwitch
        self.resolvedLanguage = resolvedLanguage
    }

    public static func analyze(text: String, detectedLanguage: String?) -> SpeechLanguageEvidence {
        let probe = languageProbe(text)
        let scripts = Set(probe.unicodeScalars.compactMap(script(for:)))
        let expected = expectedScript(for: detectedLanguage)
        let isMixed = isMixedLanguageScript(scripts)
        let meaningfulCharacterCount = probe.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let hasLanguageSwitch = scripts == [.latin]
            && meaningfulCharacterCount >= minimumValidatedCharacterCount
            && PolishSpanDetector.languageSwitchBoundary(in: text) != nil
        let resolved = resolveSourceLanguage(probe: probe, hint: detectedLanguage, scripts: scripts,
            letters: meaningfulCharacterCount, hasLanguageSwitch: hasLanguageSwitch)
        let score: Double

        guard !scripts.isEmpty else {
            score = 0.5
            return SpeechLanguageEvidence(
                detectedLanguage: detectedLanguage,
                observedScripts: scripts,
                expectedScript: expected,
                score: score,
                isMixedScript: false,
                meaningfulCharacterCount: meaningfulCharacterCount,
                resolvedLanguage: resolved,
                hasLanguageSwitch: hasLanguageSwitch
            )
        }

        guard let expected else {
            score = isMixed ? 0.65 : 0.5
            return SpeechLanguageEvidence(
                detectedLanguage: detectedLanguage,
                observedScripts: scripts,
                expectedScript: nil,
                score: score,
                isMixedScript: isMixed,
                meaningfulCharacterCount: meaningfulCharacterCount,
                resolvedLanguage: resolved,
                hasLanguageSwitch: hasLanguageSwitch
            )
        }

        if scripts.contains(expected) {
            // A mixed script is normal for code-switching. It lowers confidence
            // slightly but never discards the transcript or translates it.
            score = isMixed ? 0.82 : 1.0
        } else {
            score = 0.2
        }
        return SpeechLanguageEvidence(
            detectedLanguage: detectedLanguage,
            observedScripts: scripts,
            expectedScript: expected,
            score: score,
            isMixedScript: isMixed,
            meaningfulCharacterCount: meaningfulCharacterCount,
            resolvedLanguage: resolved,
            hasLanguageSwitch: hasLanguageSwitch
        )
    }

    /// Local phrase evidence can correct a stale tag. Shared/short fragments and
    /// contradictory evidence remain uncertain rather than choosing a language.
    public var validatedLanguageCode: String? {
        resolvedLanguage
    }

    /// Hints are evidence to validate, never a fallback after validation declined.
    public static func sourceLanguage(in text: String, hint: String? = nil) -> String? {
        analyze(text: text, detectedLanguage: hint).validatedLanguageCode
    }

    private static func resolveSourceLanguage(probe: String, hint: String?, scripts: Set<Script>,
                                              letters: Int, hasLanguageSwitch: Bool) -> String? {
        guard letters >= minimumValidatedCharacterCount else { return nil }
        guard !scripts.isEmpty, !isMixedLanguageScript(scripts), !scripts.contains(.other) else { return nil }
        guard !hasLanguageSwitch else { return nil }
        if scripts.contains(.kana) || scripts.contains(.hangul) {
            // A coherent Chinese clause next to Japanese grammar is not Japanese.
            if let expression = try? NSRegularExpression(pattern: #"\p{script=Han}{4,}"#) {
                for match in expression.matches(in: probe, range: NSRange(probe.startIndex..., in: probe)) {
                    guard let range = Range(match.range, in: probe) else { continue }
                    let run = String(probe[range])
                    let chineseGrammar = run.range(of: "我们|我們|明天|今天|需要|付款|这个|這個", options: .regularExpression) != nil
                    if (run.count >= 8 || chineseGrammar), (hypotheses(in: run)["zh"] ?? 0) >= 0.9 { return nil }
                }
            }
        }
        if scripts.contains(.kana) {
            return baseCode(hint) == "ja" ? hint : "ja"
        }
        if scripts.contains(.hangul) { return baseCode(hint) == "ko" ? hint : "ko" }
        // Han alone is shared by several languages; a short name is not Chinese.
        if scripts == [.han], letters < 12 { return nil }
        let readings = hypotheses(in: probe)
        guard let best = readings.max(by: { $0.value < $1.value }), best.value >= 0.9 else { return nil }
        let hinted = baseCode(hint)
        // A shared-script classifier without a corroborating audio/request hint
        // is not enough to choose among related languages for translation.
        if hint == nil, scripts.count == 1,
           !scripts.isDisjoint(with: [.cyrillic, .arabic, .hebrew, .devanagari, .bengali]) { return nil }
        if best.key == hinted { return hint }
        // Serbian/Croatian/Bosnian share grammar as well as script. A strong
        // classifier vote cannot reliably override a compatible explicit tag.
        if hinted == "sr", ["hr", "bs"].contains(best.key) { return hint }
        if let shared = expectedScript(for: hint),
           [.cyrillic, .arabic, .hebrew, .devanagari, .bengali].contains(shared),
           scripts == [shared] { return nil }
        return best.key
    }

    static func hypotheses(in text: String) -> [String: Double] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        var readings: [String: Double] = [:]
        for (language, score) in recognizer.languageHypotheses(withMaximum: 8) {
            readings[baseCode(language.rawValue), default: 0] += score
        }
        return readings
    }

    public static func baseCode(_ language: String?) -> String {
        language?.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first.map(String.init) ?? ""
    }

    static func languageProbe(_ text: String) -> String {
        let probe = text.folding(options: .widthInsensitive, locale: nil)
        let latinWords = probe.components(separatedBy: .whitespacesAndNewlines).filter { $0.allSatisfy(\.isLetter) }
        let uppercaseSentence = latinWords.count >= 3 && latinWords.allSatisfy { $0 == $0.uppercased() && $0 != $0.lowercased() }
        let acronyms = uppercaseSentence ? "" : "[A-Z]{2,}(?![a-z])|"
        // Classify grammar around identifiers; retain the original bytes for output.
        return probe.replacingOccurrences(
            of: #"https?://[^\s]+|[^\s]+@[^\s]+|(?<![A-Za-z0-9_])(?:"# + acronyms + #"[A-Za-z][A-Za-z0-9]*[_0-9][A-Za-z0-9_]*|[A-Za-z]*[a-z][A-Z][A-Za-z]*)(?![A-Za-z0-9_])"#,
            with: "", options: .regularExpression
        )
    }

    static func isMixedLanguageScript(_ scripts: Set<Script>) -> Bool {
        if scripts.isSubset(of: [.han, .kana]) || scripts.isSubset(of: [.han, .hangul]) { return false }
        return scripts.count > 1
    }

    private static func expectedScript(for language: String?) -> Script? {
        guard let language else { return nil }
        let code = language.lowercased().split(separator: "-").first.map(String.init) ?? language
        switch code {
        case "ar", "fa", "ur": return .arabic
        case "he", "yi": return .hebrew
        case "bg", "mk", "ru", "uk": return .cyrillic
        case "sr": return language.lowercased().contains("latn") ? .latin : .cyrillic
        case "zh", "yue": return .han
        case "ja": return .kana
        case "ko": return .hangul
        case "hi", "mr", "ne", "sa": return .devanagari
        case "bn", "as": return .bengali
        case "ta": return .tamil
        case "th": return .thai
        case "el": return .greek
        case "en", "de", "es", "fr", "it", "pt", "nl", "pl", "sv", "da", "fi", "cs", "tr":
            return .latin
        default: return nil
        }
    }

    static func script(for scalar: Unicode.Scalar) -> Script? {
        guard CharacterSet.letters.contains(scalar) else { return nil }
        switch scalar.value {
        case 0x0041...0x024F, 0x1E00...0x1EFF: return .latin
        case 0x0400...0x052F: return .cyrillic
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF: return .arabic
        case 0x0590...0x05FF, 0xFB1D...0xFB4F: return .hebrew
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D: return .kana
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF: return .han
        case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xD7B0...0xD7FF: return .hangul
        case 0x0900...0x097F: return .devanagari
        case 0x0980...0x09FF: return .bengali
        case 0x0B80...0x0BFF: return .tamil
        case 0x0E00...0x0E7F: return .thai
        case 0x0370...0x03FF, 0x1F00...0x1FFF: return .greek
        default: return .other
        }
    }
}
