import Foundation

/// Pure presentation policy for the Home readiness surface.
public struct DictationReadiness: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case requestMicrophone
        case openSettings
        case retry
        case models
        case repairDownload
        case start
    }

    public let title: String
    public let subtitle: String
    public let symbol: String
    public let action: Action

    public init(
        serviceEnabled: Bool,
        microphonePermission: MicrophonePermissionState,
        modelReady: Bool,
        modelLoadState: ModelLoadState,
        status: DictationStatus,
        modelLoadFailure: String? = nil
    ) {
        if !serviceEnabled {
            self.init(title: "Dictation is paused", subtitle: "Turn dictation on here or from the Live Activity.", symbol: "waveform.slash", action: .none)
            return
        }

        if microphonePermission.isRecoverable {
            self.init(title: "Microphone access is off", subtitle: microphonePermission == .restricted ? microphonePermission.recoveryMessage ?? "" : "Allow Syllivra to use the microphone in Settings.", symbol: "mic.slash", action: .openSettings)
            return
        }
        if !microphonePermission.isAuthorized {
            self.init(title: "Microphone access needed", subtitle: "Syllivra listens only while you dictate.", symbol: "mic.badge.plus", action: .requestMicrophone)
            return
        }
        if let modelLoadFailure, !modelLoadFailure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !DictationSessionLivenessPolicy.isActive(status) {
            let problem = DictationProblem(modelLoadFailure)
            let recovery: Action
            switch problem.action {
            case .openSettings: recovery = .openSettings
            case .models: recovery = .models
            case .repairDownload: recovery = .repairDownload
            case .retry: recovery = .retry
            }
            self.init(title: "Dictation needs attention", subtitle: problem.message, symbol: "exclamationmark.triangle",
                      action: recovery)
            return
        }
        if modelLoadState == .loading && !DictationSessionLivenessPolicy.isActive(status) {
            self.init(title: "Preparing your model", subtitle: "This takes a moment the first time.", symbol: "arrow.triangle.2.circlepath", action: .none)
            return
        }
        if !modelReady && !DictationSessionLivenessPolicy.isActive(status) {
            self.init(title: "Download a voice model", subtitle: "Speech is recognized on this iPhone, so Syllivra needs a voice model first.", symbol: "arrow.down.circle", action: .none)
            return
        }

        switch status {
        case .idle, .ready:
            self.init(title: "Ready to dictate", subtitle: "Offline dictation, ready when you are.", symbol: "checkmark.circle", action: .start)
        case .requested:
            self.init(title: "Starting dictation", subtitle: "Getting the microphone ready.", symbol: "waveform", action: .none)
        case .recording:
            self.init(title: "Recording", subtitle: "Listening for your words.", symbol: "waveform", action: .none)
        case .transcribing:
            self.init(title: "Transcribing", subtitle: "Turning your recording into text.", symbol: "text.bubble", action: .none)
        case .processing:
            self.init(title: "Processing", subtitle: "Finishing your dictation.", symbol: "gearshape.2", action: .none)
        case .failed:
            self.init(title: "Dictation needs another try", subtitle: "Dictation could not complete. Try again.", symbol: "arrow.clockwise.circle", action: .retry)
        }
    }

    private init(title: String, subtitle: String, symbol: String, action: Action) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.action = action
    }
}
