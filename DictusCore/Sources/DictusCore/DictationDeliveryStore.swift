import Foundation

/// Writes a finished dictation into the App Group the keyboard reads.
///
/// History retention stays inside `RecentDictations`. This store does not
/// clear a pending delivery when the history preference changes.
public enum DictationDeliveryStore {
    public static func publishReady(
        text: String,
        request: DictationLanguageRequest,
        to defaults: UserDefaults
    ) {
        defaults.set(text, forKey: SharedKeys.lastTranscription)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
        RecentDictations.append(text, in: defaults)
        DictationDelivery.publish(text, for: request, to: defaults)
        defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
    }
}
