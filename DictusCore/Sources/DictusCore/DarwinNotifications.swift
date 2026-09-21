// DictusCore/Sources/DictusCore/DarwinNotifications.swift
import Foundation

/// Darwin notification names for cross-process signaling.
/// Darwin notifications carry no payload — they are ping-only.
/// After receiving a notification, read the actual data from AppGroup.defaults.
public enum DarwinNotificationName {
    /// Posted by the keyboard extension after publishing its current Full Access handshake.
    public static let keyboardFullAccessChanged = "de.aiity.saiity.keyboardFullAccessChanged" as CFString

    /// Posted by DictusApp when transcription result is written to App Group.
    public static let transcriptionReady = "de.aiity.saiity.transcriptionReady" as CFString

    /// Posted by DictusApp when dictation status changes.
    public static let statusChanged = "de.aiity.saiity.statusChanged" as CFString

    /// Posted by keyboard extension to request DictusApp stop recording (keyboard -> app).
    public static let stopRecording = "de.aiity.saiity.stopRecording" as CFString

    /// Posted by keyboard extension to request DictusApp cancel recording (keyboard -> app).
    public static let cancelRecording = "de.aiity.saiity.cancelRecording" as CFString

    /// Posted by DictusApp when waveform energy data is written to App Group (app -> keyboard).
    public static let waveformUpdate = "de.aiity.saiity.waveformUpdate" as CFString

    /// Posted by keyboard extension to request DictusApp start recording (keyboard -> app).
    /// Used when the app is already running in background — avoids opening the app via URL.
    /// Fallback: if app doesn't respond within 500ms, keyboard opens saiity://dictate URL.
    public static let startRecording = "de.aiity.saiity.startRecording" as CFString

    /// Posted by DictusApp when AVAudioSession is interrupted (phone call, Siri, etc.)
    /// or when media services were reset by the OS. Consumers tear down dependent
    /// state — Live Activity ends, in-flight transcription is cancelled, the keyboard
    /// can show a "session interrupted" indicator if desired (issue #106).
    public static let audioSessionInterrupted = "de.aiity.saiity.audioSessionInterrupted" as CFString

    /// Posted by DictusApp when the warm-state engine is released after the idle
    /// timeout (issue #106 Phase B). Consumers should treat the next dictation
    /// request as a cold start. Used to dismiss the Dynamic Island standby indicator
    /// so the UI no longer suggests "ready to dictate" when the engine is asleep.
    public static let warmStateReleased = "de.aiity.saiity.warmStateReleased" as CFString

    /// Posted by DictusApp when the persisted model-on-disk or model-in-RAM state
    /// changes. The keyboard re-reads both shared values after receiving it.
    public static let modelReadinessChanged = "de.aiity.saiity.modelReadinessChanged" as CFString

    /// Posted by DictusApp when keyboard interaction preferences change
    /// (key popups, material). The keyboard re-reads App Group defaults.
    public static let keyboardPreferencesChanged = "de.aiity.saiity.keyboardPreferencesChanged" as CFString

    /// Posted by the keyboard after it writes `serviceEnabled`. DictusApp applies
    /// the same enable or disable path as the Home Screen toggle.
    public static let serviceToggleRequested = "de.aiity.saiity.serviceToggleRequested" as CFString
}

/// Global callback registry for Darwin notifications.
/// Must be at module level because CFNotificationCenter callbacks are C function pointers
/// that cannot capture Swift context. The registry is thread-safe via NSLock.
private let _darwinCallbackLock = NSLock()
private var _darwinCallbacks: [String: [() -> Void]] = [:]

private let _darwinCallback: CFNotificationCallback = { _, _, cfName, _, _ in
    guard let cfName = cfName else { return }
    let key = cfName.rawValue as String
    _darwinCallbackLock.lock()
    let callbacks = _darwinCallbacks[key] ?? []
    _darwinCallbackLock.unlock()
    callbacks.forEach { $0() }
}

/// Helper to post and observe Darwin notifications.
/// Thread safety: `_darwinCallbacks` is protected by `_darwinCallbackLock`.
public enum DarwinNotificationCenter {

    public static func post(_ name: CFString) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil, nil, true
        )
    }

    public static func addObserver(
        for name: CFString,
        callback: @escaping () -> Void
    ) {
        let key = name as String
        _darwinCallbackLock.lock()
        let existing = _darwinCallbacks[key] ?? []
        _darwinCallbacks[key] = existing + [callback]
        let shouldRegister = existing.isEmpty
        _darwinCallbackLock.unlock()

        guard shouldRegister else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            _darwinCallback,
            name,
            nil,
            .deliverImmediately
        )
    }

    public static func removeObserver(for name: CFString) {
        let key = name as String
        _darwinCallbackLock.lock()
        var callbacks = _darwinCallbacks[key] ?? []
        if !callbacks.isEmpty {
            callbacks.removeFirst()
        }
        if callbacks.isEmpty {
            _darwinCallbacks.removeValue(forKey: key)
        } else {
            _darwinCallbacks[key] = callbacks
        }
        let shouldUnregister = callbacks.isEmpty
        _darwinCallbackLock.unlock()

        guard shouldUnregister else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            CFNotificationName(name),
            nil
        )
    }

    public static func removeAllObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        _darwinCallbackLock.lock()
        let names = Array(_darwinCallbacks.keys)
        _darwinCallbacks.removeAll()
        _darwinCallbackLock.unlock()

        for name in names {
            CFNotificationCenterRemoveObserver(
                center,
                nil,
                CFNotificationName(name as CFString),
                nil
            )
        }
    }
}
