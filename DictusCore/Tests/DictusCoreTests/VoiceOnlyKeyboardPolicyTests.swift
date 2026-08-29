import XCTest
@testable import DictusCore

final class VoiceOnlyKeyboardPolicyTests: XCTestCase {
    func testRightRailFitsWithinVoiceSurfaceHeight() {
        XCTAssertLessThanOrEqual(
            VoiceOnlyKeyboardPolicy.rightRailHeight,
            VoiceOnlyKeyboardPolicy.surfaceHeight
        )
    }

    func testVoiceSurfaceUsesAvailableWidthAndCentersMicBetweenEqualRails() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 430)

        XCTAssertEqual(layout.surfaceWidth, 430)
        XCTAssertEqual(layout.leftRailWidth, layout.rightRailWidth)
        XCTAssertEqual(layout.centerX, 215)
    }

    func testVoiceOnlySurfaceDoesNotUseLegacyKeyGrid() {
        XCTAssertFalse(VoiceOnlyKeyboardPolicy.usesLegacyKeyGrid)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.surfaceHeight, 220)
    }

    func testVoiceOnlyRailUsesAppleKeyboardVerticalInsets() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.verticalPadding, 16)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.leftRailVerticalPadding, 8)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.rightRailHeight, VoiceOnlyKeyboardPolicy.surfaceHeight)
    }

    func testVoiceOnlySurfaceUsesReferenceHorizontalInsetAndControlGeometry() {
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.horizontalPadding, 10)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.controlSize, 44)
        XCTAssertEqual(VoiceOnlyKeyboardPolicy.railSpacing, 4)
    }

    func testVoiceSurfaceCentersMicWithinAreaBetweenRails() {
        let layout = VoiceOnlyKeyboardPolicy.layout(for: 430)

        XCTAssertEqual(layout.centerX, 215)
        XCTAssertEqual(
            layout.centerX,
            10 + layout.leftRailWidth
                + (430 - 20 - layout.leftRailWidth - layout.rightRailWidth) / 2
        )
    }

    func testVoiceOnlyActionMappingUsesExistingCommands() {
        XCTAssertEqual(KeyboardCommand.delete.proxyAction, .deleteBackward)
        XCTAssertEqual(KeyboardCommand.returnKey.proxyAction, .insertText("\n"))
        XCTAssertEqual(KeyboardCommand.at.proxyAction, .insertText("@"))
    }
}
