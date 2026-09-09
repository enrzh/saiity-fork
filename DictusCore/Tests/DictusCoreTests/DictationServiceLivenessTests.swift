import XCTest
@testable import DictusCore

final class DictationServiceLivenessTests: XCTestCase {
    private let now: TimeInterval = 10_000

    func testDisabledServiceAlwaysRequiresApp() {
        XCTAssertTrue(
            DictationServiceLivenessPolicy.shouldOpenApp(
                serviceEnabled: false,
                appProcessHeartbeat: now,
                liveActivityPresent: true,
                now: now
            )
        )
    }

    func testFreshAppProcessIsAvailableWithoutLiveActivity() {
        XCTAssertFalse(
            DictationServiceLivenessPolicy.shouldOpenApp(
                serviceEnabled: true,
                appProcessHeartbeat: now - 1,
                liveActivityPresent: false,
                now: now
            )
        )
    }

    func testStaleAppProcessWithoutLiveActivityRequiresApp() {
        XCTAssertTrue(
            DictationServiceLivenessPolicy.shouldOpenApp(
                serviceEnabled: true,
                appProcessHeartbeat: now - DictationServiceLivenessPolicy.maximumAppHeartbeatAge - 1,
                liveActivityPresent: false,
                now: now
            )
        )
    }

    func testLiveActivityKeepsServiceAvailableAfterProcessHeartbeatGoesStale() {
        XCTAssertFalse(
            DictationServiceLivenessPolicy.shouldOpenApp(
                serviceEnabled: true,
                appProcessHeartbeat: now - DictationServiceLivenessPolicy.maximumAppHeartbeatAge - 1,
                liveActivityPresent: true,
                liveActivityUpdatedAt: now - 1,
                now: now
            )
        )
    }

    func testUnconfirmedLiveActivityDoesNotHideStaleService() {
        XCTAssertTrue(
            DictationServiceLivenessPolicy.shouldOpenApp(
                serviceEnabled: true,
                appProcessHeartbeat: now - DictationServiceLivenessPolicy.maximumAppHeartbeatAge - 1,
                liveActivityPresent: true,
                now: now
            )
        )
    }

    func testStaleLiveActivityRequiresApp() {
        XCTAssertTrue(
            DictationServiceLivenessPolicy.shouldOpenApp(
                serviceEnabled: true,
                appProcessHeartbeat: now - DictationServiceLivenessPolicy.maximumAppHeartbeatAge - 1,
                liveActivityPresent: true,
                liveActivityUpdatedAt: now - DictationServiceLivenessPolicy.maximumLiveActivityAge - 1,
                now: now
            )
        )
    }

    func testMissingSignalsRequireApp() {
        XCTAssertTrue(
            DictationServiceLivenessPolicy.shouldOpenApp(
                serviceEnabled: true,
                appProcessHeartbeat: nil,
                liveActivityPresent: false,
                now: now
            )
        )
    }

    func testProbePersistsProcessAndActivitySignals() throws {
        let suiteName = "dictus.tests.serviceLiveness"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let date = Date(timeIntervalSince1970: now)
        DictationServiceLivenessProbe.recordAppHeartbeat(at: date, into: defaults)
        DictationServiceLivenessProbe.recordLiveActivity(
            present: true,
            identifier: "activity-1",
            at: date,
            into: defaults
        )

        XCTAssertEqual(defaults.double(forKey: SharedKeys.appProcessHeartbeat), now)
        XCTAssertTrue(defaults.bool(forKey: SharedKeys.liveActivityPresent))
        XCTAssertEqual(defaults.double(forKey: SharedKeys.liveActivityUpdatedAt), now, accuracy: 0.001)
        XCTAssertEqual(defaults.string(forKey: SharedKeys.liveActivityID), "activity-1")

        DictationServiceLivenessProbe.recordLiveActivity(present: false, into: defaults)
        XCTAssertFalse(defaults.bool(forKey: SharedKeys.liveActivityPresent))
        XCTAssertNil(defaults.object(forKey: SharedKeys.liveActivityUpdatedAt))
        XCTAssertNil(defaults.object(forKey: SharedKeys.liveActivityID))
    }
}
