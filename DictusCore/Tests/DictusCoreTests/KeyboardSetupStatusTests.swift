import XCTest
@testable import DictusCore

final class KeyboardSetupStatusTests: XCTestCase {
    func testInstalledKeyboardDoesNotImplyFullAccess() {
        let status = KeyboardSetupStatus(keyboardInstalled: true, fullAccessHandshake: false)

        XCTAssertTrue(status.keyboardInstalled)
        XCTAssertFalse(status.fullAccessVerified)
        XCTAssertFalse(status.canContinue)
    }

    func testFullAccessRequiresAnInstalledKeyboardAndARealHandshake() {
        let status = KeyboardSetupStatus(keyboardInstalled: true, fullAccessHandshake: true)

        XCTAssertTrue(status.fullAccessVerified)
        XCTAssertTrue(status.canContinue)
    }

    func testStaleHandshakeIsIgnoredWhenKeyboardIsNotInstalled() {
        let status = KeyboardSetupStatus(keyboardInstalled: false, fullAccessHandshake: true)

        XCTAssertFalse(status.fullAccessVerified)
        XCTAssertFalse(status.canContinue)
    }
}
