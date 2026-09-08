import XCTest
@testable import DictusCore

final class KeyboardModelPreparationPolicyTests: XCTestCase {
    func testBackgroundIdleReadyModelKeepsDictationAvailable() {
        XCTAssertFalse(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: true,
                modelLoadState: .idle,
                appPhase: .background
            )
        )
    }

    func testLoadingModelOpensPreparationSurfaceEvenWhenPhaseIsActive() {
        XCTAssertTrue(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: true,
                modelLoadState: .loading,
                appPhase: .active
            )
        )
    }

    func testReadyModelInBackgroundKeepsDictationAvailable() {
        XCTAssertFalse(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: true,
                modelLoadState: .ready,
                appPhase: .active
            )
        )

        XCTAssertFalse(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: true,
                modelLoadState: .ready,
                appPhase: .background
            )
        )
    }

    func testMissingModelInBackgroundStillOpensDictus() {
        XCTAssertTrue(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: false,
                modelLoadState: .idle,
                appPhase: .background
            )
        )
    }

    func testUnknownPhaseDoesNotOverrideModelReadiness() {
        XCTAssertFalse(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: true,
                modelLoadState: .ready,
                appPhase: .unknown
            )
        )

        XCTAssertTrue(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: false,
                modelLoadState: .idle,
                appPhase: .unknown
            )
        )
    }
}
