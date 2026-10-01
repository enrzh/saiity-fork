import XCTest
@testable import DictusCore

final class HapticIntensityTests: XCTestCase {
    func testDefaultPresetAndOffMirrorLegacyEnablement() {
        let defaults = UserDefaults(suiteName: "dictus.haptic-intensity-tests")!
        defaults.removePersistentDomain(forName: "dictus.haptic-intensity-tests")
        XCTAssertEqual(HapticIntensity.load(from: defaults), .default)
        defaults.set(false, forKey: SharedKeys.hapticsEnabled)
        XCTAssertEqual(HapticIntensity.load(from: defaults), .off)
        HapticIntensity.default.persist(to: defaults)
        XCTAssertEqual(HapticIntensity.load(from: defaults), .default)
        XCTAssertEqual(defaults.bool(forKey: SharedKeys.hapticsEnabled), true)
    }

    func testLegacyStrengthValuesKeepDefaultFeel() {
        let defaults = UserDefaults(suiteName: "dictus.haptic-intensity-legacy-tests")!
        defaults.removePersistentDomain(forName: "dictus.haptic-intensity-legacy-tests")
        for raw in ["light", "medium", "strong", "on"] {
            defaults.set(raw, forKey: SharedKeys.hapticIntensity)
            XCTAssertEqual(HapticIntensity.load(from: defaults), .default, raw)
        }
        defaults.set("off", forKey: SharedKeys.hapticIntensity)
        XCTAssertEqual(HapticIntensity.load(from: defaults), .off)
    }

    func testAllPresetsRoundTripAndSelectTheExistingImpulses() {
        let suite = "dictus.haptic-preset-roundtrip-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(HapticIntensity.allCases.map(\.displayName), ["Off", "Default", "Snappy"])
        for preset in HapticIntensity.allCases {
            preset.persist(to: defaults)
            XCTAssertEqual(HapticIntensity.load(from: defaults), preset)
            XCTAssertEqual(defaults.bool(forKey: SharedKeys.hapticsEnabled), preset != .off)
        }
        XCTAssertNil(HapticIntensity.off.keyTapIntensity)
        XCTAssertEqual(HapticIntensity.default.keyTapIntensity, 0.42)
        XCTAssertEqual(HapticIntensity.snappy.keyTapIntensity, 1)
    }
}
