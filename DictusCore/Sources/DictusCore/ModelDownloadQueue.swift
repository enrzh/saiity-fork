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

    /// Releases the active identifier and reserves the next FIFO request.
    @discardableResult
    public mutating func finish(_ identifier: String) -> String? {
        guard activeIdentifier == identifier else { return nil }
        activeIdentifier = queuedIdentifiers.isEmpty ? nil : queuedIdentifiers.removeFirst()
        return activeIdentifier
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
