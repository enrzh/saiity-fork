import XCTest
@testable import DictusCore

final class HapticIntensityTests: XCTestCase {
    func testDefaultIntensityIsOnAndOffMirrorsLegacyDisable() {
        let defaults = UserDefaults(suiteName: "dictus.haptic-intensity-tests")!
        defaults.removePersistentDomain(forName: "dictus.haptic-intensity-tests")
        XCTAssertEqual(HapticIntensity.load(from: defaults), .on)
        defaults.set(false, forKey: SharedKeys.hapticsEnabled)
        XCTAssertEqual(HapticIntensity.load(from: defaults), .off)
        HapticIntensity.on.persist(to: defaults)
        XCTAssertEqual(HapticIntensity.load(from: defaults), .on)
        XCTAssertEqual(defaults.bool(forKey: SharedKeys.hapticsEnabled), true)
    }

    func testLegacyStrengthValuesLoadAsOn() {
        let defaults = UserDefaults(suiteName: "dictus.haptic-intensity-legacy-tests")!
        defaults.removePersistentDomain(forName: "dictus.haptic-intensity-legacy-tests")
        for raw in ["light", "medium", "strong", "on"] {
            defaults.set(raw, forKey: SharedKeys.hapticIntensity)
            XCTAssertEqual(HapticIntensity.load(from: defaults), .on, raw)
        }
        defaults.set("off", forKey: SharedKeys.hapticIntensity)
        XCTAssertEqual(HapticIntensity.load(from: defaults), .off)
    }
}
