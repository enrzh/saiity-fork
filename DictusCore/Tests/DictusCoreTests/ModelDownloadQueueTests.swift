import XCTest
@testable import DictusCore

final class ModelDownloadQueueTests: XCTestCase {
    func testSecondRequestIsQueuedUntilFirstRequestFinishes() {
        var queue = ModelDownloadQueue()

        XCTAssertEqual(queue.request("first"), .started)
        XCTAssertEqual(queue.request("second"), .queued)
        XCTAssertEqual(queue.activeIdentifier, "first")
        XCTAssertEqual(queue.queuedIdentifiers, ["second"])

        let completion = queue.complete("first", result: .succeeded)
        XCTAssertEqual(completion?.finalState, .ready)
        XCTAssertEqual(completion?.nextIdentifier, "second")
        XCTAssertEqual(queue.activeIdentifier, "second")
        XCTAssertTrue(queue.queuedIdentifiers.isEmpty)
    }

    func testCancellingQueuedRequestRemovesOnlyThatRequest() {
        var queue = ModelDownloadQueue()
        _ = queue.request("first")
        _ = queue.request("second")
        _ = queue.request("third")

        XCTAssertTrue(queue.cancel("second"))
        XCTAssertEqual(queue.activeIdentifier, "first")
        XCTAssertEqual(queue.queuedIdentifiers, ["third"])
    }

    func testFinishingActiveRequestAfterCancellationPromotesNextRequest() {
        var queue = ModelDownloadQueue()
        _ = queue.request("first")
        _ = queue.request("second")

        XCTAssertFalse(queue.cancel("first"))
        let completion = queue.complete("first", result: .cancelled)
        XCTAssertEqual(completion?.finalState, .notDownloaded)
        XCTAssertEqual(completion?.nextIdentifier, "second")
        XCTAssertEqual(queue.activeIdentifier, "second")
        XCTAssertTrue(queue.queuedIdentifiers.isEmpty)
    }

    func testFailedActiveRequestProjectsErrorAndPromotesNextRequest() {
        var queue = ModelDownloadQueue()
        _ = queue.request("first")
        _ = queue.request("second")

        let completion = queue.complete("first", result: .failed("network unavailable"))
        XCTAssertEqual(completion?.finalState, .error("network unavailable"))
        XCTAssertEqual(completion?.nextIdentifier, "second")
        XCTAssertEqual(queue.activeIdentifier, "second")
    }

}
