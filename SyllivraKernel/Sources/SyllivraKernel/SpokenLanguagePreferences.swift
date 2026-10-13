import Foundation

/// Recommendation constraints, independent of typing language and ASR decoding.
public enum SpokenLanguagePreferences {
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
        codes.isEmpty ? "Broad language support" : codes.map(displayName).joined(separator: ", ")
    }
    public static func displayName(_ code: String) -> String { Locale.current.localizedString(forLanguageCode: code) ?? code }
}

extension ModelLanguageSupport {
    public var languageCodes: [String] {
        highlights.map(\.code) + additionalCodes + tierGroups.flatMap(\.codes)
    }
}
