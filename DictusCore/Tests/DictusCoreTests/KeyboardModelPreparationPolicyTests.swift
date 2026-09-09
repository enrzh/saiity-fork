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
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: true,
                modelLoadState: .loading,
                appPhase: .active,
                modelLoadStartedAt: now.addingTimeInterval(-1),
                now: now
            )
        )
    }

    func testMissingLoadingTimestampDoesNotLeaveTheKeyboardBlocked() {
        XCTAssertFalse(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: true,
                modelLoadState: .loading,
                appPhase: .background
            )
        )
    }

    func testExpiredLoadingTimestampDoesNotLeaveTheKeyboardBlocked() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(
            KeyboardModelPreparationPolicy.shouldOpenApp(
                modelReady: true,
                modelLoadState: .loading,
                appPhase: .background,
                modelLoadStartedAt: now.addingTimeInterval(-KeyboardModelPreparationPolicy.maximumLoadingAge - 1),
                now: now
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
