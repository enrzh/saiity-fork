import Foundation

/// Result of racing one operation against a deadline without waiting for a
/// cancellation-ignoring body to finish.
public enum IsolatedDeadlineResult<T: Sendable>: Sendable {
    case success(T)
    case failure(Error)
    case timedOut(releaseWhenFinished: @Sendable () async -> Void)
    /// The caller was cancelled. The operation is not awaited; `releaseWhenFinished`
    /// completes when that leftover work exits.
    case cancelled(releaseWhenFinished: @Sendable () async -> Void)
}

public enum IsolatedDeadline: Sendable {
    /// The caller resumes when `operation` finishes or `seconds` elapses,
    /// whichever is first. After a timeout the operation keeps running; the
    /// returned closure completes when that leftover work exits. A late success
    /// is not delivered to the caller.
    public static func race<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async -> IsolatedDeadlineResult<T> {
        let gate = DeadlineGate<T>()
        let worker = Task {
            do {
                let value = try await operation()
                await gate.finish(.success(value))
            } catch {
                await gate.finish(.failure(error))
            }
        }
        let timer = Task {
            let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await gate.timeout()
        }
        let outcome = await withTaskCancellationHandler {
            await gate.wait()
        } onCancel: {
            // Detached so a cancelled caller cannot cancel the resume itself.
            Task.detached { await gate.parentCancelled() }
        }
        timer.cancel()
        switch outcome {
        case .success(let value):
            worker.cancel()
            return .success(value)
        case .failure(let error):
            worker.cancel()
            return .failure(error)
        case .timedOut:
            return .timedOut {
                _ = await worker.value
            }
        case .cancelled:
            return .cancelled {
                _ = await worker.value
            }
        }
    }
}

private actor DeadlineGate<T: Sendable> {
    private var continuation: CheckedContinuation<IsolatedDeadlineResult<T>, Never>?
    private var stored: IsolatedDeadlineResult<T>?

    func wait() async -> IsolatedDeadlineResult<T> {
        if let stored { return stored }
        return await withCheckedContinuation { continuation in
            if let stored {
                continuation.resume(returning: stored)
            } else {
                self.continuation = continuation
            }
        }
    }

    func finish(_ result: IsolatedDeadlineResult<T>) {
        resume(result)
    }

    func timeout() {
        resume(.timedOut(releaseWhenFinished: {}))
    }

    func parentCancelled() {
        resume(.cancelled(releaseWhenFinished: {}))
    }

    private func resume(_ result: IsolatedDeadlineResult<T>) {
        guard stored == nil else { return }
        stored = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}
