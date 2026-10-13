/// Shared decision for custom motion so app and keyboard surfaces respond
/// consistently to the system Reduce Motion setting.
public enum AccessibilityMotionPolicy {
    public static func permitsAnimation(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.3)
    }
}
import SwiftUI
