// DictusCore/Sources/DictusCore/SharedKeys.swift
import Foundation

/// Centralized UserDefaults keys for App Group shared storage.
/// Using an enum with static properties prevents typo-based bugs.
public enum SharedKeys {
    public static let dictationStatus = "dictus.dictationStatus"
    public static let lastTranscription = "dictus.lastTranscription"
    public static let dictationDelivery = "dictus.dictationDelivery"
    public static let lastTranscriptionTimestamp = "dictus.lastTranscriptionTimestamp"
    public static let lastError = "dictus.lastError"
    public static let failureDisposition = "dictus.failureDisposition"

    // Model management keys (added for Plan 2.3 transcription pipeline)
    public static let activeModel = "dictus.activeModel"
    public static let modelReady = "dictus.modelReady"
    public static let downloadedModels = "dictus.downloadedModels"
    /// JSON-encoded custom model registrations, kept separate from built-in models.
    public static let customModels = "dictus.customModels"
    /// Tri-state model lifecycle: "idle" / "loading" / "ready".
    /// "idle" = no active load in flight, but `modelReady` may still be true.
    /// "loading" = WhisperKit/Parakeet is being loaded into RAM (or compiling/downloading).
    /// "ready" = active model is loaded in RAM and `transcribe()` calls will succeed.
    /// The keyboard reads this to refuse mic taps during load (issue #144).
    public static let modelLoadState = "dictus.modelLoadState"
    /// Double (timeIntervalSince1970): when the current model load started.
    /// A loading state without a fresh timestamp is treated as abandoned so a
    /// crashed or suspended app cannot leave the keyboard on "Open sAiity" forever.
    public static let modelLoadStateTimestamp = "dictus.modelLoadStateTimestamp"

    // Keyboard-App cross-process contracts (added for Plan 3.1)
    /// Legacy single global keyboard layout, stored as String ("azerty"/"qwerty"/"qwertz").
    /// Since #272 the layout is per dictionary language — see `keyboardLayoutsByLanguage`.
    /// This key is now only *read* by the one-time migration, and kept up to date as a
    /// mirror of the active language's layout so a rollback to a build without #272 finds
    /// the shape the user is on. Nothing else should read or write it.
    public static let keyboardLayout = "dictus.keyboardLayout"
    /// Keyboard layout per dictionary language (#272): `[SupportedLanguage.rawValue: LayoutType.rawValue]`.
    /// An entry means the user explicitly chose that layout for that language; a missing
    /// entry means the language still inherits `SupportedLanguage.defaultLayout` and keeps
    /// tracking it. The presence of the dictionary itself — even empty — is the marker that
    /// the migration from `keyboardLayout` has run. Read and written only through
    /// `KeyboardLayoutPreference`.
    public static let keyboardLayoutsByLanguage = "dictus.keyboardLayoutsByLanguage"
    /// Bool: whether the keyboard draws a persistent digit row above the letter rows (#331).
    /// Default false — absent means off, which is `UserDefaults.bool`'s natural default, so no
    /// migration and no registration is needed and every existing install keeps its geometry.
    /// One global value, not per language: a number row is a hardware habit, not a language one.
    /// Read and written only through `NumberRowPreference`, except for the Settings toggle's
    /// @AppStorage binding — the same split every other preference on that screen uses.
    public static let numberRowEnabled = "dictus.numberRowEnabled"
    public static let keyboardAccessoryOrder = "dictus.keyboardAccessoryOrder"
    /// JSON-encoded [Float] waveform energy data written by app during recording
    public static let waveformEnergy = "dictus.waveformEnergy"
    /// Bool flag set by keyboard to request recording stop
    public static let stopRequested = "dictus.stopRequested"
    /// Bool flag set by keyboard to request recording cancellation
    public static let cancelRequested = "dictus.cancelRequested"
    /// Double: elapsed recording seconds, updated at ~5Hz during recording
    public static let recordingElapsedSeconds = "dictus.recordingElapsedSeconds"

    // Keyboard mode preference (added for Phase 09 keyboard modes)
    /// Current keyboard mode stored as String ("micro", "emojiMicro", "full")
    @available(*, deprecated, message: "Use defaultKeyboardLayer instead. Kept for migration only.")
    public static let keyboardMode = "dictus.keyboardMode"

    /// Default keyboard layer: "letters" or "numbers". Replaces keyboardMode.
    public static let defaultKeyboardLayer = "dictus.defaultKeyboardLayer"

    // User preferences (added for Plan 4.1 onboarding + settings)
    /// Legacy keyboard language code. New installs resolve to the system language,
    /// limited to English or German, and otherwise fall back to English.
    /// Drives the keyboard layout, key labels, and autocorrect/prediction.
    /// Since issue #226 this is NO longer the STT language by itself — see
    /// `transcriptionLanguage` below. STT only follows this key when the
    /// transcription language mode is "follow".
    public static let language = "dictus.language"
    /// Codable keyboard language selection: automatic system language or explicit code.
    public static let keyboardLanguageSelection = "dictus.keyboardLanguageSelection"
    /// One-time marker for migration of the implicit legacy French default.
    public static let keyboardLanguageMigrationVersion = "dictus.keyboardLanguageMigrationVersion"

    // Transcription language compatibility (issue #226)
    /// Historical STT language mode storage. New product behavior is always
    /// Auto-detect; old values remain readable for migration and diagnostics.
    /// The keyboard toolbar writes only `language`/`keyboardLayout` and cannot
    /// change the product's automatic transcription behavior.
    public static let transcriptionLanguage = "dictus.transcriptionLanguage"
    /// JSON-free request contract written by the keyboard and consumed by the app.
    public static let dictationLanguageRequest = "dictus.dictationLanguageRequest"
    /// Codable Translation.framework source/target readiness snapshot written by the app.
    public static let translationReadiness = "dictus.translationReadiness"
    /// Whether haptic feedback is enabled, default true
    public static let hapticsEnabled = "dictus.hapticsEnabled"
    /// Whether long-press alternate-character popups are enabled, default true
    public static let keyPopupsEnabled = "dictus.keyPopupsEnabled"
    /// Whether the keyboard-mode suggestion row is visible, default true.
    public static let suggestionsEnabled = "dictus.suggestionsEnabled"
    /// Whether the user has completed onboarding, default false
    public static let hasCompletedOnboarding = "dictus.hasCompletedOnboarding"
    /// Current onboarding step index (0-5). Persisted to UserDefaults so the user
    /// resumes at the right step even after iOS TCC-triggered terminations
    /// (e.g., when "Allow Full Access" is toggled during keyboard setup).
    public static let onboardingCurrentPage = "dictus.onboardingCurrentPage"
    /// Bool handshake written by the keyboard extension from `hasFullAccess`.
    /// The app cannot inspect the system toggle directly; it only trusts this
    /// value after the extension has actually appeared with Full Access.
    public static let onboardingFullAccessVerified = "dictus.onboardingFullAccessVerified"
    /// Unix timestamp of the last keyboard extension Full Access handshake.
    public static let onboardingFullAccessHandshakeDate = "dictus.onboardingFullAccessHandshakeDate"

    // Text prediction preferences (added for Phase 08)
    /// Whether autocorrect is enabled, default true
    public static let autocorrectEnabled = "dictus.autocorrectEnabled"

    // Autocorrect debug logging (DEBUG builds only - see AutocorrectDebugLog).
    /// Bool: when true, logs autocorrect decisions with the typed word + correction
    /// to the App Group persistent log for debugging. CONTAINS USER TEXT — never
    /// active in Release builds (code is compile-time excluded via #if DEBUG).
    public static let autocorrectDebugLogging = "dictus.autocorrectDebugLogging"

    // Live Activity preference
    /// Whether Live Activity (Dynamic Island + Lock Screen) is enabled, default true
    public static let liveActivityEnabled = "dictus.liveActivityEnabled"
    /// Whether the dictation service is enabled from the Home toolbar.
    public static let serviceEnabled = "dictus.serviceEnabled"
    /// Whether Live Activity detection is muted without ending standby.
    public static let detectionMuted = "dictus.detectionMuted"

    // Post-STT polish (issue #141)
    /// Whether the cleanup layer runs between STT final output and App Group write.
    /// Defaults to true; an explicit user choice is preserved by app migration.
    public static let polishEnabled = "dictus.polishEnabled"
    /// Bool: whether polish has stopped calling its engine for the rest of this app
    /// process (#315). Written only by DictusApp, read by whichever surface has to
    /// say so — the keyboard toolbar today. Absent reads false, which is the
    /// available state, so no registration and no migration are needed.
    ///
    /// Read and written only through `PolishAvailabilityChannel`, which is where
    /// the rule about clearing it lives.
    public static let polishUnavailable = "dictus.polishUnavailable"

    // Audio heartbeat (added for background waveform reliability)
    /// Double (timeIntervalSince1970): written directly from the audio thread at ~1Hz
    /// during active recording. The keyboard watchdog reads this as a fallback
    /// when Darwin waveform notifications don't arrive (iOS main thread throttling
    /// in background). If the heartbeat is fresh (< 5s), the app is still recording.
    public static let recordingHeartbeat = "dictus.recordingHeartbeat"

    // Cold start detection keys (added for Phase 13)
    /// Bool flag: true when the app was opened from the keyboard for cold start dictation.
    /// Set by handleIncomingURL when source=keyboard query parameter is present.
    /// Cleared when the app enters background.
    public static let coldStartActive = "dictus.coldStartActive"
    /// String: URL scheme of the source app (e.g., "whatsapp") or "unknown".
    /// Used by auto-return logic to navigate back to the correct app after dictation.
    public static let sourceAppScheme = "dictus.sourceAppScheme"

    // Keyboard teardown diagnostics (issue #281)
    /// String: DictusApp's last reported scene phase, one of `AppScenePhaseMarker`.
    /// Written by the app on every scene phase change, read by the keyboard extension
    /// when its controllers are torn down. Observation only — nothing branches on it.
    public static let appScenePhase = "dictus.appScenePhase"
    /// Double (timeIntervalSince1970): when `appScenePhase` was written. The pair is
    /// only meaningful together: the keys outlive the app process, so the age is what
    /// separates "the app is in the background right now" from a stale leftover.
    public static let appScenePhaseTimestamp = "dictus.appScenePhaseTimestamp"

    // App and Live Activity availability
    /// Double (timeIntervalSince1970): last heartbeat from the DictusApp process.
    public static let appProcessHeartbeat = "dictus.appProcessHeartbeat"
    /// Bool: whether DictusApp last confirmed that its Live Activity is present.
    public static let liveActivityPresent = "dictus.liveActivityPresent"
    /// String: the last Live Activity identifier published by DictusApp, for logs.
    public static let liveActivityID = "dictus.liveActivityID"

    // MARK: - Sound Feedback
    /// Whether sound feedback is enabled for recording events, default true
    public static let soundFeedbackEnabled = "dictus.soundFeedbackEnabled"
    /// Name of the WAV file (without extension) to play when recording starts
    public static let recordStartSoundName = "dictus.recordStartSoundName"
    /// Name of the WAV file (without extension) to play when recording stops
    public static let recordStopSoundName = "dictus.recordStopSoundName"
    /// Name of the WAV file (without extension) to play when recording is cancelled
    public static let recordCancelSoundName = "dictus.recordCancelSoundName"
    /// Sound volume from 0.0 to 1.0, default 0.5
    public static let soundVolume = "dictus.soundVolume"

    // MARK: - Pro / Subscription
    /// Bool: true when the user has an active Pro subscription.
    /// Written by SubscriptionManager (DictusApp), read by the keyboard extension.
    public static let proActive = "dictus.proActive"
    /// Bool: per-feature toggle for Smart Mode, default true (registered by ProStatusManager)
    public static let smartModeEnabled = "dictus.smartModeEnabled"
    /// Bool: per-feature toggle for History, default true (registered by ProStatusManager)
    public static let historyEnabled = "dictus.historyEnabled"
    /// Bool: per-feature toggle for Vocabulary, default true (registered by ProStatusManager)
    public static let vocabularyEnabled = "dictus.vocabularyEnabled"

    // MARK: - #357 spike (throwaway)
    /// Bool: arms exactly ONE Apple Foundation Models probe run inside the
    /// keyboard extension. Written by the hidden polish debug screen, read and
    /// immediately cleared by `AppleFMExtensionProbe` in DictusKeyboard.
    ///
    /// WHY it lives here rather than next to the probe: the two processes that
    /// have to agree on this string cannot see each other's targets, and a
    /// literal duplicated across a process boundary is the kind of typo that
    /// costs a device session to find. Absent — which is the shipped state —
    /// it reads false and the probe never runs.
    ///
    /// Delete with the spike.
    public static let appleFMExtensionProbeArmed = "dictus.debug.appleFMExtensionProbeArmed"
}
