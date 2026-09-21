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

    func testInputModeIdentityDoesNotConfuseNativeEnglishWithDictus() {
        XCTAssertTrue(
            KeyboardSetupStatus.isDictusKeyboardIdentifier("de.aiity.saiity.ios.keyboard")
        )
        XCTAssertTrue(
            KeyboardSetupStatus.isDictusKeyboardIdentifier("de.aiity.saiity.ios.beta.keyboard")
        )
        XCTAssertFalse(
            KeyboardSetupStatus.isDictusKeyboardIdentifier("com.apple.keyboards.en_US")
        )
        XCTAssertFalse(
            KeyboardSetupStatus.isDictusKeyboardIdentifier("com.example.de.aiity.saiity.ios.fake")
        )
        XCTAssertFalse(KeyboardSetupStatus.isDictusKeyboardIdentifier(nil))
    }

    func testFullAccessHandshakeRequiresTheCurrentProbe() {
        XCTAssertTrue(
            KeyboardSetupStatus.isCurrentFullAccessHandshake(
                verified: true,
                probe: "current",
                acknowledgedProbe: "current"
            )
        )
        XCTAssertFalse(
            KeyboardSetupStatus.isCurrentFullAccessHandshake(
                verified: true,
                probe: "current",
                acknowledgedProbe: "old"
            )
        )
        XCTAssertFalse(
            KeyboardSetupStatus.isCurrentFullAccessHandshake(
                verified: true,
                probe: nil,
                acknowledgedProbe: nil
            )
        )
        XCTAssertFalse(
            KeyboardSetupStatus.isCurrentFullAccessHandshake(
                verified: false,
                probe: "current",
                acknowledgedProbe: "current"
            )
        )
    }
}
