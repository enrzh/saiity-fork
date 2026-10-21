import XCTest
@testable import SyllivraKernel

final class DictationReadinessTests: XCTestCase {
    func testModelBeingLoadedDoesNotAskUserToDownloadItAgain() {
        let loading = make(modelReady: false, modelLoadState: .loading)
        XCTAssertEqual(loading.title, "Preparing your model")
        XCTAssertEqual(loading.action, .none)
    }
    func testServiceAndPrerequisiteStatesTakePriority() {
        let disabled = make(serviceEnabled: false, modelReady: true, status: .recording)
        XCTAssertEqual(disabled.title, "Dictation is paused")
        XCTAssertEqual(disabled.action, .none)

        let denied = make(permission: .denied, modelReady: true)
        XCTAssertEqual(denied.action, .openSettings)
        XCTAssertEqual(denied.symbol, "mic.slash")

        let needed = make(permission: .undetermined, modelReady: true)
        XCTAssertEqual(needed.action, .requestMicrophone)

        let missing = make()
        XCTAssertEqual(missing.title, "Download a voice model")
        XCTAssertEqual(missing.action, .none)

        let loading = make(modelReady: true, modelLoadState: .loading)
        XCTAssertEqual(loading.title, "Preparing your model")
        XCTAssertEqual(loading.action, .none)
    }

    func testEveryDictationStatusHasTruthfulPresentation() {
        for status in DictationStatus.allCases {
            let readiness = make(modelReady: true, modelLoadState: .ready, status: status)
            XCTAssertFalse(readiness.title.isEmpty, status.rawValue)
            XCTAssertFalse(readiness.subtitle.isEmpty, status.rawValue)
            XCTAssertFalse(readiness.symbol.isEmpty, status.rawValue)
            if status == .failed {
                XCTAssertEqual(readiness.action, .retry)
            } else if status == .idle || status == .ready {
                XCTAssertEqual(readiness.action, .start)
            } else {
                XCTAssertEqual(readiness.action, .none)
            }
        }
    }

    func testRecordingRemainsVisibleWhileTheModelLoadsInParallel() {
        let readiness = make(modelReady: true, modelLoadState: .loading, status: .recording)
        XCTAssertEqual(readiness.title, "Recording")
        XCTAssertEqual(readiness.action, .none)
    }

    func testModelLoadFailureOffersRecoveryBeforeStart() {
        let readiness = make(
            modelReady: true,
            modelLoadFailure: "The transcription model could not be loaded. Try again."
        )
        XCTAssertEqual(readiness.title, "Dictation needs attention")
        XCTAssertEqual(readiness.subtitle, "The voice model couldn’t be prepared. Choose another compatible model or repair its download.")
        XCTAssertEqual(readiness.action, .models)
    }

    func testModelLoadFailureDoesNotHideAnActiveDictation() {
        let readiness = make(
            modelReady: true,
            status: .recording,
            modelLoadFailure: "The transcription model could not be loaded. Try again."
        )
        XCTAssertEqual(readiness.title, "Recording")
        XCTAssertEqual(readiness.action, .none)
    }

    func testDisabledServiceNeverOffersStartOrRetry() {
        for status in DictationStatus.allCases {
            let readiness = make(serviceEnabled: false, modelReady: true, modelLoadState: .ready, status: status)
            XCTAssertEqual(readiness.action, .none)
            XCTAssertEqual(readiness.title, "Dictation is paused")
        }
    }

    private func make(
        serviceEnabled: Bool = true,
        permission: MicrophonePermissionState = .authorized,
        modelReady: Bool = false,
        modelLoadState: ModelLoadState = .idle,
        status: DictationStatus = .idle,
        modelLoadFailure: String? = nil
    ) -> DictationReadiness {
        DictationReadiness(serviceEnabled: serviceEnabled, microphonePermission: permission,
                           modelReady: modelReady, modelLoadState: modelLoadState, status: status,
                           modelLoadFailure: modelLoadFailure)
    }
}
