import Foundation

/// Wire names stay compatible with the installed app, keyboard and widget.
public enum DarwinNotificationName {
    public static let keyboardFullAccessChanged = "de.aiity.saiity.keyboardFullAccessChanged" as CFString
    public static let keyboardFullAccessDenied = "de.aiity.saiity.keyboardFullAccessDenied" as CFString
    public static let keyboardFullAccessProbeRequested = "de.aiity.saiity.keyboardFullAccessProbeRequested" as CFString
    public static let transcriptionReady = "de.aiity.saiity.transcriptionReady" as CFString
    public static let statusChanged = "de.aiity.saiity.statusChanged" as CFString
    public static let stopRecording = "de.aiity.saiity.stopRecording" as CFString
    public static let cancelRecording = "de.aiity.saiity.cancelRecording" as CFString
    public static let waveformUpdate = "de.aiity.saiity.waveformUpdate" as CFString
    public static let startRecording = "de.aiity.saiity.startRecording" as CFString
    public static let audioSessionInterrupted = "de.aiity.saiity.audioSessionInterrupted" as CFString
    public static let warmStateReleased = "de.aiity.saiity.warmStateReleased" as CFString
    public static let modelReadinessChanged = "de.aiity.saiity.modelReadinessChanged" as CFString
    public static let keyboardPreferencesChanged = "de.aiity.saiity.keyboardPreferencesChanged" as CFString
    public static let keyboardVocabularyChanged = "de.aiity.saiity.keyboardVocabularyChanged" as CFString
    public static let serviceToggleRequested = "de.aiity.saiity.serviceToggleRequested" as CFString
}

/// Signals only; callers read the current payload and request identity from shared storage.
public enum DarwinNotificationCenter {
    private static let lock = NSLock()
    private static var subscriptions: [String: (identity: UInt, callbacks: [(token: UInt, action: () -> Void)])] = [:]
    private static var nextIdentity: UInt = 1

    private static let receiver: CFNotificationCallback = { _, observer, name, _, _ in
        guard let observer, let name else { return }
        deliver(name.rawValue as String, identity: UInt(bitPattern: observer))
    }

    private static func deliver(_ name: String, identity: UInt) {
        let callbacks: [() -> Void] = lock.withLock {
            guard let subscription = subscriptions[name], subscription.identity == identity else { return [] }
            return subscription.callbacks.map(\.action)
        }
        for callback in callbacks { callback() }
    }

    public static func post(_ name: CFString) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(name), nil, nil, true)
    }

    @discardableResult
    public static func addObserver(for name: CFString, callback: @escaping () -> Void) -> UInt {
        lock.withLock {
            let key = name as String
            let token = nextIdentity
            nextIdentity &+= 1
            if nextIdentity == 0 { nextIdentity = 1 }
            if var existing = subscriptions[key] {
                existing.callbacks.append((token, callback))
                subscriptions[key] = existing
                return token
            }
            subscriptions[key] = (token, [(token, callback)])
            // CF treats this as an opaque identity; it is never dereferenced.
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                            UnsafeMutableRawPointer(bitPattern: token), receiver,
                                            name, nil, .deliverImmediately)
            return token
        }
    }

    public static func removeObserver(for name: CFString, token: UInt? = nil) {
        let expired: UInt? = lock.withLock {
            let key = name as String
            guard var subscription = subscriptions[key] else { return nil }
            if let token {
                guard let index = subscription.callbacks.firstIndex(where: { $0.token == token }) else { return nil }
                subscription.callbacks.remove(at: index)
            } else {
                subscription.callbacks.removeFirst()
            }
            if subscription.callbacks.isEmpty {
                subscriptions.removeValue(forKey: key)
                return subscription.identity
            }
            subscriptions[key] = subscription
            return nil
        }
        if let expired {
            // A new subscriber gets another identity, so this cannot unregister its listener.
            CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                               UnsafeMutableRawPointer(bitPattern: expired),
                                               CFNotificationName(name), nil)
        }
    }

    public static func removeAllObservers() {
        let expired = lock.withLock {
            let previous = subscriptions
            subscriptions.removeAll()
            return previous
        }
        for (name, subscription) in expired {
            CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                               UnsafeMutableRawPointer(bitPattern: subscription.identity),
                                               CFNotificationName(name as CFString), nil)
        }
    }
}
