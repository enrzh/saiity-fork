import XCTest
@testable import DictusCore

final class DictationDisabledServiceTests: XCTestCase {
    func testDisabledServiceFailureIsPersistedForTheKeyboardConsumer() {
        let defaults = UserDefaults(suiteName: "DictationDisabledServiceTests")!
        defaults.removePersistentDomain(forName: "DictationDisabledServiceTests")

        defaults.set("Dictation service is turned off.", forKey: SharedKeys.lastError)
        defaults.set(DictationFailureDisposition.requiresApp.rawValue, forKey: SharedKeys.failureDisposition)

        XCTAssertEqual(
            defaults.string(forKey: SharedKeys.lastError),
            "Dictation service is turned off."
        )
        XCTAssertEqual(
            DictationFailureDisposition(rawValue: defaults.string(forKey: SharedKeys.failureDisposition)!),
            .requiresApp
        )
    }
}
