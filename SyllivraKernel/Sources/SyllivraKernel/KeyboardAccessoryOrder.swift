import Foundation

public enum KeyboardAccessoryOrder: String, CaseIterable, Codable {
    case emojiFirst
    case numberFirst

    public var displayName: String {
        switch self {
        case .emojiFirst: return "Emoji, 123"
        case .numberFirst: return "123, Emoji"
        }
    }

    /// The accessory rail follows the native order: 123, then emoji.
    /// The old preference is intentionally ignored; keeping one order avoids
    /// symbol-page controls changing position between launches.
    public static var current: Self { .numberFirst }

    public static func load(from defaults: UserDefaults) -> Self {
        _ = defaults
        return .numberFirst
    }

    public func persist(to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(rawValue, forKey: SharedKeys.keyboardAccessoryOrder)
    }
}
