import XCTest
@testable import SyllivraKernel

final class DiagnosticTranscriptPolicyTests: XCTestCase {
    func testDiagnosticsRequireConsentAndHistory() throws {
        let name = "diagnostic-consent-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(DiagnosticTranscriptPolicy.allowsText(in: defaults))
        defaults.set(true, forKey: SharedKeys.polishDebugTranscriptsEnabled)
        XCTAssertTrue(DiagnosticTranscriptPolicy.allowsText(in: defaults))
        defaults.set(false, forKey: SharedKeys.historyEnabled)
        XCTAssertFalse(DiagnosticTranscriptPolicy.allowsText(in: defaults))
        defaults.set(true, forKey: SharedKeys.historyEnabled)
        defaults.set(false, forKey: SharedKeys.polishDebugTranscriptsEnabled)
        XCTAssertFalse(DiagnosticTranscriptPolicy.allowsText(in: defaults))
    }
}
