import XCTest
@testable import DictusCore

final class ModelDownloadQueueTests: XCTestCase {
    func testSecondRequestIsQueuedUntilFirstRequestFinishes() {
        var queue = ModelDownloadQueue()

        XCTAssertEqual(queue.request("first"), .started)
        XCTAssertEqual(queue.request("second"), .queued)
        XCTAssertEqual(queue.activeIdentifier, "first")
        XCTAssertEqual(queue.queuedIdentifiers, ["second"])

        XCTAssertEqual(queue.finish("first"), "second")
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
        XCTAssertEqual(queue.finish("first"), "second")
        XCTAssertEqual(queue.activeIdentifier, "second")
        XCTAssertTrue(queue.queuedIdentifiers.isEmpty)
    }

}
