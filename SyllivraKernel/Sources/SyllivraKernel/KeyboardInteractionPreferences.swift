// SyllivraKernel/Sources/SyllivraKernel/KeyboardInteractionPreferences.swift
import Foundation

/// Cross-process keyboard interaction preferences shared by the app and extension.
public enum KeyboardInteractionPreferences {
    public static var topBarEnabled: Bool {
        AppGroup.defaults.bool(forKey: SharedKeys.keyboardTopBarEnabled)
    }

    public static func topBarHeight(for mode: KeyboardAreaMode) -> Double {
        mode == .keys || mode == .recording || topBarEnabled
            ? VoiceOnlyKeyboardPolicy.suggestionLaneHeight : 0
    }

    /// The bar's window extension is present only while the top bar is on.
    /// Dictation pages keep their lane through `topBarHeight(for:)`.
    public static var windowAccessoryHeight: Double {
        topBarEnabled ? VoiceOnlyKeyboardPolicy.keyboardWindowAccessoryHeight : 0
    }

    /// Tell the keyboard extension to reload App Group interaction preferences.
    public static func notifyChanged() {
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardPreferencesChanged)
    }

    public static func notifyVocabularyChanged() {
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardVocabularyChanged)
    }
}
