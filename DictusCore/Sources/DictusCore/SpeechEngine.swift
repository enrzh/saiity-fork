// DictusCore/Sources/DictusCore/SpeechEngine.swift
import Foundation

/// Identifies which speech-to-text engine a model uses.
///
/// WHY an enum with raw values:
/// Each model belongs to a specific engine (WhisperKit or Parakeet). Storing
/// as a Codable rawValue ("WK"/"PK"/"QW") allows persistence in UserDefaults
/// and easy serialization.
public enum SpeechEngine: String, Codable, Sendable {
    case whisperKit = "WK"
    case parakeet = "PK"
    case qwen3ASR = "QW"

    /// Human-readable name for UI display.
    public var displayName: String {
        switch self {
        case .whisperKit: return "WhisperKit"
        case .parakeet: return "Parakeet"
        case .qwen3ASR: return "Qwen3-ASR"
        }
    }
}
