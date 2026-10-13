import Foundation

/// The keyboard's handoff into the app. Opening stays inside the touch;
/// a second tap inside the interval is ignored so one press cannot open twice.
public enum KeyboardDictationBridge {
    public static let recoveryURLString = "saiity://dictate?source=keyboard&intent=prepare"
    public static let minimumOpenInterval: TimeInterval = 0.75

    public static func recoveryURL() -> URL? {
        URL(string: recoveryURLString)
    }

    public static func shouldOpen(lastOpen: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastOpen) >= minimumOpenInterval
    }
}
