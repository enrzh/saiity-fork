// DictusCore/Sources/DictusCore/AppGroup.swift
import Foundation

public enum AppGroup {
    /// Must match `com.apple.security.application-groups` in DictusApp / DictusKeyboard / DictusWidgets entitlements.
    public static let identifier = "group.de.aiity.saiity.ios.beta"

    /// Shared UserDefaults for cross-process data.
    /// Force-unwrap justified: if this fails, the App Group entitlement
    /// is misconfigured and the app cannot function.
    public static var defaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: identifier) else {
            fatalError("App Group '\(identifier)' not configured. Check entitlements.")
        }
        return defaults
    }

    /// Shared file container URL for larger data (audio, models metadata).
    public static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        )
    }
}
