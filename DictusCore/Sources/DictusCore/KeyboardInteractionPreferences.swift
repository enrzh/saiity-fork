// DictusCore/Sources/DictusCore/KeyboardInteractionPreferences.swift
import Foundation

/// Cross-process keyboard interaction preferences shared by the app and extension.
public enum KeyboardInteractionPreferences {
    public static var usesIOSStyling: Bool {
        AppGroup.defaults.bool(forKey: SharedKeys.keyboardIOSStyling)
    }

    /// iOS styling temporarily hides the bar without overwriting its saved choice.
    public static var topBarEnabled: Bool {
        !usesIOSStyling && AppGroup.defaults.bool(forKey: SharedKeys.keyboardTopBarEnabled)
    }

    public static func topBarHeight(for mode: KeyboardAreaMode) -> Double {
        mode == .keys || mode == .recording || topBarEnabled
            ? VoiceOnlyKeyboardPolicy.suggestionLaneHeight : 0
    }

    /// Keep the same window height across pages and reclaim only the hidden lane.
    public static var windowAccessoryHeight: Double {
        VoiceOnlyKeyboardPolicy.keyboardWindowAccessoryHeight
            - (topBarEnabled ? 0 : VoiceOnlyKeyboardPolicy.suggestionLaneHeight)
    }

    /// Long-press popups stay enabled for existing installs unless the user opts out.
    public static var keyPopupsEnabled: Bool {
        KeyPopupMode.active.showsPreview
    }

    /// Accent and emoji skin-tone rows are independent of press-preview style.
    public static var accentVariantsEnabled: Bool { true }

    /// Off, balloon popup, or zoom-out popout from the pressed key.
    public static var keyPopupMode: KeyPopupMode {
        KeyPopupMode.active
    }

    /// Liquid glass is on for existing installs unless the user chooses solid chrome.
    public static var liquidGlassEnabled: Bool {
        !usesIOSStyling && (AppGroup.defaults.object(forKey: SharedKeys.liquidGlassEnabled) as? Bool ?? true)
    }

    public static var keyboardInsetEnabled: Bool {
        usesIOSStyling || (AppGroup.defaults.object(forKey: SharedKeys.keyboardInsetEnabled) as? Bool ?? true)
    }

    /// Whether letter keys draw a visible container behind the glyph.
    ///
    /// Defaults to **on**, because that is what the platform draws and what the
    /// rebuilt keyboard is meant to match: every letter key on the system keyboard has
    /// a plate, and a grid of bare glyphs floating on the panel is the single most
    /// obvious way this keyboard stops looking like the one it replaced.
    ///
    /// It defaulted to off, which reproduced the legacy look where letters had no
    /// container. That produced a keyboard whose letter page and number page disagreed
    /// with each other — the number keys always had plates, so the two pages read as
    /// different products — and it made the letter plates appear and vanish with a
    /// preference that nothing on screen indicated, which is the "the containers
    /// sometimes disappear" report.
    public static var keyContainersEnabled: Bool {
        usesIOSStyling || (AppGroup.defaults.object(forKey: SharedKeys.keyContainersEnabled) as? Bool ?? true)
    }

    /// Adaptive hit-target prediction nudges the seam between adjacent keys
    /// toward the more likely next letter. On by default; turning it off uses
    /// neutral seams, which is more predictable but gives slightly less help.
    public static var adaptiveHitPredictionEnabled: Bool {
        AppGroup.defaults.object(forKey: SharedKeys.adaptiveHitPredictionEnabled) as? Bool ?? true
    }

    /// Tell the keyboard extension to reload App Group interaction preferences.
    public static func notifyChanged() {
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardPreferencesChanged)
    }

    public static func notifyVocabularyChanged() {
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardVocabularyChanged)
    }
}
