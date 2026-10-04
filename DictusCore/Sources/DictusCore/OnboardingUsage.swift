import Foundation

public enum OnboardingUsage: String, Sendable {
    case appOnly, keyboard
    public static func active(from defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: SharedKeys.onboardingUsage) ?? "") ?? .keyboard
    }
    public var usesKeyboard: Bool { self == .keyboard }
    public func canContinue(keyboardInstalled: Bool, modelReady: Bool) -> Bool {
        modelReady && (!usesKeyboard || keyboardInstalled)
    }
}
