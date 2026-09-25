import Foundation

/// Post-recognition assembly. Speech recognition itself stays on
/// `TranscriptionService`; this type owns the text the keyboard is allowed to insert.
public enum TranscriptionPipeline {
    public struct Assembled: Equatable, Sendable {
        public let body: String
        public let formatted: String
    }

    /// Grammar floor, then the historical sentence separator.
    /// Multilingual output that must be inserted as-is skips the separator.
    public static func assemble(
        cleaned: String,
        grammarLanguage: SupportedLanguage?,
        insertAsIs: Bool
    ) -> Assembled {
        let body = PolishPostpass.grammarFloor(cleaned, language: grammarLanguage)
        return Assembled(body: body, formatted: formatted(body, insertAsIs: insertAsIs))
    }

    public static func formatted(_ text: String, insertAsIs: Bool) -> String {
        if insertAsIs { return text }
        if let last = text.last, ".!?…".contains(last) {
            return text + " "
        }
        return text + ". "
    }
}
