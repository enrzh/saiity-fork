import Foundation

/// Can be signalled immediately while an inference actor is executing synchronously.
public final class InferenceCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public var isCancelled: Bool { lock.withLock { cancelled } }
    public func cancel() { lock.withLock { cancelled = true } }
    public func check() throws {
        if isCancelled || Task.isCancelled { throw CancellationError() }
    }
}
