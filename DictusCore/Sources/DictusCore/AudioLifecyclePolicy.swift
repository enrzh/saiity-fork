import Foundation

/// The observable lifecycle of the app-owned audio resources.
public enum AudioLifecycleState: String, Equatable, Sendable {
    /// No audio engine or configured audio session is retained.
    case cold
    /// The audio session is configured but the engine is not running.
    case configuredIdle
    /// The engine is running without capturing samples.
    case warmIdle
    /// The engine is running and samples are being accumulated.
    case recording
}

/// Pure rules for deciding which audio lifecycle transitions are safe.
public enum AudioLifecyclePolicy {
    public static func shouldRestoreStandby(serviceEnabled: Bool, onboardingComplete: Bool,
                                            microphoneGranted: Bool) -> Bool {
        serviceEnabled && onboardingComplete && microphoneGranted
    }
    public static func state(
        engineRunning: Bool,
        sessionConfigured: Bool,
        isRecording: Bool
    ) -> AudioLifecycleState {
        if isRecording { return .recording }
        if engineRunning { return .warmIdle }
        if sessionConfigured { return .configuredIdle }
        return .cold
    }

    /// Whether an idle caller may deactivate resources without interrupting capture.
    public static func canDeactivate(_ state: AudioLifecycleState) -> Bool {
        switch state {
        case .cold, .recording:
            return false
        case .configuredIdle, .warmIdle:
            return true
        }
    }
}
