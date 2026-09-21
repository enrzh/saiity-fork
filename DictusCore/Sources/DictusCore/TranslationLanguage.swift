import Foundation

/// Translation targets exposed by the AUTO toolbar.
///
/// This is intentionally independent from `SupportedLanguage`: translation targets
/// do not imply a keyboard layout, prediction dictionary, or ASR source language.
public enum TranslationLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case hindi = "hi"
    case spanish = "es"
    case arabic = "ar"
    case french = "fr"
    case bengali = "bn"
    case portuguese = "pt"
    case russian = "ru"
    case indonesian = "id"
    case urdu = "ur"
    /// Kept as a compatibility target from the previous translation menu.
    case german = "de"

    /// Stable BCP-47 identifier used for persistence and translation APIs.
    public var code: String { rawValue }

    /// Stable identifier accepted by Foundation language APIs.
    public var translationIdentifier: String { rawValue }

    /// Foundation representation for APIs such as Apple's Translation framework.
    public var localeLanguage: Locale.Language { Locale.Language(identifier: translationIdentifier) }

    /// English display names keep the registry independent of app localization.
    public var displayName: String {
        switch self {
        case .english: return "English"
        case .chineseSimplified: return "Chinese (Simplified)"
        case .hindi: return "Hindi"
        case .spanish: return "Spanish"
        case .arabic: return "Arabic"
        case .french: return "French"
        case .bengali: return "Bengali"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .indonesian: return "Indonesian"
        case .urdu: return "Urdu"
        case .german: return "Deutsch"
        }
    }

    /// Short label suitable for the compact AUTO menu.
    public var shortCode: String {
        switch self {
        case .chineseSimplified: return "ZH"
        default: return code.uppercased()
        }
    }
}
