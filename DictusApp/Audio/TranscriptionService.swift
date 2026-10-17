import Foundation
import SyllivraKernel

enum TranscriptionError: Error, LocalizedError {
    case notReady
    case emptyAudio
    case noSpeech
    case transcriptionFailed(String)
    case unsupportedLanguages
    case unexpectedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "TranscriptionService is not ready — no engine initialized"
        case .emptyAudio:
            return "No audio samples to transcribe"
        case .noSpeech:
            return "No speech detected"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .unsupportedLanguages:
            return "This voice model does not cover your selected spoken languages. Choose a compatible model in Models."
        case .unexpectedLanguage(let language):
            return "Recognition returned \(SpokenLanguagePreferences.displayName(language)) outside your selected spoken languages. Try again."
        }
    }
}

/// Existing speech adapters stay replaceable; only the current admitted inference may publish a result.
final class TranscriptionService {
    private let lock = NSLock()
    private var engine: SpeechModelProtocol?
    private var revision: UInt = 0

    var hasLoadedModel: Bool { lock.withLock { engine?.isReady == true } }
    @available(iOS 18.0, *)
    var qwenEngine: QwenSpeechEngine? { lock.withLock { engine as? QwenSpeechEngine } }

    func prepare(engine: SpeechModelProtocol) {
        lock.withLock {
            revision &+= 1
            self.engine = engine
        }
    }

    func cancelCurrentInference() {
        let runtime = lock.withLock {
            revision &+= 1
            return engine
        }
        runtime?.cancelCurrentInference()
    }

    private func detach() -> SpeechModelProtocol? {
        lock.withLock {
            revision &+= 1
            let previous = engine
            engine = nil
            return previous
        }
    }

    func releaseLoadedModel() { detach()?.releaseLoadedModel() }
    func releaseLoadedModelAndWait() async { await detach()?.releaseLoadedModelAndWait() }

    func transcribe(audioSamples: [Float], languagePolicy: TranscriptionLanguagePolicy) async throws -> String {
        try await transcribeDetailed(audioSamples: audioSamples, languagePolicy: languagePolicy).text
    }

    func transcribeDetailed(audioSamples: [Float],
                            languagePolicy: TranscriptionLanguagePolicy) async throws -> SpeechTranscriptionOutput {
        try Task.checkCancellation()
        guard !audioSamples.isEmpty else { throw TranscriptionError.emptyAudio }
        guard audioSamples.allSatisfy(\.isFinite) else {
            throw TranscriptionError.transcriptionFailed("Audio contains invalid samples.")
        }
        let (runtime, admittedRevision) = lock.withLock { (engine, revision) }
        guard let runtime, runtime.isReady else { throw TranscriptionError.notReady }
        if !languagePolicy.spokenLanguages.isEmpty,
           let model = ModelInfo.forIdentifier(languagePolicy.modelIdentifier),
           !SpokenLanguagePreferences.accepts(model, languages: languagePolicy.spokenLanguages) {
            throw TranscriptionError.unsupportedLanguages
        }

        let started = DispatchTime.now().uptimeNanoseconds
        let name = languagePolicy.modelIdentifier.isEmpty ? "unknown" : languagePolicy.modelIdentifier
        PersistentLog.log(.transcriptionStarted(modelName: name))
        PersistentLog.log(.diagnosticProbe(
            component: "TranscriptionService", instanceID: "languageResolution", action: "resolved",
            details: "mode=\(languagePolicy.mode.telemetryDescription) keyboard=\(languagePolicy.keyboardLanguage.rawValue) engine=\(languagePolicy.engine.rawValue) stt=\(languagePolicy.sttLanguageCode ?? "auto") sttEffective=\(languagePolicy.sttLanguageIsEffective ? "yes" : "no")"))
        do {
            let result = try await SpokenLanguagePreferences.$recognitionLanguages.withValue(languagePolicy.spokenLanguages) {
                try await runtime.transcribeDetailed(audioSamples: audioSamples, language: languagePolicy.sttLanguageCode)
            }
            try Task.checkCancellation()
            guard lock.withLock({ revision == admittedRevision }) else { throw CancellationError() }
            let milliseconds = DictationRuntimeMetrics.elapsedMilliseconds(since: started)
            PersistentLog.log(.transcriptionCompleted(durationMs: milliseconds, wordCount: result.text.split(separator: " ").count))
            // Every current speech adapter consumes 16 kHz mono PCM; division avoids count multiplication overflow.
            PersistentLog.log(.transcriptionPerformance(modelName: name, audioDurationMs: audioSamples.count / 16,
                transcriptionDurationMs: milliseconds, peakMemoryMB: DeviceCapabilities.current().availableMemoryMB))
            ModelWarmLatencyStore.record(milliseconds, for: name, in: AppGroup.defaults)
            if let first = result.firstRegionReadyAfterSeconds {
                PersistentLog.log(.diagnosticProbe(component: "TranscriptionService", instanceID: "firstRegion", action: "ready",
                    details: "model=\(name) seconds=\(String(format: "%.3f", first))"))
            }
            return result
        } catch {
            PersistentLog.log(.transcriptionFailed(error: PolishFailureReason.other(error).slug))
            throw error
        }
    }
}
