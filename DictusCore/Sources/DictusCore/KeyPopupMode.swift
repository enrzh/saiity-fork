import Foundation

/// Press-preview style for letter, symbol, and emoji keys.
public enum KeyPopupMode: String, CaseIterable, Equatable, Sendable {
    case off
    case popup
    case popout

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .popup: return "Popup"
        case .popout: return "Popout"
        }
    }

    public var systemImage: String {
        switch self {
        case .off: return "square.slash"
        case .popup: return "bubble.middle.bottom"
        case .popout: return "arrow.up.left.and.arrow.down.right"
        }
    }

    public var showsPreview: Bool { self != .off }

    public static var active: Self {
        load(from: AppGroup.defaults)
    }

    public static func load(from defaults: UserDefaults) -> Self {
        if let stored = defaults.string(forKey: SharedKeys.keyPopupMode),
           let mode = Self(rawValue: stored) {
            return mode
        }
        let enabled = defaults.object(forKey: SharedKeys.keyPopupsEnabled) as? Bool ?? true
        return enabled ? .popup : .off
    }

    public func persist(to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(rawValue, forKey: SharedKeys.keyPopupMode)
        defaults.set(showsPreview, forKey: SharedKeys.keyPopupsEnabled)
        KeyboardInteractionPreferences.notifyChanged()
    }
}
