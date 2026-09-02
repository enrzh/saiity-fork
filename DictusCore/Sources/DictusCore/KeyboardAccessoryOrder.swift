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

    public static var current: Self { load(from: AppGroup.defaults) }

    public static func load(from defaults: UserDefaults) -> Self {
        guard let rawValue = defaults.string(forKey: SharedKeys.keyboardAccessoryOrder),
              let order = Self(rawValue: rawValue) else { return .emojiFirst }
        return order
    }

    public func persist(to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(rawValue, forKey: SharedKeys.keyboardAccessoryOrder)
    }
}
