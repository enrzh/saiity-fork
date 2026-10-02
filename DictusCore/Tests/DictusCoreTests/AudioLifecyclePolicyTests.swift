import XCTest
@testable import DictusCore

final class AudioLifecyclePolicyTests: XCTestCase {
    func testAutomaticStandbyDoesNotAskForPermissionOrRunBeforeSetup() {
        XCTAssertTrue(AudioLifecyclePolicy.shouldRestoreStandby(serviceEnabled: true,
            onboardingComplete: true, microphoneGranted: true))
        for values in [(false, true, true), (true, false, true), (true, true, false)] {
            XCTAssertFalse(AudioLifecyclePolicy.shouldRestoreStandby(serviceEnabled: values.0,
                onboardingComplete: values.1, microphoneGranted: values.2))
        }
    }
    func testStatePrioritizesRecordingOverOtherFacts() {
        XCTAssertEqual(
            AudioLifecyclePolicy.state(engineRunning: true, sessionConfigured: true, isRecording: true),
            .recording
        )
    }

    func testStateDistinguishesWarmConfiguredAndColdResources() {
        XCTAssertEqual(
            AudioLifecyclePolicy.state(engineRunning: true, sessionConfigured: true, isRecording: false),
            .warmIdle
        )
        XCTAssertEqual(
            AudioLifecyclePolicy.state(engineRunning: false, sessionConfigured: true, isRecording: false),
            .configuredIdle
        )
        XCTAssertEqual(
            AudioLifecyclePolicy.state(engineRunning: false, sessionConfigured: false, isRecording: false),
            .cold
        )
    }

    func testOnlyIdleStatesMayBeDeactivated() {
        XCTAssertFalse(AudioLifecyclePolicy.canDeactivate(.cold))
        XCTAssertFalse(AudioLifecyclePolicy.canDeactivate(.recording))
        XCTAssertTrue(AudioLifecyclePolicy.canDeactivate(.configuredIdle))
        XCTAssertTrue(AudioLifecyclePolicy.canDeactivate(.warmIdle))
    }
}
