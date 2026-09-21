import Foundation

/// Controls whether sAiity keeps the user's explicit model or selects the best
/// installed compatible model for the current device state.
public enum ModelSelectionMode: String, CaseIterable, Codable, Sendable {
    case automatic
    case manual

    public static let defaultMode: Self = .automatic

    public static func active(from defaults: UserDefaults) -> Self {
        guard let raw = defaults.string(forKey: SharedKeys.modelSelectionMode),
              let mode = Self(rawValue: raw) else {
            return defaultMode
        }
        return mode
    }

    public static var active: Self {
        active(from: AppGroup.defaults)
    }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .manual: return "Manual"
        }
    }

    public var explanation: String {
        switch self {
        case .automatic:
            return "Chooses an installed model that fits this iPhone's memory, temperature, and measured warm-up time."
        case .manual:
            return "Keeps the model you select until you change it."
        }
    }

    public func persist(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: SharedKeys.modelSelectionMode)
    }
}
