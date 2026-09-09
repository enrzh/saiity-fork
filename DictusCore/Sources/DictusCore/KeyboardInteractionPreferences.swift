// DictusCore/Sources/DictusCore/KeyboardInteractionPreferences.swift
import Foundation

/// Cross-process keyboard interaction preferences shared by the app and extension.
public enum KeyboardInteractionPreferences {
    /// Long-press popups stay enabled for existing installs unless the user opts out.
    public static var keyPopupsEnabled: Bool {
        AppGroup.defaults.object(forKey: SharedKeys.keyPopupsEnabled) as? Bool ?? true
    }
}
