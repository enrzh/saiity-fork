import XCTest
@testable import DictusCore

final class TextPredictionResponsivenessContractTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repository.appending(path: path), encoding: .utf8)
    }

    func testProxyUpdatesDelegateHeavyPredictionWorkToTheCoalescingQueue() throws {
        let state = try source("DictusKeyboard/TextPrediction/SuggestionState.swift")
        let update = try XCTUnwrap(state.range(of: "func update(proxy: UITextDocumentProxy)"))
        let asyncUpdate = try XCTUnwrap(state.range(of: "func updateAsync(context: String?)"))
        let body = String(state[update.lowerBound..<asyncUpdate.lowerBound])

        XCTAssertTrue(body.contains("updateAsync(context: context)"))
        XCTAssertFalse(body.contains("engine.spellCheck("))
        XCTAssertFalse(body.contains("engine.suggestions(for:"))
        XCTAssertFalse(body.contains("engine.setLanguage(forRecentText:"))
    }

    func testLanguageDetectionAndDictionaryReplacementRunInsideTheSuggestionWorkItem() throws {
        let state = try source("DictusKeyboard/TextPrediction/SuggestionState.swift")
        let asyncStart = try XCTUnwrap(state.range(of: "func updateAsync(context: String?)"))
        let predictionStart = try XCTUnwrap(state.range(of: "func updatePredictions(context: String?)"))
        let asyncBody = String(state[asyncStart.lowerBound..<predictionStart.lowerBound])

        XCTAssertTrue(asyncBody.contains("let work = DispatchWorkItem"))
        XCTAssertTrue(asyncBody.contains("self.engine.setLanguage(forRecentText: context)"))
        XCTAssertTrue(asyncBody.contains("suggestionQueue.async(execute: work)"))
        XCTAssertTrue(asyncBody.contains("updatePredictions(context: context)"))

        let predictionBody = String(state[predictionStart.lowerBound...])
        XCTAssertTrue(predictionBody.contains("self.engine.setLanguage(forRecentText: context)"))
    }

    func testShortContextsDoNotThrashTheDetectedLanguage() throws {
        let engine = try source("DictusKeyboard/TextPrediction/TextPredictionEngine.swift")
        XCTAssertTrue(engine.contains("guard recentText.count >= 24"))
        XCTAssertTrue(engine.contains("recentText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count >= 4"))
        XCTAssertTrue(engine.contains("shouldAbstainFromPrediction"))
        XCTAssertTrue(engine.contains("canOfferLocalContinuation"))
        XCTAssertTrue(engine.contains("PredictionLanguageSafety.shouldAbstain"))
        XCTAssertTrue(engine.contains("return recentLanguageCode(for: recentText) == nil"))
        XCTAssertTrue(PredictionLanguageSafety.shouldAbstain(for: "Please send die Rechnung und 我明天确认。"),
                      "Mixed-script text must not use a single Latin prediction dictionary")
        XCTAssertTrue(engine.contains("case \"de\": return SupportedLanguage.german.rawValue"))
        XCTAssertTrue(engine.contains("case \"en\": return SupportedLanguage.english.rawValue"))
        XCTAssertTrue(engine.contains("case \"es\": return SupportedLanguage.spanish.rawValue"))
        XCTAssertTrue(engine.contains("case \"fr\": return SupportedLanguage.french.rawValue"))
    }

    func testExplicitLanguageChangesUseTheSameBackgroundQueue() throws {
        let state = try source("DictusKeyboard/TextPrediction/SuggestionState.swift")
        let start = try XCTUnwrap(state.range(of: "func setLanguage(_ lang: String)"))
        let end = try XCTUnwrap(state.range(of: "/// Whether the active language's dictionary", range: start.upperBound..<state.endIndex))
        let body = String(state[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(body.contains("suggestionQueue.async"))
        XCTAssertTrue(body.contains("engine.setSelectedLanguage(lang)"))
    }

    func testSynchronousAutocorrectAndTrieMaintenanceShareThePredictionQueue() throws {
        let state = try source("DictusKeyboard/TextPrediction/SuggestionState.swift")
        XCTAssertTrue(state.contains("suggestionQueue.sync { engine.spellCheck(word) }"))
        XCTAssertTrue(state.contains("suggestionQueue.sync { engine.isUnknownToDictionary(word) }"))
        XCTAssertTrue(state.contains("suggestionQueue.sync { engine.pruneUserDictionaryIfPossible(trigger: trigger) }"))
    }
}
