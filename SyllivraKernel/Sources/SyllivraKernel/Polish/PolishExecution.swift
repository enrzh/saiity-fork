import Foundation

public enum PolishExecutionError: String, Error, LocalizedError, Sendable {
    case timedOut, inferenceStillRunning, outputTruncated, contextExceeded, artifactsUnavailable, unsupportedLanguage

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "Processing took too long. Try a smaller model."
        case .inferenceStillRunning: return "The previous model is still finishing. Try again when processing has stopped."
        case .outputTruncated: return "The processing model returned incomplete text."
        case .contextExceeded: return "This transcript is too long for the processing model."
        case .artifactsUnavailable: return "The processing model's files are missing or incomplete. Download or repair it on the Models page."
        case .unsupportedLanguage: return "This model could not safely process this language. Choose a multilingual processing model."
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
