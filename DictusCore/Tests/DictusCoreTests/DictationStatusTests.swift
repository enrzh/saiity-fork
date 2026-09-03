import XCTest
@testable import DictusCore

final class DictationStatusTests: XCTestCase {
    func testRecordingStatusUsesTruthfulLabelsWithoutInsertionAck() {
        XCTAssertEqual(DictationStatus.idle.recordingLabel, "Ready")
        XCTAssertEqual(DictationStatus.ready.recordingLabel, "Ready")
        XCTAssertEqual(DictationStatus.processing.recordingLabel, "Processing")
        XCTAssertNotEqual(DictationStatus.ready.recordingLabel, "Inserted")
    }

    func testMicrophonePermissionStateExposesRecoverableFailures() {
        XCTAssertTrue(MicrophonePermissionState.authorized.isAuthorized)
        XCTAssertFalse(MicrophonePermissionState.denied.isAuthorized)
        XCTAssertFalse(MicrophonePermissionState.restricted.isAuthorized)
        XCTAssertFalse(MicrophonePermissionState.undetermined.isAuthorized)
        XCTAssertEqual(
            MicrophonePermissionState.denied.recoveryMessage,
            "Microphone access is off. Enable it in Settings."
        )
        XCTAssertEqual(
            MicrophonePermissionState.restricted.recoveryMessage,
            "Microphone access is restricted. Check device restrictions."
        )
    }

    func testTranslationAndInsertionRemainBeforeAcknowledgement() {
        XCTAssertFalse(DictationStatus.processing.ownsKeyboardArea)
        XCTAssertFalse(DictationStatus.ready.ownsKeyboardArea)
    }
}
