import Foundation

public enum KeyboardLanguageSelection: Equatable, Codable, Sendable {
    case automatic
    case explicit(SupportedLanguage)

    private static let version = 1

    public func persist(to defaults: UserDefaults) {
        switch self {
        case .automatic:
            defaults.set("automatic", forKey: SharedKeys.keyboardLanguageSelection)
        case .explicit(let language):
            defaults.set(language.rawValue, forKey: SharedKeys.keyboardLanguageSelection)
        }
    }

    public static func load(from defaults: UserDefaults) -> Self {
        guard let value = defaults.string(forKey: SharedKeys.keyboardLanguageSelection) else {
            return .automatic
        }
        if value == "automatic" { return .automatic }
        guard let language = SupportedLanguage(rawValue: value),
              SupportedLanguage.allCases.contains(language) else {
            // A previously selected French/Spanish value is still readable,
            // but it must never reappear as an active product language.
            return .explicit(.english)
        }
        return .explicit(language)
    }

    public static func resolve(locale: Locale, defaults: UserDefaults) -> SupportedLanguage {
        switch load(from: defaults) {
        case .automatic: return SupportedLanguage.fromSystem(locale: locale)
        case .explicit(let language): return language
        }
    }

    public static func migrateLegacyFrenchIfNeeded(in defaults: UserDefaults) {
        guard defaults.integer(forKey: SharedKeys.keyboardLanguageMigrationVersion) < version else { return }
        if defaults.object(forKey: SharedKeys.keyboardLanguageSelection) == nil,
           let stored = defaults.string(forKey: SharedKeys.language),
           let language = SupportedLanguage(rawValue: stored) {
            // Preserve supported choices from pre-selection releases. The old
            // implicit French default alone migrates to system language.
            if SupportedLanguage.allCases.contains(language) {
                explicit(language).persist(to: defaults)
            } else {
                automatic.persist(to: defaults)
            }
        }
        defaults.set(version, forKey: SharedKeys.keyboardLanguageMigrationVersion)
    }
}
