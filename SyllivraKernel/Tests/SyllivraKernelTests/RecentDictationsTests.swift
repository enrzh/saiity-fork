import XCTest
@testable import SyllivraKernel

final class RecentDictationsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        suiteName = "recents-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testKeepsTheLastThirtyNewestFirst() {
        for index in 1...35 {
            RecentDictations.append("note \(index)", in: defaults)
        }
        let loaded = RecentDictations.load(from: defaults)
        XCTAssertEqual(loaded.count, 30)
        XCTAssertEqual(loaded.first?.text, "note 35")
        XCTAssertEqual(loaded.last?.text, "note 6")
        XCTAssertEqual(RecentDictations.retentionLimit, 30)
    }

    func testDeduplicatesMatchingTextByMovingItFirst() {
        RecentDictations.append("hello", in: defaults)
        RecentDictations.append("world", in: defaults)
        RecentDictations.append("hello", in: defaults)
        let loaded = RecentDictations.load(from: defaults)
        XCTAssertEqual(loaded.map(\.text), ["hello", "world"])
    }

    func testDisabledHistoryDoesNotPersistNewEntriesOrMigrateLegacyText() {
        defaults.set(false, forKey: SharedKeys.historyEnabled)
        defaults.set("legacy", forKey: SharedKeys.lastTranscription)
        RecentDictations.append("new", in: defaults)

        XCTAssertTrue(RecentDictations.load(from: defaults).isEmpty)
        XCTAssertNotNil(defaults.data(forKey: SharedKeys.recentDictations))
        defaults.set(true, forKey: SharedKeys.historyEnabled)
        XCTAssertTrue(RecentDictations.load(from: defaults).isEmpty)
    }

    func testDisablingHistoryPreservesExistingEntries() {
        RecentDictations.append("before", in: defaults)
        defaults.set(false, forKey: SharedKeys.historyEnabled)
        RecentDictations.append("after", in: defaults)

        XCTAssertEqual(RecentDictations.load(from: defaults).map(\.text), ["before"])
    }

    func testClearRemovesLegacyMigrationSource() {
        RecentDictations.append("saved", in: defaults)
        defaults.set("legacy", forKey: SharedKeys.lastTranscription)
        defaults.set(123.0, forKey: SharedKeys.lastTranscriptionTimestamp)

        RecentDictations.clear(in: defaults)

        XCTAssertTrue(RecentDictations.load(from: defaults).isEmpty)
        XCTAssertEqual(defaults.string(forKey: SharedKeys.lastTranscription), "legacy")
        XCTAssertEqual(defaults.object(forKey: SharedKeys.lastTranscriptionTimestamp) as? Double, 123.0)
    }

    func testDisablingHistoryTombstonesOnlyWhenNoStoredHistoryExists() {
        defaults.set("legacy", forKey: SharedKeys.lastTranscription)
        RecentDictations.disable(in: defaults)
        XCTAssertTrue(RecentDictations.load(from: defaults).isEmpty)

        RecentDictations.append("saved", in: defaults)
        defaults.set(false, forKey: SharedKeys.historyEnabled)
        RecentDictations.disable(in: defaults)
        XCTAssertEqual(RecentDictations.load(from: defaults).map(\.text), ["saved"])
    }
}

final class DictationPresenceModeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        suiteName = "presence-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testMigratesLegacyLiveActivityToggle() {
        defaults.set(false, forKey: SharedKeys.liveActivityEnabled)
        XCTAssertEqual(DictationPresenceMode.load(from: defaults), .off)
        defaults.set(true, forKey: SharedKeys.liveActivityEnabled)
        XCTAssertEqual(DictationPresenceMode.load(from: defaults), .liveActivity)
    }

    func testMigratesRemovedPictureInPicturePreferenceToLiveActivity() {
        defaults.set("pictureInPicture", forKey: SharedKeys.dictationPresenceMode)
        XCTAssertEqual(DictationPresenceMode.load(from: defaults), .liveActivity)
    }
}

final class SpeechAudioGainTests: XCTestCase {
    func testAmplifiesQuietSpeechAndLeavesLoudSpeech() {
        let quiet = (0..<8).map { $0 == 0 ? Float(0.04) : 0 }
        let amplified = SpeechAudioGain.amplifyIfQuiet(quiet)
        XCTAssertGreaterThan(amplified.map(abs).max() ?? 0, 0.1)

        let loud = [Float](repeating: 0.6, count: 8)
        XCTAssertEqual(SpeechAudioGain.amplifyIfQuiet(loud), loud)
    }
}
