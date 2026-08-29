import XCTest
@testable import DictusCore

final class DictationStatusTests: XCTestCase {
    func testInsertionAcknowledgementIsRequiredBeforeCompletionLabel() {
        XCTAssertEqual(
            HomeRecordingPresentation(status: .processing, insertionAcknowledged: false).label,
            "Processing"
        )
        XCTAssertEqual(
            HomeRecordingPresentation(status: .processing, insertionAcknowledged: true).label,
            "Inserted"
        )
    }
}
