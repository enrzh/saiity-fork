// SyllivraKernel/Sources/SyllivraKernel/HapticFeedback.swift
// Haptic feedback helpers for dictation recording lifecycle events.
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// User-facing keyboard haptic preset. `off` keeps the legacy
/// `hapticsEnabled=false` contract so older builds stay in sync.
public enum HapticIntensity: String, CaseIterable, Sendable {
    case off
    case `default`
    case snappy

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .default: return "Default"
        case .snappy: return "Snappy"
        }
    }

    public var isEnabled: Bool { self != .off }

    /// The existing ordinary-key tick and full-strength Emoji Delete impulse.
    var keyTapIntensity: Double? {
        switch self {
        case .off: return nil
        case .default: return 0.42
        case .snappy: return 1
        }
    }

    public static var current: HapticIntensity {
        load(from: UserDefaults(suiteName: AppGroup.identifier))
    }

    public static func load(from defaults: UserDefaults?) -> HapticIntensity {
        if let raw = defaults?.string(forKey: SharedKeys.hapticIntensity) {
            // Older on/light/medium/strong values keep the ordinary-key feel.
            return Self(rawValue: raw) ?? .default
        }
        if defaults?.object(forKey: SharedKeys.hapticsEnabled) as? Bool == false {
            return .off
        }
        return .default
    }

    public func persist(to defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.identifier)) {
        defaults?.set(rawValue, forKey: SharedKeys.hapticIntensity)
        defaults?.set(isEnabled, forKey: SharedKeys.hapticsEnabled)
    }
}

/// Provides distinct haptic feedback for key dictation events.
///
/// WHY this lives in SyllivraKernel:
/// Both DictusApp (RecordingView) and DictusKeyboard (mic button, transcription insert)
/// use the same haptic patterns. Centralizing them ensures consistent tactile feedback
/// across both targets.
///
/// WHY #if canImport(UIKit):
/// SyllivraKernel is a Swift package that compiles on macOS for testing (swift test).
/// UIKit is only available on iOS. The #if guard prevents build failures during
/// macOS-based SPM test runs while keeping the code available on iOS targets.
///
/// WHY pre-allocated static generators:
/// Creating a new UIImpactFeedbackGenerator per call adds 2-5ms latency because the
/// Taptic Engine needs to spin up. Static instances stay warm, and calling .prepare()
/// after each use re-primes the hardware for the next tap with zero perceptible delay.
///
/// WHY three distinct patterns:
/// - recordingStarted: medium impact -- user needs to feel that recording is actively happening
/// - recordingStopped: light impact -- subtle confirmation that recording stopped
/// - textInserted: success notification -- distinct "done" feel when transcribed text appears
    /// - keyTapped: selected keyboard preset -- shared by ordinary taps and delete
/// - trackpadActivated: medium impact -- confirms spacebar trackpad mode activation
public enum HapticFeedback {

    // MARK: - Pre-allocated generators

    #if canImport(UIKit) && !os(macOS)
    /// Light impact for recording-stop and secondary feedback.
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)

    /// Dedicated short rigid impulse for keyboard taps. Sharing the recording
    /// generator makes key taps feel soft and delayed on rapid input.
    private static let keyGenerator = UIImpactFeedbackGenerator(style: .rigid)

    /// Medium impact generator for recording events and trackpad activation.
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    /// Rigid impact when a hold-to-variant popup appears.
    private static let popupGenerator = UIImpactFeedbackGenerator(style: .rigid)

    /// Subtle press acknowledgement for the dictation control. Recording has
    /// its own stronger transition haptic once the request is accepted.
    private static let dictationPressGenerator = UISelectionFeedbackGenerator()

    /// Notification generator for success/error feedback (e.g., text inserted).
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Selection feedback generator for cursor movement during trackpad drag.
    /// UISelectionFeedbackGenerator produces the same subtle "tick" Apple uses
    /// for pickers and the native cursor — distinct from impact feedback,
    /// specifically designed for discrete selection changes.
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    /// Ignore duplicate callbacks from overlapping UIKit/SwiftUI hit layers.
    /// Native keyboard taps are distinct, but never arrive as two ticks within
    /// the same few milliseconds.
    private static var lastSelectionTick = Date.distantPast
    private static let minimumSelectionInterval: TimeInterval = 0.04
    #endif

    // MARK: - Cached enabled state

    /// Cached haptic enabled state. Initialized once, refreshed on keyboard appear.
    ///
    /// WHY cached: Reading UserDefaults on every key tap adds ~0.5-1ms overhead.
    /// For a 16.67ms frame budget (60fps), that's 3-6% of the budget wasted.
    /// Caching eliminates this per-tap cost entirely.
    ///
    /// WHY `object(forKey:) as? Bool ?? true` instead of `bool(forKey:)`:
    /// `bool(forKey:)` returns false when the key has never been set.
    /// The correct default is true (haptics enabled out of the box).
    /// `object(forKey:)` returns nil for missing keys, letting us provide the right default.
    #if canImport(UIKit) && !os(macOS)
    private static var _intensity: HapticIntensity = HapticIntensity.current

    /// Refresh cached intensity from UserDefaults.
    /// Call on keyboard appear (KeyboardRootView.onAppear) and when
    /// settings-changed notification arrives.
    public static func refreshEnabledState() {
        _intensity = HapticIntensity.current
    }

    private static func isEnabled() -> Bool {
        _intensity.isEnabled
    }

    /// Prime the Taptic Engine for the next tap. Call on every touchDown.
    ///
    /// WHY on touchDown: The Taptic Engine has a ~2ms cold-start if not primed.
    /// Calling prepare() on every touchDown ensures the engine is ready for
    /// the NEXT tap even during rapid typing (>6 taps/second).
    public static func prepareForNextTap() {
        keyGenerator.prepare()
        lightGenerator.prepare()
        selectionGenerator.prepare()
        dictationPressGenerator.prepare()
    }
    #endif

    /// Prepare all generators for immediate use.
    /// Call this once at keyboard load (e.g., in KeyboardRootView.onAppear) so the
    /// first key tap has zero latency. Each generator's .prepare() tells the Taptic
    /// Engine to spin up in advance.
    public static func warmUp() {
        #if canImport(UIKit) && !os(macOS)
        keyGenerator.prepare()
        lightGenerator.prepare()
        mediumGenerator.prepare()
        popupGenerator.prepare()
        dictationPressGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
        #endif
    }

    /// Medium impact feedback when the dictation hold is recognized and
    /// recording is about to begin.
    public static func recordingStarted() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        mediumGenerator.impactOccurred(intensity: 0.65)
        mediumGenerator.prepare()
        #endif
    }

    /// Light impact feedback when recording stops.
    public static func recordingStopped() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        lightGenerator.impactOccurred(intensity: 0.45)
        lightGenerator.prepare()
        #endif
    }

    /// Success notification feedback when transcribed text is inserted into the text field.
    public static func textInserted() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
        #endif
    }

    /// Error notification feedback when an action is refused (e.g. mic tap during a model load).
    public static func actionRefused() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
        #endif
    }

    /// Selected keyboard impulse, shared by delete and ordinary keys.
    ///
    /// `prepare()` before `impactOccurred()` delays the tick. Prime after the
    /// impulse so the next repeat is already warm.
    public static func keyTapped() {
        #if canImport(UIKit) && !os(macOS)
        emitKeyTap()
        #endif
    }

    /// Native-style key tap: a short Taptic tick plus the system click sound.
    ///
    /// `playInputClick()` alone is only a sound. Vibration uses the selected
    /// preset; sound continues to follow the system keyboard-click setting.
    public static func playInputClick() {
        #if canImport(UIKit) && !os(macOS)
        emitKeyTap()
        // Keyboard clicks follow the system sound setting, not the vibration switch.
        UIDevice.current.playInputClick()
        #endif
    }

    /// Immediate acknowledgement when a dictation hold begins. This is separate
    /// from `recordingStarted()` because the microphone request is asynchronous.
    public static func dictationPressBegan() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        dictationPressGenerator.selectionChanged()
        dictationPressGenerator.prepare()
        #endif
    }

    /// Confirmation when a hold-to-variant popup appears.
    public static func variantPopupPresented() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        popupGenerator.impactOccurred(intensity: 0.55)
        popupGenerator.prepare()
        #endif
    }

    /// Selection tick while sliding across accent, symbol, or emoji variants.
    public static func variantHighlightChanged() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        emitSelectionTick()
        #endif
    }

    /// Light impact feedback when autocorrect changes a word.
    /// Slightly stronger than a normal key tap to signal "something changed".
    public static func autocorrectApplied() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        lightGenerator.impactOccurred(intensity: 0.45)
        lightGenerator.prepare()
        #endif
    }

    /// Medium impact feedback for spacebar trackpad mode activation.
    /// Provides a stronger haptic cue when the user activates cursor movement
    /// mode by long-pressing the spacebar (Plan 04 feature).
    public static func trackpadActivated() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
        #endif
    }

    /// Selection tick feedback for each character of cursor movement during trackpad drag.
    /// Uses UISelectionFeedbackGenerator — the same subtle "tick" Apple uses for pickers
    /// and the native cursor. This is the #1 factor for perceived trackpad fluidity.
    /// Called once for each actual character move; category scrubbing keeps its
    /// separate rate limit.
    public static func cursorMoved() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }

    #if canImport(UIKit) && !os(macOS)
    private static func emitKeyTap() {
        guard let intensity = _intensity.keyTapIntensity else { return }
        if _intensity == .snappy {
            keyGenerator.impactOccurred()
        } else {
            keyGenerator.impactOccurred(intensity: CGFloat(intensity))
        }
        keyGenerator.prepare()
    }

    private static func emitSelectionTick() {
        let now = Date()
        guard now.timeIntervalSince(lastSelectionTick) >= minimumSelectionInterval else { return }
        lastSelectionTick = now
        selectionGenerator.selectionChanged()
    }
    #endif
}
