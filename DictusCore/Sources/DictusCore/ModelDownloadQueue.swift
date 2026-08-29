import Foundation

/// FIFO ownership for model download operations.
///
/// The manager keeps the active slot until download and model preparation finish,
/// so a queued request cannot start work before the preceding request is done.
public struct ModelDownloadQueue: Equatable, Sendable {
    public enum Request: Equatable, Sendable {
        case started
        case queued
        case alreadyActive
        case alreadyQueued
    }

    public enum CompletionResult: Equatable, Sendable {
        case succeeded
        case cancelled
        case failed(String)
    }

    public enum FinalState: Equatable, Sendable {
        case ready
        case notDownloaded
        case error(String)
    }

    public struct Completion: Equatable, Sendable {
        public let finalState: FinalState
        public let nextIdentifier: String?

        public init(finalState: FinalState, nextIdentifier: String?) {
            self.finalState = finalState
            self.nextIdentifier = nextIdentifier
        }
    }

    public private(set) var activeIdentifier: String?
    public private(set) var queuedIdentifiers: [String] = []

    public init() { }

    public mutating func request(_ identifier: String) -> Request {
        if activeIdentifier == identifier {
            return .alreadyActive
        }
        if queuedIdentifiers.contains(identifier) {
            return .alreadyQueued
        }
        if activeIdentifier == nil && queuedIdentifiers.isEmpty {
            activeIdentifier = identifier
            return .started
        }
        queuedIdentifiers.append(identifier)
        return .queued
    }

    /// Releases the active identifier, projects its final state, and reserves
    /// the next FIFO request.
    @discardableResult
    public mutating func complete(
        _ identifier: String,
        result: CompletionResult
    ) -> Completion? {
        guard activeIdentifier == identifier else { return nil }
        let finalState: FinalState
        switch result {
        case .succeeded:
            finalState = .ready
        case .cancelled:
            finalState = .notDownloaded
        case .failed(let message):
            finalState = .error(message)
        }
        activeIdentifier = queuedIdentifiers.isEmpty ? nil : queuedIdentifiers.removeFirst()
        return Completion(finalState: finalState, nextIdentifier: activeIdentifier)
    }

    /// Removes a queued request. An active request is released only by `finish`
    /// after its manager-owned task has completed cleanup.
    @discardableResult
    public mutating func cancel(_ identifier: String) -> Bool {
        guard activeIdentifier != identifier else { return false }
        let count = queuedIdentifiers.count
        queuedIdentifiers.removeAll { $0 == identifier }
        return queuedIdentifiers.count != count
    }
}
