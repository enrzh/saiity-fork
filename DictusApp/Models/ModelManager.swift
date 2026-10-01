// DictusApp/Models/ModelManager.swift
// Manages the WhisperKit model lifecycle: download, select, delete, state tracking.
import Foundation
import Combine
import DictusCore
import WhisperKit
import FluidAudio

/// Represents the current state of a model in the download/preparation lifecycle.
///
/// WHY an enum with associated value for error:
/// Swift enums with associated values let us attach context (the error message)
/// directly to the state, instead of needing a separate error property. This makes
/// state handling exhaustive via switch — the compiler ensures every state is handled.
enum ModelState: Equatable {
    case notDownloaded
    case downloading
    case prewarming
    case ready
    case error(String)
}

/// Byte counters for an in-flight model download, rounded to whole megabytes
/// for display ("22 MB of 483 MB").
struct ModelDownloadBytes: Equatable {
    let downloadedMB: Int
    let totalMB: Int

    init(_ progress: ModelRepoDownloader.Progress) {
        downloadedMB = Int(progress.bytesDownloaded / 1_000_000)
        totalMB = Int(progress.totalBytes / 1_000_000)
    }
}

/// Manages WhisperKit model download, selection, deletion, and App Group persistence.
///
/// WHY @MainActor:
/// All @Published properties are observed by SwiftUI views on the main thread.
/// @MainActor guarantees all mutations happen on main, preventing data races.
///
/// WHY ObservableObject:
/// SwiftUI's @StateObject/@EnvironmentObject require ObservableObject conformance
/// to automatically re-render views when @Published properties change.
@MainActor
class ModelManager: ObservableObject {

    // MARK: - Published State

    /// Identifiers of models currently downloaded on device.
    @Published var downloadedModels: [String] = []

    /// The currently selected model identifier for transcription.
    @Published var activeModel: String?

    /// Whether the active model is chosen by the device-aware resolver or by the user.
    @Published var selectionMode: ModelSelectionMode = .automatic
    @Published var selectionProfile: ModelSelectionProfile = .balanced

    /// Per-model download progress (0.0 to 1.0). Only populated during active downloads.
    @Published var downloadProgress: [String: Float] = [:]

    /// Per-model byte counters ("22 MB of 483 MB") shown alongside the percentage.
    /// A moving byte counter reads as alive even while the percentage crawls
    /// through a huge weight file (issue #207). Populated for both engines
    /// since issue #210 unified the download pipeline.
    @Published var downloadByteInfo: [String: ModelDownloadBytes] = [:]

    /// Per-model lifecycle state. Updated as models move through download/prewarm/ready.
    @Published var modelStates: [String: ModelState] = [:]

    /// Current load state of the active model in the coordinator (issue #144).
    /// Mirrors `DictationCoordinator.modelLoadState` via App Group + NotificationCenter
    /// so SwiftUI can drive the loading overlay reactively.
    @Published var modelLoadState: ModelLoadState = .idle
    @Published var customModels: [CustomModel] = []
    /// Selected dictation cleanup / grammar backend (Apple Intelligence or Ollama).
    @Published var cleanupBackend: PolishCleanupBackend = .appleIntelligence

    // MARK: - Private

    private let defaults = AppGroup.defaults
    private var loadStateObserver: NSObjectProtocol?
    private var catalogDownloads: [String: Task<Void, Never>] = [:]

    /// Own download tasks outside recycled/filterable SwiftUI rows so Cancel always works.
    func startCatalogDownload(_ identifier: String, onError: @escaping (String) -> Void) {
        guard catalogDownloads[identifier] == nil else { return }
        catalogDownloads[identifier] = Task { @MainActor in
            defer { catalogDownloads[identifier] = nil }
            do { try await downloadModel(identifier) }
            catch is CancellationError { }
            catch { onError(error.localizedDescription) }
        }
    }

    func cancelCatalogDownload(_ identifier: String) {
        catalogDownloads[identifier]?.cancel()
    }

    /// Serial prewarm lock — only one CoreML compilation at a time.
    /// The Neural Engine cannot handle multiple models compiling simultaneously
    /// (causes ANE "E5 bundle" errors). Downloads are parallel, prewarms are serial.
    private let preparation = ModelPreparationCoordinator()

    /// Directory inside the App Group container where model files are stored.
    /// Using the shared container means the keyboard extension could also access
    /// models here in the future (though currently only the app downloads them).
    private var modelsDirectory: URL? {
        AppGroup.containerURL?.appendingPathComponent("Models", isDirectory: true)
    }

    /// WhisperKit's on-disk repo directory — the HubApi snapshot layout that
    /// `WhisperKit.download` historically used and that `WhisperKitConfig(modelFolder:)`
    /// expects: `Documents/huggingface/models/argmaxinc/whisperkit-coreml/{identifier}`.
    /// Single source of truth so download, delete, and cleanup stay path-parallel (issue #210).
    ///
    /// The path itself now lives in `WhisperModelRepository` so the dictation path can
    /// resolve the very same folder and load models without touching the network
    /// (issue #249). This property is kept as the local shorthand for the call sites below.
    private var whisperKitRepoDirectory: URL? {
        WhisperModelRepository.repositoryURL()
    }

    /// Per-model last-logged progress decile, so PersistentLog gets ~10 lines per
    /// download instead of hundreds. Main-actor confined like all other state here.
    private var lastLoggedDeciles: [String: Int] = [:]

    // MARK: - Init

    init() {
        loadState()
        // Initialize states for all known models (including deprecated Tiny/Base so
        // already-downloaded deprecated models still get their state set to .ready).
        for model in ModelInfo.allIncludingDeprecated {
            if downloadedModels.contains(model.identifier) {
                modelStates[model.identifier] = .ready
            } else {
                modelStates[model.identifier] = .notDownloaded
            }
        }
        // Mirror the coordinator's load state so SwiftUI can react (issue #144).
        // We read the persisted value once for cold-start consistency, then subscribe
        // to subsequent changes posted by `DictationCoordinator.setModelLoadState`.
        if let raw = defaults.string(forKey: SharedKeys.modelLoadState),
           let state = ModelLoadState(rawValue: raw) {
            modelLoadState = state
        }
        loadStateObserver = NotificationCenter.default.addObserver(
            forName: .dictusModelLoadStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?["state"] as? String,
                  let state = ModelLoadState(rawValue: raw) else { return }
            self?.modelLoadState = state
        }
    }

    deinit {
        if let observer = loadStateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    /// Reads persisted model state from App Group UserDefaults.
    ///
    /// WHY JSON for downloadedModels:
    /// UserDefaults can store arrays natively, but using JSON (Data) is more
    /// explicit and avoids type-casting issues. We store a JSON-encoded [String].
    func loadState() {
        selectionMode = ModelSelectionMode.active(from: defaults)
        selectionProfile = ModelSelectionProfile.active(from: defaults)
        var didMigrateRemovedModels = false
        if let data = defaults.data(forKey: SharedKeys.downloadedModels),
           let models = try? JSONDecoder().decode([String].self, from: data) {
            // Drop identifiers from engines removed in a later release.
            downloadedModels = models.filter { identifier in
                guard ModelInfo.forIdentifier(identifier) != nil else { return false }
                let installed = isArtifactInstalled(identifier)
                if !installed {
                    PersistentLog.log(.diagnosticProbe(
                        component: "ModelManager",
                        instanceID: identifier,
                        action: "artifactInvalid",
                        details: "persisted model has no complete local artifact"
                    ))
                }
                return installed
            }
            didMigrateRemovedModels = downloadedModels != models
        }
        let storedActiveModel = defaults.string(forKey: SharedKeys.activeModel)
        let storedOrFirst = storedActiveModel.flatMap { downloadedModels.contains($0) ? $0 : nil }
            ?? downloadedModels.first
        activeModel = selectionMode == .automatic
            ? automaticActiveModel() ?? storedOrFirst
            : storedOrFirst
        didMigrateRemovedModels = didMigrateRemovedModels || storedActiveModel != activeModel
        customModels = CustomModel.load(from: defaults)
        cleanupBackend = PolishCleanupBackend.load(from: defaults, customModels: customModels)

        if didMigrateRemovedModels {
            persistState()
        }

        // Resync modelStates with loaded downloadedModels so models downloaded
        // by onboarding's separate ModelManager instance show as .ready here.
        for model in ModelInfo.allIncludingDeprecated
        where downloadedModels.contains(model.identifier) {
            if modelStates[model.identifier] == nil || modelStates[model.identifier] == .notDownloaded {
                modelStates[model.identifier] = .ready
            }
        }
    }

    func addCustomModel(_ model: CustomModel) {
        if let index = customModels.firstIndex(where: {
            $0.id == model.id || $0.identityKey == model.identityKey
        }) {
            customModels[index] = model
        } else {
            customModels.append(model)
        }
        CustomModel.save(customModels, to: defaults)
    }

    func deleteCustomModel(_ model: CustomModel) {
        customModels.removeAll { $0.id == model.id }
        CustomModel.save(customModels, to: defaults)
        PolishCleanupBackend.handleDeletedModel(model, remaining: customModels, defaults: defaults)
        cleanupBackend = PolishCleanupBackend.load(from: defaults, customModels: customModels)
    }

    func selectCleanupBackend(_ backend: PolishCleanupBackend) {
        backend.persist(to: defaults)
        cleanupBackend = backend
    }

    /// Downloads a model variant, prewarms it, and updates state.
    ///
    /// WHY engine-aware download:
    /// Both engines download their HuggingFace repo via the shared
    /// ModelRepoDownloader (issue #210), but their on-disk layouts and
    /// prewarm/compile pipelines differ (WhisperKitConfig vs FluidAudio's
    /// AsrModels). This method routes to the correct path based on the engine.
    ///
    /// WHY foreground download (not background session):
    /// Background URLSession adds significant complexity (delegate callbacks, session
    /// restoration, app lifecycle handling). For v1, foreground download with visible
    /// progress is simpler and sufficient. Users will have the app open during download.
    func downloadModel(_ identifier: String) async throws {
        switch ModelInfo.forIdentifier(identifier)?.engine {
        case .parakeet:
            guard let version = parakeetVersion(for: identifier) else {
                throw ModelManagerError.parakeetUnavailable
            }
            try await downloadParakeetModel(identifier, version: version)
        default:
            try await downloadWhisperKitModel(identifier)
        }
    }

    /// Download a WhisperKit model variant from HuggingFace.
    ///
    /// WHY prewarm after download:
    /// WhisperKit models need Core ML compilation on first use. Prewarming does this
    /// compilation immediately after download, so the first transcription is fast.
    /// Without prewarming, the first transcription would have a ~10-30s delay.
    private func downloadWhisperKitModel(_ identifier: String) async throws {
        guard let modelsDir = modelsDirectory else {
            throw ModelManagerError.noContainer
        }

        // Create the models directory if it doesn't exist
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        guard let repoDir = whisperKitRepoDirectory else {
            throw ModelManagerError.noContainer
        }

        modelStates[identifier] = .downloading
        downloadProgress[identifier] = 0.0
        lastLoggedDeciles[identifier] = -1
        let catalogSizeMB = Int((ModelInfo.forIdentifier(identifier)?.sizeBytes ?? 0) / 1_000_000)
        PersistentLog.log(.modelDownloadStarted(name: identifier, sizeMB: catalogSizeMB))

        // Tracks which phase a failure (if any) belongs to. Download-phase failures
        // keep files on disk (every file is complete thanks to atomic per-file
        // moves) so a retry resumes where it left off; prewarm-phase failures still
        // clean up, because ANE compilation failures (E5 bundle errors) can leave
        // behind unusable cached files that prevent retry from working.
        var downloadPhaseCompleted = false

        do {
            // Download the variant's files ourselves instead of WhisperKit.download()
            // (issue #210): HubApi's progress is file-count weighted (a 5 MB config
            // moves the bar as much as a 300 MB weight blob), exposes no byte totals
            // for the MB counter, and has no stall detection or retry. The unified
            // ModelRepoDownloader gives WhisperKit models the same byte-accurate
            // progress, stall handling, and resume as Parakeet (issue #207), and
            // writes the exact on-disk layout WhisperKit already expects.
            let downloader = ModelRepoDownloader(configuration: .whisperKit(variant: identifier))
            try await downloader.download(to: repoDir, modelName: identifier) { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(progress, identifier: identifier)
                }
            }
            let modelFolder = repoDir.appendingPathComponent(identifier, isDirectory: true)

            PersistentLog.log(.modelDownloadCompleted(name: identifier))
            downloadPhaseCompleted = true

            // Prewarm: compile Core ML model for this device's Neural Engine/GPU.
            // Serialized — only one model compiles at a time. Multiple simultaneous
            // CoreML compilations crash the ANE with "E5 bundle" errors.
            //
            // WHY transition state BEFORE removing progress:
            // If we remove downloadProgress first while state is still .downloading,
            // ModelCardView's .downloading case reads progress ?? 0 = 0%, showing a
            // stuck-at-zero bar. Setting .prewarming first eliminates this gap.
            modelStates[identifier] = .prewarming
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)

            // Wait for any other prewarm to finish (poll on MainActor is safe)
            try await preparation.waitUntilIdle()

            preparation.beginPrewarm()
            defer { preparation.endPrewarm() }

            PersistentLog.log(.modelCompilationStarted(name: identifier))

            // Phase 37 instrumentation: capture timing + jetsam-headroom delta across prewarm.
            // `peakMB` in the log event stores the delta of available memory (in MB) between
            // pre- and post-prewarm. Positive delta ≈ steady-state memory footprint the model
            // retains after CoreML compilation finishes, which is the signal that matters for
            // per-device gating decisions on memory-constrained devices (e.g. iPhone 15 Pro Max).
            let prewarmStart = Date()
            let availableBeforeMB = DeviceCapabilities.current().availableMemoryMB

            let config = WhisperKitConfig(
                model: identifier,
                modelFolder: modelFolder.path,
                // Issue #370: A12/A13 need the audio encoder off the Neural Engine.
                // This is the site the onboarding hang happens at (prewarm/compile).
                computeOptions: WhisperComputeOptions.current(),
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )

            // Phase 37: guard the CoreML prewarm against indefinite hangs.
            // On iPhone ANE, some WhisperKit model variants fail to compile and the
            // async init never returns (E5 bundle load failure — issue #104,
            // 2026-04-22 iPhone 15 Pro Max). 120s is well above the observed normal
            // worst case (~17s for Parakeet Encoder on this device) so we don't
            // false-positive on legitimately long prewarms.
            let prewarmTimeoutSeconds = 120
            do {
                let outcome = await IsolatedDeadline.race(seconds: TimeInterval(prewarmTimeoutSeconds)) {
                    try await WhisperKit(config)
                }
                switch outcome {
                case .success(let kit):
                    _ = kit
                case .failure(let error):
                    throw error
                case .timedOut(let releaseWhenFinished):
                    preparation.quarantineFailedPrewarm(identifier, releaseWhenFinished: releaseWhenFinished) {
                        self.cleanupModelFiles($0)
                    }
                    throw ModelManagerError.prewarmTimeout(seconds: prewarmTimeoutSeconds)
                case .cancelled(let releaseWhenFinished):
                    preparation.quarantineFailedPrewarm(identifier, releaseWhenFinished: releaseWhenFinished) {
                        self.cleanupModelFiles($0)
                    }
                    throw CancellationError()
                }
            } catch let err as ModelManagerError {
                if case .prewarmTimeout(let s) = err {
                    PersistentLog.log(.modelPrewarmTimeout(name: identifier, timeoutSeconds: s))
                }
                throw err
            }

            let prewarmDurationMs = Int(Date().timeIntervalSince(prewarmStart) * 1000)
            let availableAfterMB = DeviceCapabilities.current().availableMemoryMB
            let consumedMB = max(0, availableBeforeMB - availableAfterMB)

            // Update state
            if !downloadedModels.contains(identifier) {
                downloadedModels.append(identifier)
            }

            // Automatic mode resolves again so a newly installed compatible model
            // can take over without another tap. Manual mode keeps the explicit
            // download selection behavior from earlier builds.
            activeModel = selectionMode == .automatic
                ? automaticActiveModel() ?? identifier
                : identifier

            modelStates[identifier] = .ready
            persistState()

            PersistentLog.log(.modelCompilationCompleted(name: identifier, durationMs: prewarmDurationMs))
            PersistentLog.log(.modelPrewarmPeakMemory(modelName: identifier, peakMB: consumedMB))
            PersistentLog.log(.modelSelected(name: identifier))

            // Issue #144: eagerly load the now-active model into the coordinator's
            // RAM-resident WhisperKit instance. The compile above used a throwaway
            // WhisperKit just to populate the Core ML cache.
            DictationCoordinator.shared.preloadActiveModel()
        } catch {
            modelStates[identifier] = .error(error.localizedDescription)
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)

            if downloadPhaseCompleted && !preparation.prewarmQuarantined {
                // Prewarm failure: clean up. ANE compilation failures (E5 bundle
                // errors) leave behind unusable cached files that prevent
                // re-download from working correctly. A timed-out or cancelled
                // initializer still has those files open; its quarantine task
                // deletes them after the initializer exits.
                cleanupModelFiles(identifier)
            }
            // Download failure: deliberately NO cleanup (issue #210, same policy as
            // the Parakeet path) — the downloader moves each file into place
            // atomically, so anything on disk is a complete file and a retry skips
            // it and resumes where it left off. Since issue #235, tapping the card's
            // "Retry" affordance retries in place; the full reset lives in the
            // overflow menu's "Delete partial download" entry (cleanupFailedModel).

            PersistentLog.log(.modelDownloadFailed(name: identifier, error: error.localizedDescription))
            throw error
        }
    }

    /// Download a Parakeet model via the app-side downloader, then compile via FluidAudio.
    ///
    /// WHY a separate method:
    /// WhisperKit and Parakeet use completely different download pipelines and
    /// cache locations. This method downloads the raw model files itself, then
    /// hands off to FluidAudio for CoreML compilation.
    ///
    /// Since Dictus now targets iOS 17, no availability guard is needed.
    /// FluidAudio is always available.
    private func downloadParakeetModel(_ identifier: String, version: AsrModelVersion) async throws {
        modelStates[identifier] = .downloading
        downloadProgress[identifier] = 0.0
        lastLoggedDeciles[identifier] = -1
        let catalogSizeMB = Int((ModelInfo.forIdentifier(identifier)?.sizeBytes ?? 0) / 1_000_000)
        PersistentLog.log(.modelDownloadStarted(name: identifier, sizeMB: catalogSizeMB))

        do {
            // Step 1: Download all raw model files with REAL byte-level progress
            // (issue #207). FluidAudio's DownloadUtils.downloadRepo uses the async
            // URLSession API, which never delivers didWriteData — progress only
            // moved on whole-file completion, and with Encoder's weight.bin being
            // ~92% of the payload the bar froze at ~5% for minutes (App Review
            // rejected 1.7.1(19) as "frozen at 4%"). ModelRepoDownloader downloads
            // the same files into the same cache directory using a delegate-based
            // downloadTask that does deliver byte callbacks.
            let cacheDir = AsrModels.defaultCacheDirectory(for: version)
            let downloader = ModelRepoDownloader(configuration: .parakeet(version: version))
            try await downloader.download(to: cacheDir, modelName: identifier) { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownloadProgress(progress, identifier: identifier)
                }
            }

            // Step 2: Wait for any other prewarm to finish (ANE conflict avoidance).
            // A timed-out Whisper initializer still owns its files; do not compile
            // Parakeet over that work.
            try await preparation.waitUntilIdle()

            // Step 3: Switch to prewarming state — download is done, CoreML compilation starts.
            preparation.beginPrewarm()
            modelStates[identifier] = .prewarming
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)
            PersistentLog.log(.modelPrewarmStarted(name: identifier))
            defer { preparation.endPrewarm() }

            // Step 4: Load and compile CoreML models.
            // ParakeetEngine.prepare() loads the files step 1 just downloaded and compiles
            // them; it never downloads anything itself (issue #252). This method is the
            // only place a Parakeet download starts.
            //
            // Phase 37 instrumentation mirrors the WhisperKit path: measure prewarm
            // duration + jetsam-headroom delta so both engines produce comparable
            // gating signals.
            let prewarmStart = Date()
            let availableBeforeMB = DeviceCapabilities.current().availableMemoryMB

            let parakeetEngine = ParakeetEngine()
            try await parakeetEngine.prepare(modelIdentifier: identifier)

            let prewarmDurationMs = Int(Date().timeIntervalSince(prewarmStart) * 1000)
            let availableAfterMB = DeviceCapabilities.current().availableMemoryMB
            let consumedMB = max(0, availableBeforeMB - availableAfterMB)

            // Update state
            if !downloadedModels.contains(identifier) {
                downloadedModels.append(identifier)
            }

            activeModel = selectionMode == .automatic
                ? automaticActiveModel() ?? identifier
                : identifier

            modelStates[identifier] = .ready
            persistState()

            PersistentLog.log(.modelCompilationCompleted(name: identifier, durationMs: prewarmDurationMs))
            PersistentLog.log(.modelPrewarmPeakMemory(modelName: identifier, peakMB: consumedMB))
            PersistentLog.log(.modelDownloadCompleted(name: identifier))
            PersistentLog.log(.modelSelected(name: identifier))

            // Issue #144: same proactive load as the WhisperKit path — see comment there.
            DictationCoordinator.shared.preloadActiveModel()
        } catch {
            modelStates[identifier] = .error(error.localizedDescription)
            downloadProgress.removeValue(forKey: identifier)
            downloadByteInfo.removeValue(forKey: identifier)
            lastLoggedDeciles.removeValue(forKey: identifier)

            // Deliberately NO cleanupModelFiles here after a download failure:
            // the downloader moves each file into place atomically, so anything on
            // disk is a complete file — leaving the cache intact lets a retry skip
            // already-downloaded files and resume where it left off. Since issue
            // #235, tapping the card's "Retry" affordance retries in place; the
            // full reset lives in the overflow menu's "Delete partial download"
            // entry (cleanupFailedModel).
            PersistentLog.log(.modelDownloadFailed(name: identifier, error: error.localizedDescription))
            throw error
        }
    }

    /// Applies one downloader progress tick: percentage bar, MB counter, and
    /// decile-throttled persistent logging (~10 log lines per download).
    /// Shared by the WhisperKit and Parakeet download paths (issue #210).
    private func updateDownloadProgress(_ progress: ModelRepoDownloader.Progress, identifier: String) {
        downloadProgress[identifier] = Float(progress.fraction)
        downloadByteInfo[identifier] = ModelDownloadBytes(progress)

        let decile = Int(progress.fraction * 10)
        if decile > (lastLoggedDeciles[identifier] ?? -1) {
            lastLoggedDeciles[identifier] = decile
            PersistentLog.log(.modelDownloadProgress(
                name: identifier,
                percent: Int(progress.fraction * 100),
                mbDownloaded: Int(progress.bytesDownloaded / 1_000_000),
                mbTotal: Int(progress.totalBytes / 1_000_000)
            ))
        }
    }

    /// Sets the active model for transcription and eagerly loads it into RAM.
    ///
    /// Issue #144: Before this proactive load, `selectModel` only wrote `activeModel`
    /// to App Group. The actual WhisperKit/Parakeet swap was deferred to the next
    /// `ensureEngineReady` call (triggered by the user tapping the mic). For large
    /// models like Whisper turbo, the swap took 1-3 minutes — and any mic taps
    /// during that window cascaded into concurrent `transcribe()` calls that
    /// cancelled each other with `Swift.CancellationError`.
    ///
    /// We now flip `modelLoadState` to `.loading` immediately and trigger the load
    /// up front. If the keyboard is tapped while a load is in flight, it opens
    /// Dictus in a prepare-only flow; `ModelLoadingOverlay` surfaces the wait.
    func selectModel(_ identifier: String) {
        guard downloadedModels.contains(identifier), isArtifactInstalled(identifier) else { return }
        selectionMode = .manual
        activeModel = identifier
        persistState()
        PersistentLog.log(.modelSelected(name: identifier))
        // Trigger an eager load so the model is in RAM before the next mic tap.
        DictationCoordinator.shared.preloadActiveModel()
    }

    /// Deletes a model from disk and updates state.
    ///
    /// WHY guard count > 1:
    /// The app must always have at least one model available for transcription.
    /// Without this guard, the user could delete all models and the keyboard
    /// would have no model to use, resulting in a broken experience.
    func deleteModel(_ identifier: String) throws {
        guard downloadedModels.count > 1 else {
            PersistentLog.log(.modelDeleteFailed(name: identifier, error: "cannot delete last model"))
            throw ModelManagerError.cannotDeleteLastModel
        }

        let engine = ModelInfo.forIdentifier(identifier)?.engine ?? .whisperKit

        // Remove model files from App Group container
        if let modelsDir = modelsDirectory {
            let modelPath = modelsDir.appendingPathComponent(identifier)
            if FileManager.default.fileExists(atPath: modelPath.path) {
                try FileManager.default.removeItem(at: modelPath)
            }
        }

        // Remove from WhisperKit's on-disk repo location
        // (Documents/huggingface/models/argmaxinc/whisperkit-coreml/{identifier} —
        // same path construction as the download, see whisperKitRepoDirectory).
        if let whisperKitDir = whisperKitRepoDirectory?.appendingPathComponent(identifier) {
            if FileManager.default.fileExists(atPath: whisperKitDir.path) {
                try FileManager.default.removeItem(at: whisperKitDir)
            }
        }

        // Remove only the selected FluidAudio cache so switching Parakeet versions
        // does not unexpectedly remove the other choice.
        switch engine {
        case .parakeet:
            if let version = parakeetVersion(for: identifier) {
                let versionDir = AsrModels.defaultCacheDirectory(for: version)
                if FileManager.default.fileExists(atPath: versionDir.path) {
                    try FileManager.default.removeItem(at: versionDir)
                }
            }
        default:
            break
        }

        downloadedModels.removeAll { $0 == identifier }
        modelStates[identifier] = .notDownloaded

        // If deleted model was active, switch to first remaining
        if activeModel == identifier {
            activeModel = selectionMode == .automatic
                ? automaticActiveModel() ?? downloadedModels.first
                : downloadedModels.first
        }

        persistState()
        PersistentLog.log(.modelDeleted(name: identifier, engine: engine.displayName))
    }

    /// Checks if a model is the device-recommended variant.
    ///
    /// WHY delegate to ModelInfo:
    /// The recommendation logic is RAM-based and belongs in the catalog layer
    /// (ModelInfo), not the state manager. This instance method preserves the
    /// call-site signature so views don't need to change.
    func isRecommended(_ identifier: String) -> Bool {
        identifier == selectionProfile.preferredIdentifier(for: DeviceCapabilities.current())
    }

    func setSelectionProfile(_ profile: ModelSelectionProfile) {
        selectionProfile = profile
        defaults.set(profile.rawValue, forKey: SharedKeys.modelSelectionProfile)
        setSelectionMode(.automatic)
    }

    /// Changes model policy and immediately applies the resulting model.
    func setSelectionMode(_ mode: ModelSelectionMode) {
        let previousModel = activeModel
        selectionMode = mode
        if mode == .automatic {
            activeModel = automaticActiveModel() ?? activeModel ?? downloadedModels.first
            persistState()
            if activeModel != nil && (activeModel != previousModel || modelLoadState != .ready && modelLoadState != .loading) {
                DictationCoordinator.shared.preloadActiveModel()
            }
        } else {
            persistState()
        }
    }

    /// Cleans up a failed model's files and resets its state to not downloaded.
    /// Called from the error card's overflow menu ("Delete partial download",
    /// issue #235) when the user wants to free disk space instead of retrying.
    func cleanupFailedModel(_ identifier: String) {
        cleanupModelFiles(identifier)
        modelStates[identifier] = .notDownloaded
    }

    /// Removes partially downloaded or corrupted model files from disk.
    /// Called after download/prewarm failure so a retry starts clean.
    private func cleanupModelFiles(_ identifier: String) {
        // Clean from App Group container
        if let modelsDir = modelsDirectory {
            let modelPath = modelsDir.appendingPathComponent(identifier)
            try? FileManager.default.removeItem(at: modelPath)
        }

        // Clean from WhisperKit's on-disk repo location (same path construction
        // as the download, see whisperKitRepoDirectory).
        if let whisperKitDir = whisperKitRepoDirectory?.appendingPathComponent(identifier) {
            try? FileManager.default.removeItem(at: whisperKitDir)
        }

        let engine = ModelInfo.allIncludingDeprecated.first(where: { $0.identifier == identifier })?.engine
        switch engine {
        case .parakeet:
            if let version = parakeetVersion(for: identifier) {
                try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: version))
            }
        default:
            break
        }

        PersistentLog.log(.modelCleanupPerformed(name: identifier, reason: "download-or-prewarm-failure"))

        // Remove from downloaded list if it was added prematurely
        downloadedModels.removeAll { $0 == identifier }
        if activeModel == identifier {
            activeModel = selectionMode == .automatic
                ? automaticActiveModel() ?? downloadedModels.first
                : downloadedModels.first
        }
        persistState()
    }

    /// Whether at least one model is downloaded and ready for transcription.
    var isModelReady: Bool {
        guard let activeModel else { return false }
        return downloadedModels.contains(activeModel) && isArtifactInstalled(activeModel)
    }

    // MARK: - Private

    private func parakeetVersion(for identifier: String) -> AsrModelVersion? {
        switch identifier {
        case "parakeet-tdt-0.6b-v2": return .v2
        case "parakeet-tdt-0.6b-v3": return .v3
        default: return nil
        }
    }

    private func automaticActiveModel() -> String? {
        guard !downloadedModels.isEmpty else { return nil }
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return selectionProfile.resolvedIdentifier(
            installed: Set(downloadedModels),
            osMajor: osMajor,
            capabilities: DeviceCapabilities.current()
        )
    }

    /// UserDefaults is only a claim that a model was downloaded. Validate the
    /// artifact before exposing it as runnable so a stale or partial cache
    /// cannot trap the keyboard in a load failure loop.
    private func isArtifactInstalled(_ identifier: String) -> Bool {
        guard let model = ModelInfo.forIdentifier(identifier) else { return false }
        switch model.engine {
        case .whisperKit:
            return WhisperModelRepository.isModelInstalled(identifier)
        case .parakeet:
            guard let version = parakeetVersion(for: identifier) else { return false }
            return ParakeetEngine.installedModelCacheDirectory(version: version) != nil
        }
    }

    /// Persists model state to App Group UserDefaults so the keyboard extension
    /// can read which model is active and whether transcription is available.
    private func persistState() {
        if let data = try? JSONEncoder().encode(downloadedModels) {
            defaults.set(data, forKey: SharedKeys.downloadedModels)
        }
        defaults.set(activeModel, forKey: SharedKeys.activeModel)
        defaults.set(selectionMode.rawValue, forKey: SharedKeys.modelSelectionMode)
        defaults.set(!downloadedModels.isEmpty, forKey: SharedKeys.modelReady)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.modelReadinessChanged)
    }
}

/// Errors specific to model management operations.
enum ModelManagerError: Error, LocalizedError {
    case cannotDeleteLastModel
    case noContainer
    case parakeetUnavailable
    case prewarmTimeout(seconds: Int)
    case prewarmBusy

    var errorDescription: String? {
        switch self {
        case .cannotDeleteLastModel:
            return "Cannot delete the last remaining model"
        case .noContainer:
            return "App Group container not available"
        case .parakeetUnavailable:
            return "Parakeet requires iOS 17+ or FluidAudio is not linked"
        case .prewarmTimeout(let seconds):
            return "Model optimization did not complete within \(seconds)s"
        case .prewarmBusy:
            return "A previous model optimization is still finishing. Wait until it ends before starting another."
        }
    }
}
