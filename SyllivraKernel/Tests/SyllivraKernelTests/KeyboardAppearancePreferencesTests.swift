import XCTest
@testable import SyllivraKernel

final class KeyboardAppearancePreferencesTests: XCTestCase {
    func testCompactLandscapeKeepsVisibleBottomControlsAndBoardAction() {
        for width in [320.0, 667, 852] {
            for top in [0.0, 32] {
                let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 158,
                    topAccessoryHeight: top, compactChrome: true)
                let controls = [layout.chromeNumbersFrame, layout.chromeLettersFrame,
                                layout.chromeReturnFrame, layout.chromeWideSpaceFrame]
                XCTAssertTrue(controls.allSatisfy { !$0.isEmpty && layout.surfaceFrame.contains($0) })
                XCTAssertTrue(controls.allSatisfy { $0.height == 54 })
                XCTAssertFalse(layout.dictateFrame.isEmpty)
                XCTAssertFalse(layout.dictationServiceToggleFrame.isEmpty)
            }
        }
    }

    func testOnlyTheDictationBoardHasATopLane() {
        for mode in [KeyboardAreaMode.letters, .panel, .emoji, .numberPad] {
            XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: mode), 0)
        }
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .keys), 32)
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .recording), 32)
    }

    func testFlashModePreservesChoiceWithoutAnEnlargedPreview() throws {
        let suite = "key-flash-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        KeyPopupMode.flash.persist(to: defaults)
        XCTAssertEqual(KeyPopupMode.load(from: defaults), .flash)
        XCTAssertEqual(KeyPopupMode.flash.displayName, "Key flash")
        XCTAssertFalse(KeyPopupMode.flash.showsPreview)
        XCTAssertFalse(defaults.bool(forKey: SharedKeys.keyPopupsEnabled))
        XCTAssertTrue(KeyPopupMode.popup.showsPreview)
        XCTAssertTrue(KeyPopupMode.popout.showsPreview)
    }
}
