import Foundation

/// Decides whether a keyboard action should foreground DictusApp.
///
/// The keyboard normally runs while DictusApp is backgrounded, so scene phase alone
/// is not a valid availability signal. A recent app heartbeat is enough while the
/// app is alive; once it has gone quiet, a confirmed Live Activity keeps the service
/// available while the app is suspended.
public enum DictationServiceLivenessPolicy {
    /// Long enough for normal process suspension gaps, short enough to recover from
    /// a terminated app without leaving the keyboard on a dead microphone action.
    public static let maximumAppHeartbeatAge: TimeInterval = 45

    public static func shouldOpenApp(
        serviceEnabled: Bool,
        appProcessHeartbeat: TimeInterval?,
        liveActivityPresent: Bool,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        guard serviceEnabled else { return true }
        if liveActivityPresent { return false }
        guard let appProcessHeartbeat, appProcessHeartbeat > 0 else { return true }

        let age = now - appProcessHeartbeat
        return age < 0 || age > maximumAppHeartbeatAge
    }
}

/// Writes the App Group availability contract from DictusApp.
public enum DictationServiceLivenessProbe {
    public static func recordAppHeartbeat(
        at date: Date = Date(),
        into defaults: UserDefaults = AppGroup.defaults
    ) {
        defaults.set(date.timeIntervalSince1970, forKey: SharedKeys.appProcessHeartbeat)
        defaults.synchronize()
    }

    public static func recordLiveActivity(
        present: Bool,
        identifier: String? = nil,
        into defaults: UserDefaults = AppGroup.defaults
    ) {
        defaults.set(present, forKey: SharedKeys.liveActivityPresent)
        if let identifier {
            defaults.set(identifier, forKey: SharedKeys.liveActivityID)
        } else if !present {
            defaults.removeObject(forKey: SharedKeys.liveActivityID)
        }
        defaults.synchronize()
    }
}
