import Foundation

/// Spoken-language choices captured for recognition, independently of typing.
public enum SpokenLanguagePreferences {
    @TaskLocal public static var recognitionLanguages: [String] = []

    public static func recognitionName(_ code: String) -> String {
        let base = normalized([code]).first ?? code
        return Locale(identifier: "en").localizedString(forLanguageCode: base)?.capitalized ?? base
    }

    public static func bestLanguage(scores: [String: Double], among languages: [String]) -> String? {
        let allowed = Set(normalized(languages))
        return scores.filter { $0.value.isFinite && allowed.contains(normalized([$0.key]).first ?? "") }
            .max { left, right in left.value == right.value ? left.key > right.key : left.value < right.value }
            .flatMap { normalized([$0.key]).first }
    }

    /// Short Latin fragments stay uncertain because names can resemble foreign speech.
    public static func unexpectedLanguage(in text: String, languages: [String]) -> String? {
        let allowed = Set(normalized(languages))
        guard !allowed.isEmpty else { return nil }
        for span in PolishSpanDetector.translationSpans(in: text) {
            guard let raw = span.languageCode, let language = normalized([raw]).first,
                  !allowed.contains(language) else { continue }
            let probe = SpeechLanguageEvidence.languageProbe(span.text)
            let words = probe.split(whereSeparator: \.isWhitespace)
            if words.count < 3 && probe.unicodeScalars.allSatisfy({
                !CharacterSet.letters.contains($0) || SpeechLanguageEvidence.script(for: $0) == .latin
            }) { continue }
            return language
        }
        return nil
    }
    public static var availableCodes: [String] {
        normalized(ModelInfo.allIncludingDeprecated.flatMap { $0.languageSupport.languageCodes }).sorted {
            displayName($0) < displayName($1)
        }
    }

    public static func normalized(_ codes: [String]) -> [String] {
        Array(Set(codes.map { code in
            let base = code.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? ""
            return base == "fil" ? "tl" : base == "jw" ? "jv" : base
        }.filter { !$0.isEmpty })).sorted()
    }

    public static func load(from defaults: UserDefaults) -> [String] {
        normalized(defaults.stringArray(forKey: SharedKeys.spokenLanguages) ?? [])
    }

    public static func accepts(_ model: ModelInfo, languages: [String]) -> Bool {
        let required = normalized(languages)
        if required.isEmpty {
            return model.languageSupport.coverage == .whisperMultilingual || model.languageSupport.coverage == .qwenMultilingual
        }
        if required.contains("yue"), model.engine == .whisperKit, !model.identifier.contains("large-v3") { return false }
        let supported = Set(normalized(model.languageSupport.languageCodes))
        return required.allSatisfy(supported.contains)
    }

    public static func summary(_ codes: [String]) -> String {
        codes.isEmpty ? "Any Language" : codes.map(displayName).joined(separator: ", ")
    }
    public static func displayName(_ code: String) -> String { Locale.current.localizedString(forLanguageCode: code) ?? code }
}

extension ModelLanguageSupport {
    public var languageCodes: [String] {
        highlights.map(\.code) + additionalCodes + tierGroups.flatMap(\.codes)
    }
}
