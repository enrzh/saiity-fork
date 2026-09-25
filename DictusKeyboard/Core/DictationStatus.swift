import Foundation

/// Status of a dictation session.
///
/// This enum is the single source of truth for what the dictation pipeline is
/// doing. It lives in DictusCore so both the app and the keyboard extension
/// share the exact same cases and semantics.
public enum DictationStatus: String, Codable, Equatable, CaseIterable, Sendable {
    /// No active or pending dictation.
    case idle
    /// The user has requested dictation (pressed the mic) but audio hasn't started.
    case requested
    /// Audio is being captured.
    case recording
    /// Audio capture finished; transcription in progress.
    case transcribing
    /// Transcription finished; post-processing / cleanup.
    case processing
    /// Transcription ready to insert.
    case ready
    /// Something went wrong; user-visible error state.
    case failed
}

/// The user's preferred default surface when the keyboard appears.
public enum DefaultKeyboardMode: String, Codable, Equatable, CaseIterable, Sendable {
    /// Start on the dictation board (mic + spacebar).
    case dictationBoard
    /// Start on the letter keyboard.
    case keyboard

    /// Resolved from App Group defaults; falls back to `.dictationBoard`.
    public static var active: DefaultKeyboardMode {
        let defaults = UserDefaults(suiteName: "group.de.aiity.saiity.ios.beta")
        if let raw = defaults?.string(forKey: "dictus.defaultKeyboardMode"),
           let mode = DefaultKeyboardMode(rawValue: raw) {
            return mode
        }
        return .dictationBoard
    }
}