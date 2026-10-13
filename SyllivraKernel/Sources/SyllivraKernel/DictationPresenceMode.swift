import Foundation

/// Where dictation status appears while the user is speaking or waiting.
public enum DictationPresenceMode: String, CaseIterable, Equatable, Sendable {
    case off
    case liveActivity

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .liveActivity: return "Live Activity"
        }
    }

    public var systemImage: String {
        switch self {
        case .off: return "eye.slash"
        case .liveActivity: return "dot.radiowaves.left.and.right"
        }
    }

    public var showsLiveActivity: Bool { self == .liveActivity }

    public static var active: Self {
        let defaults = AppGroup.defaults
        if let stored = defaults.string(forKey: SharedKeys.dictationPresenceMode) {
            if stored == "pictureInPicture" { return .liveActivity }
            if let mode = Self(rawValue: stored) { return mode }
        }
        let enabled = defaults.object(forKey: SharedKeys.liveActivityEnabled) as? Bool ?? true
        return enabled ? .liveActivity : .off
    }

    public static func load(from defaults: UserDefaults) -> Self {
        if let stored = defaults.string(forKey: SharedKeys.dictationPresenceMode) {
            if stored == "pictureInPicture" { return .liveActivity }
            if let mode = Self(rawValue: stored) { return mode }
        }
        let enabled = defaults.object(forKey: SharedKeys.liveActivityEnabled) as? Bool ?? true
        return enabled ? .liveActivity : .off
    }

    public func persist(to defaults: UserDefaults = AppGroup.defaults) {
        defaults.set(rawValue, forKey: SharedKeys.dictationPresenceMode)
        defaults.set(showsLiveActivity, forKey: SharedKeys.liveActivityEnabled)
    }
}
