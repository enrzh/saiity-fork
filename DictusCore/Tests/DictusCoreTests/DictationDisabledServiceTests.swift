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

    func testDisabledServiceStartUsesHandleErrorSoTheKeyboardReceivesFailure() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinator = try String(
            contentsOf: repository.appending(path: "DictusApp/DictationCoordinator.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(coordinator.range(of: "func startDictation("))
        let remainder = coordinator[start.upperBound...]
        let next = remainder.range(of: "\n    func ")
        let body: String
        if let next {
            body = String(coordinator[start.lowerBound..<next.lowerBound])
        } else {
            body = String(coordinator[start.lowerBound...].prefix(2500))
        }
        XCTAssertTrue(body.contains("handleError(\"Dictation service is turned off.\", disposition: .requiresApp)"))
        XCTAssertFalse(body.contains("status = .failed"))
    }
}
