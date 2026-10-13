import Foundation

/// Conservative cleanup style controls. It changes phrasing only when the
/// cleanup engine already has a valid rewrite; it never changes the source
/// language or author facts.
public enum WritingStyle: String, CaseIterable, Codable, Sendable {
    case balanced
    case formal
    case casual
    case concise

    public static let defaultStyle: Self = .balanced

    public static func active(from defaults: UserDefaults) -> Self {
        guard let raw = defaults.string(forKey: SharedKeys.writingStyle),
              let style = Self(rawValue: raw) else {
            return defaultStyle
        }
        return style
    }

    public static var active: Self {
        active(from: AppGroup.defaults)
    }

    public var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .concise: return "Concise"
        }
    }

    public var explanation: String {
        switch self {
        case .balanced:
            return "Keeps your natural tone while fixing clear dictation errors."
        case .formal:
            return "Uses a professional tone without changing names, facts, or language."
        case .casual:
            return "Keeps a relaxed, conversational tone while removing obvious speech clutter."
        case .concise:
            return "Removes redundant filler and repetition, without summarizing or dropping facts."
        }
    }

    /// Prompt fragment sent to the local cleanup backend. The constraints are
    /// deliberately explicit because style must never become translation or
    /// silent content replacement.
    public var promptInstruction: String {
        switch self {
        case .balanced:
            return "Natural tone; keep clear wording."
        case .formal:
            return "Professional tone only where the source permits it."
        case .casual:
            return "Relaxed conversational tone; retain meaningful wording."
        case .concise:
            return "Be concise: remove speech clutter only; never summarize or omit facts."
        }
    }

    public func persist(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: SharedKeys.writingStyle)
    }
}
