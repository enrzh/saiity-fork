import XCTest
@testable import DictusCore

final class PolishExecutionTests: XCTestCase {
    private static func blockingSDKCall() -> String {
        Thread.sleep(forTimeInterval: 0.2)
        return "late"
    }

    func testDeadlineIsNotBlockedBySynchronousSDKWork() async throws {
        let gate = PolishExecution()
        do {
            _ = try await gate.run(deadline: PolishDeadline(timeout: .milliseconds(30))) {
                Self.blockingSDKCall()
            }
            XCTFail("Expected timeout while the SDK still owns its worker")
        } catch { XCTAssertEqual(error as? PolishExecutionError, .timedOut) }
        for _ in 0..<200 {
            if await !gate.isRunning { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("SDK did not release inference ownership")
    }
    func testTimeoutReturnsWithoutWaitingForNoncooperativeInference() async throws {
        let gate = PolishExecution()
        let blocked = AsyncStream<String>.makeStream()
        let started = expectation(description: "inference started")
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await gate.run(deadline: PolishDeadline(timeout: .milliseconds(30))) {
                started.fulfill()
                // This deliberately ignores cancellation, like a slow SDK call.
                return await withCheckedContinuation { continuation in
                    Task.detached {
                        for await value in blocked.stream { continuation.resume(returning: value); break }
                    }
                }
            }
            XCTFail("Expected deadline")
        } catch { XCTAssertEqual(error as? PolishExecutionError, .timedOut) }
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
        await fulfillment(of: [started], timeout: 1)
        do {
            _ = try await gate.run(deadline: PolishDeadline()) { XCTFail("Must not overlap"); return "new" }
            XCTFail("Expected retained inference ownership")
        } catch { XCTAssertEqual(error as? PolishExecutionError, .inferenceStillRunning) }
        blocked.continuation.yield("discarded stale output")
        blocked.continuation.finish()
        // Wait for ownership to clear, bounded by the test deadline.
        for _ in 0..<100 {
            do {
                let value = try await gate.run(deadline: PolishDeadline()) { "fresh" }
                XCTAssertEqual(value, "fresh")
                return
            } catch { try await Task.sleep(for: .milliseconds(2)) }
        }
        XCTFail("Inference ownership did not clear")
    }

    func testParentCancellationReachesEngineAndReturnsPromptly() async throws {
        let gate = PolishExecution()
        let started = expectation(description: "engine started")
        let cancelled = expectation(description: "engine cancelled")
        let task = Task {
            try await gate.run(deadline: PolishDeadline()) {
                started.fulfill()
                do { try await Task.sleep(for: .seconds(30)); return "late" }
                catch { cancelled.fulfill(); throw error }
            }
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testExpiredSharedBudgetNeverStartsAnotherSpan() async {
        let gate = PolishExecution()
        do {
            _ = try await gate.run(deadline: PolishDeadline(timeout: .zero)) {
                XCTFail("Expired session budget must skip inference")
                return ""
            }
            XCTFail("Expected deadline")
        } catch { XCTAssertEqual(error as? PolishExecutionError, .timedOut) }
    }
}
