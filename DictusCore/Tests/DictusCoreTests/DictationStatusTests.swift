import XCTest
@testable import DictusCore

final class DictationStatusTests: XCTestCase {
    func testRecordingStatusUsesTruthfulLabelsWithoutInsertionAck() {
        XCTAssertEqual(DictationStatus.idle.recordingLabel, "Ready")
        XCTAssertEqual(DictationStatus.ready.recordingLabel, "Ready")
        XCTAssertEqual(DictationStatus.recording.recordingLabel, "Listening")
        XCTAssertEqual(DictationStatus.transcribing.recordingLabel, "Preparing your text")
        XCTAssertEqual(DictationStatus.processing.recordingLabel, "Finishing your text")
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

    /// The cancel-versus-dictate decision used to be spelled out inline in three
    /// places and drifted between them. Pin the single definition.
    func testCancellationStageIsExactlyTheThreeCancellablePhases() {
        let cancellable: Set<DictationStatus> = [.requested, .transcribing, .processing]
        for status in DictationStatus.allCases {
            XCTAssertEqual(
                status.isCancellationStage,
                cancellable.contains(status),
                "\(status.rawValue) disagreed about being a cancellation stage"
            )
        }
    }

    /// A live session must never be displaced by the recovery control, so the
    /// phases that own the keyboard area are exactly the ones that keep the
    /// dictate control. `showsRecoveryAction` gates on this, so pin the overlap.
    func testPhasesThatOwnTheKeyboardAreaKeepTheDictateControl() {
        for status in DictationStatus.allCases where status.ownsKeyboardArea {
            XCTAssertTrue(
                status == .requested || status == .recording,
                "\(status.rawValue) unexpectedly owns the keyboard area"
            )
        }
        XCTAssertTrue(DictationStatus.requested.ownsKeyboardArea)
        XCTAssertTrue(DictationStatus.recording.ownsKeyboardArea)
    }
}
