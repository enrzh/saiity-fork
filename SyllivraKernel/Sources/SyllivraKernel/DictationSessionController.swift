import Foundation

/// Owns which dictation may still write status, insert text, or move the Live Activity.
///
/// `DictationCoordinator` keeps the audio engine and the published status. This
/// type owns the generation counter and the abandonment check those writes use.
public final class DictationSessionController {
    public private(set) var generation = DictationSessionGeneration()

    public init() {}

    public var current: Int { generation.current }

    public func beginSession() {
        generation.beginSession()
    }

    public func abandonSession() {
        generation.abandonSession()
    }

    public func mayReport(from generation: Int) -> Bool {
        self.generation.mayReport(from: generation)
    }

    public func mayReport(
        from generation: Int,
        request: DictationLanguageRequest,
        currentRequest: DictationLanguageRequest
    ) -> Bool {
        self.generation.mayReport(from: generation, request: request, currentRequest: currentRequest)
    }

    /// Session generation plus the App Group cancel/identity check.
    /// App-originated requests are not cancelled by the keyboard's cancel flag.
    public func mayReportOutcome(
        session: Int,
        what: String,
        cancelRequested: Bool,
        currentRequest: DictationLanguageRequest,
        persistedRequest: DictationLanguageRequest
    ) -> Bool {
        guard generation.mayReport(from: session) else {
            PersistentLog.log(.dictationDeferred(
                reason: "abandoned session dropped \(what) (gen \(session) != \(generation.current))"
            ))
            return false
        }
        if currentRequest.clientIdentifier?.hasPrefix("app-") != true {
            guard !cancelRequested,
                  currentRequest.hasSameIdentity(as: persistedRequest) else {
                return false
            }
        }
        return true
    }
}
