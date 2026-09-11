import XCTest
@testable import DictusCore

final class KeyboardShiftStateTests: XCTestCase {
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
