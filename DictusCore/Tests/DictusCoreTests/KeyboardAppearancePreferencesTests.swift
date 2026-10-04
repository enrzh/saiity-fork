import XCTest
@testable import DictusCore

final class KeyboardAppearancePreferencesTests: XCTestCase {
    func testCompactLandscapeKeepsVisibleBottomControlsAndBoardAction() {
        for width in [320.0, 667, 852] {
            for top in [0.0, 32] {
                let layout = VoiceOnlyKeyboardPolicy.layout(for: width, surfaceHeight: 158,
                    topAccessoryHeight: top, compactChrome: true)
                let controls = [layout.chromeNumbersFrame, layout.chromeLettersFrame,
                                layout.chromeReturnFrame, layout.chromeWideSpaceFrame]
                XCTAssertTrue(controls.allSatisfy { !$0.isEmpty && layout.surfaceFrame.contains($0) })
                XCTAssertTrue(controls.allSatisfy { $0.height == 53 })
                XCTAssertFalse(layout.dictateFrame.isEmpty)
                XCTAssertFalse(layout.dictationServiceToggleFrame.isEmpty)
            }
        }
    }

    func testIOSStyleOverridesAreReversibleAndLeaveStoredChoicesIntact() {
        let defaults = AppGroup.defaults
        let keys = [SharedKeys.keyboardIOSStyling, SharedKeys.keyboardTopBarEnabled,
                    SharedKeys.keyboardInsetEnabled, SharedKeys.keyContainersEnabled,
                    SharedKeys.liquidGlassEnabled]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        XCTAssertFalse(KeyboardInteractionPreferences.usesIOSStyling)
        XCTAssertFalse(KeyboardInteractionPreferences.topBarEnabled)
        XCTAssertEqual(KeyboardInteractionPreferences.windowAccessoryHeight, 12)
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .letters), 0)
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .keys), 32)

        defaults.set(true, forKey: SharedKeys.keyboardTopBarEnabled)
        defaults.set(false, forKey: SharedKeys.keyboardInsetEnabled)
        defaults.set(false, forKey: SharedKeys.keyContainersEnabled)
        defaults.set(true, forKey: SharedKeys.liquidGlassEnabled)
        defaults.set(true, forKey: SharedKeys.keyboardIOSStyling)
        XCTAssertFalse(KeyboardInteractionPreferences.topBarEnabled)
        XCTAssertTrue(KeyboardInteractionPreferences.keyboardInsetEnabled)
        XCTAssertTrue(KeyboardInteractionPreferences.keyContainersEnabled)
        XCTAssertFalse(KeyboardInteractionPreferences.liquidGlassEnabled)
        for mode in [KeyboardAreaMode.letters, .panel, .emoji, .numberPad] {
            XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: mode), 0)
        }
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .recording), 32)
        XCTAssertTrue(defaults.bool(forKey: SharedKeys.keyboardTopBarEnabled))
        XCTAssertFalse(defaults.bool(forKey: SharedKeys.keyboardInsetEnabled))
        XCTAssertFalse(defaults.bool(forKey: SharedKeys.keyContainersEnabled))
        XCTAssertTrue(defaults.bool(forKey: SharedKeys.liquidGlassEnabled))

        defaults.set(false, forKey: SharedKeys.keyboardIOSStyling)
        XCTAssertTrue(KeyboardInteractionPreferences.topBarEnabled)
        XCTAssertEqual(KeyboardInteractionPreferences.windowAccessoryHeight, 44)
        XCTAssertFalse(KeyboardInteractionPreferences.keyboardInsetEnabled)
        XCTAssertFalse(KeyboardInteractionPreferences.keyContainersEnabled)
        XCTAssertTrue(KeyboardInteractionPreferences.liquidGlassEnabled)
    }
}
