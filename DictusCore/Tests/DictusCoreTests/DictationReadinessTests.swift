import XCTest
@testable import DictusCore

final class DictationReadinessTests: XCTestCase {
    func testServiceAndPrerequisiteStatesTakePriority() {
        let disabled = make(serviceEnabled: false, modelReady: true, status: .recording)
        XCTAssertEqual(disabled.title, "Dictation service is off")
        XCTAssertEqual(disabled.action, .none)

        let denied = make(permission: .denied, modelReady: true)
        XCTAssertEqual(denied.action, .openSettings)
        XCTAssertEqual(denied.symbol, "mic.slash")

        let needed = make(permission: .undetermined, modelReady: true)
        XCTAssertEqual(needed.action, .requestMicrophone)

        let missing = make()
        XCTAssertEqual(missing.title, "Choose a local model")
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

    func testDisabledServiceNeverOffersStartOrRetry() {
        for status in DictationStatus.allCases {
            let readiness = make(serviceEnabled: false, modelReady: true, modelLoadState: .ready, status: status)
            XCTAssertEqual(readiness.action, .none)
            XCTAssertEqual(readiness.title, "Dictation service is off")
        }
    }

    private func make(
        serviceEnabled: Bool = true,
        permission: MicrophonePermissionState = .authorized,
        modelReady: Bool = false,
        modelLoadState: ModelLoadState = .idle,
        status: DictationStatus = .idle
    ) -> DictationReadiness {
        DictationReadiness(serviceEnabled: serviceEnabled, microphonePermission: permission,
                           modelReady: modelReady, modelLoadState: modelLoadState, status: status)
    }
}
