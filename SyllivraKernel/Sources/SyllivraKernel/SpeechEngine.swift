// SyllivraKernel/Sources/SyllivraKernel/SpeechEngine.swift
import Foundation

/// Identifies which speech-to-text engine a model uses. Whisper is the only
/// engine; the raw value keeps the persisted "WK" format.
public enum SpeechEngine: String, Codable, Sendable {
    case whisperKit = "WK"

    /// Human-readable name for UI display.
    public var displayName: String { "WhisperKit" }
}
