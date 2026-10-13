import Foundation

/// Conservative policy for local word prediction. A single Latin dictionary
/// is not a safe fallback for mixed or unsupported scripts.
public enum PredictionLanguageSafety {
    private enum Script: Hashable {
        case latin
        case cyrillic
        case greek
        case arabic
        case hebrew
        case indic
        case cjk
        case other
    }

    /// Returns true only for sufficiently long text that is visibly outside
    /// the supported single-Latin-dictionary prediction path.
    public static func shouldAbstain(for text: String) -> Bool {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard text.count >= 24, words.count >= 4 else { return false }

        let scripts = Set(text.unicodeScalars.compactMap { script(for: $0) })
        guard !scripts.isEmpty else { return true }
        return scripts.count != 1 || scripts.first != .latin
    }

    private static func script(for scalar: Unicode.Scalar) -> Script? {
        guard scalar.properties.generalCategory == .uppercaseLetter
                || scalar.properties.generalCategory == .lowercaseLetter
                || scalar.properties.generalCategory == .titlecaseLetter
                || scalar.properties.generalCategory == .otherLetter
                || scalar.properties.generalCategory == .modifierLetter
                || scalar.properties.generalCategory == .letterNumber else {
            return nil
        }

        switch scalar.value {
        case 0x0000...0x024F, 0x1E00...0x1EFF:
            return .latin
        case 0x0370...0x03FF, 0x1F00...0x1FFF:
            return .greek
        case 0x0400...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
            return .cyrillic
        case 0x0590...0x05FF:
            return .hebrew
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF:
            return .arabic
        case 0x0900...0x0DFF, 0x0F00...0x109F:
            return .indic
        case 0x1100...0x11FF, 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF:
            return .cjk
        default:
            return .other
        }
    }
}
