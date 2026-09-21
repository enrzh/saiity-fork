import XCTest
@testable import DictusCore

final class LastDictationIssueReportTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        suiteName = "issue-report-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testExportOmitsTranscriptUnlessRequested() throws {
        let snapshot = sample(raw: "raw hello", cleaned: "Raw hello.")
        let omitted = LastDictationIssueReport.exportSnapshot(snapshot, includeText: false)
        XCTAssertNil(omitted.rawText)
        XCTAssertNil(omitted.cleanedText)
        XCTAssertEqual(omitted.modelIdentifier, "openai_whisper-tiny")
        XCTAssertEqual(omitted.outputMode, "multilingual")

        let included = LastDictationIssueReport.exportSnapshot(snapshot, includeText: true)
        XCTAssertEqual(included.rawText, "raw hello")
        XCTAssertEqual(included.cleanedText, "Raw hello.")

        let preview = LastDictationIssueReport.previewString(snapshot, includeText: false)
        XCTAssertFalse(preview.contains("raw hello"))
        XCTAssertFalse(preview.contains("Raw hello."))
        XCTAssertTrue(preview.contains("openai_whisper-tiny"))
        XCTAssertFalse(preview.lowercased().contains("password"))
        XCTAssertFalse(preview.lowercased().contains("token"))
    }

    func testStoreOverwritesPreviousSnapshotAndBoundsText() {
        LastDictationIssueReport.store(sample(raw: "first", cleaned: "First."), in: defaults)
        LastDictationIssueReport.store(
            sample(raw: String(repeating: "a", count: 12_000), cleaned: "ok"),
            in: defaults
        )
        let loaded = LastDictationIssueReport.load(from: defaults)
        XCTAssertEqual(loaded?.rawText?.count, LastDictationIssueReport.maxTextCharacters)
        XCTAssertEqual(loaded?.cleanedText, "ok")
        XCTAssertEqual(LastDictationIssueReport.retentionLimit, 1)
        XCTAssertEqual(LastDictationIssueReport.recoverableRawText(from: defaults)?.count,
                       LastDictationIssueReport.maxTextCharacters)
    }

    func testFailureReportIsUsefulWithoutTranscript() throws {
        var snapshot = sample(raw: "secret words", cleaned: nil)
        snapshot.stage = "transcribing"
        snapshot.failureStage = "transcribing"
        snapshot.errorSummary = "engineLoadFailed"
        snapshot.rawText = "secret words"
        LastDictationIssueReport.store(snapshot, in: defaults)
        let preview = LastDictationIssueReport.previewString(
            LastDictationIssueReport.load(from: defaults)!,
            includeText: false
        )
        XCTAssertTrue(preview.contains("engineLoadFailed"))
        XCTAssertTrue(preview.contains("transcribing"))
        XCTAssertFalse(preview.contains("secret words"))
        let data = try LastDictationIssueReport.exportData(snapshot, includeText: false)
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("secret words"))
    }

    private func sample(raw: String?, cleaned: String?) -> LastDictationIssueSnapshot {
        LastDictationIssueSnapshot(
            appVersion: "1.0.0",
            buildNumber: "104",
            modelIdentifier: "openai_whisper-tiny",
            engineName: "whisperKit",
            outputMode: "multilingual",
            transcriptionMode: "autoDetect",
            stage: "ready",
            rawText: raw,
            cleanedText: cleaned
        )
    }
}
