import Foundation

/// One self-contained result, bound to the request that produced it. Read/clear
/// runs serially on the keyboard's main queue before invoking the text proxy.
/// This gives at-most-once consumption within a live extension; iOS offers no
/// atomic transaction spanning UserDefaults and insertion into another app.
public enum DictationDelivery {
    public struct Result: Codable, Sendable {
        public let text: String
        public let request: DictationLanguageRequest
        public var timings: DictationRuntimeMetrics?
        public let originalText: String?
    }

    public static func publish(_ text: String, for request: DictationLanguageRequest, to defaults: UserDefaults,
                               timings: DictationRuntimeMetrics? = nil, originalText: String? = nil) {
        guard request.isBound, !text.isEmpty,
              let data = try? JSONEncoder().encode(Result(text: text, request: request, timings: timings,
                                                         originalText: originalText)) else { return }
        defaults.set(data, forKey: SharedKeys.dictationDelivery)
        defaults.synchronize()
    }

    public static func consume(for request: DictationLanguageRequest, from defaults: UserDefaults) -> String? {
        consumeResult(for: request, from: defaults)?.text
    }

    public static func consumeResult(for request: DictationLanguageRequest, from defaults: UserDefaults) -> Result? {
        guard request.isBound,
              let data = defaults.data(forKey: SharedKeys.dictationDelivery),
              let result = try? JSONDecoder().decode(Result.self, from: data),
              result.request.hasSameIdentity(as: request) else { return nil }
        clear(in: defaults)
        return result
    }

    public static func consumeResult(for request: DictationLanguageRequest, from defaults: UserDefaults,
                                     documentIdentifier: UUID?) -> Result? {
        guard let documentIdentifier, request.clientIdentifier == documentIdentifier.uuidString else { return nil }
        return consumeResult(for: request, from: defaults)
    }

    public static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: SharedKeys.dictationDelivery)
        defaults.removeObject(forKey: SharedKeys.lastTranscription)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.synchronize()
    }
}

/// Releasing before capture is ready must cancel startup, not launch an empty
/// transcription or leave a deferred cold start recording after release.
public enum DictationStopAction: Equatable, Sendable {
    case cancel
    case transcribe
    case ignore

    public static func resolve(status: DictationStatus, isRecording: Bool,
                               isTranscribingInFlight: Bool = false) -> Self {
        // Stop has drained capture before its UI task updates the stage. A
        // repeated release in that interval must not cancel the admitted result.
        guard !isTranscribingInFlight else { return .ignore }
        switch status {
        case .requested: return isRecording ? .transcribe : .cancel
        case .recording: return isRecording ? .transcribe : .cancel
        case .idle, .ready, .failed, .transcribing, .processing: return .ignore
        }
    }
}
