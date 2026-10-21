import Foundation

public enum KeyboardVariantKind: String, CaseIterable, Sendable {
    case letter, symbol, emoji, phone
}

/// One catalog of long-press alternates for the keyboard.
public enum KeyboardVariantPreferences {
    public static func options(for key: String, kind: KeyboardVariantKind) -> [String] {
        switch kind {
        case .letter:
            if let accents = AccentedCharacters.accents(for: key) { return [key] + accents }
            return SymbolKeyVariants.options(for: key).isEmpty ? [key] : SymbolKeyVariants.options(for: key)
        case .symbol: return SymbolKeyVariants.options(for: key).isEmpty ? [key] : SymbolKeyVariants.options(for: key)
        case .emoji: return EmojiSkinToneVariants.options(for: key)
        case .phone: return key == "0" ? ["0", "+"] : [key]
        }
    }
}

/// Shared character rows used by the live grid and the settings keyboard.
public enum KeyboardVariantLayout {
    public static func rows(for layout: LayoutType) -> [[String]] {
        switch layout {
        case .azerty: return [Array("azertyuiop"), Array("qsdfghjklm"), Array("wxcvbn'")].map { $0.map(String.init) }
        case .qwerty: return QWERTYLayout.lettersRows.map { $0.map { $0.lowercased() } }
        case .qwertz: return QWERTZLayout.lowercasedLettersRows
        case .qwertzStandard: return QWERTZLayout.standardRows.map { $0.map { $0.lowercased() } }
        case .dvorak: return AlternateLatinLayout.dvorakRows
        case .colemak: return AlternateLatinLayout.colemakRows
        case .workman: return AlternateLatinLayout.workmanRows
        case .norman: return AlternateLatinLayout.normanRows
        }
    }
}
