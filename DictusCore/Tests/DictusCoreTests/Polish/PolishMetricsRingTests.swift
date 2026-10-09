import XCTest
@testable import DictusCore

final class PolishMetricsRingTests: XCTestCase {
    func testConsentControlsDiskWritesAndExportsWithoutDeletingLegacyData() async throws {
        let suite = "polish-store-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let metrics = PolishMetrics(engine: "fixture", mode: .auto, targetLanguage: nil,
            detectedLanguage: "en", rawCharCount: 6, polishedCharCount: 6, latencyMs: 1, outcome: .success)
        let entry = PolishDebugEntry(raw: "secret", polished: "Secret", metrics: metrics)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let legacy = directory.appendingPathComponent("polish_events.jsonl")
        let legacyData = try encoder.encode(entry)
        try legacyData.write(to: legacy)
        let ring = PolishMetricsRing(defaults: defaults, directory: directory)

        await ring.append(entry)
        let file = directory.appendingPathComponent("polish_events_v2.jsonl")
        let metadata = try String(contentsOf: file)
        XCTAssertFalse(metadata.contains("secret"))
        XCTAssertFalse(metadata.contains("Secret"))
        let redacted = await ring.allEntries()
        XCTAssertEqual(redacted.count, 2)
        let visible = await ring.snapshot()
        XCTAssertEqual(visible.count, 2)
        XCTAssertTrue(visible.allSatisfy { $0.raw == nil && $0.polished == nil })
        XCTAssertTrue(redacted.allSatisfy { $0.raw == nil && $0.polished == nil })
        XCTAssertEqual(try Data(contentsOf: legacy), legacyData)

        defaults.set(true, forKey: SharedKeys.polishDebugTranscriptsEnabled)
        await ring.append(entry)
        let consented = await ring.allEntries()
        XCTAssertTrue(consented.contains { $0.raw == "secret" })

        defaults.set(false, forKey: SharedKeys.historyEnabled)
        await ring.append(entry)
        let historyOff = await ring.allEntries()
        XCTAssertTrue(historyOff.allSatisfy { $0.raw == nil && $0.polished == nil })
        let lines = try String(contentsOf: file).split(separator: "\n")
        XCTAssertFalse(try XCTUnwrap(lines.last).contains("secret"))

        try await ring.clear()
        let cleared = await ring.allEntries()
        XCTAssertEqual(cleared.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testClearDoesNotRestoreAnOlderQueuedEventAfterRestart() async throws {
        let suite = "polish-clear-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let metrics = PolishMetrics(engine: "fixture", mode: .auto, targetLanguage: nil,
            detectedLanguage: "en", rawCharCount: 6, polishedCharCount: 6, latencyMs: 1, outcome: .success)
        let entry = PolishDebugEntry(raw: "secret", polished: "Secret", metrics: metrics)
        let ring = PolishMetricsRing(defaults: defaults, directory: directory)
        await ring.append(entry)
        try await ring.clear()
        await ring.append(entry)
        let restarted = PolishMetricsRing(defaults: defaults, directory: directory)
        let entries = await restarted.allEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    func testClearSurfacesDiskFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("polish-clear-failure-" + UUID().uuidString)
        try Data([1]).write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ring = PolishMetricsRing(directory: directory)
        do {
            try await ring.clear()
            XCTFail("Clear hid an unusable storage directory")
        } catch { }
    }
}
