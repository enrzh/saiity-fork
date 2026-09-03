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
        let status = KeyboardSetupStatus(keyboardInstalled: true, fullAccessHandshake: true, handshakeDate: Date())

        XCTAssertTrue(status.fullAccessVerified)
        XCTAssertTrue(status.canContinue)
    }

    func testHandshakeProvesKeyboardDuringTransientEmptyInputModeList() {
        let status = KeyboardSetupStatus(keyboardInstalled: false, fullAccessHandshake: true, handshakeDate: Date())

        XCTAssertTrue(status.keyboardDetected)
        XCTAssertTrue(status.fullAccessVerified)
        XCTAssertTrue(status.canContinue)
    }

    func testOldHandshakeStillVerifiesFullAccessWhenKeyboardIsInstalled() {
        let status = KeyboardSetupStatus(
            keyboardInstalled: true,
            fullAccessHandshake: true,
            handshakeDate: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(status.fullAccessVerified)
        XCTAssertTrue(status.canContinue)
    }

    func testInputModeIdentityDoesNotConfuseNativeEnglishWithDictus() {
        XCTAssertTrue(
            KeyboardSetupStatus.isDictusKeyboardIdentifier("de.aiity.saiity.ios.keyboard")
        )
        XCTAssertFalse(
            KeyboardSetupStatus.isDictusKeyboardIdentifier("com.apple.keyboards.en_US")
        )
        XCTAssertFalse(
            KeyboardSetupStatus.isDictusKeyboardIdentifier("com.example.de.aiity.saiity.ios.fake")
        )
        XCTAssertFalse(KeyboardSetupStatus.isDictusKeyboardIdentifier(nil))
    }
}
