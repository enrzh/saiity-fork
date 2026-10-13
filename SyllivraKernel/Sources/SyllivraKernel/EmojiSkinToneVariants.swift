import Foundation

/// Fitzpatrick skin-tone extras for emoji that the native keyboard can modify.
public enum EmojiSkinToneVariants {
    public static let modifiers = ["🏻", "🏼", "🏽", "🏾", "🏿"]

    private static let toneScalars: Set<UInt32> = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]
    private static let variationSelector16: UInt32 = 0xFE0F
    /// Unicode `Emoji_Modifier_Base` ranges. Only these scalars combine with
    /// Fitzpatrick tones the way the native emoji keyboard does.
    private static let modifierBaseRanges: [ClosedRange<UInt32>] = [
        0x261D...0x261D,
        0x26F9...0x26F9,
        0x270A...0x270D,
        0x1F385...0x1F385,
        0x1F3C2...0x1F3C4,
        0x1F3C7...0x1F3C7,
        0x1F3CA...0x1F3CC,
        0x1F442...0x1F443,
        0x1F446...0x1F450,
        0x1F466...0x1F469,
        0x1F46E...0x1F46E,
        0x1F470...0x1F478,
        0x1F47C...0x1F47C,
        0x1F481...0x1F483,
        0x1F485...0x1F487,
        0x1F48F...0x1F48F,
        0x1F491...0x1F491,
        0x1F4AA...0x1F4AA,
        0x1F574...0x1F575,
        0x1F57A...0x1F57A,
        0x1F590...0x1F590,
        0x1F595...0x1F596,
        0x1F645...0x1F647,
        0x1F64B...0x1F64F,
        0x1F6A3...0x1F6A3,
        0x1F6B4...0x1F6B6,
        0x1F6C0...0x1F6C0,
        0x1F6CC...0x1F6CC,
        0x1F90C...0x1F90C,
        0x1F90F...0x1F90F,
        0x1F918...0x1F91F,
        0x1F926...0x1F926,
        0x1F930...0x1F939,
        0x1F93C...0x1F93E,
        0x1F977...0x1F977,
        0x1F9B5...0x1F9B6,
        0x1F9B8...0x1F9B9,
        0x1F9BB...0x1F9BB,
        0x1F9CD...0x1F9CF,
        0x1F9D1...0x1F9DD,
        0x1FAC3...0x1FAC5,
        0x1FAF0...0x1FAF8
    ]

    /// Default plus five skin tones, or empty when the emoji has no tone variants.
    public static func options(for emoji: String) -> [String] {
        let base = strippingSkinTones(emoji)
        guard !base.isEmpty else { return [] }
        let toned = modifiers.compactMap { apply(base, tone: $0) }
        guard toned.count == modifiers.count else { return [] }
        return [base] + toned
    }

    public static func strippingSkinTones(_ emoji: String) -> String {
        let scalars = emoji.unicodeScalars.filter { !toneScalars.contains($0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func apply(_ emoji: String, tone: String) -> String? {
        guard let toneScalar = tone.unicodeScalars.first else { return nil }
        var scalars = Array(emoji.unicodeScalars)
        guard let baseIndex = scalars.firstIndex(where: { isModifierBase($0) }) else {
            return nil
        }
        let insertAt = scalars.index(after: baseIndex)
        if insertAt < scalars.endIndex, scalars[insertAt].value == variationSelector16 {
            scalars.remove(at: insertAt)
        }
        scalars.insert(toneScalar, at: insertAt)
        let candidate = String(String.UnicodeScalarView(scalars))
        return candidate.count == emoji.count ? candidate : nil
    }

    private static func isModifierBase(_ scalar: Unicode.Scalar) -> Bool {
        modifierBaseRanges.contains { $0.contains(scalar.value) }
    }
}
