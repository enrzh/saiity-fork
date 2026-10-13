import XCTest
@testable import SyllivraKernel

final class KeyboardShiftStateTests: XCTestCase {
    func testDoubleTapWindowMatchesANativeCapsLockGesture() {
        XCTAssertEqual(KeyboardShiftState.doubleTapWindow, 0.5, accuracy: 0.0001)
    }

    func testFirstTapEntersTemporaryShift() {
        XCTAssertEqual(
            KeyboardShiftState.normal.state(afterTapIsWithinDoubleTapWindow: false),
            .shifted
        )
    }

    func testSecondTapWithinWindowEntersCapsLock() {
        XCTAssertEqual(
            KeyboardShiftState.shifted.state(afterTapIsWithinDoubleTapWindow: true),
            .capsLock
        )
    }

    func testSecondTapOutsideWindowLeavesTemporaryShift() {
        XCTAssertEqual(
            KeyboardShiftState.shifted.state(afterTapIsWithinDoubleTapWindow: false),
            .normal
        )
    }

    func testEveryTapOnCapsLockTurnsItOff() {
        XCTAssertEqual(
            KeyboardShiftState.capsLock.state(afterTapIsWithinDoubleTapWindow: true),
            .normal
        )
        XCTAssertEqual(
            KeyboardShiftState.capsLock.state(afterTapIsWithinDoubleTapWindow: false),
            .normal
        )
    }
}
