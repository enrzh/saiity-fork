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
        XCTAssertFalse(KeyboardInteractionPreferences.topBarEnabled)
        XCTAssertEqual(KeyboardInteractionPreferences.windowAccessoryHeight, 0)
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .letters), 0)
        XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: .keys), 32)

        defaults.set(true, forKey: SharedKeys.keyboardTopBarEnabled)
        defaults.set(false, forKey: SharedKeys.keyboardInsetEnabled)
        defaults.set(false, forKey: SharedKeys.keyContainersEnabled)
        defaults.set(true, forKey: SharedKeys.liquidGlassEnabled)
        defaults.set(true, forKey: SharedKeys.keyboardIOSStyling)
        XCTAssertTrue(KeyboardInteractionPreferences.topBarEnabled)
        XCTAssertFalse(KeyboardInteractionPreferences.keyboardInsetEnabled)
        XCTAssertFalse(KeyboardInteractionPreferences.keyContainersEnabled)
        XCTAssertTrue(KeyboardInteractionPreferences.liquidGlassEnabled)
        for mode in [KeyboardAreaMode.letters, .panel, .emoji, .numberPad] {
            XCTAssertEqual(KeyboardInteractionPreferences.topBarHeight(for: mode), 32)
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
