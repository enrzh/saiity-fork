// DictusApp/Audio/TranscriptionService.swift
// Encapsulates speech-to-text transcription with multi-engine routing.
import Foundation
import WhisperKit
import DictusCore

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
///
/// Phase 10.3 additions:
/// - SpeechModelProtocol-based engine routing (WhisperKit or Parakeet)
/// - Backward-compatible: existing prepare(whisperKit:) still works
class TranscriptionService {
    private var whisperKit: WhisperKit?

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
        whisperKit = nil
        loadedModelFolder = nil
        await engine?.releaseLoadedModelAndWait()
    }
    @available(iOS 18.0, *)
    var qwenEngine: QwenSpeechEngine? { activeEngine as? QwenSpeechEngine }

    /// The folder path of the currently loaded model, used to detect when
    /// we need to reinitialize WhisperKit for a different model.
    private var loadedModelFolder: String?

    /// Whether a model object is retained by either the compatibility path or
    /// the active engine path.
    var hasLoadedModel: Bool {
        whisperKit != nil || activeEngine?.isReady == true
    }

    /// Inject or re-use a WhisperKit instance (backward-compatible path).
    ///
    /// WHY keep this method:
    /// DictationCoordinator injects the WhisperKit instance for the transcription path.
    /// UnifiedAudioEngine doesn't need WhisperKit — it uses native AVAudioEngine.
    func prepare(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    /// Set the active engine for protocol-based transcription routing.
    ///
    /// WHY a separate method from prepare(whisperKit:):
    /// The engine abstraction is layered on top of the existing WhisperKit path.
    /// When activeEngine is set, transcribe() delegates to it instead of using
    /// the raw WhisperKit instance. This allows both paths to coexist during
    /// the transition to multi-engine support.
    func prepare(engine: SpeechModelProtocol) {
        self.activeEngine = engine
    }

    /// Release the active runtime while leaving downloaded model files untouched.
    /// The coordinator guards this call against active transcription and model init.
    func releaseLoadedModel() {
        activeEngine?.releaseLoadedModel()
        activeEngine = nil
        whisperKit = nil
        loadedModelFolder = nil
    }

    /// Prepare TranscriptionService with a specific model at a given path.
    ///
    /// WHY a separate prepare method for model paths:
    /// When the user switches models, we need to reinitialize WhisperKit with
    /// the new model. This method handles that switch transparently.
    func prepare(modelPath: String) async throws {
        // Skip reinitialization if same model is already loaded
        if loadedModelFolder == modelPath, whisperKit != nil {
            return
        }

        let config = WhisperKitConfig(
            modelFolder: modelPath,
            // Issue #370: A12/A13 need the audio encoder off the Neural Engine.
            computeOptions: WhisperComputeOptions.current(),
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )

        let kit = try await WhisperKit(config)
        self.whisperKit = kit
        self.loadedModelFolder = modelPath
    }

    /// Transcribe audio samples to text.
    ///
    /// Routes to the active SpeechModelProtocol engine if set,
    /// otherwise falls back to the direct WhisperKit path.
    ///
    /// WHY the fallback:
    /// During transition to multi-engine, the prepare(whisperKit:) path is still used.
    /// The fallback ensures zero regressions while new engine routing is added.
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
        if let activeEngine {
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

        // Fallback: direct WhisperKit path (backward compatibility)
        guard let whisperKit else {
            throw TranscriptionError.notReady
        }

        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        do {
            let output = try await WhisperKitTranscriptionSupport.transcribeDetailed(
                whisperKit: whisperKit,
                audioSamples: audioSamples,
                language: language,
                logComponent: "TranscriptionService"
            )
            let durationMs = DictationRuntimeMetrics.elapsedMilliseconds(since: transcriptionStart)
            let wordCount = output.text.split(separator: " ").count
            PersistentLog.log(.transcriptionCompleted(durationMs: durationMs, wordCount: wordCount))
            logPerformance(
                modelName: modelName,
                audioSamples: audioSamples,
                transcriptionDurationMs: durationMs,
                firstRegionReadyAfterSeconds: output.firstRegionReadyAfterSeconds
            )
            return output
        } catch let error as TranscriptionError {
            PersistentLog.log(.transcriptionFailed(error: PolishFailureReason.other(error).slug))
            throw error
        } catch {
            PersistentLog.log(.transcriptionFailed(error: PolishFailureReason.other(error).slug))
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Phase 37 instrumentation: emits `transcriptionPerformance` alongside the existing
    /// `transcriptionCompleted` event. Kept as a small helper so both the multi-engine
    /// path and the legacy WhisperKit path log identical schema.
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
