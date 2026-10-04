import Foundation

/// Small user-facing recovery contract. Technical details remain in diagnostics.
public struct DictationProblem: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case retry, openSettings, models, repairDownload }
    public let message: String
    public let action: Action
    public var actionTitle: String {
        switch action {
        case .retry: return "Try again"
        case .openSettings: return "Open Settings"
        case .models: return "Models & downloads"
        case .repairDownload: return "Repair download"
        }
    }

    public init(_ detail: String, downloading: Bool = false) {
        // ponytail: classify the existing string-only channel; use typed codes if that channel changes.
        let text = detail.lowercased()
        if text.contains("microphone permission not yet requested") {
            message = "Microphone access hasn’t been requested yet. Try dictation again to allow it."
            action = .retry
        } else if text.contains("microphone permission") || text.contains("microphone access") {
            message = "Microphone access is off. Allow access in iPhone Settings, then return here."
            action = .openSettings
        } else if text.contains("enough space") || text.contains("insufficient space") || text.contains("disk space") || text.contains("disk full") || text.contains("no space left") || text.contains("storage") {
            message = "There isn’t enough space for this model. Free some storage, then try again."
            action = .retry
        } else if text.contains("checksum") || text.contains("corrupt") || text.contains("receipt") || text.contains("incomplete") || text.contains("missing file") {
            message = "The voice model’s download is incomplete or damaged. Repair it from Models & downloads."
            action = .repairDownload
        } else if text.contains("network") || text.contains("internet") || text.contains("connection") {
            message = downloading ? "The download couldn’t finish. Check your connection and try again."
                : "This action needs a connection. Your installed local voice models still work offline."
            action = .retry
        } else if text.contains("foreground") || text.contains("keep saiity open") {
            message = "This voice model needs sAiity to stay open. Choose Whisper for dictation from your keyboard."
            action = .models
        } else if downloading && (text.contains("server") || text.contains("could not be downloaded")) {
            message = text.contains("busy")
                ? "The model server is busy. Try the download again in a few minutes."
                : "The model couldn’t be downloaded. Try again in a few minutes."
            action = .retry
        } else if text.contains("model") || text.contains("memory") || text.contains("qwen") {
            message = "The voice model couldn’t be prepared. Choose another compatible model or repair its download."
            action = .models
        } else if text.contains("microphone is busy") || text.contains("phone call") || text.contains("appel") {
            message = "The microphone is busy. Finish the call or other recording, then try again."
            action = .retry
        } else if text.contains("too short") || text.contains("no audio") {
            message = "No usable speech was captured. Speak a little longer, then finish dictation."
            action = .retry
        } else {
            message = downloading ? "The model couldn’t be installed. Try again, or choose another model."
                : "Dictation couldn’t finish. Try again."
            action = .retry
        }
    }
}
