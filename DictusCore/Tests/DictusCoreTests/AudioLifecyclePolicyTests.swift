import XCTest
@testable import DictusCore

final class AudioLifecyclePolicyTests: XCTestCase {
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
