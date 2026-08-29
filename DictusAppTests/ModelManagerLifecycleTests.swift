import XCTest
@testable import DictusApp
import DictusCore

@MainActor
final class ModelManagerLifecycleTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    private actor OperationGate {
        private var continuations: [String: CheckedContinuation<Void, Error>] = [:]
        private var cancelled: Set<String> = []

        func run(_ identifier: String) async throws {
            if cancelled.contains(identifier) {
                throw CancellationError()
            }

            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if cancelled.contains(identifier) {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuations[identifier] = continuation
                    }
                }
            }, onCancel: {
                Task { await self.cancel(identifier) }
            })
        }

        func release(_ identifier: String) {
            continuations.removeValue(forKey: identifier)?.resume()
        }

        func cancel(_ identifier: String) {
            cancelled.insert(identifier)
            continuations.removeValue(forKey: identifier)?.resume(throwing: CancellationError())
        }

        func fail(_ identifier: String, with error: Error) {
            continuations.removeValue(forKey: identifier)?.resume(throwing: error)
        }
    }

    private func waitForState(
        _ manager: ModelManager,
        identifier: String,
        _ expected: ModelState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if manager.modelStates[identifier] == expected {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected \(identifier) to be \(expected), got \(String(describing: manager.modelStates[identifier]))", file: file, line: line)
    }

    func testQueuedRequestAndQueuedCancelUseManagerLifecycle() async {
        let first = ModelInfo.redesignCatalog[0].identifier
        let second = ModelInfo.redesignCatalog[1].identifier
        let gate = OperationGate()
        let manager = ModelManager(downloadOperation: { identifier in
            try await gate.run(identifier)
        })

        let firstTask = Task { @MainActor in try? await manager.downloadModel(first) }
        await waitForState(manager, identifier: first, .downloading)

        let secondTask = Task { @MainActor in
            do {
                try await manager.downloadModel(second)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        await waitForState(manager, identifier: second, .queued)

        manager.cancelDownload(second)
        XCTAssertEqual(manager.modelStates[second], ModelState.notDownloaded)
        let secondWasCancelled = await secondTask.value
        XCTAssertTrue(secondWasCancelled)

        manager.cancelDownload(first)
        _ = await firstTask.value
        await waitForState(manager, identifier: first, .notDownloaded)
    }

    func testActiveSuccessPromotesQueuedRequest() async {
        let first = ModelInfo.redesignCatalog[2].identifier
        let second = ModelInfo.redesignCatalog[3].identifier
        let gate = OperationGate()
        let manager = ModelManager(downloadOperation: { identifier in
            try await gate.run(identifier)
        })

        let firstTask = Task { @MainActor in try? await manager.downloadModel(first) }
        await waitForState(manager, identifier: first, .downloading)
        let secondTask = Task { @MainActor in try? await manager.downloadModel(second) }
        await waitForState(manager, identifier: second, .queued)

        await gate.release(first)
        await waitForState(manager, identifier: first, .ready)
        await waitForState(manager, identifier: second, .downloading)

        await gate.release(second)
        _ = await firstTask.value
        _ = await secondTask.value
        await waitForState(manager, identifier: second, .ready)
    }

    func testActiveCancellationConvergesFromCancellingToNotDownloaded() async {
        let identifier = ModelInfo.redesignCatalog[4].identifier
        let gate = OperationGate()
        let manager = ModelManager(downloadOperation: { model in
            try await gate.run(model)
        })
        let task = Task { @MainActor in try? await manager.downloadModel(identifier) }

        await waitForState(manager, identifier: identifier, .downloading)
        manager.cancelDownload(identifier)
        XCTAssertEqual(manager.modelStates[identifier], ModelState.cancelling)
        _ = await task.value
        await waitForState(manager, identifier: identifier, .notDownloaded)
    }

    func testActiveFailureBecomesErrorAndPromotesQueuedRequest() async {
        let failed = ModelInfo.redesignCatalog[5].identifier
        let next = ModelInfo.redesignCatalog[6].identifier
        let gate = OperationGate()
        let manager = ModelManager(downloadOperation: { identifier in
            if identifier == failed {
                try await gate.run(identifier)
                throw TestError.failed
            }
            try await gate.run(identifier)
        })

        let failedTask = Task { @MainActor in
            do {
                try await manager.downloadModel(failed)
                return false
            } catch {
                return true
            }
        }
        await waitForState(manager, identifier: failed, .downloading)
        let nextTask = Task { @MainActor in try? await manager.downloadModel(next) }
        await waitForState(manager, identifier: next, .queued)

        await gate.fail(failed, with: TestError.failed)
        let failedAsExpected = await failedTask.value
        XCTAssertTrue(failedAsExpected)
        guard case .error = manager.modelStates[failed] else {
            return XCTFail("Expected ordinary failure to produce .error")
        }
        await waitForState(manager, identifier: next, .downloading)
        manager.cancelDownload(next)
        _ = await nextTask.value
        await waitForState(manager, identifier: next, .notDownloaded)
    }
}
