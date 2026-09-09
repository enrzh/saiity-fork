// DictusApp/Audio/SpeechModelProtocol.swift
// Protocol abstraction for multi-engine speech-to-text.
import Foundation
import WhisperKit
import DictusCore

/// Common interface for all speech-to-text engines (WhisperKit, Parakeet, etc.).
///
/// WHY a protocol:
/// Dictus supports multiple STT engines — WhisperKit and Parakeet. Instead of
/// embedding engine-specific code in TranscriptionService, each engine conforms
/// to this protocol. TranscriptionService dispatches to whichever engine is active.
/// This makes adding new engines trivial: implement the protocol, register in the catalog.
protocol SpeechModelProtocol {
    /// Human-readable engine name for logging and UI.
    var engineName: String { get }

    /// Whether the engine is initialized and ready to transcribe.
    var isReady: Bool { get }

    /// Prepare the engine with a specific model variant.
    /// - Parameter modelIdentifier: The catalog identifier (e.g., "openai_whisper-small").
    func prepare(modelIdentifier: String) async throws

    /// Transcribe audio samples to text.
    /// - Parameters:
    ///   - audioSamples: Float32 audio samples at 16 kHz mono.
    ///   - language: BCP-47 language code (e.g., "fr", "en"), or `nil` to let
    ///     the engine auto-detect the spoken language (issue #226 Auto-detect
    ///     mode — Whisper's built-in language detection).
    /// - Returns: Transcribed text string.
    func transcribe(audioSamples: [Float], language: String?) async throws -> String
}

/// Failures raised while preparing a speech model for transcription.
///
/// WHY a dedicated error type (issue #249):
/// The dictation path used to hand WhisperKit the model *name* with downloads
/// enabled, so a missing or unreachable model surfaced WhisperKit's own English
/// developer-facing string ("Model not found. Please check the model or repo name
/// and try again.") straight into the keyboard's error banner. These cases carry
/// localised, user-actionable text instead, while `diagnosticDescription` keeps the
/// English technical detail for `PersistentLog`.
enum SpeechModelError: LocalizedError {
    /// The selected variant is absent from the local model repository, or its
    /// folder holds no compiled Core ML bundle.
    case modelNotInstalled(identifier: String)

    /// The model files are present but the engine failed to load them.
    case engineLoadFailed(identifier: String, underlying: Error)

    /// User-facing text. Written to `DictationErrorChannel` and displayed by whichever
    /// surface the user is on — the keyboard's toolbar, the app's failure screen, or both.
    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return String(localized: "This model is not installed. Open sAiity and download it in Settings > Models.")
        case .engineLoadFailed:
            return String(localized: "The transcription model could not be loaded. Open sAiity and try again.")
        }
    }

    /// English technical detail for the log. Never shown to the user.
    var diagnosticDescription: String {
        switch self {
        case .modelNotInstalled(let identifier):
            return "model not installed locally: \(identifier)"
        case .engineLoadFailed(let identifier, let underlying):
            return "engine load failed for \(identifier): \(underlying)"
        }
    }
}

/// WhisperKit engine conforming to SpeechModelProtocol.
///
/// WHY a wrapper class instead of making TranscriptionService conform directly:
/// TranscriptionService orchestrates the transcription pipeline (error handling,
/// settings reading, post-processing). WhisperKitEngine is a thin adapter that
/// maps WhisperKit's API to the protocol, keeping concerns separate.
class WhisperKitEngine: SpeechModelProtocol {
    var engineName: String { "WhisperKit" }

    /// The underlying WhisperKit instance, injected from DictationCoordinator.
    private var whisperKit: WhisperKit?

    /// The model folder currently loaded, to avoid redundant reinitialization.
    private var loadedModelName: String?

    var isReady: Bool {
        whisperKit != nil
    }

    /// Accept a pre-initialized WhisperKit instance (from DictationCoordinator).
    ///
    /// WHY this separate method:
    /// DictationCoordinator already manages WhisperKit's lifecycle (pre-loading at
    /// launch, audio session configuration). Rather than duplicating that logic,
    /// the coordinator passes its WhisperKit instance to the engine.
    func setWhisperKit(_ kit: WhisperKit) {
        self.whisperKit = kit
    }

    func prepare(modelIdentifier: String) async throws {
        // Skip if same model is already loaded
        if loadedModelName == modelIdentifier, whisperKit != nil {
            return
        }

        // Load from the local repository only (issue #249). Downloading belongs to
        // the model manager, never to a transcription path — see the equivalent
        // guard in DictationCoordinator.ensureWhisperKitEngineReady.
        guard let modelFolder = WhisperModelRepository.installedModelFolderURL(for: modelIdentifier) else {
            throw SpeechModelError.modelNotInstalled(identifier: modelIdentifier)
        }

        let config = WhisperKitConfig(
            model: modelIdentifier,
            modelFolder: modelFolder.path,
            // Issue #370: A12/A13 need the audio encoder off the Neural Engine.
            computeOptions: WhisperComputeOptions.current(),
            verbose: false,
            prewarm: true,
            load: true,
            download: false
        )

        let kit = try await WhisperKit(config)
        self.whisperKit = kit
        self.loadedModelName = modelIdentifier
    }

    func transcribe(audioSamples: [Float], language: String?) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.notReady
        }

        return try await WhisperKitTranscriptionSupport.transcribe(
            whisperKit: whisperKit,
            audioSamples: audioSamples,
            language: language,
            logComponent: "WhisperKitEngine"
        )
    }
}

/// Shared WhisperKit decode policy used by the active engine and compatibility
/// fallback. Auto mode is segmented only when the detector finds multiple
/// regions; ordinary recordings retain the original full-recording request.
enum WhisperKitTranscriptionSupport {
    private static let segmenter = SpeechRegionSegmenter()

    static func transcribe(
        whisperKit: WhisperKit,
        audioSamples: [Float],
        language: String?,
        logComponent: String
    ) async throws -> String {
        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let options = decodingOptions(language: language)
        if language == nil {
            let regions = segmenter.regions(in: audioSamples)
            if regions.count > 1 {
                let transcripts = try await SpeechRegionTranscriptionRunner.run(
                    audioSamples: audioSamples,
                    regions: regions
                ) { index, slice, region in
                    try Task.checkCancellation()
                    let results: [TranscriptionResult] = try await whisperKit.transcribe(
                        audioArray: Array(slice),
                        decodeOptions: options
                    )
                    let text = results.map { $0.text }.joined(separator: " ")
                    let detectedLanguage = results.first?.language
                    PersistentLog.log(.diagnosticProbe(
                        component: logComponent,
                        instanceID: "autoRegion-\(index)",
                        action: "decoded",
                        details: "regionIndex=\(index) startSample=\(region.startSample) endSample=\(region.endSample) durationSec=\(String(format: "%.2f", region.durationSeconds())) detected=\(detectedLanguage ?? "unknown") chars=\(text.count)"
                    ))
                    return SpeechRegionTranscript(
                        region: region,
                        text: text,
                        detectedLanguage: detectedLanguage
                    )
                }

                let merged = SpeechTranscriptMerger.merge(transcripts)
                guard !merged.isEmpty else {
                    throw TranscriptionError.transcriptionFailed("Empty transcription result")
                }
                return merged
            }
        }

        let results: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        if language == nil {
            let detected = results.first?.language ?? "unknown"
            PersistentLog.log(.diagnosticProbe(
                component: logComponent,
                instanceID: "languageDetection",
                action: "detected",
                details: "detected=\(detected)"
            ))
        }

        let totalSegments = results.reduce(0) { $0 + $1.segments.count }
        let totalCharCount = results.reduce(0) { $0 + $1.text.count }
        let lastSegmentEnd = results.flatMap { $0.segments }.map { $0.end }.max() ?? 0
        let audioDurationSec = Float(audioSamples.count) / 16_000.0
        PersistentLog.log(.diagnosticProbe(
            component: logComponent,
            instanceID: "transcribe",
            action: "segmentsReturned",
            details: "results=\(results.count) segments=\(totalSegments) chars=\(totalCharCount) audioSec=\(String(format: "%.2f", audioDurationSec)) lastSegmentEndSec=\(String(format: "%.2f", lastSegmentEnd))"
        ))

        let text = results.map { $0.text }.joined(separator: " ")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionError.transcriptionFailed("Empty transcription result")
        }
        return trimmed
    }

    private static func decodingOptions(language: String?) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            // An English prefill is useful for a fixed English decode but can
            // anchor Whisper's first language token in Auto mode. Let every
            // independently decoded region choose its own language.
            usePrefillPrompt: language != nil,
            usePrefillCache: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            chunkingStrategy: .vad
        )
    }
}
