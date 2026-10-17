import Foundation

public enum AppGroup {
    /// Shared container identity is part of the installed app's data contract.
    public static let identifier = "group.de.aiity.saiity.ios.beta"

    public static let defaults: UserDefaults = {
        guard let shared = UserDefaults(suiteName: identifier) else {
            preconditionFailure("Cannot open Syllivra's shared preferences. Verify App Group entitlements.")
        }
        return shared
    }()

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
