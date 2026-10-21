// DictusApp/DictationCoordinator.swift
// Manages the dictation lifecycle: recording via UnifiedAudioEngine + transcription via TranscriptionService.
import Foundation
import Combine
import AVFoundation
import UIKit
import SyllivraKernel
import WhisperKit
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif

/// Manages the dictation lifecycle in the main app.
/// Phase 3.1: Observes keyboard stop/cancel signals via Darwin notifications,
/// forwards waveform energy to App Group for keyboard visualization.
///
/// WHY this class is @MainActor and uses static let shared:
/// - @MainActor ensures all @Published property updates happen on the main thread (required by SwiftUI)
/// - Singleton pattern because there's only ever one dictation session active at a time,
///   and multiple views need to observe the same coordinator (ContentView, RecordingView)
@MainActor
class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()

    // MARK: - Published State

    @Published var status: DictationStatus = .idle

    /// The last transcription, and only that. Nil on every failure by construction —
    /// `startDictation` resets it and nothing but a successful transcription assigns it —
    /// so it is not, and must not be read as, a failure channel (#320). What went wrong
    /// lives in `DictationErrorChannel`.
    @Published var lastResult: String?
    private var deferredPreload = false
    var canChangeSpeechRuntime: Bool {
        DictationModelPreferences.canChangeRuntime(status: status, finalizing: isTranscribingInFlight)
    }
    /// Transient ASR output, before explicit translation or cleanup. History-off
    /// keeps this only for the current result/recovery flow, not diagnostics.
    @Published private(set) var lastOriginalResult: String?
    @Published private(set) var lastTranslationFallbackReason: TranslationFallbackReason?

    /// Forwarded from UnifiedAudioEngine for waveform visualization in RecordingView.
    @Published var bufferEnergy: [Float] = []

    /// Forwarded from UnifiedAudioEngine for elapsed time display in RecordingView.
    @Published var bufferSeconds: Double = 0

    // MARK: - Private

    private let defaults = AppGroup.defaults
    private let audioEngine = UnifiedAudioEngine()
    private let transcriptionService = TranscriptionService()

    /// Whether the audio engine is currently running.
    /// Used by DictusApp to detect "warm but engine-dead" state after Power button stop.
    var isEngineRunning: Bool { audioEngine.isEngineRunning }
    var isKeyboardModelReady: Bool {
        currentModelName == defaults.string(forKey: SharedKeys.activeModel) && transcriptionService.hasLoadedModel
    }

    /// Explicit, process-local opt-in. Loading a model or relaunching the app
    /// never starts a microphone session on its own.
    @Published private(set) var keyboardSessionEnabled = false
    @Published private(set) var isPreparingKeyboardSession = false
    private var keyboardSessionTask: Task<Void, Never>?

    func setKeyboardDictationEnabled(_ enabled: Bool) {
        KeyboardDictationService.setEnabled(enabled, in: defaults)
        if enabled {
            defaults.set(OnboardingUsage.keyboard.rawValue, forKey: SharedKeys.onboardingUsage)
            enableKeyboardSession()
        } else {
            disableKeyboardSession()
            if DictationSessionLivenessPolicy.isActive(status) { cancelDictation() }
            LiveActivityManager.shared.updateServiceEnabled(false)
        }
    }

    func enableKeyboardSession() {
        if status == .failed {
            DictationErrorChannel.clear()
            updateStatus(.idle)
        }
        keyboardSessionEnabled = true
        KeyboardDictationService.setEnabled(true, in: defaults)
        guard UIApplication.shared.applicationState == .active else { return }
        guard canChangeSpeechRuntime else { return }
        guard keyboardSessionTask == nil, !audioEngine.isEngineRunning else { return }
        isPreparingKeyboardSession = true
        keyboardSessionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.keyboardSessionTask = nil
                self.isPreparingKeyboardSession = false
                if Task.isCancelled && self.keyboardSessionEnabled {
                    self.enableKeyboardSession()
                }
            }
            do {
                guard try await self.audioEngine.ensureMicrophonePermission() else {
                    throw AudioEngineError.permissionDenied
                }
                try await self.ensureEngineReady(preferredModel: self.defaults.string(forKey: SharedKeys.activeModel)
                    ?? ModelInfo.defaultIdentifier)
                guard !Task.isCancelled, self.keyboardSessionEnabled,
                      UIApplication.shared.applicationState == .active else { return }
                try self.audioEngine.configureAudioSession()
                try self.audioEngine.warmUp()
                self.setModelLoadState(.ready, reason: "keyboard-session-ready")
                LiveActivityManager.shared.startStandbyActivity()
                LiveActivityManager.shared.updateServiceEnabled(true)
            } catch {
                guard !Task.isCancelled else { return }
                if let error = error as? ModelManagerError, case .modelInUse = error { return }
                self.setKeyboardDictationEnabled(false)
                self.handleError(error.localizedDescription, disposition: .requiresApp)
            }
        }
    }

    func disableKeyboardSession() {
        keyboardSessionEnabled = false
        keyboardSessionTask?.cancel()
        LiveActivityManager.shared.updateServiceEnabled(false, persistSetting: false)
        // The task clears its own slot on exit, preventing a cancelled model
        // preparation from clobbering a newer task's ownership.
        if !audioEngine.isRecording { audioEngine.deactivateIfIdle() }
    }

    private func collectCompletedRecording() -> [Float] {
        if keyboardSessionEnabled {
            // Idle buffers are discarded by the engine; its existing ten-minute
            // idle timeout bounds microphone ownership between keyboard holds.
            return audioEngine.collectSamples()
        }
        return audioEngine.collectSamplesAndDeactivate()
    }

    func refreshKeyboardModel() {
        guard canChangeSpeechRuntime, keyboardSessionEnabled else { return }
        disableKeyboardSession()
        enableKeyboardSession()
    }

    /// Release audio resources when the coordinator is not in an active dictation.
    /// A pending/recording session must survive a scene transition so a cold start
    /// can finish or an existing background recording can continue.
    func deactivateAudioIfIdle() {
        // The setup guide owns playback while its PiP video accompanies Settings.
        guard AVAudioSession.sharedInstance().category != .playback else { return }
        guard !DictationSessionLivenessPolicy.isActive(status) else { return }
        guard !keyboardSessionEnabled else { return }
        audioEngine.deactivateIfIdle()
    }

    /// Timeout watchdog for whichever post-recording stage is running.
    ///
    /// WHY one timer for two stages (#267): they are mutually exclusive and the
    /// failure it catches is the same one -- a stage that never hands over, leaving
    /// the keyboard's overlay up with nothing behind it. What differs is only how
    /// long is too long, which `stageWatchdogTimeout(for:)` answers.
    ///
    /// The status it was armed for is captured by the timer's own closure, which
    /// re-checks it before firing -- a stage that has handed over to the next one
    /// must not be torn down by the previous one's timer.
    private var stageWatchdog: Timer?

    private var whisperKit: WhisperKit?
    private var currentModelName: String?
    private var dictationTask: Task<Void, Never>?
    private var memoryWarningObserver: NSObjectProtocol?

    /// Fires ~1.5s into a recording to prewarm the Apple FM polish model (#141).
    /// Held so it can be cancelled if the user stops before it fires. See
    /// `schedulePolishPrewarm()`.
    private var polishPrewarmTask: Task<Void, Never>?

    /// Which dictation the app is currently in. Moves when one starts and when one
    /// is abandoned -- see `DictationSessionGeneration` for why both matter.
    private let sessions = DictationSessionController()

    /// The generation delayed UI closures capture (issue #60). RecordingView's
    /// dismiss and onboarding auto-advance bail out when it has moved on, so a
    /// stale reset can never tear down a fresh recording.
    var dictationGeneration: Int { sessions.current }

    /// Set when cold start dictation is deferred because the app is .inactive.
    ///
    /// Cleared by whichever of its two consumers gets there first: the
    /// `didBecomeActive` retry, or `resolvePendingColdStartOnBackground()` when the
    /// app leaves the foreground without ever having become active (#311). The
    /// second one is not an optimisation -- it is the only exit that always exists.
    /// `didBecomeActive` is an event the user can withhold simply by swiping back
    /// fast enough, and four of twelve deliberately fast dictations did exactly that.
    ///
    /// Not `private` only because the second consumer lives in `ColdStartResolution.swift`
    /// and `private` is file-scoped. Still single-writer.
    var pendingColdStartDictation = false

    /// Background execution assertion held across the resolution of a parked cold
    /// start (#311). `.invalid` when none is held. Managed entirely from
    /// `ColdStartResolution.swift`, which is why it is not `private`.
    ///
    /// WHY this exists: the cold-start path runs from the `.background` scene
    /// transition, so the process is on its way to suspension, and the runtime it
    /// needs is the runtime it is trying to earn -- the audio mode grants nothing
    /// until `startRecording()` has succeeded, which is the far side of the window.
    /// Without an assertion that window is covered only by iOS's default
    /// post-background grace, which is a behaviour and not a contract. A suspension
    /// inside it would leave the flag cleared, no engine started and nothing reported:
    /// the exact silence this whole change exists to make impossible, with a log line
    /// to prove we had thought about it.
    var coldStartAssertion: UIBackgroundTaskIdentifier = .invalid

    /// Background execution assertion held across Whisper + polish after recording
    /// stops. `.invalid` when none is held.
    ///
    /// Audio background mode keeps the process alive only while the engine is
    /// capturing. `collectSamples()` ends capture, and without an assertion iOS
    /// suspends Dictus as soon as the user is looking at another app's keyboard.
    /// That is why dictation finishes on the in-app setup screen (foreground) and
    /// sits on "Cleaning up..." everywhere else.
    var transcriptionAssertion: UIBackgroundTaskIdentifier = .invalid

    /// Task that resolves when WhisperKit is fully loaded.
    /// WHY: Both init() pre-load and startDictation() call ensureEngineReady().
    /// If startDictation() arrives while pre-load is still running, it must AWAIT
    /// the ongoing init instead of starting a duplicate one. This Task acts as
    /// a concurrency lock — the first caller creates it, subsequent callers await it.
    private var initTask: Task<Void, Error>?
    private var preparingModelIdentifier: String?

    /// Re-entry flag for stopDictation. Prevents the 3+ concurrent transcribe()
    /// calls observed in #144 when a user taps stop multiple times during a model
    /// swap (turbo load). Set synchronously on entry, cleared in the Task's defer.
    private var isTranscribingInFlight = false

    /// Captured when the app accepts a dictation request.
    private var currentLanguageRequest = DictationLanguageRequest(
        mode: .followKeyboard,
        translationTarget: nil
    )
    private var currentLanguagePolicy = TranscriptionLanguagePolicy(
        mode: .followKeyboard,
        keyboardLanguage: .english,
        engine: .whisperKit,
        modelIdentifier: ""
    )
    private var issueRecordingDurationMs: Int?
    private var issueTranscribeMs: Int?
    private var issuePolishMs: Int?
    private var issueRawText: String?

#if canImport(Translation)
    @Published private(set) var translationConfiguration: Any?

    /// Each readiness refresh supersedes every earlier refresh, including one with
    /// the same source language. The async availability calls can finish out of order.
    private var translationReadinessGeneration = 0

    private struct PendingTranslation {
        let id: UUID
        let sessionID: String
        let generation: Int
        let requestGeneration: Int
        let sourceText: String
        let source: String?
        let target: TranslationLanguage
        let clientIdentifier: String
        let originalText: String
        let continuation: CheckedContinuation<TranslationOutcome, Never>
    }

    private var pendingTranslation: PendingTranslation?
    private var activeTranslationSession: Any?
#endif

    /// Combine subscriptions forwarding UnifiedAudioEngine's published values to coordinator.
    private var energyCancellable: AnyCancellable?
    private var secondsCancellable: AnyCancellable?

    private init() {
        DictationModelPreferences.migrate(in: defaults)
        // Forward UnifiedAudioEngine's energy levels and seconds to coordinator.
        // NOTE: App Group forwarding for the keyboard is handled directly from
        // the audio thread in UnifiedAudioEngine's processBuffer.
        energyCancellable = audioEngine.$bufferEnergy
            .receive(on: DispatchQueue.main)
            .sink { [weak self] energy in
                guard let self else { return }
                self.bufferEnergy = energy
                // Only forward to Dynamic Island when user is actively recording
                guard self.audioEngine.isRecording else { return }
                LiveActivityManager.shared.updateWaveform(levels: energy)
            }
        secondsCancellable = audioEngine.$bufferSeconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                self?.bufferSeconds = seconds
            }

        // Observe keyboard-initiated stop/cancel signals via Darwin notifications.
        observeKeyboardSignals()

        // Clear stale transcription left over from a previous crash or missed pickup.
        // 5-minute threshold: if the keyboard didn't read it by now, it never will.
        if let ts = defaults.object(forKey: SharedKeys.lastTranscriptionTimestamp) as? Double,
           Date().timeIntervalSince1970 - ts > 300 {
            defaults.removeObject(forKey: SharedKeys.lastTranscription)
            defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
            defaults.synchronize()
        }

        // Audit the shared dictation state before anything reads it (issue #261).
        reconcileOrphanedDictationState()

        if #available(iOS 26.0, *) {
            refreshTranslationReadiness()
        }

        // Phase 37 instrumentation: snapshot device capabilities once per app launch
        // so the log stream has a stable anchor for per-device gating analysis.
        let snapshot = DeviceCapabilities.current()
        PersistentLog.log(.deviceCapabilitySnapshot(
            model: snapshot.deviceModelIdentifier,
            ramGB: snapshot.physicalMemoryGB,
            availableMemoryMB: snapshot.availableMemoryMB,
            thermalState: snapshot.thermalState.logLabel
        ))

        // Pre-load the speech model eagerly on app launch, but keep the microphone
        // cold. Model preparation does not need AVAudioSession and activating it here
        // makes iOS show the microphone indicator while the app is merely idle.
        Task {
            let modelReady = defaults.bool(forKey: SharedKeys.appDictationModelReady)
            guard modelReady else {
                self.setModelLoadState(.idle, reason: "init-preload-no-model")
                return
            }

            self.setModelLoadState(.loading, reason: "init-preload")
            do {
                try await ensureEngineReady()
                PersistentLog.log(.appWhisperKitLoaded(modelName: self.currentModelName ?? "unknown"))
                self.setModelLoadState(.ready, reason: "init-preload-success")
            } catch {
                if error is CancellationError { return }
                if let error = error as? ModelManagerError, case .modelInUse = error { return }
                PersistentLog.log(.engineWarmUpFailed(context: "init-preload-model", error: error.localizedDescription))
                self.recordModelLoadFailure(error, context: "init-preload-model")
                self.setModelLoadState(.idle, reason: "init-preload-failed")
            }
        }

        // Stop audio engine when user taps Power button in Dynamic Island.
        // WHY here (not in LiveActivityManager):
        // The audio engine is owned by DictationCoordinator.
        // StopStandbyIntent posts this notification because it can't reference coordinator
        // directly (the intent file is compiled into DictusWidgets too).
        NotificationCenter.default.addObserver(
            forName: Notification.Name("DictusStopStandbyRequested"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Stop any active dictation first, including transcription or
                // processing stages that may still own a background assertion.
                self.disableKeyboardSession()
                if DictationSessionLivenessPolicy.isActive(self.status) {
                    self.cancelDictation()
                }
                // Kill any configured audio session — removes the orange mic
                // indicator even when the engine was already stopped.
                self.audioEngine.deactivateIfIdle()
                // Keep the Live Activity visible as the control that can turn
                // dictation back on. The service toggle intent updates its state.
                LiveActivityManager.shared.updateServiceEnabled(false)
                PersistentLog.log(.engineWarmUpFailed(context: "standby-power-off", error: "user stopped standby"))
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("DictusServiceToggleRequested"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let enabled = KeyboardDictationService.isEnabled(in: self.defaults)
                self.setKeyboardDictationEnabled(enabled)
            }
        }

        // Cancel any in-flight dictation when the audio session is interrupted
        // (phone call, Siri, etc.) or media services are reset. UnifiedAudioEngine
        // already tore down the engine; we just need to clean up the dictation
        // pipeline state and notify the keyboard that the recording failed
        // (issue #106).
        NotificationCenter.default.addObserver(
            forName: .dictusAudioSessionInterrupted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.disableKeyboardSession()
                self?.handleAudioInterruptionDuringDictation()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .dictusWarmStateReleased, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.disableKeyboardSession() }
        }

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.releaseLoadedModelIfSafe(reason: "memory-warning")
            }
        }

        // WHY observe didBecomeActive (not willEnterForeground):
        // willEnterForeground fires while the app is still transitioning.
        // didBecomeActive is the first point where foreground-only model preparation
        // and any pending URL cold-start retry are safe to perform.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // `sessionConfigured` used to be a hardcoded `true` here, so
                // every `sessionConfigured=true` in a device log was a literal
                // rather than a measurement — including the one quoted as
                // evidence in #293. Both fields are now read from the engine.
                PersistentLog.log(.engineStateSnapshot(
                    engineRunning: self.audioEngine.isEngineRunning,
                    isRecording: self.audioEngine.isRecording,
                    hasWhisperKit: self.whisperKit != nil,
                    sessionConfigured: self.audioEngine.sessionConfigured,
                    allowsHaptics: self.audioEngine.allowsHapticsDuringRecording,
                    context: "didBecomeActive"
                ))

                // Wall-clock backstop for older warm-state sessions (issue #106).
                // Then remove any remaining idle session immediately. Neither path
                // touches a pending or active dictation.
                self.audioEngine.enforceIdleReleaseIfDue()
                self.deactivateAudioIfIdle()
                if self.keyboardSessionEnabled { self.enableKeyboardSession() }

                // Recover DI if it was lost (Activity.request fails from background on cold start).
                // Must happen BEFORE pendingColdStartDictation so transitionToRecording finds an activity.
                LiveActivityManager.shared.ensureActivityAlive()

                // Retry deferred cold start dictation now that app is fully active.
                // WHY here: URL scheme launches fire handleIncomingURL at .inactive state,
                // where engine.start() fails. startDictation sets pendingColdStartDictation
                // and returns. Now that we're .active, retry the full startDictation flow.
                //
                // This stays the primary path — it is the one that runs from a fully
                // active app with a recovered audio session. The background path added
                // in #311 is the fallback for when this event never arrives.
                if self.pendingColdStartDictation {
                    self.pendingColdStartDictation = false
                    // Only retry if keyboard is still waiting (watchdog hasn't reset to idle)
                    let keyboardStatus = self.defaults.string(forKey: SharedKeys.dictationStatus) ?? "nil"
                    PersistentLog.log(.coldStartRetry(keyboardStatus: keyboardStatus))
                    if keyboardStatus == DictationStatus.requested.rawValue {
                        self.startDictation(fromURL: true)
                    }
                    return
                }

                guard self.canChangeSpeechRuntime else { return }
                let modelReady = self.defaults.bool(forKey: SharedKeys.appDictationModelReady)
                guard modelReady else {
                    return
                }

                let activeModel = self.defaults.string(forKey: SharedKeys.appDictationModel)
                    ?? ModelInfo.sAiityDefaultIdentifier
                guard self.currentModelName != activeModel else {
                    self.setModelLoadState(.ready, reason: "didBecomeActive-model-already-loaded")
                    return
                }

                do {
                    self.setModelLoadState(.loading, reason: "didBecomeActive-model-preload")
                    try await self.ensureEngineReady()
                    PersistentLog.log(.appWhisperKitLoaded(modelName: self.currentModelName ?? "unknown"))
                    self.setModelLoadState(.ready, reason: "didBecomeActive-model-preload-success")
                } catch {
                    if error is CancellationError { return }
                    if let error = error as? ModelManagerError, case .modelInUse = error { return }
                    PersistentLog.log(.engineWarmUpFailed(context: "didBecomeActive-model-preload", error: error.localizedDescription))
                    self.recordModelLoadFailure(error, context: "didBecomeActive-model-preload")
                    self.setModelLoadState(.idle, reason: "didBecomeActive-model-preload-failed")
                }
            }
        }
    }

    /// Schedule a prewarm of the Apple FM polish model partway into a recording (#141).
    ///
    /// Apple recommends calling `prewarm()` at least one second before
    /// `respond()`, "when interaction is imminent". The start of a recording is
    /// exactly that signal: we know polish will run in a few seconds, and the
    /// recording itself provides the lead time. Firing at ~1.5s also aligns with
    /// the polish engine's <2s skip gate — if we're still recording at 1.5s the
    /// clip will almost certainly cross 2s and actually be polished, so warming
    /// is not wasted on flash dictations.
    ///
    /// The `status == .recording` guard drops the prewarm if the user already
    /// stopped. `PolishCoordinator.prewarm()` is itself a no-op when the toggle
    /// is off, so we don't load the model into memory for nothing.
    private func schedulePolishPrewarm() {
        polishPrewarmTask?.cancel()
        polishPrewarmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.status == .recording else { return }
            PolishCoordinator.shared.prewarm()
        }
    }

    // MARK: - Public API

    /// Start the recording pipeline.
    /// Called from URL scheme (first time) or Darwin notification (subsequent times).
    ///
    /// Two paths:
    /// - WARM START: engine already running → purge idle samples + startRecording()
    /// - COLD START: engine not running → startRecording() starts it (<100ms) + load model in parallel
    ///
    /// - Parameters:
    ///   - fromURL: If true, the app was opened via URL scheme from the keyboard.
    ///   - allowInactiveStart: Skip the cold-start defer below and attempt the start
    ///     from whatever state the app is in. Set only by
    ///     `resolvePendingColdStartOnBackground()`, which is the last chance a parked
    ///     start gets (#311) — deferring a second time there would park it forever.
    func startDictation(fromURL: Bool = false, allowInactiveStart: Bool = false) {
        // Refuse a duplicate before clearing output or cancelling ongoing polish.
        guard ColdStartResolutionPolicy.canStartNewDictation(from: status) else { return }
        if fromURL {
            guard defaults.string(forKey: SharedKeys.dictationStatus) == DictationStatus.requested.rawValue,
                  !defaults.bool(forKey: SharedKeys.cancelRequested) else { return }
        }
        guard (!fromURL && UIApplication.shared.applicationState == .active) || defaults.object(forKey: SharedKeys.serviceEnabled) == nil
                || defaults.bool(forKey: SharedKeys.serviceEnabled) else {
            handleError("Dictation service is turned off.", disposition: .requiresApp)
            return
        }

        // Clear previous recording state before starting new recording.
        // WHY here (not in stopDictation): DI tap and lockscreen paths call
        // startDictation directly without going through stopDictation first.
        // The old result must be cleared regardless of entry path so
        // RecordingView never shows a stale transcription card.
        lastResult = nil
        lastOriginalResult = nil
        lastTranslationFallbackReason = nil
        issueRecordingDurationMs = nil
        issueTranscribeMs = nil
        issuePolishMs = nil
        issueRawText = nil
        // Same argument, one process further out (#320): the previous attempt's failure
        // reason is stale the moment a new attempt begins, and this is the only event
        // that makes it so. Clearing here — rather than when a surface reads it — is
        // what lets both the keyboard and the app read it, in either order.
        DictationErrorChannel.clear()
        bufferEnergy = []
        bufferSeconds = 0
        // Cancel any polish still running from the previous dictation (#141).
        PolishCoordinator.shared.cancelInflight()
        polishPrewarmTask?.cancel()
        PersistentLog.log(.statusChanged(from: status.rawValue, to: "clearing-for-new", source: "startDictation-reset"))

        // New session supersedes any pending delayed reset (issue #60) and any
        // outstanding work from the previous one (#267).
        sessions.beginSession()
#if canImport(Translation)
        if #available(iOS 26.0, *) {
            cancelPendingTranslation()
        }
#endif
        captureLanguageRequest()
        // A background assertion cannot activate a cold microphone. Offer an
        // explicit recovery action without switching apps during a keyboard hold.
        let appState = UIApplication.shared.applicationState
        if !fromURL && appState != .active && !audioEngine.isEngineRunning {
            handleError("Keyboard dictation is not enabled. Open Syllivra to enable it.", disposition: .requiresApp)
            return
        }

        PersistentLog.log(.dictationStarted(fromURL: fromURL, appState: "\(appState.rawValue)", engineRunning: audioEngine.isEngineRunning))

        // Check if a model is downloaded and ready.
        // Force a cross-process sync before reading — right after a URL-scheme wake
        // the App Group defaults can return a stale `false`, producing a bogus
        // "no model downloaded" error on the first attempt (observed in #102).
        defaults.synchronize()
        let modelReady = currentLanguageRequest.clientIdentifier?.hasPrefix("app-") == true
            ? defaults.bool(forKey: SharedKeys.appDictationModelReady) : defaults.bool(forKey: SharedKeys.modelReady)
        guard modelReady else {
            PersistentLog.log(.dictationFailed(error: "No model downloaded"))
            // Localised since #249 — this sibling of the model-availability failure
            // reached the keyboard banner in English regardless of device language.
            handleError(String(localized: "No model downloaded. Open Syllivra to download a model."), disposition: .requiresApp)
            return
        }

        // Refuse new dictation if an explicit model swap is in flight.
        // Issue #144: tapping the mic during a turbo load caused the keyboard to
        // queue dispatches that all collapsed into 3+ concurrent transcribe()
        // calls when the load resolved. Reading the App Group state lets us short-
        // circuit cleanly — the keyboard's overlay UI surfaces the wait to the user.
        //
        // Issue #167: URL-scheme cold-start launches arrive while the init-preload
        // is still loading the model. Failing here would route first-use dictation
        // into `failed` state. Skip the guard for fromURL=true and let the existing
        // cold-start defer at line ~368 park the request as `pendingColdStartDictation`
        // — the retry's `ensureEngineReady` awaits the in-flight initTask via its lock.
        let currentLoadState = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        if currentLoadState == ModelLoadState.loading.rawValue && !fromURL {
            PersistentLog.log(.dictationDeferred(reason: "model load in flight (state=loading)"))
            // The keyboard watchdog re-reads shared state and offers an explicit
            // recovery action if preparation does not finish in time.
            return
        }

        // Cancel any in-flight dictation before starting a new one
        dictationTask?.cancel()
        updateStatus(.requested)

        // The session these start paths belong to. `ensureMicrophonePermission` is
        // an await even when permission is already granted, so a cancel queued on
        // the main actor can land between here and the first write below (#267).
        let session = sessions.current

        if audioEngine.isEngineRunning {
            // WARM START: engine already running → purge + record (instant)
            dictationTask = Task {
                do {
                    let hasPermission = try await audioEngine.ensureMicrophonePermission()
                    guard hasPermission else {
                        guard mayReport(session, "permission denial") else { return }
                        handleError("Microphone permission denied", disposition: .requiresApp)
                        return
                    }
                    // Before `startRecording`, not merely before the status write:
                    // a cancelled start that reached the engine would leave the mic
                    // capturing for a dictation the user called off -- the orphaned
                    // engine of #60, arrived at from the other end.
                    guard mayReport(session, "warm start") else { return }
                    try await ensureEngineReady(preferredModel: currentLanguagePolicy.modelIdentifier)
                    guard mayReport(session, "prepared warm start") else { return }
                    try audioEngine.startRecording()
                    updateStatus(.recording)
                    LiveActivityManager.shared.transitionToRecording()
                    PersistentLog.log(.audioEngineStarted)
                    schedulePolishPrewarm()
                    await verifyAudioFlow()
                } catch {
                    PersistentLog.log(.dictationFailed(error: "Warm start: \(error.localizedDescription)"))
                    guard mayReport(session, "warm start failure") else { return }
                    handleError(error.localizedDescription)
                }
            }
        } else {
            // COLD START: engine not running → start engine + record + load model in parallel
            //
            // WHY defer when not .active:
            // URL scheme launches fire handleIncomingURL while app is still .inactive.
            // AVAudioEngine.start() fails with AUIOClient_StartIO error from non-active state.
            // Deferring to didBecomeActive guarantees the app is fully active.
            //
            // WHY the flag can override it (#311): `allowInactiveStart` is set only by
            // the background-transition path, where `.active` is no longer coming. A
            // second defer there would re-park the request with nothing left to unpark
            // it, which is the bug this whole change is about.
            if appState != .active && !allowInactiveStart {
                pendingColdStartDictation = true
                PersistentLog.log(.dictationDeferred(
                    reason: "cold start deferred to didBecomeActive, appState=\(appState.rawValue)"))
                return
            }

            dictationTask = Task {
                // Backstop for the background assertion a last-chance start holds
                // (#311). The two outcomes release it themselves, each at the earliest
                // moment it is safe to; this catches the exits that are neither -- a
                // permission denial, and the `mayReport` guards that drop an abandoned
                // session. A no-op when no assertion is held, which is every other call.
                defer { self.endColdStartAssertion(reason: "task-exit") }
                do {
                    let hasPermission = try await audioEngine.ensureMicrophonePermission()
                    guard hasPermission else {
                        guard mayReport(session, "permission denial") else { return }
                        handleError("Microphone permission denied", disposition: .requiresApp)
                        return
                    }
                    guard mayReport(session, "cold start") else { return }
                    try audioEngine.startRecording()
                    updateStatus(.recording)
                    LiveActivityManager.shared.transitionToRecording()
                    PersistentLog.log(.audioEngineStarted)
                    // The engine is capturing, so `UIBackgroundModes: audio` keeps the
                    // process alive on its own now. Released here rather than at the end
                    // of the task so the model load below, which can run for tens of
                    // seconds, does not sit on an assertion it no longer needs.
                    endColdStartAssertion(reason: "engine-started")
                    schedulePolishPrewarm()
                    await verifyAudioFlow()

                    // Load the transcription model in parallel while recording
                    self.setModelLoadState(.loading, reason: "cold-start-load")
                    try await ensureEngineReady(preferredModel: currentLanguagePolicy.modelIdentifier)
                    let loadedName = self.currentModelName ?? "unknown"
                    PersistentLog.log(.appWhisperKitLoaded(modelName: loadedName))
                    self.setModelLoadState(.ready, reason: "cold-start-success")
                } catch {
                    PersistentLog.log(.dictationFailed(error: "Cold start engine load: \(error.localizedDescription)"))
                    // A last-chance start (#311) fails for a reason the user can do
                    // nothing about and cannot read: the #73 AUIOClient_StartIO failure
                    // reaches `localizedDescription` as a bare CoreAudio error number.
                    // The raw text stays in the log line above, where it belongs; the
                    // keyboard banner gets the one action that works.
                    let message = allowInactiveStart
                        ? self.strandedColdStartMessage
                        : error.localizedDescription
                    // The model load runs inside this task and takes seconds on a
                    // cold start, so this is the widest window in the app for a
                    // cancel to arrive mid-flight. `setModelLoadState` stays ungated
                    // on purpose: it describes the model, which outlives any one
                    // dictation, and the next session needs it to be accurate.
                    self.setModelLoadState(.idle, reason: "cold-start-failed")
                    self.recordModelLoadFailure(error, context: "cold-start-load")
                    guard self.mayReport(session, "cold start failure") else { return }
                    self.handleError(message)
                    // The keyboard has been told. Released here so the assertion ends on
                    // a reported failure exactly as it does on a started engine.
                    self.endColdStartAssertion(reason: "failure-reported")
                }
            }
        }
    }

    /// Preserve a pending keyboard request's transport identity, or create an app-only
    /// identity, and capture language policy before asynchronous preparation starts.
    private func captureLanguageRequest() {
        let loaded = DictationLanguageRequest.load(from: defaults)
        let mode = loaded.modeForNextDictation(defaultingTo: TranscriptionLanguageMode.active)
        let outputMode = TranscriptionOutputMode.active
        let isKeyboardRequest = loaded.isBound
            && defaults.string(forKey: SharedKeys.dictationStatus) == DictationStatus.requested.rawValue
        let request = isKeyboardRequest ? loaded : loaded.unbound().bound(
            sessionID: UUID().uuidString,
            generation: sessions.current,
            clientIdentifier: "app-\(UUID().uuidString)"
        )
        let requestedModelIdentifier = DictationModelPreferences.requestedModel(for: request, in: defaults)
        let spokenLanguages = SpokenLanguagePreferences.load(from: defaults)
        let modelIdentifier = resolveRuntimeModelIdentifier(requestedModelIdentifier, languages: spokenLanguages)
        let capability = ASRCapability.forModelIdentifier(
            modelIdentifier, mode: mode, keyboardLanguage: SupportedLanguage.active, outputMode: outputMode)
        currentLanguageRequest = request.withResolvedSourceLanguage(capability.sourceLanguage)
        if !loaded.hasSameIdentity(as: request) { DictationDelivery.clear(in: defaults) }
        currentLanguagePolicy = TranscriptionLanguagePolicy(
            mode: mode, keyboardLanguage: SupportedLanguage.active,
            engine: ModelInfo.forIdentifier(modelIdentifier)?.engine ?? .whisperKit,
            modelIdentifier: modelIdentifier,
            outputMode: outputMode,
            spokenLanguages: spokenLanguages
        )
        if #available(iOS 26.0, *) { refreshTranslationReadiness(for: currentLanguageRequest) }
    }

    /// Tell the keyboard that a parked cold start will not run.
    ///
    /// WHY `handleError` and not a bespoke channel: the keyboard's status message is an
    /// in-process property of `KeyboardState`; nothing the app writes reaches it directly.
    /// `DictationErrorChannel` plus a `.failed` status is the app's actual channel —
    /// `KeyboardState.refreshFromDefaults` picks the error up and shows it for three
    /// seconds, and `.failed` does not own the keyboard area, so the "Démarrage…"
    /// overlay drops on the same write. The keyboard clears its own toolbar line when
    /// the three seconds are up; the stored reason stays until the next dictation (#320).
    ///
    /// The wording asks for a second tap rather than explaining the race: by the time
    /// this is read the user is in their host app looking at a stuck keyboard, and what
    /// they need is the one action that works.
    func reportStrandedColdStart() {
        PersistentLog.log(.dictationFailed(error: "cold start stranded: app left the foreground before it could run"))
        handleError(strandedColdStartMessage)
    }

    /// What the keyboard says when a cold start could not run. Shared by the two ways
    /// that happens — no attempt was possible, or the attempt threw — because from the
    /// user's side they are the same event and deserve the same sentence.
    private var strandedColdStartMessage: String {
        String(localized: "Dictation could not start. Tap the microphone again.")
    }

    /// Called when user taps the stop button.
    /// Stops recording and starts transcription using the already-loaded model.
    ///
    /// Capture ends before transcription. Only an explicitly enabled keyboard
    /// session retains audio readiness for the next hold.

    /// Minimum audio duration required for transcription (in seconds).
    /// WHY 0.5s: WhisperKit handles clips ≥0.5s reliably for short words (oui, non, ok).
    /// Below 0.5s, it tends to hallucinate (invent words not spoken).
    /// Previous value was 1.0s (Parakeet requirement), but Parakeet is no longer used
    /// in the dictation pipeline — only WhisperKit via keyboard.
    private let minimumRecordingDuration: TimeInterval = 0.5

    func stopDictation() {
        switch DictationStopAction.resolve(status: status, isRecording: audioEngine.isRecording,
                                           isTranscribingInFlight: isTranscribingInFlight) {
        case .cancel:
            cancelDictation()
            return
        case .ignore:
            return
        case .transcribe:
            break
        }
        // Claim finalization before capture drains or a UI task is scheduled.
        isTranscribingInFlight = true

        dictationTask?.cancel()
        // The recording is ending; the prewarm (if it hasn't fired) is moot.
        polishPrewarmTask?.cancel()

        // Hold the process after capture ends so Whisper and polish can finish
        // while the user is looking at another app's keyboard.
        beginTranscriptionAssertion()

        // The session this run belongs to. Every write it makes below is gated on
        // still being that session (#267) -- see `mayReport`.
        let session = sessions.current
        let capturedLanguageRequest = currentLanguageRequest
        let capturedModelIdentifier = currentLanguagePolicy.modelIdentifier
        let cleanupSettings = PolishCoordinator.shared.snapshotSettings()

        var runtimeMetrics = DictationRuntimeMetrics(sessionID: capturedLanguageRequest.sessionID ?? "unbound")
        // Capture ends at Stop, not when a scheduled UI task eventually runs.
        let samples = collectCompletedRecording()
        runtimeMetrics.mark("sampleDrain")
        runtimeMetrics.setContext("cleanupEngine", value: cleanupSettings.engine.identifier)
        runtimeMetrics.setContext("style", value: cleanupSettings.style.rawValue)
        runtimeMetrics.setContext("thermal", value: String(ProcessInfo.processInfo.thermalState.rawValue))
        runtimeMetrics.setContext("os", value: UIDevice.current.systemVersion)
        runtimeMetrics.setContext("asrResident", value: transcriptionService.hasLoadedModel ? "1" : "0")

        dictationTask = Task {
            var published = false
            defer {
                if !published {
                    runtimeMetrics.mark("finished")
                    runtimeMetrics.log(outcome: Task.isCancelled ? "cancelled" : "failed")
                }
                // A cancelled task can finish after its successor has started.
                // It must not release that successor's lock or background time.
                if self.sessions.mayReport(from: session) {
                    self.isTranscribingInFlight = false
                    self.endTranscriptionAssertion(reason: "task-exit")
                    self.applyDeferredModelChanges()
                }
            }
            do {
                guard !samples.isEmpty else {
                    guard mayReport(session, "empty recording") else { return }
                    handleError("No audio recorded")
                    return
                }

                let audioDuration = Double(samples.count) / 16000.0

                guard audioDuration >= minimumRecordingDuration else {
                    PersistentLog.log(.recordingTooShort(durationMs: Int(audioDuration * 1000)))
                    guard mayReport(session, "short recording") else { return }
                    handleError("Recording too short")
                    return
                }

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Recording stopped. Samples: \(samples.count, privacy: .public), Duration: \(String(format: "%.1f", audioDuration), privacy: .public)s")
                }

                updateStatus(.transcribing)
                LiveActivityManager.shared.transitionToTranscribing()
                // Arm watchdog: if DI fails to leave .recording, force recovery after 10s.
                // If transitionToTranscribing succeeded, the watchdog's guard exits harmlessly.
                LiveActivityManager.shared.startRecordingWatchdog()

                try await ensureEngineReady(preferredModel: capturedModelIdentifier)
                guard mayReport(session, "frozen model ready") else { return }
                runtimeMetrics.mark("modelReady")

                // One language-policy snapshot per dictation (#226): mode,
                // keyboard language, engine, and model are captured HERE and
                // propagated through STT, polish, and finalization. Without
                // the snapshot, each stage would re-read App Group state and a
                // keyboard-toolbar language change while transcription runs
                // could make Whisper transcribe in one language and polish in
                // another.
                let languagePolicy = currentLanguagePolicy
                runtimeMetrics.setContext("asrModel", value: languagePolicy.modelIdentifier)
                issueRecordingDurationMs = Int(audioDuration * 1000)

                let transcribeStarted = DispatchTime.now().uptimeNanoseconds
                let transcriptionOutput = try await DictationVocabulary.$currentHints.withValue(cleanupSettings.vocabulary) {
                    try await transcriptionService.transcribeDetailed(audioSamples: samples, languagePolicy: languagePolicy)
                }
                try Task.checkCancellation()
                guard mayReport(session, "recognition complete") else { return }
                issueTranscribeMs = DictationRuntimeMetrics.elapsedMilliseconds(since: transcribeStarted)
                runtimeMetrics.mark("asrAndMerge")
                for (index, region) in transcriptionOutput.regions.enumerated() {
                    if let duration = region.decodeDurationSeconds {
                        runtimeMetrics.setContext("region\(index)DecodeMs", value: String(format: "%.2f", duration * 1000))
                    }
                }
                let rawText = transcriptionOutput.text
                guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    handleError("No speech detected")
                    return
                }
                if let unexpected = SpokenLanguagePreferences.unexpectedLanguage(in: rawText, languages: languagePolicy.spokenLanguages) {
                    lastOriginalResult = rawText
                    issueRawText = rawText
                    handleError(TranscriptionError.unexpectedLanguage(unexpected).localizedDescription)
                    return
                }
                // Translate before cleanup so the language-agnostic Auto cleanup
                // operates on the selected output language.
                let translation = await processAuthoritativeFinalTranscript(
                    rawText,
                    request: capturedLanguageRequest,
                    regions: transcriptionOutput.regions,
                    generation: session
                )
                try Task.checkCancellation()
                guard mayReport(session, "translation complete") else { return }
                let translatedRawText = translation.resolvedText
                let effectiveTarget = translation.fallbackReason == nil ? capturedLanguageRequest.translationTarget : nil
                lastTranslationFallbackReason = translation.fallbackReason
                runtimeMetrics.setContext("translationOutcome", value: capturedLanguageRequest.translationTarget == nil
                    ? "notRequested" : translation.fallbackReason.map { "originalKept:\($0.rawValue)" } ?? "accepted")
                runtimeMetrics.mark("translation")

                // Polish layer (#141) — passes raw through only when the toggle is
                // off; otherwise it applies the model or deterministic cleanup floor.
                //
                // The status moves to `.processing` from inside the call rather than
                // before it (#267): every one of those pass-through paths returns in
                // about a millisecond, and announcing a stage for them would flash a
                // label and a new animation for a single frame. `onEngineWillRun`
                // fires only once an engine worth waiting for is about to run.
                let polishStarted = DispatchTime.now().uptimeNanoseconds
                var cleaned = translation.fallbackReason != nil ? translatedRawText : await CleanupPipeline.clean(
                    raw: translatedRawText,
                    languagePolicy: languagePolicy,
                    recordingDuration: audioDuration,
                    translationTarget: effectiveTarget,
                    regions: effectiveTarget == nil
                        ? transcriptionOutput.regions
                        : [],
                    settings: cleanupSettings,
                    // Gated like every other write this task makes: the callback
                    // fires from inside `polish`, which a cancel does not interrupt,
                    // so an abandoned dictation would otherwise reopen the keyboard
                    // overlay on "Traitement..." and drive the Live Activity into a
                    // stage it had already left (#267).
                    onEngineWillRun: { [weak self] in
                        guard let self, self.mayReport(session, "processing stage") else { return }
                        self.updateStatus(.processing)
                        LiveActivityManager.shared.transitionToProcessing()
                    }
                )
                try Task.checkCancellation()
                guard mayReport(session, "cleanup complete") else { return }
                if effectiveTarget == nil,
                   SpokenLanguagePreferences.unexpectedLanguage(in: cleaned, languages: languagePolicy.spokenLanguages) != nil {
                    cleaned = translatedRawText
                }
                issuePolishMs = DictationRuntimeMetrics.elapsedMilliseconds(since: polishStarted)
                runtimeMetrics.mark("cleanup")
                issueRawText = translatedRawText
                // Grammar floor after cleanup/translation. Idempotent, strips ASR
                // event labels, and is the text the keyboard later offers
                // next-word predictions from. Multilingual output skips
                // per-language filler/punctuation rules so mixed speech stays intact.
                let assembled = TranscriptionPipeline.assemble(
                    cleaned: cleaned,
                    grammarLanguage: languagePolicy.grammarFloorLanguage(
                        translationTarget: effectiveTarget
                    ),
                    insertAsIs: translation.fallbackReason != nil || (languagePolicy.insertsTranscriptionAsIs
                        && effectiveTarget == nil),
                    preserveOriginal: translation.fallbackReason != nil
                )
                let text = assembled.body
                let formattedText = assembled.formatted
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    guard mayReport(session, "empty final result") else { return }
                    handleError("No speech detected")
                    return
                }

                let decision = DictationFinalizationDecision.make(
                    transcript: text,
                    outcome: translation.replacingText(formattedText),
                    request: capturedLanguageRequest,
                    currentRequest: currentLanguageRequest
                )

                // The gate that matters most. Everything below is irreversible from
                // the user's point of view: it writes the transcription to the App
                // Group and posts `transcriptionReady`, which is what makes the
                // keyboard type it into their document. A dictation the user
                // cancelled must not insert text a few seconds later (#267).
                guard mayReport(session, "transcription result"),
                      decision.shouldPublish,
                      let finalText = decision.finalText else { return }

                // Write result to App Group
                lastResult = finalText
                lastOriginalResult = rawText
                status = .ready
                runtimeMetrics.mark("published")
                runtimeMetrics.log(outcome: "published")
                DictationDeliveryStore.publishReady(
                    text: finalText,
                    request: capturedLanguageRequest,
                    to: defaults,
                    timings: runtimeMetrics,
                    originalText: rawText
                )
                published = true

                DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
                DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
                LiveActivityManager.shared.endWithResult()
                // This one-slot snapshot also supports explicit raw recovery;
                // its report export separately requires Include transcript text.
                let keepTranscript = defaults.object(forKey: SharedKeys.historyEnabled) as? Bool ?? true
                persistLastDictationIssue(
                    stage: DictationStatus.ready.rawValue,
                    rawText: keepTranscript ? translatedRawText : nil,
                    cleanedText: keepTranscript ? finalText : nil
                )

                if #available(iOS 14.0, *) {
                    DictusLogger.app.info("Transcription complete: \(finalText, privacy: .private)")
                }

                cleanupRecordingKeys()
            } catch {
                guard mayReport(session, "transcription failure") else { return }
                if #available(iOS 14.0, *) {
                    DictusLogger.app.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
                }
                if error is SpeechModelError {
                    recordModelLoadFailure(error, context: "transcription-load")
                }
                // A cancelled task lands here, and so does one that failed for its
                // own reasons after the session ended. Either way the failure
                // belongs to a dictation that is over: writing `.failed` re-presents
                // the recording screen the user just dismissed (#267).
                handleError(error.localizedDescription)
            }
        }
    }

    func processAuthoritativeFinalTranscript(
        _ transcript: String,
        request: DictationLanguageRequest,
        regions: [SpeechRegionTranscript] = [],
        generation: Int? = nil
    ) async -> TranslationOutcome {
        guard let target = request.translationTarget, !transcript.isEmpty else { return .original(transcript) }
        guard sessions.mayReport(
            from: generation ?? sessions.current,
            request: request, currentRequest: currentLanguageRequest
        ) else {
            return .fallback(transcript, reason: .cancelled)
        }

#if canImport(Translation)
        if #available(iOS 26.0, *) {
            let hint = regions.count == 1 ? regions.first?.validatedLanguage : nil
            let spans = PolishSpanDetector.translationSpans(in: transcript, sourceHint: hint)
            let deadline = PolishDeadline()
            var outcomes: [TranslationOutcome] = []
            for span in spans {
                guard !Task.isCancelled, sessions.mayReport(from: generation ?? sessions.current,
                    request: request, currentRequest: currentLanguageRequest) else {
                    return .fallback(transcript, reason: .cancelled)
                }
                guard deadline.instant > .now else { return .fallback(transcript, reason: .unavailable) }
                let text = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { outcomes.append(.original(span.text)); continue }
                let outcome = await translationOutcome(text, target: target, sourceHint: span.languageCode,
                    request: request, generation: generation ?? sessions.current, deadline: deadline)
                guard outcome.fallbackReason == nil else { return .fallback(transcript, reason: outcome.fallbackReason ?? .rejectedOutput) }
                let leading = String(span.text.prefix(while: \.isWhitespace))
                let trailing = String(span.text.reversed().prefix(while: \.isWhitespace).reversed())
                outcomes.append(outcome.replacingText(leading + outcome.resolvedText + trailing))
            }
            guard !Task.isCancelled, sessions.mayReport(from: generation ?? sessions.current,
                request: request, currentRequest: currentLanguageRequest) else {
                return .fallback(transcript, reason: .cancelled)
            }
            guard deadline.instant > .now else { return .fallback(transcript, reason: .unavailable) }
            return TranslationOutcome.combined(original: transcript, clauses: spans.map(\.text), outcomes: outcomes, target: target)
        }
#endif
        return .fallback(transcript, reason: .unavailable)
    }

#if canImport(Translation)
    @available(iOS 26.0, *)
    private func refreshTranslationReadiness(for request: DictationLanguageRequest? = nil) {
        let request = request ?? DictationLanguageRequest(
            mode: TranscriptionLanguageMode.active,
            translationTarget: nil
        )
        translationReadinessGeneration += 1
        let refreshGeneration = translationReadinessGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            let capability = ASRCapability.forModelIdentifier(
                self.defaults.string(forKey: SharedKeys.activeModel),
                mode: request.mode,
                keyboardLanguage: SupportedLanguage.active,
                outputMode: TranscriptionOutputMode.active
            )
            if capability.sourceLanguage == nil {
                guard refreshGeneration == self.translationReadinessGeneration else { return }
                TranslationTargetReadiness(source: "auto", installedTargets: [],
                    supportedTargets: Set(TranslationLanguage.allCases.map(\.rawValue))).persist(to: self.defaults)
                return
            }
            let sourceCodes: [String] = capability.sourceLanguage.map { [$0.rawValue] }
                ?? []
            let availability = LanguageAvailability()
            var installedTargets = Set<String>()
            var supportedTargets = Set<String>()

            for sourceCode in sourceCodes {
                let sourceLocale = Locale.Language(identifier: sourceCode)
                for target in TranslationLanguage.allCases
                    where !languageCodesEquivalent(sourceCode, target.translationIdentifier) {
                    let status = await availability.status(
                        from: sourceLocale,
                        to: target.localeLanguage
                    )
                    switch status {
                    case .installed:
                        installedTargets.insert(target.rawValue)
                        supportedTargets.insert(target.rawValue)
                    case .supported:
                        supportedTargets.insert(target.rawValue)
                    case .unsupported:
                        break
                    }
                }
            }

            // A later refresh may have observed a different request or model while
            // this one was awaiting LanguageAvailability. Never publish this result.
            guard refreshGeneration == self.translationReadinessGeneration else { return }

            TranslationTargetReadiness(
                source: capability.sourceLanguage?.rawValue ?? "auto",
                installedTargets: installedTargets,
                supportedTargets: supportedTargets
            ).persist(to: self.defaults)
        }
    }

    @available(iOS 26.0, *)
    private func translationOutcome(
        _ transcript: String,
        target: TranslationLanguage,
        sourceHint: String? = nil,
        request: DictationLanguageRequest,
        generation: Int,
        deadline: PolishDeadline
    ) async -> TranslationOutcome {
        guard !Task.isCancelled, sessions.mayReport(
            from: generation, request: request, currentRequest: currentLanguageRequest
        ) else {
            return .fallback(transcript, reason: .cancelled)
        }

        guard deadline.instant > .now else { return .fallback(transcript, reason: .unavailable) }

        let source = SpeechLanguageEvidence.sourceLanguage(in: transcript, hint: sourceHint ?? translationSource(for: request))
        if target.alreadyContains(transcript, sourceHint: source) {
            return TranslationOutcome.resolved(original: transcript, translated: transcript,
                clientIdentifierMatches: true, target: target, source: source)
        }
        if target == .chineseSimplified, SpeechLanguageEvidence.baseCode(source) == "zh",
           let simplified = transcript.applyingTransform(StringTransform(rawValue: "Hant-Hans"), reverse: false) {
            return TranslationOutcome.resolved(original: transcript, translated: simplified,
                clientIdentifierMatches: true, target: target, source: source)
        }
        let targetLocale = target.localeLanguage
        let availability = LanguageAvailability()
        let status: LanguageAvailability.Status

        do {
            if let source {
                status = await availability.status(
                    from: Locale.Language(identifier: source),
                    to: targetLocale
                )
            } else {
                status = try await availability.status(for: transcript, to: targetLocale)
            }
        } catch {
            return .fallback(transcript, reason: Task.isCancelled ? .cancelled : .unavailable)
        }

        guard !Task.isCancelled, sessions.mayReport(
            from: generation, request: request, currentRequest: currentLanguageRequest
        ) else {
            return .fallback(transcript, reason: .cancelled)
        }
        guard deadline.instant > .now, status != .unsupported else {
            return .fallback(transcript, reason: .unavailable)
        }

        if let source, status == .installed {
            let installed = await translateWithInstalledSource(
                transcript,
                source: source,
                target: target,
                request: request,
                generation: generation,
                deadline: deadline
            )
            if case .translated = installed {
                return installed
            }
        }

        return await translateWithHostLimited(
            transcript,
            source: source,
            target: target,
            request: request,
            generation: generation,
            deadline: deadline
        )
    }

    private func languageCodesEquivalent(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    @available(iOS 26.0, *)
    private func translateWithHostLimited(
        _ transcript: String,
        source: String?,
        target: TranslationLanguage,
        request: DictationLanguageRequest,
        generation: Int,
        deadline: PolishDeadline
    ) async -> TranslationOutcome {
        guard !Task.isCancelled, sessions.mayReport(from: generation, request: request,
            currentRequest: currentLanguageRequest) else { return .fallback(transcript, reason: .cancelled) }
        guard deadline.instant > .now else { return .fallback(transcript, reason: .unavailable) }
        let id = UUID()
        return await withTaskGroup(of: TranslationOutcome.self) { group in
            group.addTask { @MainActor in
                await self.translateWithHost(
                    transcript,
                    source: source,
                    target: target,
                    request: request,
                    generation: generation,
                    id: id
                )
            }
            group.addTask {
                try? await ContinuousClock().sleep(until: deadline.instant)
                return .fallback(transcript, reason: .unavailable)
            }
            let first = await group.next() ?? .fallback(transcript, reason: .unavailable)
            group.cancelAll()
            if case .fallbackOriginal(_, .unavailable) = first {
                await MainActor.run {
                    self.cancelPendingTranslation(id: id)
                }
            }
            return first
        }
    }

    @available(iOS 26.0, *)
    private func translationSource(for request: DictationLanguageRequest) -> String? {
        switch request.mode {
        case .autoDetect:
            return nil
        case .explicit(let language):
            return language.rawValue
        case .followKeyboard:
            return request.resolvedSourceLanguage?.rawValue
        }
    }

    @available(iOS 26.0, *)
    private func translateWithInstalledSource(
        _ transcript: String,
        source: String,
        target: TranslationLanguage,
        request: DictationLanguageRequest,
        generation: Int,
        deadline: PolishDeadline
    ) async -> TranslationOutcome {
        guard !Task.isCancelled, sessions.mayReport(
            from: generation, request: request, currentRequest: currentLanguageRequest
        ) else {
            return .fallback(transcript, reason: .cancelled)
        }
        guard deadline.instant > .now else { return .fallback(transcript, reason: .unavailable) }
        let clientIdentifier = request.clientIdentifier ?? UUID().uuidString
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: source),
            target: target.localeLanguage
        )
        let timeout = Task { @MainActor in
            do {
                try await ContinuousClock().sleep(until: deadline.instant)
                session.cancel()
            } catch { /* The call finished or was cancelled. */ }
        }
        defer { timeout.cancel() }
        do {
            let responses = try await withTaskCancellationHandler {
                try await session.translations(from: [
                    TranslationSession.Request(sourceText: transcript, clientIdentifier: clientIdentifier)
                ])
            } onCancel: {
                Task { @MainActor in session.cancel() }
            }
            let response = responses.first
            guard !Task.isCancelled, sessions.mayReport(from: generation, request: request,
                currentRequest: currentLanguageRequest) else { return .fallback(transcript, reason: .cancelled) }
            guard deadline.instant > .now else { return .fallback(transcript, reason: .unavailable) }
            return TranslationOutcome.resolved(
                original: transcript,
                translated: response?.targetText,
                clientIdentifierMatches: response?.clientIdentifier == clientIdentifier,
                target: target, source: source
            )
        } catch {
            return .fallback(transcript, reason: Task.isCancelled ? .cancelled : .unavailable)
        }
    }

    @available(iOS 26.0, *)
    private func translateWithHost(
        _ transcript: String,
        source: String?,
        target: TranslationLanguage,
        request: DictationLanguageRequest,
        generation: Int,
        id: UUID
    ) async -> TranslationOutcome {
        guard !Task.isCancelled, sessions.mayReport(from: generation, request: request,
            currentRequest: currentLanguageRequest) else {
            return .fallback(transcript, reason: .cancelled)
        }

        let clientIdentifier = request.clientIdentifier ?? UUID().uuidString
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<TranslationOutcome, Never>) in
                cancelPendingTranslation()
                var configuration = TranslationSession.Configuration(
                    source: source.map { Locale.Language(identifier: $0) },
                    target: target.localeLanguage
                )
                pendingTranslation = PendingTranslation(
                    id: id,
                    sessionID: currentLanguageRequest.sessionID ?? "",
                    generation: generation,
                    requestGeneration: request.generation ?? generation,
                    sourceText: transcript,
                    source: source,
                    target: target,
                    clientIdentifier: clientIdentifier,
                    originalText: transcript,
                    continuation: continuation
                )
                configuration.invalidate()
                translationConfiguration = configuration
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelPendingTranslation(id: id)
            }
        })
    }

    @available(iOS 26.0, *)
    func consumeTranslationSession(_ session: TranslationSession) async {
        guard let pending = pendingTranslation else { return }
        let id = pending.id
        activeTranslationSession = session

        guard pending.generation == sessions.current else {
            finishTranslation(id: id, outcome: .fallback(pending.originalText, reason: .cancelled))
            return
        }

        do {
            let availability = LanguageAvailability()
            let status: LanguageAvailability.Status
            if let source = pending.source {
                status = await availability.status(
                    from: Locale.Language(identifier: source),
                    to: pending.target.localeLanguage
                )
            } else {
                status = try await availability.status(
                    for: pending.sourceText,
                    to: pending.target.localeLanguage
                )
            }
            guard status == .supported || status == .installed else {
                finishTranslation(id: id, outcome: .fallback(pending.originalText, reason: .unavailable))
                return
            }
            guard pendingTranslation?.id == id,
                  pending.generation == sessions.current,
                  currentLanguageRequest.matches(
                      sessionID: pending.sessionID,
                      generation: pending.requestGeneration,
                      clientIdentifier: pending.clientIdentifier
                  ) else {
                finishTranslation(id: id, outcome: .fallback(pending.originalText, reason: .cancelled))
                return
            }
            try await session.prepareTranslation()
            guard pendingTranslation?.id == id,
                  currentLanguageRequest.matches(
                      sessionID: pending.sessionID,
                      generation: pending.requestGeneration,
                      clientIdentifier: pending.clientIdentifier
                  ),
                  pending.generation == sessions.current else {
                finishTranslation(id: id, outcome: .fallback(pending.originalText, reason: .cancelled))
                return
            }
            let responses = try await session.translations(from: [
                TranslationSession.Request(
                    sourceText: pending.sourceText,
                    clientIdentifier: pending.clientIdentifier
                )
            ])
            guard pendingTranslation?.id == id,
                  currentLanguageRequest.matches(
                      sessionID: pending.sessionID,
                      generation: pending.requestGeneration,
                      clientIdentifier: pending.clientIdentifier
                  ),
                  pending.generation == sessions.current else {
                finishTranslation(id: id, outcome: .fallback(pending.originalText, reason: .cancelled))
                return
            }
            let response = responses.first
            let matches = response?.clientIdentifier == pending.clientIdentifier
            finishTranslation(
                id: id,
                outcome: TranslationOutcome.resolved(
                    original: pending.originalText,
                    translated: response?.targetText,
                    clientIdentifierMatches: matches,
                    target: pending.target, source: pending.source
                )
            )
        } catch {
            finishTranslation(
                id: id,
                outcome: .fallback(pending.originalText, reason: .unavailable)
            )
        }
    }

    @available(iOS 26.0, *)
    private func finishTranslation(id: UUID, outcome: TranslationOutcome) {
        guard let pending = pendingTranslation, pending.id == id else { return }
        pendingTranslation = nil
        activeTranslationSession = nil
        translationConfiguration = nil
        pending.continuation.resume(returning: outcome)
    }

    @available(iOS 26.0, *)
    private func cancelPendingTranslation(id: UUID? = nil) {
        if let id, pendingTranslation?.id != id { return }
        guard let pending = pendingTranslation else { return }
        (activeTranslationSession as? TranslationSession)?.cancel()
        activeTranslationSession = nil
        pendingTranslation = nil
        translationConfiguration = nil
        pending.continuation.resume(
            returning: .fallback(pending.originalText, reason: .cancelled)
        )
    }
#endif

    /// Cancel the current dictation without transcribing.
    /// Called when the keyboard sends a cancel signal via Darwin notification.
    func cancelDictation() {
        initTask?.cancel()
        transcriptionService.cancelCurrentInference()
        pendingColdStartDictation = false
        DictationDelivery.clear(in: defaults)
        DictationLanguageRequest.load(from: defaults).unbound().persist(to: defaults)
        // FIRST, before anything is cancelled: from here on, the transcription task
        // is working for a session that no longer exists and may not report (#267).
        // `Task.cancel()` below is only a request -- neither WhisperKit nor Apple FM
        // promises to return promptly -- so the task can still finish seconds from
        // now, and this is what makes its outcome land nowhere.
        sessions.abandonSession()
#if canImport(Translation)
        if #available(iOS 26.0, *) {
            cancelPendingTranslation()
        }
#endif
        PolishCoordinator.shared.cancelInflight()
        dictationTask?.cancel()
        dictationTask = nil
        // Reset the transcribe re-entry flag so the next stop/cancel cycle can proceed.
        isTranscribingInFlight = false
        endTranscriptionAssertion(reason: "cancelled")
        stopStageWatchdog()

        // Discard this recording. Explicit keyboard sessions retain readiness;
        // service disable clears that opt-in before reaching this method.
        _ = collectCompletedRecording()

        // Reset all state
        bufferEnergy = []
        bufferSeconds = 0
        cleanupRecordingKeys()
        // Return Dynamic Island to standby (cancel = no transcription, go back to "On")
        Task { await LiveActivityManager.shared.returnToStandby() }
        // `returnToStandby` only comes back from .recording/.ready/.failed, and the
        // recording watchdog below only unsticks .recording -- so a dictation
        // abandoned inside a post-recording stage had no path home at all, and the
        // pill stayed on that stage and rejected the next dictation (#267 review).
        // The two calls are mutually exclusive by their own guards, so the order
        // between them does not matter.
        LiveActivityManager.shared.recoverFromAbandonedStage()
        // Arm watchdog: safety net if returnToStandby's guard rejects.
        LiveActivityManager.shared.startRecordingWatchdog()
        updateStatus(.idle)

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Dictation cancelled by keyboard")
        }
    }

    // MARK: - Transcription background assertion

    func beginTranscriptionAssertion() {
        guard transcriptionAssertion == .invalid else { return }
        transcriptionAssertion = UIApplication.shared.beginBackgroundTask(
            withName: "dictus.transcription"
        ) { [weak self] in
            self?.handleTranscriptionAssertionExpiryFromAnyThread()
        }
    }

    func endTranscriptionAssertion(reason: String) {
        guard transcriptionAssertion != .invalid else { return }
        PersistentLog.log(.diagnosticProbe(
            component: "transcription", instanceID: "0",
            action: "assertionEnded",
            details: "reason=\(reason)"
        ))
        PersistentLog.flush()
        UIApplication.shared.endBackgroundTask(transcriptionAssertion)
        transcriptionAssertion = .invalid
    }

    nonisolated func handleTranscriptionAssertionExpiryFromAnyThread() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { self.handleTranscriptionAssertionExpiry() }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { self.handleTranscriptionAssertionExpiry() }
            }
        }
    }

    func handleTranscriptionAssertionExpiry() {
        guard transcriptionAssertion != .invalid else { return }
        PersistentLog.log(.diagnosticProbe(
            component: "transcription", instanceID: "0",
            action: "assertionExpired",
            details: "status=\(status.rawValue)"
        ))
        endTranscriptionAssertion(reason: "expired")
    }

    /// Reset status to idle (e.g., after user returns to keyboard).
    ///
    /// Issue #60: a UI-only reset while the pipeline is active orphans the audio
    /// engine (keeps capturing) and the Live Activity (stuck on REC), so an active
    /// session must go through the real teardown instead.
    ///
    /// WHY the shared predicate and not a list of cases spelled out here (#267):
    /// this asks "is a dictation in flight", which is the exact question
    /// `isActive` answers over an exhaustive switch. A hand-written list is a list
    /// the next status case can be left out of, silently, and this one guards a
    /// teardown -- the same shape of omission #260 and #261 were made of.
    func resetStatus() {
        if DictationSessionLivenessPolicy.isActive(status) {
            cancelDictation()
            return
        }
        updateStatus(.idle)
        // Keep lastResult so HomeView can display the last transcription card.
    }

    /// Handle an audio session interruption that fired while dictation was active.
    ///
    /// UnifiedAudioEngine has already stopped the engine and posted the in-process
    /// notification. We only need to clean up the dictation pipeline: cancel the
    /// in-flight task, drop accumulated samples, write a "failed" status to App
    /// Group so the keyboard's overlay closes, and notify the user via the Live
    /// Activity (LiveActivityManager handles its own end via the same notification).
    /// Issue #106.
    private func handleAudioInterruptionDuringDictation() {
        // Only capture depends on the audio session. A pending start handles
        // activation errors itself; transcription/cleanup already own their audio.
        guard status == .recording, !pendingColdStartDictation else {
            return
        }

        // Same reasoning as `cancelDictation`: this teardown ends the session, so
        // the task must not report into it afterwards (#267). The `.failed` written
        // below is this handler speaking, not the task, and is not gated.
        sessions.abandonSession()
#if canImport(Translation)
        if #available(iOS 26.0, *) {
            cancelPendingTranslation()
        }
#endif
        dictationTask?.cancel()
        dictationTask = nil
        isTranscribingInFlight = false
        stopStageWatchdog()

        bufferEnergy = []
        bufferSeconds = 0
        cleanupRecordingKeys()
        audioEngine.deactivateIfIdle()

        // updateStatus(.failed) handles both the App Group write and the Darwin
        // statusChanged post — no manual duplication needed (issue #106 review).
        DictationErrorChannel.record(String(localized: "Recording interrupted. Please try again."))
        updateStatus(.failed)

        if #available(iOS 14.0, *) {
            DictusLogger.app.warning("Dictation cancelled by audio session interruption")
        }
    }

    // MARK: - Private Helpers

    /// Register Darwin notification observers for keyboard stop/cancel signals.
    private func observeKeyboardSignals() {
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.stopRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let requested = self.defaults.bool(forKey: SharedKeys.stopRequested)
                if requested {
                    self.defaults.set(false, forKey: SharedKeys.stopRequested)
                    self.defaults.synchronize()
                    self.stopDictation()
                }
            }
        }

        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.serviceToggleRequested) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("DictusServiceToggleRequested"),
                    object: nil
                )
            }
        }

        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.cancelRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let requested = self.defaults.bool(forKey: SharedKeys.cancelRequested)
                if requested {
                    self.defaults.set(false, forKey: SharedKeys.cancelRequested)
                    self.defaults.synchronize()
                    self.cancelDictation()
                }
            }
        }

        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.startRecording) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.defaults.string(forKey: SharedKeys.dictationStatus) == DictationStatus.requested.rawValue,
                      !self.defaults.bool(forKey: SharedKeys.cancelRequested) else { return }
                let appState = UIApplication.shared.applicationState
                PersistentLog.log(.engineDarwinStartReceived(
                    appState: "\(appState.rawValue)",
                    engineRunning: self.audioEngine.isEngineRunning
                ))
                self.startDictation()
            }
        }
    }

    /// Clear a dictation the previous process never finished (issue #261).
    ///
    /// The invariant this restores: `dictationStatus` describes an active dictation,
    /// but no live coordinator owns a session for it. That is trivially decidable
    /// here — this method runs from `init`, so the process has just started and owns
    /// no session by construction. Nothing else audited the key, which is why an app
    /// terminated mid-recording left `recording` behind for the keyboard to restore
    /// an overlay from.
    ///
    /// WHY `.requested` is excluded: the keyboard writes it moments before opening
    /// `dictus://dictate`, i.e. moments before launching this very process. Clearing
    /// it here would break every cold-start dictation — including the retry in
    /// `didBecomeActive`, which proceeds only while the stored status is still
    /// `requested`.
    ///
    /// WHY it writes `.idle` and no `lastError`: this audit is hygiene, not speech.
    /// The first version wrote `.failed` plus a localised error so the keyboard's
    /// failure path would show it, which had two problems. By the time the app
    /// relaunches the moment has passed — the keyboard reconciles in-process, within
    /// seconds, and that is the surface that tells the user. And `failed` has no
    /// expiry in the App Group: `KeyboardState.refreshFromDefaults` adopts a stored
    /// `failed` and shows the stored reason whenever the extension is next loaded,
    /// however old it is, until a new dictation clears it (#320). That is pre-existing
    /// behaviour, but writing `failed` here on every reconciliation would have made a
    /// stale error message a routine sight.
    ///
    /// WHY it does NOT go through `updateStatus`: this process is not failing
    /// anything. It is auditing state a dead one left behind, and `status` is
    /// correctly `.idle` here.
    private func reconcileOrphanedDictationState() {
        // WHY the cases are spelled out here and not asked of `isActive` (#267):
        // this list is deliberately narrower. `.requested` is active but is written
        // by the keyboard moments before it launches this app, so reconciling it at
        // launch would kill every cold-start dictation. `.processing` belongs with
        // `.recording` and `.transcribing`: the app that wrote it is the app that
        // just died, so a launch finding it is finding a corpse.
        guard let raw = defaults.string(forKey: SharedKeys.dictationStatus),
              let stored = DictationStatus(rawValue: raw),
              stored == .recording || stored == .transcribing || stored == .processing else { return }

        PersistentLog.log(.dictationStateReconciled(
            source: "app-launch",
            staleStatus: raw,
            heartbeatAgeMs: -1
        ))
        defaults.set(DictationStatus.idle.rawValue, forKey: SharedKeys.dictationStatus)
        // Clears the heartbeat, the waveform keys and the pending stop/cancel flags
        // the dead process never got to clean up, and synchronizes. Dropping the
        // heartbeat matters most: one that outlives its session is what the keyboard
        // would otherwise judge the *next* session by (#261).
        cleanupRecordingKeys()
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Clean up recording-related App Group keys after recording completes or is cancelled.
    private func cleanupRecordingKeys() {
        // NOTE: Do NOT clear lastTranscription here — the keyboard extension reads it
        // asynchronously via Darwin notification. Clearing it here would race with the
        // keyboard and delete the transcription before it can be inserted.
        // Stale transcriptions are cleaned up on app launch (5-min threshold in init).
        defaults.removeObject(forKey: SharedKeys.waveformEnergy)
        defaults.removeObject(forKey: SharedKeys.recordingElapsedSeconds)
        defaults.removeObject(forKey: SharedKeys.recordingHeartbeat)
        defaults.set(false, forKey: SharedKeys.stopRequested)
        defaults.set(false, forKey: SharedKeys.cancelRequested)
        defaults.set(false, forKey: SharedKeys.coldStartActive)
        defaults.removeObject(forKey: SharedKeys.sourceAppScheme)
        // Keep the request identity until the keyboard consumes DictationDelivery.
        // The Darwin notification can arrive after this cleanup runs, and unbinding
        // here makes a valid result look unrelated to the visible keyboard.
        defaults.synchronize()
    }

    /// Drop compiled speech-model objects under memory pressure while preserving
    /// the downloaded files and the user's selected model. Active work always wins.
    private func releaseLoadedModelIfSafe(reason: String) {
        guard !DictationSessionLivenessPolicy.isActive(status),
              !isTranscribingInFlight,
              initTask == nil else {
            PersistentLog.log(.diagnosticProbe(
                component: "DictationCoordinator",
                instanceID: "modelMemory",
                action: "releaseSkipped",
                details: "reason=\(reason) status=\(status.rawValue) transcribing=\(isTranscribingInFlight) initializing=\(initTask != nil)"
            ))
            return
        }
        guard transcriptionService.hasLoadedModel || whisperKit != nil || currentModelName != nil else { return }

        disableKeyboardSession()

        let task = Task<Void, Error> {
            defer { self.initTask = nil }
            await self.transcriptionService.releaseLoadedModelAndWait()
            self.whisperKit = nil
            self.currentModelName = nil
        }
        initTask = task
        setModelLoadState(.idle, reason: "model-released-\(reason)")
        PersistentLog.log(.diagnosticProbe(
            component: "DictationCoordinator",
            instanceID: "modelMemory",
            action: "released",
            details: "reason=\(reason)"
        ))
    }

    /// Reads the list of downloaded model identifiers from App Group UserDefaults.
    private func readDownloadedModels() -> [String] {
        guard let data = defaults.data(forKey: SharedKeys.downloadedModels),
              let models = try? JSONDecoder().decode([String].self, from: data) else {
            if let active = defaults.string(forKey: SharedKeys.activeModel) {
                return [active]
            }
            return []
        }
        return models
    }

    /// Whether the transcription task started under `session` may still report.
    ///
    /// A dictation that was abandoned -- cancelled, watchdog-reset, interrupted --
    /// moves the generation, so work started before it silently stops here instead
    /// of writing status, inserting text or driving the Live Activity into a session
    /// that no longer exists (#267).
    ///
    /// WHY it logs rather than returning quietly: a dropped outcome is invisible
    /// otherwise, and the device log is how this class of bug gets diagnosed here.
    /// The signature to look for afterwards is the absence of rejected Live Activity
    /// transitions following a clean abandon.
    ///
    /// ### What is deliberately NOT gated, and why
    ///
    /// Every `await` in a session-owned task is a place a cancel can land, but not
    /// every continuation past one publishes session state. These were each checked
    /// rather than gated by reflex:
    ///
    /// - `verifyAudioFlow()` already opens with `guard status == .recording`, and an
    ///   abandoned session is `.idle` by then. Its engine restart is unreachable
    ///   after a cancel.
    /// - `setModelLoadState(...)` describes the *model*, which outlives any one
    ///   dictation. Suppressing it would leave the next session reading a load state
    ///   that never happened.
    /// - `schedulePolishPrewarm()` warms a model and publishes nothing.
    /// - The stage watchdog re-checks `self.status` against the status it was armed
    ///   for before it fires.
    /// - `pendingColdStartDictation` is retried from `didBecomeActive` only when the
    ///   App Group still reads `.requested`; a cancel writes `.idle` first, so the
    ///   deferred start does not resurrect.
    private func mayReport(_ session: Int, _ what: String) -> Bool {
        sessions.mayReportOutcome(
            session: session,
            what: what,
            cancelRequested: defaults.bool(forKey: SharedKeys.cancelRequested),
            currentRequest: currentLanguageRequest,
            persistedRequest: DictationLanguageRequest.load(from: defaults)
        )
    }

    // MARK: - Stage Watchdog

    /// How long a post-recording stage may run before it is declared stuck.
    /// Nil for statuses no stage watchdog covers.
    ///
    /// WHY 30s for transcription: WhisperKit transcription of a typical dictation
    /// (<60s audio) should complete in under 10s even on older devices. 30s provides
    /// generous margin while still catching genuinely stuck transcriptions.
    ///
    /// WHY 60s for the LLM stage (#267) and not the same 30s: generation time scales
    /// with the output, which is exactly why this stage was split out, and the cost
    /// of firing early is higher here than during transcription -- the transcript
    /// already exists and the recovery below throws it away with the rest of the
    /// session. The number is a last-resort unfreeze, not a latency budget.
    private func stageWatchdogTimeout(for status: DictationStatus) -> TimeInterval? {
        switch status {
        case .transcribing:
            return 30
        case .processing:
            return 60
        case .idle, .requested, .recording, .ready, .failed:
            return nil
        }
    }

    /// Log source for a fired stage watchdog. `appTranscription` is unchanged from
    /// before #267 so log lines written by older builds keep meaning what they meant.
    private func stageWatchdogSource(for status: DictationStatus) -> String {
        status == .processing ? "appProcessing" : "appTranscription"
    }

    private func startStageWatchdog(for status: DictationStatus) {
        stopStageWatchdog()
        guard let timeout = stageWatchdogTimeout(for: status) else { return }
        stageWatchdog = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard self.status == status else { return }
                PersistentLog.log(.watchdogReset(
                    source: self.stageWatchdogSource(for: status),
                    staleState: status.rawValue
                ))
                self.cancelDictation()
            }
        }
    }

    private func stopStageWatchdog() {
        stageWatchdog?.invalidate()
        stageWatchdog = nil
    }

    /// Write dictation status to App Group so the keyboard can observe it.
    private func updateStatus(_ newStatus: DictationStatus) {
        // Invariant (issue #60): entering .idle while the engine is still capturing
        // means some path skipped the teardown. Stop capture (engine stays warm per
        // #106), force the Live Activity out of .recording, and log the violation so
        // any future recurrence of this class is one log line, not a silent
        // background recording.
        if newStatus == .idle && audioEngine.isRecording {
            PersistentLog.log(.idleInvariantViolation(
                from: status.rawValue,
                engineRunning: audioEngine.isEngineRunning
            ))
            if #available(iOS 14.0, *) {
                DictusLogger.app.fault("Invariant violation: entering .idle while engine is recording — forcing teardown")
            }
            _ = audioEngine.collectSamplesAndDeactivate()
            Task { await LiveActivityManager.shared.returnToStandby() }
            LiveActivityManager.shared.startRecordingWatchdog()
        }

        let oldStatus = status
        PersistentLog.log(.statusChanged(from: oldStatus.rawValue, to: newStatus.rawValue, source: "coordinator"))
        status = newStatus
        defaults.set(newStatus.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()

        // Re-arm on every stage the watchdog covers, disarm on everything else.
        // The `.transcribing -> .processing` hand-over is the case that makes the
        // second branch matter: leaving the transcription timer armed would let it
        // fire 30s into a stage it knows nothing about (#267).
        if stageWatchdogTimeout(for: newStatus) != nil {
            startStageWatchdog(for: newStatus)
        } else if stageWatchdogTimeout(for: oldStatus) != nil {
            stopStageWatchdog()
        }

        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
        if canChangeSpeechRuntime { applyDeferredModelChanges() }
    }

    private func applyDeferredModelChanges() {
        guard canChangeSpeechRuntime else { return }
        NotificationCenter.default.post(name: .dictusDictationSessionEnded, object: nil)
        if deferredPreload { deferredPreload = false; preloadActiveModel() }
    }

    /// Verify audio samples are actually being captured after startRecording.
    /// Detects "zombie engine" state where engine.isRunning but tap receives no buffers.
    /// If 0 samples after 2s, force-restarts the engine and retries once.
    private func verifyAudioFlow() async {
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch { return } // Task cancelled (user stopped recording)

        guard status == .recording else { return }

        let sampleCount = audioEngine.currentSampleCount
        if sampleCount > 0 { return } // Healthy — samples flowing

        PersistentLog.log(.dictationFailed(error: "Zombie engine: 0 samples after 2s, force-restarting"))

        // Force restart: stop engine, reconfigure, restart
        audioEngine.forceRestart()
        do {
            try audioEngine.startRecording()
        } catch {
            handleError("Micro indisponible. Relancez l'application.", disposition: .requiresApp)
            return
        }

        // Check again after restart
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
        } catch { return }

        guard status == .recording else { return }

        if audioEngine.currentSampleCount == 0 {
            handleError("Micro indisponible. Relancez l'application.", disposition: .requiresApp)
        } else {
            PersistentLog.log(.engineWarmUpSuccess(context: "zombie-recovery"))
        }
    }

    /// Handle errors by updating status and writing error to App Group.
    ///
    /// The message goes to `DictationErrorChannel`, which both the keyboard's toolbar
    /// and the app's own failure screen read (#320). Neither consumes it: it stays put
    /// until the next dictation starts, so a user who reads it on one surface and then
    /// opens the other is told the same thing twice rather than something else.
    private func handleError(_ message: String, disposition: DictationFailureDisposition = .recoverableRetry) {
        initTask?.cancel()
        transcriptionService.cancelCurrentInference()
        disableKeyboardSession()
        // Errors can arrive during requested/recording or after capture has
        // stopped. In both cases no microphone resource should survive the
        // terminal state.
        if audioEngine.isRecording {
            audioEngine.deactivateSession()
        } else {
            audioEngine.deactivateIfIdle()
        }
        DictationErrorChannel.record(message, disposition: disposition)
        let keepTranscript = defaults.object(forKey: SharedKeys.historyEnabled) as? Bool ?? true
        persistLastDictationIssue(
            stage: status.rawValue,
            failureStage: status.rawValue,
            errorSummary: message,
            rawText: keepTranscript ? issueRawText : nil
        )
        defaults.set(false, forKey: SharedKeys.coldStartActive)
        defaults.removeObject(forKey: SharedKeys.sourceAppScheme)
        defaults.synchronize()
        updateStatus(.failed)
        LiveActivityManager.shared.endWithFailure()
        // Arm watchdog: safety net if endWithFailure's transition guard rejects.
        LiveActivityManager.shared.startRecordingWatchdog()
    }

    /// Overwrites the single last-dictation issue slot. Transcript text is stored
    /// so Settings can offer an opt-in export; nothing is sent automatically.
    private func persistLastDictationIssue(
        stage: String,
        failureStage: String? = nil,
        errorSummary: String? = nil,
        rawText: String? = nil,
        cleanedText: String? = nil
    ) {
        LastDictationIssueReport.store(
            LastDictationIssueSnapshot(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
                modelIdentifier: currentLanguagePolicy.modelIdentifier,
                engineName: currentLanguagePolicy.engine.rawValue,
                outputMode: currentLanguagePolicy.outputMode.rawValue,
                transcriptionMode: currentLanguagePolicy.mode.storedValue,
                translationTarget: currentLanguageRequest.translationTarget?.rawValue,
                stage: stage,
                failureStage: failureStage,
                errorSummary: errorSummary,
                recordingDurationMs: issueRecordingDurationMs,
                transcribeMs: issueTranscribeMs,
                polishMs: issuePolishMs,
                rawText: rawText,
                cleanedText: cleanedText
            ),
            in: defaults
        )
    }

    // MARK: - Model load orchestration (issue #144)

    /// Read the current persisted model load state from the App Group.
    /// SwiftUI views read this through NotificationCenter posts emitted by
    /// `setModelLoadState` (see `Notification.Name.dictusModelLoadStateChanged`).
    var modelLoadState: ModelLoadState {
        let raw = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        return ModelLoadState(rawValue: raw) ?? .idle
    }

    /// Update the tri-state load flag, persist it to the App Group so the keyboard
    /// can gate mic taps, and broadcast a notification so any in-app overlay can react.
    /// Must be called on the main actor (the class is @MainActor).
    func setModelLoadState(_ newState: ModelLoadState, reason: String) {
        let oldRaw = defaults.string(forKey: SharedKeys.modelLoadState) ?? ModelLoadState.idle.rawValue
        // Refresh the timestamp even when a second warm-up enters the same
        // `.loading` state. This gives the keyboard a bounded, truthful window
        // instead of inheriting an old timestamp from a previous app process.
        if newState == .loading {
            defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.modelLoadStateTimestamp)
            defaults.removeObject(forKey: SharedKeys.modelLoadFailure)
            defaults.removeObject(forKey: SharedKeys.modelLoadFailureTimestamp)
        } else if newState == .ready {
            defaults.removeObject(forKey: SharedKeys.modelLoadFailure)
            defaults.removeObject(forKey: SharedKeys.modelLoadFailureTimestamp)
        } else {
            defaults.removeObject(forKey: SharedKeys.modelLoadStateTimestamp)
        }
        guard oldRaw != newState.rawValue else {
            defaults.synchronize()
            return
        }
        defaults.set(newState.rawValue, forKey: SharedKeys.modelLoadState)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.modelReadinessChanged)
        PersistentLog.log(.modelLoadStateChanged(from: oldRaw, to: newState.rawValue, reason: reason))
        NotificationCenter.default.post(
            name: .dictusModelLoadStateChanged,
            object: nil,
            userInfo: ["state": newState.rawValue, "reason": reason]
        )
    }

    /// Keeps recovery actionable after a preload failure without exposing raw
    /// Core ML or filesystem details in the readiness UI.
    func recordModelLoadFailure(_ error: Error, context: String) {
        let message = (error as? SpeechModelError)?.errorDescription
            ?? "The transcription model could not be loaded. Try again."
        defaults.set(message, forKey: SharedKeys.modelLoadFailure)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.modelLoadFailureTimestamp)
        defaults.synchronize()
        PersistentLog.log(.diagnosticProbe(
            component: "ModelRuntime",
            instanceID: currentLanguagePolicy.modelIdentifier,
            action: "failurePresented",
            details: "context=\(context) message=\(message)"
        ))
    }

    /// Eagerly load the active model into RAM. Called from `ModelManager.selectModel`
    /// after a model swap so the user does not have to wait for the first mic tap to
    /// trigger the lazy load (issue #144 — turbo swap took 1-3 minutes which collapsed
    /// into a cancellation storm without this proactive path).
    ///
    /// Safe to call repeatedly: the underlying `initTask` lock dedupes concurrent loads.
    func preloadActiveModel() {
        guard canChangeSpeechRuntime else { deferredPreload = true; return }
        let preferredModel = UIApplication.shared.applicationState == .active
            ? defaults.string(forKey: SharedKeys.appDictationModel)
            : defaults.string(forKey: SharedKeys.activeModel)
        guard let preferredModel else { return }
        Task {
            guard self.canChangeSpeechRuntime else { self.deferredPreload = true; return }
            self.setModelLoadState(.loading, reason: "selectModel-proactive")
            do {
                try await ensureEngineReady(preferredModel: preferredModel)
                PersistentLog.log(.appWhisperKitLoaded(modelName: self.currentModelName ?? "unknown"))
                self.setModelLoadState(.ready, reason: "selectModel-proactive-success")
            } catch {
                if error is CancellationError { return }
                if let error = error as? ModelManagerError, case .modelInUse = error {
                    self.deferredPreload = true
                    return
                }
                PersistentLog.log(.engineWarmUpFailed(
                    context: "selectModel-proactive",
                    error: error.localizedDescription
                ))
                self.recordModelLoadFailure(error, context: "selectModel-proactive")
                self.setModelLoadState(.idle, reason: "selectModel-proactive-failed")
            }
        }
    }
}

// MARK: - Speech engine initialization

/// Engine initialization lives in its own extension so the coordinator class body
/// stays within the SwiftLint `type_body_length` budget. These methods are still
/// file-private members of the coordinator and touch the same stored properties.
@MainActor
private extension DictationCoordinator {
    /// Initialize the appropriate STT engine based on the active model.
    ///
    /// Falls back to the active model from App Group, then to the new-install default.
    func ensureEngineReady(preferredModel: String? = nil) async throws {
        try await ensureEngineReady(preferredModel: preferredModel, fallbackExclusions: [])
    }

    private func ensureEngineReady(
        preferredModel: String?,
        fallbackExclusions: Set<String>
    ) async throws {
        try Task.checkCancellation()
        let preparationGeneration = sessions.current
        let requestedModelName = preferredModel
            ?? (DictationSessionLivenessPolicy.isActive(status) ? currentLanguagePolicy.modelIdentifier : nil)
            ?? defaults.string(forKey: SharedKeys.appDictationModel)
            ?? DictationModelPreferences.requestedAppModel(in: defaults)
        let modelName = resolveRuntimeModelIdentifier(requestedModelName)
        if modelName != requestedModelName {
            PersistentLog.log(.diagnosticProbe(
                component: "DictationCoordinator",
                instanceID: "modelRuntime",
                action: "fallbackSelected",
                details: "requested=\(requestedModelName) resolved=\(modelName)"
            ))
        }

        let modelInfo = ModelInfo.forIdentifier(modelName)
        let spokenLanguages = DictationSessionLivenessPolicy.isActive(status)
            ? currentLanguagePolicy.spokenLanguages : SpokenLanguagePreferences.load(from: defaults)
        if !spokenLanguages.isEmpty, let modelInfo,
           !SpokenLanguagePreferences.accepts(modelInfo, languages: spokenLanguages) {
            throw TranscriptionError.unsupportedLanguages
        }

        do {
            while let pending = initTask {
                let pendingModel = preparingModelIdentifier
                do { try await pending.value }
                catch { if pendingModel == modelName && !pending.isCancelled && !(error is CancellationError) { throw error } }
                try Task.checkCancellation()
            }
            try requireSessionModel(modelName)
            if currentModelName == modelName, transcriptionService.hasLoadedModel { return }
            let task = Task<Void, Error> {
                defer {
                    self.initTask = nil; self.preparingModelIdentifier = nil
                    if Task.isCancelled { self.setModelLoadState(.idle, reason: "model-preparation-cancelled") }
                }
                try self.requireSessionModel(modelName)
                await self.transcriptionService.releaseLoadedModelAndWait()
                self.whisperKit = nil; self.currentModelName = nil
                try self.requireSessionModel(modelName)
                let kit = try await self.ensureWhisperKitEngineReady(modelName: modelName)
                let prepared = WhisperKitEngine()
                prepared.setWhisperKit(kit)
                do { try self.requireSessionModel(modelName) }
                catch { await prepared.releaseLoadedModelAndWait(); throw error }
                self.whisperKit = kit
                self.transcriptionService.prepare(engine: prepared)
                self.currentModelName = modelName
            }
            preparingModelIdentifier = modelName
            initTask = task
            try await task.value
        } catch {
            try Task.checkCancellation()
            guard sessions.mayReport(from: preparationGeneration) else { throw CancellationError() }
            guard error is SpeechModelError,
                  let fallback = installedWhisperFallback(
                      excluding: fallbackExclusions.union([modelName])
                  ) else {
                throw error
            }

            PersistentLog.log(.diagnosticProbe(
                component: "ModelRuntime",
                instanceID: modelName,
                action: "loadFallback",
                details: "requested=\(requestedModelName) failed=\(modelName) resolved=\(fallback)"
            ))
            updateLanguagePolicyForLoadedModel(fallback, replacing: modelName)
            try await ensureEngineReady(
                preferredModel: fallback,
                fallbackExclusions: fallbackExclusions.union([modelName])
            )
        }
    }

    private func updateLanguagePolicyForLoadedModel(_ model: String, replacing failedModel: String) {
        guard currentLanguagePolicy.modelIdentifier == failedModel else { return }
        currentLanguagePolicy = TranscriptionLanguagePolicy(
            mode: currentLanguagePolicy.mode,
            keyboardLanguage: currentLanguagePolicy.keyboardLanguage,
            engine: .whisperKit,
            modelIdentifier: model,
            outputMode: currentLanguagePolicy.outputMode,
            spokenLanguages: currentLanguagePolicy.spokenLanguages
        )
    }

    private func requireSessionModel(_ identifier: String) throws {
        try Task.checkCancellation()
        guard DictationModelPreferences.canPrepareModel(identifier,
            sessionModel: currentLanguagePolicy.modelIdentifier, status: status, finalizing: isTranscribingInFlight) else {
            deferredPreload = true
            throw ModelManagerError.modelInUse
        }
    }

    /// Returns the first installed multilingual Whisper model that is known to
    /// fit this device. A failed model must not strand dictation when a usable
    /// local model is already available; the selected model remains persisted so
    /// the app can retry it after the user repairs or replaces its files.
    private func installedWhisperFallback(excluding: Set<String>) -> String? {
        let capabilities = DeviceCapabilities.current()
        let installed = Set(readDownloadedModels())
        var candidates = [ModelInfo.recommendedIdentifier(for: capabilities)]
        if let recommended = ModelSelectionProfile.active(from: defaults).resolvedIdentifier(
            installed: installed.subtracting(excluding), osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            capabilities: capabilities,
            requiredLanguages: SpokenLanguagePreferences.load(from: defaults)) {
            candidates.insert(recommended, at: 0)
        }
        candidates.append(contentsOf: [
            "openai_whisper-small",
            "openai_whisper-base",
            "openai_whisper-tiny"
        ])

        var seen = Set<String>()
        return candidates.first { identifier in
            guard seen.insert(identifier).inserted,
                  !excluding.contains(identifier),
                  installed.contains(identifier),
                  let model = ModelInfo.forIdentifier(identifier),
                  model.engine == .whisperKit,
                  model.languageSupport.coverage == .whisperMultilingual,
                  SpokenLanguagePreferences.accepts(model, languages: SpokenLanguagePreferences.load(from: defaults)),
                  model.isSupported(on: capabilities),
                  WhisperModelRepository.installedModelFolderURL(for: identifier) != nil else {
                return false
            }
            return true
        }
    }

    /// Resolve a selected catalog row to a locally installed model that this
    /// device and OS can load. The selected row remains persisted; the fallback
    /// is a runtime decision and can be retried after the user installs the row.
    func resolveRuntimeModelIdentifier(_ requestedIdentifier: String, languages: [String]? = nil) -> String {
        let resolution = ModelInfo.runtimeResolution(
            for: requestedIdentifier,
            installedIdentifiers: Set(readDownloadedModels()),
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            capabilities: DeviceCapabilities.current(),
            fallbackLanguages: languages ?? (DictationSessionLivenessPolicy.isActive(status)
                ? currentLanguagePolicy.spokenLanguages : SpokenLanguagePreferences.load(from: defaults))
        )
        return resolution.resolvedIdentifier ?? requestedIdentifier
    }

    /// Initialize WhisperKit with the preferred model if not already loaded.
    ///
    /// Loads strictly from the local model repository (issue #249). This path used to
    /// build its config from the model name with `download: true` and no
    /// `modelFolder`, so WhisperKit resolved the identifier against the Hugging Face
    /// hub — every Whisper model was unusable without connectivity, and a hub outage
    /// or airplane mode failed dictation with WhisperKit's untranslated
    /// "Model not found…" message. Downloading stays the model manager's job.
    func ensureWhisperKitEngineReady(modelName: String) async throws -> WhisperKit {
        if let whisperKit, currentModelName == modelName {
            return whisperKit
        }

        // Fail fast, before any task is created, when the model is not on disk.
        // `SharedKeys.modelReady` only reflects App Group bookkeeping; this checks
        // the files WhisperKit will actually read.
        guard let modelFolder = WhisperModelRepository.installedModelFolderURL(for: modelName) else {
            let error = SpeechModelError.modelNotInstalled(identifier: modelName)
            PersistentLog.log(.diagnosticProbe(
                component: "WhisperKitLoad",
                instanceID: modelName,
                action: "localModelMissing",
                details: error.diagnosticDescription
            ))
            throw error
        }

        PersistentLog.log(.diagnosticProbe(
            component: "WhisperKitLoad",
            instanceID: modelName,
            action: "localModelResolved",
            details: "folder=\(modelFolder.lastPathComponent) download=false tokenizerCache=\(WhisperModelRepository.cachedTokenizerRepositoryNames().joined(separator: "|"))"
        ))

        do {
            if #available(iOS 14.0, *) {
                DictusLogger.app.info("Initializing WhisperKit with model: \(modelName, privacy: .public)")
            }

            let config = WhisperKitConfig(
                model: modelName,
                modelFolder: modelFolder.path,
                // Issue #370: A12/A13 need the audio encoder off the Neural Engine.
                computeOptions: WhisperComputeOptions.current(),
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )

            let kit = try await WhisperKit(config)

            if #available(iOS 14.0, *) {
                DictusLogger.app.info("WhisperKit ready with model: \(modelName, privacy: .public)")
            }
            return kit
        } catch {
            // Wrap anything WhisperKit or Core ML raises (issue #249). Their messages
            // are English and developer-facing; `handleError` writes whatever reaches
            // it straight into the keyboard's error banner. The raw text stays in the
            // log, the user gets a localised one.
            let wrapped = SpeechModelError.engineLoadFailed(identifier: modelName, underlying: error)
            PersistentLog.log(.diagnosticProbe(
                component: "WhisperKitLoad",
                instanceID: modelName,
                action: "loadFailed",
                details: wrapped.diagnosticDescription
            ))
            throw wrapped
        }
    }


}
