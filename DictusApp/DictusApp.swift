// DictusApp/DictusApp.swift
import SwiftUI
import AVFoundation
import StoreKit
import DictusCore
#if canImport(Translation)
import Translation
#endif

// MARK: - AppDelegate (sourceApplication diagnostic)
// Temporary diagnostic: UIApplicationDelegateAdaptor captures sourceApplication
// from the legacy application(_:open:options:) callback, which SwiftUI's onOpenURL
// does not expose. This lets us empirically confirm that sourceApplication returns nil
// for cross-team apps (e.g., WhatsApp opening DictusApp via dictus:// URL).
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        let source = options[.sourceApplication] as? String
        PersistentLog.log(.diagnosticProbe(
            component: "sourceApp", instanceID: "0",
            action: "delegateSourceApp",
            details: "source=\(source ?? "nil") url=\(url.absoluteString)"
        ))
        // Return false so SwiftUI onOpenURL still handles the URL
        return false
    }

    /// Installs `DictusSceneDelegate` so the launch URL can be read at scene connection.
    ///
    /// WHY here rather than in Info.plist: the app has no `UISceneConfigurations` entry,
    /// and UIKit asks the app delegate first. Returning a configuration with our delegate
    /// class is the least invasive way to get `UIScene.ConnectionOptions` — the only API
    /// that exposes the launch URL before SwiftUI evaluates its first body (issue #264).
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = DictusSceneDelegate.self
        return configuration
    }
}

@main
struct DictusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = DictationCoordinator.shared
    @StateObject private var proStatus: ProStatusManager
    @StateObject private var subscriptionManager: SubscriptionManager

    /// Onboarding completion state shared through the App Group.
    /// It is read once into local `@State` during app initialization, then persisted
    /// back to the shared UserDefaults by the `onChange` handler below.
    /// A missing value is treated as `false`, so first-time users see onboarding.
    @State private var hasCompletedOnboarding: Bool

    init() {
        // Read the shared value after the app group is available to the process.
        // This avoids seeding SwiftUI's storage from a stale pre-entitlement value
        // on a fresh install or after the keyboard extension changed the suite.
        _hasCompletedOnboarding = State(
            initialValue: AppGroup.defaults.bool(forKey: SharedKeys.hasCompletedOnboarding)
        )
        PersistentLog.source = "APP"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        PersistentLog.log(.appLaunched(version: version))
        PerformanceMetricsSubscriber.shared.start()
        #if DEBUG
        CleanupModelProbe.startIfRequested()
        #endif

        // Clean up any Live Activities left over from a previous app session.
        // WHY in init: If the app crashed or was force-quit, the Dynamic Island
        // keeps showing stale data for up to 8 hours. Cleaning up here ensures
        // a fresh start.
        LiveActivityManager.shared.cleanupStaleActivities()

        let result = AppGroupDiagnostic.run()
        DictusLogger.app.info(
            "AppGroup diagnostic: healthy=\(result.isHealthy, privacy: .public)"
        )

        // Read n-gram diagnostic written by keyboard extension
        if let ngramDiag = UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: "ngramDiagnostic") {
            DictusLogger.app.info("ngramDiagnostic: \(ngramDiag, privacy: .public)")
        }

        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        if let defaults {
            KeyboardLanguageSelection.migrateLegacyFrenchIfNeeded(in: defaults)
        }
        // Transcription always uses Auto-detect at the ASR boundary. Preserve
        // the separately persisted output-mode preference from Settings.
        if let defaults {
            TranscriptionLanguagePolicy.persistProductDefaults(to: defaults)
        }
        // Freeze the layout an updating install is already typing on, before anything can
        // change the active language (#272). The migration is idempotent and also runs from
        // the first layout read in either process — the keyboard extension can run before
        // this app is ever launched again — so this call is only about doing it as early as
        // possible on the app side.
        KeyboardLayoutPreference.migrateToPerLanguageLayoutsIfNeeded()

        // Register liveActivityEnabled default as true for existing users.
        // WHY: UserDefaults.bool(forKey:) returns false for missing keys.
        // Without this, existing users upgrading would see Live Activity disabled.
        if defaults?.object(forKey: SharedKeys.liveActivityEnabled) == nil {
            defaults?.set(true, forKey: SharedKeys.liveActivityEnabled)
        }
        if defaults?.object(forKey: SharedKeys.dictationPresenceMode) == nil {
            let enabled = defaults?.object(forKey: SharedKeys.liveActivityEnabled) as? Bool ?? true
            (enabled ? DictationPresenceMode.liveActivity : .off).persist(to: defaults ?? AppGroup.defaults)
        }
        if defaults?.object(forKey: SharedKeys.serviceEnabled) == nil {
            defaults?.set(true, forKey: SharedKeys.serviceEnabled)
        }
        // Publish a process heartbeat so the keyboard can distinguish a normal
        // backgrounded app from an app that is no longer available.
        DictationServiceLivenessProbe.recordAppHeartbeat()
        // Cleanup is the product default. Preserve an explicit off choice from
        // an earlier install by migrating only when the preference is absent.
        if defaults?.object(forKey: SharedKeys.polishEnabled) == nil {
            defaults?.set(true, forKey: SharedKeys.polishEnabled)
        }

        // Initialize Pro subscription management.
        // WHY explicit _proStatus / _subscriptionManager initialization:
        // SubscriptionManager depends on ProStatusManager (it writes Pro status
        // to App Group). We need to create proStatus first, pass it to
        // SubscriptionManager, then wrap both in StateObject.
        let proStatus = ProStatusManager()
        _proStatus = StateObject(wrappedValue: proStatus)
        _subscriptionManager = StateObject(wrappedValue: SubscriptionManager(proStatus: proStatus))

        // Warm up the polish engine for the current target language (#141).
        // No-op when the toggle is off or when the engine has nothing to warm.
        PolishCoordinator.shared.prewarm()
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(coordinator)
                .environmentObject(proStatus)
                .environmentObject(subscriptionManager)
            .overlay {
                    if #available(iOS 26.0, *) {
                        TranslationHost(coordinator: coordinator)
                    }
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--live-activity-preview") {
                        coordinator.resetStatus()
                        LiveActivityManager.shared.startStandbyActivity()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--model-download-probe") {
                        do { try ModelRepoDownloader.checkDownloadReceipt() }
                        catch { print("MODEL_DOWNLOAD_PROBE failed: \(error.localizedDescription)") }
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--cleanup-model-probe") { return }
                    if ProcessInfo.processInfo.arguments.contains("--keyboard-settings-probe") {
                        coordinator.resetStatus()
                        return
                    }
                    #endif
                    // Automatic restoration must not request microphone access
                    // on Welcome. Setup and explicit dictation own that request.
                    let serviceEnabled = AppGroup.defaults.object(forKey: SharedKeys.serviceEnabled) == nil
                        || AppGroup.defaults.bool(forKey: SharedKeys.serviceEnabled)
                    if AudioLifecyclePolicy.shouldRestoreStandby(serviceEnabled: serviceEnabled,
                        onboardingComplete: hasCompletedOnboarding,
                        microphoneGranted: AVAudioSession.sharedInstance().recordPermission == .granted) {
                        coordinator.enableKeyboardSession()
                    }

                    // Keep the cross-process availability signal fresh while the
                    // app process remains alive, including during background audio.
                    // iOS suspends this task when the process is suspended; the
                    // keyboard then correctly falls back to the Live Activity signal.
                    while !Task.isCancelled {
                        DictationServiceLivenessProbe.recordAppHeartbeat()
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                    }
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onChange(of: scenePhase) { phase in
                    // #281 probe: publish the phase before anything else in this
                    // closure, so the keyboard extension reads a value that is at
                    // worst microseconds behind the transition it describes. It is
                    // written from the same callback that logs the lifecycle line
                    // below, which is what lets the two be compared at all.
                    AppScenePhaseProbe.record(phase.sceneMarker)
                    DictationServiceLivenessProbe.recordAppHeartbeat()

                    switch phase {
                    case .active:
                        PersistentLog.log(.appDidBecomeActive)
                    case .inactive:
                        coordinator.stopForegroundOnlyRecognitionIfNeeded()
                        PersistentLog.log(.appWillResignActive)
                    case .background:
                        PersistentLog.log(.appDidEnterBackground)

                        // A configured-but-idle audio session keeps the microphone
                        // indicator alive. Release it at the scene boundary while
                        // preserving pending and active dictations.
                        coordinator.deactivateAudioIfIdle()

                        // A cold start parked waiting for `.active` gets its last
                        // chance here (#311), because `.active` is not coming — the
                        // user swiped back before the app settled. Called from this
                        // handler rather than from a `didEnterBackground` observer of
                        // its own so the recovery and the `appDidEnterBackground` line
                        // the regression grep pivots on come from one event and cannot
                        // drift apart.
                        let resumedColdStart = coordinator.resolvePendingColdStartOnBackground()

                        // Exhaustive by construction (#267): a status added later
                        // cannot be left out of this list and silently clear the
                        // cold-start flag mid-dictation.
                        //
                        // A cold start resumed one line above counts as recording even
                        // though `status` has not moved yet — it starts inside a Task.
                        // Without the first clause, the two decisions below would clear
                        // `coldStartActive` out from under it (killing the keyboard's
                        // 15 s watchdog grace) and race a standby activity against the
                        // recording one, both of which the comments below already warn
                        // against for the healthy cold start.
                        let isRecordingActive = resumedColdStart
                            || DictationSessionLivenessPolicy.isActive(coordinator.status)

                        // Only clear cold start state if NOT recording.
                        // During cold start, the app transitions to background while recording
                        // continues. Clearing the flag here kills the keyboard's watchdog grace period
                        // and freezes the keyboard UI. The flag is cleared later in
                        // DictationCoordinator.cleanupRecordingKeys() when the recording finishes.
                        if !isRecordingActive {
                            AppGroup.defaults.set(false, forKey: SharedKeys.coldStartActive)
                            AppGroup.defaults.removeObject(forKey: SharedKeys.sourceAppScheme)
                            AppGroup.defaults.synchronize()
                            PersistentLog.log(.coldStartFlagSet(active: false, context: "background-cleanup"))
                        }

                        // Only start standby activity if NOT recording.
                        // During cold start recording, transitionToRecording() already manages
                        // the Live Activity. Calling startStandbyActivity() here creates a race:
                        // it detects the recording activity as "stale" and replaces it with a new
                        // standby activity, losing all waveform updates to the Dynamic Island.
                        if !isRecordingActive {
                            LiveActivityManager.shared.startStandbyActivity()
                        }
                    @unknown default:
                        break
                    }
                }
                .onChange(of: hasCompletedOnboarding) { _, completed in
                    AppGroup.defaults.set(completed, forKey: SharedKeys.hasCompletedOnboarding)
                    AppGroup.defaults.synchronize()
                    // WHY this notification:
                    // MainTabView's HomeView mounts BEHIND the fullScreenCover before
                    // onboarding completes. Its onAppear fires early with stale state.
                    // When onboarding finishes and the cover dismisses, onAppear does NOT
                    // re-fire. This notification tells HomeView to refresh model state.
                    if completed {
                        NotificationCenter.default.post(
                            name: Notification.Name("DictusOnboardingCompleted"),
                            object: nil
                        )
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { _ in }
                )) {
                    OnboardingView(isComplete: $hasCompletedOnboarding)
                        .environmentObject(coordinator)
                        .environmentObject(proStatus)
                        .environmentObject(subscriptionManager)
                }
        }
    }

    /// In-memory flag: true after the app has handled its first URL or become active.
    /// Resets naturally when iOS terminates the process (true cold start).
    /// WHY static: @State/@StateObject reset on view recreation, but a static var persists
    /// for the entire process lifetime — exactly matching "app was killed vs still in memory".
    private static var hasBeenActive = false

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "saiity" else { return }

        // Temporary diagnostic: log all URL components for cold start investigation.
        // This captures what information IS available from the URL itself (host, query params).
        // Combined with AppDelegate.sourceApplication logging, this lets us confirm empirically
        // that iOS provides no way to identify the keyboard's host app from a URL open.
        let diagComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        PersistentLog.log(.diagnosticProbe(
            component: "sourceApp", instanceID: "0",
            action: "urlComponents",
            details: "host=\(url.host ?? "nil") query=\(diagComponents?.queryItems?.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ",") ?? "none")"
        ))

        switch url.host {
        case "dictate":
            // Single source of truth for what the keyboard is asking (issue #264).
            let keyboardIntent = KeyboardDictationURL.intent(from: url)
            let isFromKeyboard = keyboardIntent != nil

            if keyboardIntent == .prepare {
                DictusLogger.app.info("Keyboard requested model preparation without recording")
                PersistentLog.log(.dictationDeferred(reason: "keyboard prepare-only URL"))
                // The keyboard opens this URL when the model is not warm enough for a
                // background start. Start preparation explicitly so the overlay reflects
                // real work instead of waiting on a state change that never arrives.
                coordinator.enableKeyboardSession()
                NotificationCenter.default.post(
                    name: .dictusKeyboardPreparationRequested,
                    object: nil
                )
                return
            }

            // Show cold start overlay when:
            // 1. TRUE cold start: app was terminated by iOS and keyboard just launched it
            // 2. Engine-dead restart: app is in memory but audio engine was stopped
            //    (e.g., Power button in Dynamic Island). Functionally a cold start because
            //    the app must come to foreground to restart the engine.
            let isColdStart = isFromKeyboard && !Self.hasBeenActive
            let isEngineDeadRestart = isFromKeyboard && Self.hasBeenActive
                && !DictationCoordinator.shared.isEngineRunning

            PersistentLog.log(.coldStartURLReceived(
                isColdStart: isColdStart,
                isEngineDead: isEngineDeadRestart,
                hasBeenActive: Self.hasBeenActive
            ))

            if isColdStart || isEngineDeadRestart {
                let reason = isColdStart ? "first launch" : "engine dead"
                DictusLogger.app.info("Cold/engine-dead start from keyboard (\(reason, privacy: .public)) — showing swipe-back overlay")
                AppGroup.defaults.set(true, forKey: SharedKeys.coldStartActive)
                AppGroup.defaults.synchronize()
                PersistentLog.log(.coldStartFlagSet(active: true, context: reason))
            } else if isFromKeyboard {
                DictusLogger.app.info("Warm start dictation from keyboard — skipping overlay")
            }

            Self.hasBeenActive = true
            coordinator.startDictation(fromURL: true)

            // On cold start, the swipe-back overlay (Plan 02) guides the user back.
            // Auto-return was removed because there's no public API to detect which app
            // the keyboard is serving — iterating KnownAppSchemes always opened the first
            // installed app (e.g., WhatsApp) regardless of where the user actually was.
        case "stop":
            // Stop recording from Dynamic Island expanded view button.
            coordinator.stopDictation()
        default:
            break
        }
    }
}

#if canImport(Translation)
@available(iOS 26.0, *)
private struct TranslationHost: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        Group {
            if let configuration = coordinator.translationConfiguration as? TranslationSession.Configuration {
                Color.clear
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .translationTask(configuration) { session in
                        await coordinator.consumeTranslationSession(session)
                    }
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
}
#endif

extension ScenePhase {
    /// This phase as the App Group marker the keyboard extension reads (#281).
    ///
    /// `ScenePhase` is a SwiftUI type and the keyboard has no business linking SwiftUI
    /// for a log field, so the crossing happens here, on the app side, and only the
    /// `String` raw value travels between the processes.
    var sceneMarker: AppScenePhaseMarker {
        switch self {
        case .active: return .active
        case .inactive: return .inactive
        case .background: return .background
        // A phase SwiftUI adds after this was written is reported honestly rather
        // than guessed at: the probe's value comes from being trustworthy.
        @unknown default: return .unknown
        }
    }
}

extension Notification.Name {
    /// Posted by `DictationCoordinator.setModelLoadState` whenever the persisted
    /// `SharedKeys.modelLoadState` changes. UI overlays observe this to dismiss
    /// themselves once the model is `.ready` (issue #144).
    static let dictusModelLoadStateChanged = Notification.Name("DictusModelLoadStateChanged")

    /// Posted when the keyboard opens Dictus only to prepare a model before a
    /// later, explicit microphone tap (issue #262).
    static let dictusKeyboardPreparationRequested = Notification.Name(
        "DictusKeyboardPreparationRequested"
    )
}
