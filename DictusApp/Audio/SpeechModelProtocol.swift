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

    /// Release model objects and compiled runtime state while retaining downloaded files.
    /// This is used after a memory warning and must never be called during preparation
    /// or an active transcription.
    func releaseLoadedModel()
    func releaseLoadedModelAndWait() async
    func cancelCurrentInference()

    /// Transcribe audio samples to text.
    /// - Parameters:
    ///   - audioSamples: Float32 audio samples at 16 kHz mono.
    ///   - language: BCP-47 language code (e.g., "fr", "en"), or `nil` to let
    ///     the engine auto-detect the spoken language (issue #226 Auto-detect
    ///     mode — Whisper's built-in language detection).
    /// - Returns: Transcribed text string.
    func transcribe(audioSamples: [Float], language: String?) async throws -> String

    /// Returns text plus any per-region language metadata available from the engine.
    func transcribeDetailed(audioSamples: [Float], language: String?) async throws -> SpeechTranscriptionOutput
}

/// The text produced by one model call plus any language metadata the engine can
/// provide. The metadata is optional so Parakeet and older engines keep their
/// existing protocol behavior.
struct SpeechTranscriptionOutput {
    let text: String
    let regions: [SpeechRegionTranscript]
    /// Approximate time until the first sequential region was decoded. This is
    /// diagnostic only; the final merged transcript remains authoritative.
    let firstRegionReadyAfterSeconds: Double?

    var detectedLanguageCodes: [String] {
        var seen = Set<String>()
        return regions.compactMap { region in
            guard let raw = region.detectedLanguage?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            let code = raw.lowercased()
            guard seen.insert(code).inserted else { return nil }
            return raw
        }
    }

    init(text: String,
         regions: [SpeechRegionTranscript] = [],
         firstRegionReadyAfterSeconds: Double? = nil) {
        self.text = text
        self.regions = regions
        self.firstRegionReadyAfterSeconds = firstRegionReadyAfterSeconds
    }
}

extension SpeechModelProtocol {
    func releaseLoadedModelAndWait() async { releaseLoadedModel() }
    func cancelCurrentInference() {}
    /// Compatibility default for engines that only return text.
    func transcribeDetailed(audioSamples: [Float], language: String?) async throws -> SpeechTranscriptionOutput {
        SpeechTranscriptionOutput(
            text: try await transcribe(audioSamples: audioSamples, language: language)
        )
    }
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

    func releaseLoadedModel() {
        whisperKit = nil
        loadedModelName = nil
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
        try await transcribeDetailed(audioSamples: audioSamples, language: language).text
    }

    func transcribeDetailed(audioSamples: [Float], language: String?) async throws -> SpeechTranscriptionOutput {
        guard let whisperKit else {
            throw TranscriptionError.notReady
        }

        return try await WhisperKitTranscriptionSupport.transcribeDetailed(
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
    private static let retryContextSamples = 4_000
    private static let retryLogProbabilityThreshold = -1.0

    private struct DecodedRegion {
        let results: [TranscriptionResult]
        let text: String
        let detectedLanguage: String?
        let averageLogProbability: Double?

        var isLowConfidence: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (averageLogProbability.map {
                    $0 < WhisperKitTranscriptionSupport.retryLogProbabilityThreshold
                } ?? false)
        }
    }

    static func transcribe(
        whisperKit: WhisperKit,
        audioSamples: [Float],
        language: String?,
        logComponent: String
    ) async throws -> String {
        try await transcribeDetailed(
            whisperKit: whisperKit,
            audioSamples: audioSamples,
            language: language,
            logComponent: logComponent
        ).text
    }

    static func transcribeDetailed(
        whisperKit: WhisperKit,
        audioSamples: [Float],
        language: String?,
        logComponent: String
    ) async throws -> SpeechTranscriptionOutput {
        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let hintTokens = DictationVocabulary.recognitionPrompt.isEmpty ? nil
            : whisperKit.tokenizer.map { Array($0.encode(text: DictationVocabulary.recognitionPrompt).prefix(96)) }
        let options = decodingOptions(language: language, promptTokens: hintTokens)
        let audioQuality = SpeechAudioQuality.analyze(audioSamples)
        let gain = SpeechAudioGain.gain(for: audioSamples)
        let regions = segmenter.regions(in: audioSamples)
        logCoverage(regions: regions, sampleCount: audioSamples.count, component: logComponent)
        PersistentLog.log(.diagnosticProbe(
            component: logComponent,
            instanceID: "audioQuality",
            action: "measured",
            details: "condition=\(audioQuality.condition.rawValue) rms=\(String(format: "%.4f", audioQuality.rms)) peak=\(String(format: "%.4f", audioQuality.peak)) noise=\(String(format: "%.4f", audioQuality.estimatedNoiseFloor)) snrDB=\(String(format: "%.1f", audioQuality.signalToNoiseRatioDB)) clipping=\(String(format: "%.4f", audioQuality.clippingRatio)) gain=\(String(format: "%.2f", gain))"
        ))
        guard !regions.isEmpty else {
            throw TranscriptionError.noSpeech
        }
        if language == nil {
            // Segment the original signal and apply one bounded gain to each
            // region. This avoids retaining a second full recording while the
            // sequential runner is holding the source buffer.
            if regions.count > 1 {
                let transcripts = try await SpeechRegionTranscriptionRunner.run(
                    audioSamples: audioSamples,
                    regions: regions
                ) { index, slice, region in
                    try Task.checkCancellation()
                    let decodeStartedAt = Date()
                    let regionGain = SpeechAudioGain.gain(for: slice)
                    let first = try await decode(
                        whisperKit: whisperKit,
                        audioSamples: SpeechAudioGain.applying(regionGain, to: slice),
                        options: options
                    )
                    var selected = first
                    var retryAttempted = false
                    if first.isLowConfidence {
                        retryAttempted = true
                        let retryStart = max(0, region.startSample - retryContextSamples)
                        let retryEnd = min(audioSamples.count, region.endSample + retryContextSamples)
                        let retrySamples = SpeechAudioGain.applying(
                            regionGain,
                            to: audioSamples[retryStart..<retryEnd]
                        )
                        let retry = try await decode(
                            whisperKit: whisperKit,
                            audioSamples: retrySamples,
                            options: decodingOptions(language: language, temperature: 0.2, promptTokens: hintTokens)
                        )
                        if isBetter(retry, than: first) {
                            selected = retry
                        }
                    }
                    let decodeDuration = Date().timeIntervalSince(decodeStartedAt)
                    let fallbackReason: String?
                    if selected.results.isEmpty {
                        fallbackReason = "noResults"
                    } else if retryAttempted {
                        fallbackReason = selected.text == first.text
                            ? "lowConfidenceRetryRejected"
                            : "lowConfidenceRetry"
                    } else {
                        fallbackReason = nil
                    }
                    let languageEvidence = SpeechLanguageEvidence.analyze(
                        text: selected.text,
                        detectedLanguage: selected.detectedLanguage
                    )
                    PersistentLog.log(.diagnosticProbe(
                        component: logComponent,
                        instanceID: "autoRegion-\(index)",
                        action: retryAttempted ? "decodedWithRetry" : "decoded",
                        details: "regionIndex=\(index) startSample=\(region.startSample) endSample=\(region.endSample) durationSec=\(String(format: "%.2f", region.durationSeconds())) decodeMs=\(Int(decodeDuration * 1000)) detected=\(selected.detectedLanguage ?? "unknown") validated=\(languageEvidence.validatedLanguageCode ?? "unknown") evidence=\(String(format: "%.2f", languageEvidence.score)) chars=\(selected.text.count) avgLogProb=\(selected.averageLogProbability.map { String(format: "%.3f", $0) } ?? "unknown") fallback=\(fallbackReason ?? "none")"
                    ))
                    return SpeechRegionTranscript(
                        region: region,
                        text: selected.text,
                        detectedLanguage: selected.detectedLanguage,
                        validatedLanguage: languageEvidence.validatedLanguageCode,
                        decodeDurationSeconds: decodeDuration,
                        averageLogProbability: selected.averageLogProbability,
                        fallbackReason: fallbackReason,
                        languageEvidenceScore: languageEvidence.score
                    )
                }

                let merged = SpeechTranscriptMerger.merge(transcripts)
                guard !merged.isEmpty else {
                    throw TranscriptionError.transcriptionFailed("Empty transcription result")
                }
                return SpeechTranscriptionOutput(
                    text: merged,
                    regions: transcripts,
                    firstRegionReadyAfterSeconds: transcripts.first?.decodeDurationSeconds
                )
            }
        }

        let preparedSamples = gain == 1
            ? audioSamples
            : SpeechAudioGain.applying(gain, to: audioSamples[...])
        let decodeStartedAt = Date()
        let results: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: preparedSamples,
            decodeOptions: options
        )
        let decodeDuration = Date().timeIntervalSince(decodeStartedAt)

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
        let logProbabilities = results.flatMap { $0.segments }.map { Double($0.avgLogprob) }
        let averageLogProbability = logProbabilities.isEmpty
            ? nil
            : logProbabilities.reduce(0, +) / Double(logProbabilities.count)
        let fallbackReason = results.isEmpty ? "noResults" : nil
        let audioDurationSec = Float(audioSamples.count) / 16_000.0
        let text = results.map { $0.text }.joined(separator: " ")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionError.transcriptionFailed("Empty transcription result")
        }
        let detectedLanguage = results.first?.language
        let languageEvidence = SpeechLanguageEvidence.analyze(
            text: trimmed,
            detectedLanguage: detectedLanguage
        )
        PersistentLog.log(.diagnosticProbe(
            component: logComponent,
            instanceID: "transcribe",
            action: "segmentsReturned",
            details: "results=\(results.count) segments=\(totalSegments) chars=\(totalCharCount) audioSec=\(String(format: "%.2f", audioDurationSec)) decodeMs=\(Int(decodeDuration * 1000)) lastSegmentEndSec=\(String(format: "%.2f", lastSegmentEnd)) detected=\(detectedLanguage ?? "unknown") validated=\(languageEvidence.validatedLanguageCode ?? "unknown") evidence=\(String(format: "%.2f", languageEvidence.score)) avgLogProb=\(averageLogProbability.map { String(format: "%.3f", $0) } ?? "unknown") fallback=\(fallbackReason ?? "none")"
        ))

        return SpeechTranscriptionOutput(
            text: trimmed,
            regions: [SpeechRegionTranscript(
                region: SpeechRegion(startSample: 0, endSample: audioSamples.count),
                text: trimmed,
                detectedLanguage: detectedLanguage,
                validatedLanguage: languageEvidence.validatedLanguageCode,
                decodeDurationSeconds: decodeDuration,
                averageLogProbability: averageLogProbability,
                fallbackReason: fallbackReason,
                languageEvidenceScore: languageEvidence.score
            )],
            firstRegionReadyAfterSeconds: decodeDuration
        )
    }

    private static func decode(
        whisperKit: WhisperKit,
        audioSamples: [Float],
        options: DecodingOptions
    ) async throws -> DecodedRegion {
        let results: [TranscriptionResult] = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )
        let text = results.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let logProbabilities = results.flatMap { $0.segments }.map { Double($0.avgLogprob) }
        let averageLogProbability = logProbabilities.isEmpty
            ? nil
            : logProbabilities.reduce(0, +) / Double(logProbabilities.count)
        return DecodedRegion(
            results: results,
            text: text,
            detectedLanguage: results.first?.language,
            averageLogProbability: averageLogProbability
        )
    }

    private static func isBetter(_ candidate: DecodedRegion, than baseline: DecodedRegion) -> Bool {
        guard !candidate.text.isEmpty else { return false }
        guard baseline.text.isEmpty else {
            guard let candidateScore = candidate.averageLogProbability else { return false }
            guard let baselineScore = baseline.averageLogProbability else { return true }
            return candidateScore > baselineScore
        }
        return true
    }

    private static func logCoverage(regions: [SpeechRegion],
                                    sampleCount: Int,
                                    component: String) {
        let coverage = SpeechRegionCoverage(regions: regions, totalSampleCount: sampleCount)
        PersistentLog.log(.diagnosticProbe(
            component: component,
            instanceID: "regionCoverage",
            action: "measured",
            details: "regions=\(regions.count) totalSamples=\(coverage.totalSampleCount) coveredSamples=\(coverage.coveredSampleCount) overlapSamples=\(coverage.overlapSampleCount) uncoveredSamples=\(coverage.uncoveredSampleCount) uncoveredWithinSpeechSpan=\(coverage.uncoveredWithinSpeechSpan)"
        ))
    }

    private static func decodingOptions(
        language: String?,
        temperature: Float = 0.0,
        promptTokens: [Int]? = nil
    ) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: temperature,
            // WhisperKit's language detector requires the prefill path: it
            // detects the language token first, then rebuilds the prompt with
            // that token before decoding the transcript. Without the prefill,
            // `detectLanguage` can report the right language but the decoder
            // still starts from Whisper's default English prompt, which makes
            // multilingual speech look translated into English. Every Auto
            // region gets its own fresh detection and prompt refresh.
            usePrefillPrompt: true,
            // Never reuse a decoder prefill cache for Auto regions. A cache can
            // carry the previous region's language token, which makes a mixed
            // recording look translated into the first language detected.
            usePrefillCache: language != nil,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            promptTokens: promptTokens,
            chunkingStrategy: .vad
        )
    }
}
