// DictusApp/Audio/ParakeetEngine.swift
// FluidAudio-based Parakeet STT engine, iOS 17+ only.
import Foundation
import DictusCore
import FluidAudio

/// Parakeet TDT speech-to-text engine using FluidAudio SDK.
///
/// WHY @available(iOS 17.0, *):
/// FluidAudio's CoreML models require APIs only available on iOS 17+.
/// Since Dictus now targets iOS 17, this guard is technically redundant
/// but kept as documentation and future-proofing.
///
/// IMPORTANT: Never run Parakeet model load simultaneously with WhisperKit prewarm.
/// Both use the Neural Engine for CoreML compilation. Simultaneous compilation
/// causes ANE "E5 bundle" crashes. The caller (DictationCoordinator) must serialize
/// engine initialization — only one engine loads at a time.
@available(iOS 17.0, *)
class ParakeetEngine: SpeechModelProtocol {
    var engineName: String { "Parakeet" }

    private var asrManager: AsrManager?
    private var isInitialized = false

    var isReady: Bool {
        isInitialized
    }

    /// The FluidAudio cache directory when it holds a complete model set, otherwise `nil`.
    ///
    /// WHY it lives here (issue #252):
    /// This is the single place that binds FluidAudio's own constants — the cache location
    /// and the file names it loads — to the completeness rule in `ParakeetModelRepository`.
    /// `DictationCoordinator` uses it to fail fast before starting an init task, and
    /// `prepare` uses it to guard the load itself, so neither has to know the layout.
    /// Reading the names from `ModelNames.ASR` rather than restating them means a
    /// dependency bump that renames a bundle is a compile-time change, not a silent one.
    ///
    /// IMPORTANT: `AsrModels.defaultCacheDirectory` resolves Application Support for the
    /// *current process*, so this must be called from DictusApp. FluidAudio is not linked
    /// into the keyboard extension, which could not load a model anyway.
    static func installedModelCacheDirectory(version: AsrModelVersion = .v3) -> URL? {
        ParakeetModelRepository.installedCacheDirectory(
            AsrModels.defaultCacheDirectory(for: version),
            requiredModelBundles: ModelNames.ASR.requiredModels,
            vocabularyFileName: ModelNames.ASR.vocabularyFile
        )
    }

    /// Load and initialize the selected Parakeet model from the local cache.
    ///
    /// WHY this never downloads (issue #252):
    /// This used to call `AsrModels.downloadAndLoad`, which loads locally when the files
    /// are cached but starts a HuggingFace download when they are not — during dictation,
    /// while the user waits, with no progress and no way to cancel. That is the asymmetry
    /// issue #249 removed for Whisper: downloading is the model manager's job, where
    /// progress and cancellation already exist. The cache is verified first and the load
    /// is strictly local; an absent or partial cache fails fast with the same localised
    /// message the Whisper path produces.
    ///
    /// The model manager still works: `ModelManager.downloadParakeetModel` downloads the
    /// repo itself through `ModelRepoDownloader` and only then calls this method, which
    /// performs the Core ML compilation step.
    ///
    /// - Parameter modelIdentifier: Catalog identifier used to select v2 or v3.
    func prepare(modelIdentifier: String) async throws {
        guard !isInitialized else { return }

        let version: AsrModelVersion = modelIdentifier == "parakeet-tdt-0.6b-v2" ? .v2 : .v3

        guard let cacheDirectory = Self.installedModelCacheDirectory(version: version) else {
            let error = SpeechModelError.modelNotInstalled(identifier: modelIdentifier)
            PersistentLog.log(.diagnosticProbe(
                component: "ParakeetLoad",
                instanceID: modelIdentifier,
                action: "localModelMissing",
                details: error.diagnosticDescription
            ))
            throw error
        }

        do {
            // Compile the cached Parakeet v3 CoreML models. `load` reads the bundles the
            // guard above verified; it does not resolve anything over the network.
            let models = try await AsrModels.load(from: cacheDirectory, version: version)

            // Initialize the ASR manager for transcription
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)

            self.asrManager = manager
            self.isInitialized = true

            DictusLogger.app.info("ParakeetEngine: \(modelIdentifier) loaded and ready")
        } catch {
            isInitialized = false
            asrManager = nil

            DictusLogger.app.error("ParakeetEngine: initialization failed — \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func releaseLoadedModel() {
        asrManager = nil
        isInitialized = false
    }

    /// Transcribe audio samples using Parakeet v3.
    ///
    /// - Parameters:
    ///   - audioSamples: Float32 audio samples at 16 kHz mono.
    ///   - language: Language code (or `nil` for Auto-detect mode, #226).
    ///     Parakeet TDT v3 auto-detects language from audio — this parameter is
    ///     a no-op either way. Dictation uses Auto-detect for every model; this
    ///     parameter remains for the shared engine interface. Language forcing
    ///     requires a separate ASR backend such as Qwen3-ASR (iOS 18+).
    /// - Returns: Transcribed text.
    func transcribe(audioSamples: [Float], language: String?) async throws -> String {
        guard let asrManager else {
            throw TranscriptionError.notReady
        }

        guard !audioSamples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        do {
            let result = try await asrManager.transcribe(audioSamples)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw TranscriptionError.transcriptionFailed("Empty Parakeet transcription result")
            }

            return text
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.transcriptionFailed("Parakeet: \(error.localizedDescription)")
        }
    }
}

/// Errors specific to ParakeetEngine.
enum ParakeetEngineError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Parakeet engine is not available on this iOS version"
        }
    }
}
