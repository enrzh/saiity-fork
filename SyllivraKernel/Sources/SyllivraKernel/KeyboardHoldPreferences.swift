import Foundation

public enum KeyboardHoldSpeed: String, CaseIterable, Sendable {
    case slow, `default`, fast, snappy

    public var displayName: String { rawValue.capitalized }
    public var duration: TimeInterval {
        switch self {
        case .slow: return 0.55
        case .default: return 0.35
        case .fast: return 0.25
        case .snappy: return 0.15
        }
    }
    public static var current: Self {
        Self(rawValue: AppGroup.defaults.string(forKey: SharedKeys.keyboardHoldSpeed) ?? "") ?? .default
    }
    public func scaled(_ original: TimeInterval) -> TimeInterval { original * duration / 0.35 }
}

public enum KeyboardVariantKind: String, CaseIterable, Sendable {
    case letter, symbol, emoji, phone
}

/// One catalog and preference filter for the keyboard and its settings preview.
public enum KeyboardVariantPreferences {
    private static var disabled = load(from: AppGroup.defaults)

    public static func reload() { disabled = load(from: AppGroup.defaults) }

    public static func load(from defaults: UserDefaults) -> [String: [String]] {
        guard let data = defaults.data(forKey: SharedKeys.disabledKeyVariants),
              let value = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return value
    }

    public static func allOptions(for key: String, kind: KeyboardVariantKind) -> [String] {
        switch kind {
        case .letter:
            if let accents = AccentedCharacters.accents(for: key) { return [key] + accents }
            return SymbolKeyVariants.options(for: key).isEmpty ? [key] : SymbolKeyVariants.options(for: key)
        case .symbol: return SymbolKeyVariants.options(for: key).isEmpty ? [key] : SymbolKeyVariants.options(for: key)
        case .emoji: return EmojiSkinToneVariants.options(for: key)
        case .phone: return key == "0" ? ["0", "+"] : [key]
        }
    }

    public static func options(for key: String, kind: KeyboardVariantKind) -> [String] {
        filter(allOptions(for: key, kind: kind), key: key, kind: kind, disabled: disabled)
    }

    public static func filter(_ options: [String], key: String, kind: KeyboardVariantKind,
                              disabled: [String: [String]]) -> [String] {
        let mask = Set(disabled[identifier(key, kind)] ?? [])
        let tones = kind == .emoji && !key.unicodeScalars.contains(where: { $0.value == 0x200D })
            ? Set((disabled["emoji:tones"] ?? []).flatMap(\.unicodeScalars)) : []
        return options.enumerated().compactMap { index, option in
            index == 0 || (!mask.contains(option.lowercased()) && !option.unicodeScalars.contains(where: tones.contains)) ? option : nil
        }
    }

    public static func isToneEnabled(_ tone: String) -> Bool {
        !(disabled["emoji:tones"] ?? []).contains(tone)
    }

    public static var defaultSkinTone: String {
        let tone = AppGroup.defaults.string(forKey: SharedKeys.defaultEmojiSkinTone) ?? ""
        return EmojiSkinToneVariants.modifiers.contains(tone) ? tone : ""
    }

    public static func setDefaultSkinTone(_ tone: String) {
        guard tone.isEmpty || EmojiSkinToneVariants.modifiers.contains(tone) else { return }
        AppGroup.defaults.set(tone, forKey: SharedKeys.defaultEmojiSkinTone)
        if !tone.isEmpty { setToneEnabled(true, tone: tone) }
        KeyboardInteractionPreferences.notifyChanged()
    }

    /// Keep explicit recent tones and joined combinations exactly as selected.
    public static func preferredEmoji(_ emoji: String, tone: String = defaultSkinTone) -> String {
        guard !tone.isEmpty, !emoji.unicodeScalars.contains(where: { $0.value == 0x200D }),
              EmojiSkinToneVariants.strippingSkinTones(emoji) == emoji,
              let index = EmojiSkinToneVariants.modifiers.firstIndex(of: tone) else { return emoji }
        let options = EmojiSkinToneVariants.options(for: emoji)
        guard options.indices.contains(index + 1) else { return emoji }
        let candidate = options[index + 1]
        return self.options(for: emoji, kind: .emoji).contains(candidate) ? candidate : emoji
    }

    public static func setToneEnabled(_ enabled: Bool, tone: String) {
        guard EmojiSkinToneVariants.modifiers.contains(tone) else { return }
        var mask = Set(disabled["emoji:tones"] ?? [])
        if enabled { mask.remove(tone) } else { mask.insert(tone) }
        if !enabled && defaultSkinTone == tone {
            AppGroup.defaults.removeObject(forKey: SharedKeys.defaultEmojiSkinTone)
        }
        if mask.isEmpty { disabled.removeValue(forKey: "emoji:tones") }
        else { disabled["emoji:tones"] = mask.sorted() }
        save()
    }

    public static func isEnabled(_ option: String, for key: String, kind: KeyboardVariantKind) -> Bool {
        !(disabled[identifier(key, kind)] ?? []).contains(option.lowercased())
    }

    public static func setEnabled(_ enabled: Bool, option: String, key: String, kind: KeyboardVariantKind) {
        // The base remains available even when every alternate is disabled.
        guard option != allOptions(for: key, kind: kind).first else { return }
        let id = identifier(key, kind)
        var mask = Set(disabled[id] ?? [])
        if enabled { mask.remove(option.lowercased()) } else { mask.insert(option.lowercased()) }
        if mask.isEmpty { disabled.removeValue(forKey: id) } else { disabled[id] = mask.sorted() }
        save()
    }

    private static func save() {
        if let data = try? JSONEncoder().encode(disabled) {
            AppGroup.defaults.set(data, forKey: SharedKeys.disabledKeyVariants)
            AppGroup.defaults.synchronize()
            KeyboardInteractionPreferences.notifyChanged()
        }
    }

    private static func identifier(_ key: String, _ kind: KeyboardVariantKind) -> String {
        let normalized = kind == .emoji ? EmojiSkinToneVariants.strippingSkinTones(key) : key.lowercased()
        return "\(kind.rawValue):\(normalized)"
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
