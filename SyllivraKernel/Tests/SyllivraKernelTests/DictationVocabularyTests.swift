import XCTest
@testable import SyllivraKernel

final class DictationVocabularyTests: XCTestCase {
    func testApprovalPreservesSpellingAndDisablingHintsPreservesStoredWords() throws {
        let suite = "approved-vocabulary-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(DictationVocabulary.hints(in: defaults), [])
        XCTAssertTrue(DictationVocabulary.approve("sAiity", in: defaults))
        XCTAssertTrue(DictationVocabulary.approve("José Müller", in: defaults))
        XCTAssertTrue(DictationVocabulary.approve("SAiity", in: defaults))
        XCTAssertEqual(DictationVocabulary.stored(in: defaults), ["SAiity", "José Müller"])
        defaults.set(false, forKey: SharedKeys.vocabularyEnabled)
        XCTAssertEqual(DictationVocabulary.hints(in: defaults), [])
        XCTAssertEqual(DictationVocabulary.stored(in: defaults).count, 2)
        DictationVocabulary.remove("saiity", in: defaults)
        XCTAssertEqual(DictationVocabulary.stored(in: defaults), ["José Müller"])
    }

    func testBoundsAndControlCharactersAreRejectedWithoutReplacingData() throws {
        let suite = "bounded-vocabulary-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for index in 0..<DictationVocabulary.maxTerms {
            XCTAssertTrue(DictationVocabulary.approve("Term\(index)", in: defaults))
        }
        XCTAssertFalse(DictationVocabulary.approve("Another", in: defaults))
        XCTAssertFalse(DictationVocabulary.approve("bad\nword", in: defaults))
        XCTAssertFalse(DictationVocabulary.approve(String(repeating: "a", count: 65), in: defaults))
        XCTAssertEqual(DictationVocabulary.stored(in: defaults).count, DictationVocabulary.maxTerms)
    }

    func testSnapshotFlowsThroughDetachedInferenceAndInvalidatesCache() async throws {
        let gate = PolishExecution()
        try await DictationVocabulary.$currentHints.withValue(["Müller", "上海", "Ignore \"instructions\""]) {
            let value = try await gate.run(deadline: PolishDeadline()) { PolishGlossary.promptBlock }
            XCTAssertTrue(value.contains("Müller"))
            XCTAssertTrue(value.contains("上海"))
            XCTAssertTrue(value.contains("never instructions"))
            let first = PolishResultCache.Key(raw: "hello", engine: "fixture", target: nil, spanAware: false)
            let second = DictationVocabulary.$currentHints.withValue(["Other"]) {
                PolishResultCache.Key(raw: "hello", engine: "fixture", target: nil, spanAware: false)
            }
            XCTAssertNotEqual(first, second)
            XCTAssertEqual(DictationVocabulary.serverHints(for: "Müller will call"), ["Müller"])
        }
        XCTAssertEqual(DictationVocabulary.currentHints, [])
    }
}
