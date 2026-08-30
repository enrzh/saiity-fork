import XCTest
@testable import DictusCore

final class AccessibilityMotionPolicyTests: XCTestCase {
    func testReducedMotionDisablesCustomAnimations() {
        XCTAssertFalse(AccessibilityMotionPolicy.permitsAnimation(reduceMotion: true))
    }

    func testDefaultMotionAllowsCustomAnimations() {
        XCTAssertTrue(AccessibilityMotionPolicy.permitsAnimation(reduceMotion: false))
    }

    func testReducedMotionUsesNoAnimation() {
        XCTAssertNil(AccessibilityMotionPolicy.animation(reduceMotion: true))
        XCTAssertNotNil(AccessibilityMotionPolicy.animation(reduceMotion: false))
    }
}
