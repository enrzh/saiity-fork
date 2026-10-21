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

    func testRetiredIOSStyleCannotOverrideStoredChoices() {
        let defaults = AppGroup.defaults
        let keys = [SharedKeys.keyboardIOSStyling, SharedKeys.keyboardTopBarEnabled]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        XCTAssertFalse(KeyboardInteractionPreferences.topBarEnabled)
        XCTAssertEqual(KeyboardInteractionPreferences.windowAccessoryHeight, 0)
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .letters), 0)
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .keys), 32)

        defaults.set(true, forKey: SharedKeys.keyboardTopBarEnabled)
        defaults.set(true, forKey: SharedKeys.keyboardIOSStyling)
        XCTAssertTrue(KeyboardInteractionPreferences.topBarEnabled)
        for mode in [KeyboardAreaMode.letters, .panel, .emoji, .numberPad] {
            XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: mode), 32)
        }
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .recording), 32)
        XCTAssertTrue(defaults.bool(forKey: SharedKeys.keyboardTopBarEnabled))

        defaults.set(false, forKey: SharedKeys.keyboardIOSStyling)
        XCTAssertTrue(KeyboardInteractionPreferences.topBarEnabled)
        XCTAssertEqual(KeyboardInteractionPreferences.windowAccessoryHeight, 44)
    }
}
