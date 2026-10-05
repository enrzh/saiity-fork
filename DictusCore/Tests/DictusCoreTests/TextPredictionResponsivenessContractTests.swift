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
        XCTAssertFalse(state.contains("touchRecallTokens"),
                       "touch routing must not depend on dictionary/name recall")
        XCTAssertTrue(state.contains("prepared.correction.flatMap"))
        XCTAssertTrue(state.contains("let correction: String?"), "completed negative checks must also be cached")
        let start = try XCTUnwrap(state.range(of: "func handleSpace(proxy:"))
        let end = try XCTUnwrap(state.range(of: "func noteTypedCharacter", range: start.upperBound..<state.endIndex))
        let touchBody = state[start.lowerBound..<end.lowerBound]
        XCTAssertFalse(touchBody.contains("performSpellCheck("), "Space must not synchronously wait for prediction")
        XCTAssertFalse(touchBody.contains("suggestionQueue.sync"))
        XCTAssertTrue(state.contains("UserDictionary.shared.reload()"))
        XCTAssertTrue(state.contains("suggestionQueue.sync { engine.spellCheck(word) }"))
        XCTAssertTrue(state.contains("suggestionQueue.sync { engine.isUnknownToDictionary(word) }"))
        XCTAssertTrue(state.contains("suggestionQueue.sync { engine.pruneUserDictionaryIfPossible(trigger: trigger) }"))
    }

    func testTouchPriorsDoNotInventCommonWordsAfterAFact() throws {
        let engine = try source("DictusKeyboard/TextPrediction/TextPredictionEngine.swift")
        let boundary = try XCTUnwrap(engine.range(of: "func nextCharacterProbabilities(\n        after previousWords: [String]"))
        let body = String(engine[boundary.lowerBound...])
        XCTAssertTrue(engine.contains("TypingFact.isOpenPrefix(partialWord)"))
        XCTAssertTrue(engine.contains("localContinuationCandidates(after: contextualWords, maxResults: 12)"))
        XCTAssertTrue(body.contains("localContinuationCandidates(after: contextualWords, maxResults: 8)"))
        XCTAssertTrue(body.contains("TypingFact.contextWords(from: previousWords)"))
        XCTAssertFalse(body.contains("predictNextWords(after: previousWords, maxResults: 8)"))
        XCTAssertFalse(body.contains("frequencyDict.topWords"),
                       "A touch prior must not fall back to the most common words")
    }

    func testAdaptiveTouchPriorsUseLocalContextOffTheTouchPath() throws {
        let state = try source("DictusKeyboard/TextPrediction/SuggestionState.swift")
        let start = try XCTUnwrap(state.range(of: "func updateAdaptiveTouchPrediction"))
        let end = try XCTUnwrap(state.range(of: "    private func preparedSpaceCommit", range: start.upperBound..<state.endIndex))
        let body = String(state[start.lowerBound..<end.lowerBound])
        let workStart = try XCTUnwrap(body.range(of: "let work = DispatchWorkItem"))
        XCTAssertFalse(body[..<workStart.lowerBound].contains("engine.nextCharacterProbabilities"),
                       "dictionary lookup must never run during touch delivery")

        XCTAssertTrue(body.contains("self.engine.nextCharacterProbabilities("))
        XCTAssertTrue(body.contains("suggestionQueue.async(execute: work)"))
        XCTAssertTrue(body.contains("self.adaptiveTouchRequestGate.isCurrent(requestToken)"),
                      "a stale worker must never move a current hit target")
        XCTAssertTrue(body.contains("probabilities.isEmpty ? nil : probabilities"),
                      "uncertain context leaves the gap neutral")
        XCTAssertFalse(body.contains("StaticLetterTouchPrediction.nextCharacterProbabilities"),
                       "static English-like frequencies must not bias multilingual typing")
        XCTAssertTrue(body.contains("guard hostPolicy.suggestionsAllowed else"),
                      "protected fields must drop a stale touch prior")
        XCTAssertTrue(body.contains("self.engine.shouldAbstainFromPrediction(for: inputContext)"),
                      "code-like or uncertain context should not bias a key")
    }

    func testVisualPreferencesDoNotReloadVocabulary() throws {
        let state = try source("DictusKeyboard/TextPrediction/SuggestionState.swift")
        let preferenceStart = try XCTUnwrap(state.range(of: "func refreshPreferences()"))
        let vocabularyStart = try XCTUnwrap(state.range(of: "func refreshVocabulary()", range: preferenceStart.upperBound..<state.endIndex))
        let preferenceBody = String(state[preferenceStart.lowerBound..<vocabularyStart.lowerBound])
        let vocabularyBody = String(state[vocabularyStart.lowerBound...])

        XCTAssertFalse(preferenceBody.contains("UserDictionary.shared.reload()"))
        XCTAssertTrue(preferenceBody.contains("enabled != lastAutocorrectEnabled"))
        XCTAssertTrue(vocabularyBody.contains("UserDictionary.shared.reload()"))

        let settings = try source("DictusApp/Views/SettingsView.swift")
        let vocabularyView = try XCTUnwrap(settings.range(of: "struct VocabularyView:"))
        XCTAssertFalse(settings[..<vocabularyView.lowerBound].contains("KeyboardInteractionPreferences.notifyVocabularyChanged()"))
        XCTAssertTrue(settings[vocabularyView.lowerBound...].contains("DictationVocabulary.approve"))
    }
}
