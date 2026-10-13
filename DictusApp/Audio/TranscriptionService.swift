// DictusApp/Audio/TranscriptionService.swift
// Encapsulates speech-to-text transcription with multi-engine routing.
import Foundation
import SyllivraKernel

/// Errors that can occur during transcription.
enum TranscriptionError: Error, LocalizedError {
    case notReady
    case emptyAudio
    case noSpeech
    case transcriptionFailed(String)

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
        }
    }
}

/// Handles transcription with multi-engine routing via SpeechModelProtocol.
///
/// WHY this is a separate class from UnifiedAudioEngine:
/// Single Responsibility — UnifiedAudioEngine handles recording, TranscriptionService handles
/// transcription. This also makes it easy to swap or test each independently.
class TranscriptionService {
    /// The active STT engine, set via prepare(engine:).
    /// WHY a protocol reference:
    /// DictationCoordinator creates the appropriate engine (WhisperKitEngine or
    /// ParakeetEngine) based on the user's active model. TranscriptionService
    /// doesn't know or care which engine it is — it just calls transcribe().
    private var activeEngine: SpeechModelProtocol?
    func cancelCurrentInference() { activeEngine?.cancelCurrentInference() }
    func releaseLoadedModelAndWait() async {
        let engine = activeEngine
        activeEngine = nil
        await engine?.releaseLoadedModelAndWait()
    }
    @available(iOS 18.0, *)
    var qwenEngine: QwenSpeechEngine? { activeEngine as? QwenSpeechEngine }

    /// Whether the active engine retains a ready model.
    var hasLoadedModel: Bool {
        activeEngine?.isReady == true
    }

    /// Use the engine prepared by DictationCoordinator.
    func prepare(engine: SpeechModelProtocol) {
        self.activeEngine = engine
    }

    /// Release the active runtime while leaving downloaded model files untouched.
    /// The coordinator guards this call against active transcription and model init.
    func releaseLoadedModel() {
        activeEngine?.releaseLoadedModel()
        activeEngine = nil
    }

    /// Transcribe audio samples to text.
    ///
    /// Routes to the active SpeechModelProtocol engine.
    ///
    /// WHY `languagePolicy` is a parameter instead of reading App Group here (#226):
    /// The STT language is decoupled from the keyboard language, and the whole
    /// dictation pipeline (STT + polish + finalization) must run on ONE
    /// consistent snapshot. DictationCoordinator captures the policy once at
    /// transcription start and passes it down, so a mid-dictation keyboard
    /// language change cannot desync transcription from polish. In particular,
    /// the keyboard toolbar switcher only ever writes SharedKeys.language, so
    /// an explicit or auto choice can never be overridden by it.
    func transcribe(audioSamples: [Float],
                    languagePolicy: TranscriptionLanguagePolicy) async throws -> String {
        try await transcribeDetailed(audioSamples: audioSamples, languagePolicy: languagePolicy).text
    }

    func transcribeDetailed(audioSamples: [Float],
                            languagePolicy: TranscriptionLanguagePolicy) async throws -> SpeechTranscriptionOutput {
        let transcriptionStart = DispatchTime.now().uptimeNanoseconds

        // nil = Whisper auto-detection. Parakeet ignores the value entirely.
        let language = languagePolicy.sttLanguageCode

        // Determine active model name for logging (from the same snapshot the
        // engine choice was derived from, so logs describe the actual model).
        let modelName = languagePolicy.modelIdentifier.isEmpty
            ? "unknown" : languagePolicy.modelIdentifier
        PersistentLog.log(.transcriptionStarted(modelName: modelName))
        // Trace the resolution so device tests (#226 acceptance: Mandarin via
        // Auto-detect, toolbar-switcher non-override) can verify it from logs.
        //
        // `mode` spells the mode out rather than printing its stored value
        // (#332): a bare "fr" could not be told from a coincidence, and a
        // reader of `mode=fr keyboard=en` had no way to see that the user had
        // explicitly chosen French. `sttEffective` says whether the engine
        // honours `stt=` at all — Parakeet ignores it and auto-detects from
        // audio, which is how `stt=en` came to sit above a French transcript.
        PersistentLog.log(.diagnosticProbe(
            component: "TranscriptionService",
            instanceID: "languageResolution",
            action: "resolved",
            details: "mode=\(languagePolicy.mode.telemetryDescription) keyboard=\(languagePolicy.keyboardLanguage.rawValue) engine=\(languagePolicy.engine.rawValue) stt=\(language ?? "auto") sttEffective=\(languagePolicy.sttLanguageIsEffective ? "yes" : "no")"
        ))

        // Route to active engine if set (multi-engine path)
        guard let activeEngine else {
            throw TranscriptionError.notReady
        }
        do {
            let result = try await activeEngine.transcribeDetailed(
                audioSamples: audioSamples,
                language: language
            )
            let durationMs = DictationRuntimeMetrics.elapsedMilliseconds(since: transcriptionStart)
            let wordCount = result.text.split(separator: " ").count
            PersistentLog.log(.transcriptionCompleted(durationMs: durationMs, wordCount: wordCount))
            logPerformance(
                modelName: modelName,
                audioSamples: audioSamples,
                transcriptionDurationMs: durationMs,
                firstRegionReadyAfterSeconds: result.firstRegionReadyAfterSeconds
            )
            return result
        } catch {
            PersistentLog.log(.transcriptionFailed(error: PolishFailureReason.other(error).slug))
            throw error
        }
    }

    /// Phase 37 instrumentation: emits `transcriptionPerformance` alongside the existing
    /// `transcriptionCompleted` event for every engine.
    ///
    /// `peakMemoryMB` here is a point-in-time reading of remaining jetsam headroom right
    /// after transcription, not a true peak. Paired with the prewarm delta in
    /// `modelPrewarmPeakMemory`, it gives a coarse-but-useful signal for per-device gating.
    private func logPerformance(modelName: String,
                                audioSamples: [Float],
                                transcriptionDurationMs: Int,
                                firstRegionReadyAfterSeconds: Double?) {
        // WhisperKit and FluidAudio both consume audio at 16 kHz. Hardcoded to stay
        // consistent with the sample-rate assumption everywhere else in the pipeline.
        let sampleRateHz = 16_000
        let audioDurationMs = audioSamples.isEmpty ? 0 : (audioSamples.count * 1000) / sampleRateHz
        let peakMemoryMB = DeviceCapabilities.current().availableMemoryMB
        PersistentLog.log(.transcriptionPerformance(
            modelName: modelName,
            audioDurationMs: audioDurationMs,
            transcriptionDurationMs: transcriptionDurationMs,
            peakMemoryMB: peakMemoryMB
        ))
        ModelWarmLatencyStore.record(
            transcriptionDurationMs,
            for: modelName,
            in: AppGroup.defaults
        )
        if let firstRegionReadyAfterSeconds {
            PersistentLog.log(.diagnosticProbe(
                component: "TranscriptionService",
                instanceID: "firstRegion",
                action: "ready",
                details: "model=\(modelName) seconds=\(String(format: "%.3f", firstRegionReadyAfterSeconds))"
            ))
        }
    }
}
