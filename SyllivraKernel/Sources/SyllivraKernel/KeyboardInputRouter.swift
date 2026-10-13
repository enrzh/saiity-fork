import Foundation

/// Whether this keyboard controller may insert text or run a proxy command.
public enum KeyboardInputRouter {
    public static func canRoute(
        isAttached: Bool,
        isOnScreen: Bool,
        activeControllerID: String?,
        controllerID: String
    ) -> Bool {
        isAttached && isOnScreen && activeControllerID == controllerID
    }
}
