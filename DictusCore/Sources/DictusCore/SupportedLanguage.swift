// DictusCore/Sources/DictusCore/SupportedLanguage.swift
// Type-safe language representation shared between DictusApp and DictusKeyboard.
import Foundation

/// Languages supported by Dictus for typing layouts, autocorrect, and predictions.
///
/// WHY an enum instead of raw strings:
/// Language codes were previously scattered as "fr"/"en" string literals across
/// SettingsView, KeyboardViewController, TextPredictionEngine, and TranscriptionService.
/// A single enum prevents typos, centralizes display names and layout defaults,
/// and makes adding new languages a one-place change.
public enum SupportedLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case polish = "pl"
    case swedish = "sv"
    case danish = "da"
    case finnish = "fi"
    case czech = "cs"

    /// Languages offered by the keyboard AUTO/language menu. Same as `allCases`
    /// so Settings and the typing chip cannot drift.
    public static var typingMenuLanguages: [SupportedLanguage] { allCases }

    /// Localized display name for settings UI.
    public var displayName: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        case .french: return "Fran\u{00E7}ais"
        case .spanish: return "Espa\u{00F1}ol"
        case .italian: return "Italiano"
        case .portuguese: return "Portugu\u{00EA}s"
        case .dutch: return "Nederlands"
        case .polish: return "Polski"
        case .swedish: return "Svenska"
        case .danish: return "Dansk"
        case .finnish: return "Suomi"
        case .czech: return "\u{010C}e\u{0161}tina"
        }
    }

    /// Two-letter uppercase code for the keyboard toolbar language switcher.
    public var shortCode: String { rawValue.uppercased() }

    /// Default keyboard layout for this language.
    ///
    /// Since #272 this is a *default*, not a rule: it seeds the layout of a language the
    /// user has never given one, and it keeps applying while they never do. The moment they
    /// pick a layout for that language, their choice wins and this stops being consulted —
    /// see `KeyboardLayoutPreference`. Nobody's keyboard changes shape on update.
    public var defaultLayout: LayoutType {
        switch self {
        case .french: return .azerty
        case .german: return .qwertz
        case .polish, .czech: return .qwertzStandard
        case .english, .spanish, .italian, .portuguese, .dutch, .swedish, .danish, .finnish:
            return .qwerty
        }
    }

    /// Spacebar label matching each language's convention.
    public var spaceName: String {
        switch self {
        case .english: return "space"
        case .german: return "Leertaste"
        case .french: return "espace"
        case .spanish: return "espacio"
        case .italian: return "spazio"
        case .portuguese: return "espa\u{00E7}o"
        case .dutch: return "spatie"
        case .polish: return "spacja"
        case .swedish: return "mellanslag"
        case .danish: return "mellemrum"
        case .finnish: return "v\u{00E4}lily\u{00F6}nti"
        case .czech: return "mezern\u{00ED}k"
        }
    }

    /// Return key label matching each language's convention.
    public var returnName: String {
        switch self {
        case .english: return "return"
        case .german: return "Eingabe"
        case .french: return "retour"
        case .spanish: return "intro"
        case .italian: return "invio"
        case .portuguese: return "return"
        case .dutch: return "return"
        case .polish: return "enter"
        case .swedish: return "retur"
        case .danish: return "retur"
        case .finnish: return "rivinvaihto"
        case .czech: return "enter"
        }
    }

    /// Reads the active language from the persisted selection and system locale.
    public static var active: SupportedLanguage {
        let defaults = AppGroup.defaults
        KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        return KeyboardLanguageSelection.resolve(locale: .current, defaults: defaults)
    }

    public static func fromSystem(locale: Locale) -> SupportedLanguage {
        switch locale.language.languageCode?.identifier {
        case "de": return .german
        case "fr": return .french
        case "es": return .spanish
        case "it": return .italian
        case "pt": return .portuguese
        case "nl": return .dutch
        case "pl": return .polish
        case "sv": return .swedish
        case "da": return .danish
        case "fi": return .finnish
        case "cs": return .czech
        default: return .english
        }
    }

    /// Makes `language` the active keyboard language.
    ///
    /// Writes the language and nothing else about the layout (#272): the layout the user
    /// now types on is whatever they chose for this language, or its default while they
    /// never chose one. Before #272 this overwrote the layout with `defaultLayout`, which
    /// is exactly what made "English autocorrect on an AZERTY keyboard" unreachable.
    ///
    /// WHY here and not in the picker view: #241 moved language selection from the
    /// toolbar into the keyboard panel, and the same write has to happen wherever
    /// selection ends up living. In DictusCore it is also testable — the keyboard
    /// extension target has no test bundle.
    public static func activate(_ language: SupportedLanguage) {
        // Before the language moves: the #272 migration freezes the stored layout under
        // whichever language is active *at that moment*, and that has to be the one the
        // user has been typing on, not the one they are switching to.
        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        AppGroup.defaults.set(language.rawValue, forKey: SharedKeys.language)
        KeyboardLanguageSelection.explicit(language).persist(to: AppGroup.defaults)
        // The mirror describes the active language's layout, so it is computed after the
        // switch — see `KeyboardLayoutPreference.mirrorToLegacyKey`.
        KeyboardLayoutPreference.mirrorToLegacyKey(KeyboardLayoutPreference.layout(for: language))
    }
}
