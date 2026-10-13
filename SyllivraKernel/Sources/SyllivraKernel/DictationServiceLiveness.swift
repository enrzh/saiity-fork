import Foundation

/// Decides whether a keyboard action should foreground DictusApp.
///
/// The keyboard normally runs while DictusApp is backgrounded, so scene phase alone
/// is not a valid availability signal. A recent app heartbeat is the only proof the
/// process is alive: ActivityKit can keep a Live Activity on screen after the app
/// has been killed, which previously left Hold-to-dictate pointing at a dead mic.
public enum DictationServiceLivenessPolicy {
    /// Long enough for normal process suspension gaps, short enough to recover from
    /// a terminated app without leaving the keyboard on a dead microphone action.
    public static let maximumAppHeartbeatAge: TimeInterval = 45
    /// ActivityKit can retain an activity after the owning process has died.
    /// Require a recent confirmation before treating the flag as service liveness.
    public static let maximumLiveActivityAge: TimeInterval = 120

    /// Decides whether the keyboard should show a persistent recovery action.
    ///
    /// A fresh process heartbeat is enough to keep Hold-to-dictate. ActivityKit
    /// can keep a Live Activity after the app has been killed, so a stale or
    /// missing heartbeat must surface "Open Syllivra" even when a model file is
    /// still marked ready.
    public static func shouldOfferRecovery(
        modelReady: Bool,
        serviceEnabled: Bool,
        appProcessHeartbeat: TimeInterval?,
        liveActivityPresent: Bool,
        liveActivityUpdatedAt: TimeInterval? = nil,
        audioReady: Bool = true,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        guard serviceEnabled else { return true }
        guard audioReady else { return true }
        if shouldOpenApp(
            serviceEnabled: serviceEnabled,
            appProcessHeartbeat: appProcessHeartbeat,
            liveActivityPresent: liveActivityPresent,
            liveActivityUpdatedAt: liveActivityUpdatedAt,
            audioReady: audioReady,
            now: now
        ) {
            return true
        }
        return !modelReady
    }

    public static func shouldOpenApp(
        serviceEnabled: Bool,
        appProcessHeartbeat: TimeInterval?,
        liveActivityPresent: Bool,
        liveActivityUpdatedAt: TimeInterval? = nil,
        audioReady: Bool = true,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        guard serviceEnabled, audioReady else { return true }
        _ = liveActivityPresent
        _ = liveActivityUpdatedAt
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
        at date: Date = Date(),
        into defaults: UserDefaults = AppGroup.defaults
    ) {
        defaults.set(present, forKey: SharedKeys.liveActivityPresent)
        if let identifier {
            defaults.set(identifier, forKey: SharedKeys.liveActivityID)
        } else if !present {
            defaults.removeObject(forKey: SharedKeys.liveActivityID)
        }
        if present {
            defaults.set(date.timeIntervalSince1970, forKey: SharedKeys.liveActivityUpdatedAt)
        } else {
            defaults.removeObject(forKey: SharedKeys.liveActivityUpdatedAt)
        }
        defaults.synchronize()
    }
}
