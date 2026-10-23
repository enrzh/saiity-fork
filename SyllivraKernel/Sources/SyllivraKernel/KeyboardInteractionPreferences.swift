// SyllivraKernel/Sources/SyllivraKernel/KeyboardInteractionPreferences.swift
import Foundation

/// Cross-process keyboard interaction preferences shared by the app and extension.
public enum KeyboardInteractionPreferences {
    /// Only the dictation board has a top lane, for More and power. Typing
    /// pages have no top bar.
    public static func topBarHeight(for mode: KeyboardAreaMode) -> Double {
        mode == .keys || mode == .recording ? VoiceOnlyKeyboardPolicy.suggestionLaneHeight : 0
    }

    /// Off, popup, popout, or a one-shot flash of the existing key face.
    public static var keyPopupMode: KeyPopupMode {
        KeyPopupMode.active
    }

    /// Tell the keyboard extension to reload App Group interaction preferences.
    public static func notifyChanged() {
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardPreferencesChanged)
    }

    public static func notifyVocabularyChanged() {
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardVocabularyChanged)
    }
}
