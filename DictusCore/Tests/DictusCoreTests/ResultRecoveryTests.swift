import XCTest
@testable import DictusCore

final class ResultRecoveryTests: XCTestCase {
    func testRestorationNeedsTheCompleteInsertionAndBoundedLength() {
        XCTAssertEqual(DictationUndo.originalRestorationCount(context: "Before Hello. ", insertedText: "Hello. "), 7)
        XCTAssertNil(DictationUndo.originalRestorationCount(context: "Hello. later", insertedText: "Hello. "))
        XCTAssertNil(DictationUndo.originalRestorationCount(context: nil, insertedText: "Hello. "))
        let long = String(repeating: "a", count: 201)
        XCTAssertNil(DictationUndo.originalRestorationCount(context: long, insertedText: long))
        let partial = String(repeating: "a", count: 100)
        XCTAssertNil(DictationUndo.originalRestorationCount(context: partial, insertedText: partial + partial))
    }

    func testLegacyHistoryDecodesAndEditingPreservesOriginal() throws {
        let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"text\":\"Hello\",\"createdAt\":1}".utf8)
        XCTAssertNil(try JSONDecoder().decode(RecentDictation.self, from: legacy).originalText)
        let suite = "result-recovery-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        RecentDictations.append("Hello.", in: defaults, originalText: "uh hello")
        var item = try XCTUnwrap(RecentDictations.load(from: defaults).first)
        item.text = "Hello again."
        RecentDictations.update(item, in: defaults)
        RecentDictations.recordFeedback(.needsEditing, for: item.id, in: defaults)
        let edited = try XCTUnwrap(RecentDictations.load(from: defaults).first)
        XCTAssertEqual(edited.originalText, "uh hello")
        XCTAssertEqual(edited.feedback, .needsEditing)
        defaults.set(false, forKey: SharedKeys.historyEnabled)
        RecentDictations.append("Private.", in: defaults, originalText: "private original")
        XCTAssertFalse(RecentDictations.load(from: defaults).contains { $0.text == "Private." })
    }

    func testTransientDeliveryCarriesOriginalEvenWhenHistoryIsOff() throws {
        let suite = "transient-original-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: SharedKeys.historyEnabled)
        let request = DictationLanguageRequest(mode: .autoDetect, translationTarget: nil)
            .bound(sessionID: "fixture", generation: 1, clientIdentifier: "fixture")
        DictationDeliveryStore.publishReady(text: "Hello.", request: request, to: defaults, originalText: "uh hello")
        let result = try XCTUnwrap(DictationDelivery.consumeResult(for: request, from: defaults))
        XCTAssertEqual(result.originalText, "uh hello")
        XCTAssertEqual(RecentDictations.load(from: defaults), [])
        XCTAssertNil(DictationDelivery.consumeResult(for: request, from: defaults))
    }
}
