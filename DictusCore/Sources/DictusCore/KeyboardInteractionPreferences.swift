// DictusCore/Sources/DictusCore/KeyboardInteractionPreferences.swift
import Foundation

/// Cross-process keyboard interaction preferences shared by the app and extension.
public enum KeyboardInteractionPreferences {
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
        AppGroup.defaults.object(forKey: SharedKeys.liquidGlassEnabled) as? Bool ?? true
    }

    /// Per-key plates are off unless the user turns them on. Popout still uses its own overlay.
    public static var keyContainersEnabled: Bool {
        AppGroup.defaults.object(forKey: SharedKeys.keyContainersEnabled) as? Bool ?? false
    }

    /// Tell the keyboard extension to reload App Group interaction preferences.
    public static func notifyChanged() {
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardPreferencesChanged)
    }
}
