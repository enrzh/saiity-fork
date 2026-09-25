import Foundation

/// The keyboard dictation on/off preference shared by Speak, the keyboard,
/// and the Live Activity.
///
/// A missing value means enabled. That is a different fact from whether the
/// microphone is warmed up and allowed to record.
public enum KeyboardDictationService {
    public static func isEnabled(in defaults: UserDefaults?) -> Bool {
        guard let defaults, defaults.object(forKey: SharedKeys.serviceEnabled) != nil else {
            return true
        }
        return defaults.bool(forKey: SharedKeys.serviceEnabled)
    }
}
