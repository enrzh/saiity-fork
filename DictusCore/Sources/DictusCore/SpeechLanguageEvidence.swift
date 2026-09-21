import Foundation

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
        case other
    }

    public let detectedLanguage: String?
    public let observedScripts: Set<Script>
    public let expectedScript: Script?
    public let score: Double
    public let isMixedScript: Bool
    public let meaningfulCharacterCount: Int

    public init(detectedLanguage: String?,
                observedScripts: Set<Script>,
                expectedScript: Script?,
                score: Double,
                isMixedScript: Bool,
                meaningfulCharacterCount: Int = 0) {
        self.detectedLanguage = detectedLanguage
        self.observedScripts = observedScripts
        self.expectedScript = expectedScript
        self.score = score
        self.isMixedScript = isMixedScript
        self.meaningfulCharacterCount = meaningfulCharacterCount
    }

    public static func analyze(text: String, detectedLanguage: String?) -> SpeechLanguageEvidence {
        let scripts = Set(text.unicodeScalars.compactMap(script(for:)))
        let expected = expectedScript(for: detectedLanguage)
        let isMixed = scripts.count > 1
        let meaningfulCharacterCount = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let score: Double

        guard !scripts.isEmpty else {
            score = 0.5
            return SpeechLanguageEvidence(
                detectedLanguage: detectedLanguage,
                observedScripts: scripts,
                expectedScript: expected,
                score: score,
                isMixedScript: false,
                meaningfulCharacterCount: meaningfulCharacterCount
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
                meaningfulCharacterCount: meaningfulCharacterCount
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
            meaningfulCharacterCount: meaningfulCharacterCount
        )
    }

    /// Returns the detector language only when its script evidence is strong
    /// enough to be used by cleanup or translation. Short text, unknown script
    /// families, and incompatible mixed scripts deliberately return nil.
    public var validatedLanguageCode: String? {
        guard let detectedLanguage,
              meaningfulCharacterCount >= Self.minimumValidatedCharacterCount,
              score >= Self.minimumValidatedScore,
              let expectedScript,
              isCompatibleScriptFamily(expectedScript, observed: observedScripts) else {
            return nil
        }
        return detectedLanguage
    }

    private func isCompatibleScriptFamily(_ expected: Script, observed: Set<Script>) -> Bool {
        guard !observed.isEmpty else { return false }
        switch expected {
        case .latin:
            return observed == [.latin]
        case .cyrillic:
            return observed == [.cyrillic]
        case .arabic:
            return observed == [.arabic]
        case .han:
            return observed == [.han]
        case .kana:
            // Japanese commonly mixes Kanji and Kana in one region.
            return observed.isSubset(of: [.han, .kana])
                && (observed.contains(.han) || observed.contains(.kana))
        case .hangul:
            return observed == [.hangul]
        case .devanagari:
            return observed == [.devanagari]
        case .other:
            return false
        }
    }

    private static func expectedScript(for language: String?) -> Script? {
        guard let language else { return nil }
        let code = language.lowercased().split(separator: "-").first.map(String.init) ?? language
        switch code {
        case "ar", "fa", "he", "ur": return .arabic
        case "bg", "mk", "ru", "sr", "uk": return .cyrillic
        case "zh", "yue": return .han
        case "ja": return .kana
        case "ko": return .hangul
        case "hi", "mr", "ne", "sa": return .devanagari
        case "en", "de", "es", "fr", "it", "pt", "nl", "pl", "sv", "da", "fi", "cs", "tr":
            return .latin
        default: return nil
        }
    }

    private static func script(for scalar: Unicode.Scalar) -> Script? {
        switch scalar.value {
        case 0x0041...0x024F, 0x1E00...0x1EFF: return .latin
        case 0x0400...0x052F: return .cyrillic
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF: return .arabic
        case 0x3040...0x30FF, 0x31F0...0x31FF: return .kana
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: return .han
        case 0xAC00...0xD7AF, 0x1100...0x11FF: return .hangul
        case 0x0900...0x097F: return .devanagari
        default: return nil
        }
    }
}
