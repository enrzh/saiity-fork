import Foundation

public enum PolishExecutionError: String, Error, LocalizedError, Sendable {
    case timedOut, inferenceStillRunning, outputTruncated, contextExceeded

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "Cleanup took too long."
        case .inferenceStillRunning: return "The previous cleanup is still finishing. Try again in a moment."
        case .outputTruncated: return "Cleanup returned incomplete text."
        case .contextExceeded: return "This transcript is too long for cleanup."
        }
    }
}

/// One budget covers all sequential spans. Eight seconds is a conservative
/// safety ceiling, not a measured phone latency target; tune from runtime data.
public struct PolishDeadline: Sendable {
    public let instant: ContinuousClock.Instant
    public init(timeout: Duration = .seconds(8)) {
        instant = ContinuousClock.now.advanced(by: timeout)
    }
}

/// Return promptly even if an SDK ignores cancellation. Retain ownership until
/// that SDK actually exits so a new request cannot start overlapping inference.
public actor PolishExecution {
    public static let shared = PolishExecution()
    private var activeID: UUID?
    private var continuation: CheckedContinuation<String, Error>?
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { activeID != nil }

    public func run(deadline: PolishDeadline,
                    operation: @escaping @Sendable () async throws -> String) async throws -> String {
        try Task.checkCancellation()
        guard activeID == nil else { throw PolishExecutionError.inferenceStillRunning }
        guard deadline.instant > .now else { throw PolishExecutionError.timedOut }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeID = id
                self.continuation = continuation
                let hints = DictationVocabulary.currentHints
                worker = Task.detached(priority: Task.currentPriority) {
                    do {
                        let value = try await DictationVocabulary.$currentHints.withValue(hints) { try await operation() }
                        await self.finish(id: id, result: .success(value))
                    }
                    catch { await self.finish(id: id, result: .failure(error)) }
                }
                timer = Task {
                    do {
                        try await ContinuousClock().sleep(until: deadline.instant)
                        abort(id: id, error: PolishExecutionError.timedOut)
                    } catch { /* The operation finished or was cancelled. */ }
                }
            }
        } onCancel: {
            Task { await self.abort(id: id, error: CancellationError()) }
        }
    }

    private func abort(id: UUID, error: Error) {
        guard activeID == id else { return }
        let pending = continuation
        continuation = nil
        worker?.cancel()
        timer?.cancel()
        pending?.resume(throwing: error)
    }

    private func finish(id: UUID, result: Result<String, Error>) {
        guard activeID == id else { return }
        let pending = continuation
        continuation = nil
        timer?.cancel()
        timer = nil
        worker = nil
        activeID = nil
        pending?.resume(with: result)
    }
}
