import XCTest
@testable import SyllivraKernel

final class PolishSpanPipelineTests: XCTestCase {
    private func regions(_ texts: [String], language: String = "en") -> [SpeechRegionTranscript] {
        texts.enumerated().map { index, text in
            SpeechRegionTranscript(region: SpeechRegion(startSample: index * 16_000, endSample: (index + 1) * 16_000),
                text: text, detectedLanguage: language, validatedLanguage: language)
        }
    }

    func testSameLanguageRegionsShareOneEngineCall() async {
        let input = regions(["Please send the invoice tomorrow.", "Confirm the meeting with Alex on Friday.",
                             "Please keep the invoice for 240 euros and send it tomorrow."])
        let engine = CountingPolishEngine { text, _, _ in text }
        let result = await PolishSpanPipeline.polish(regions: input, engine: engine)

        XCTAssertEqual(result.text, SpeechTranscriptMerger.merge(input))
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(engine.calls, 1, "Adjacent verified speech should not pay model startup per audio region")
        XCTAssertEqual(result.polishedSpanCount, input.count)
    }

    func testRegionBatchingKeepsLanguageSwitchesSeparate() async {
        let input = regions(["Please send the invoice tomorrow."])
            + regions(["Merci de confirmer la réunion de demain."], language: "fr")
        let engine = CountingPolishEngine { text, _, _ in text }
        let result = await PolishSpanPipeline.polish(regions: input, engine: engine)
        XCTAssertEqual(engine.calls, 2)
        XCTAssertEqual(result.text, SpeechTranscriptMerger.merge(input))
    }

    func testRegionBatchingKeepsOverlapBoundariesSeparate() async {
        let input = regions(["Please send the invoice tomorrow."]) + [
            SpeechRegionTranscript(region: SpeechRegion(startSample: 15_000, endSample: 32_000),
                text: "The invoice tomorrow should include 240 euros.", detectedLanguage: "en",
                validatedLanguage: "en", overlapsPreviousRegion: true)
        ]
        let engine = CountingPolishEngine { text, _, _ in text }
        let result = await PolishSpanPipeline.polish(regions: input, engine: engine)
        XCTAssertEqual(engine.calls, 2)
        XCTAssertEqual(result.text, SpeechTranscriptMerger.merge(input))
    }

    func testRegionBatchingLeavesUncertainFragmentsBetweenCalls() async {
        let input = regions(["Please send the invoice tomorrow.", "API_240", "Confirm the meeting with Alex on Friday."])
        let engine = CountingPolishEngine { text, _, _ in text }
        let result = await PolishSpanPipeline.polish(regions: input, engine: engine)
        XCTAssertEqual(engine.calls, 2)
        XCTAssertEqual(result.passthroughSpanCount, 1)
        XCTAssertEqual(result.text, SpeechTranscriptMerger.merge(input))
    }

    func testRegionBatchingKeepsTheTailOfAnOverlapSeparate() async {
        let input = regions(["Please send the invoice tomorrow."]) + [
            SpeechRegionTranscript(region: SpeechRegion(startSample: 15_000, endSample: 32_000),
                text: "The invoice tomorrow should include 240 euros.", detectedLanguage: "en",
                validatedLanguage: "en", overlapsPreviousRegion: true),
            SpeechRegionTranscript(region: SpeechRegion(startSample: 32_000, endSample: 48_000),
                text: "Please confirm the meeting with Alex tomorrow.", detectedLanguage: "en", validatedLanguage: "en")
        ]
        let engine = CountingPolishEngine { text, _, _ in text }
        let result = await PolishSpanPipeline.polish(regions: input, engine: engine)
        XCTAssertEqual(engine.calls, 3, "An overlap must not consume a following region's deliberate repetition")
        XCTAssertEqual(result.text, SpeechTranscriptMerger.merge(input))
    }

    func testRegionBatchingRespectsTheEnginesContextBudget() async {
        let input = regions(["Please send the invoice tomorrow.", "Confirm the meeting with Alex on Friday.",
                             "Please keep the invoice for 240 euros and send it tomorrow."])
        let engine = CountingPolishEngine(maximumInputCharacters: 60) { text, _, _ in text }
        let result = await PolishSpanPipeline.polish(regions: input, engine: engine)
        XCTAssertEqual(engine.calls, input.count)
        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.text, SpeechTranscriptMerger.merge(input))
    }

    func testRejectedRegionBatchRetainsFactsWithoutRetrying() async {
        let input = regions(["Please send the invoice tomorrow.", "Please keep the invoice for 240 euros and send it tomorrow."])
        let engine = CountingPolishEngine { text, _, _ in text.replacingOccurrences(of: "240", with: "999") }
        let result = await PolishSpanPipeline.polish(regions: input, engine: engine)
        XCTAssertEqual(engine.calls, 1)
        XCTAssertEqual(result.outcome, .rejectedGuardrail)
        XCTAssertEqual(result.text, SpeechTranscriptMerger.merge(input))
        XCTAssertEqual(result.passthroughSpanCount, input.count)
    }

    func testCancelledRegionBatchReturnsTheWholeFloor() async {
        let input = regions(["Please send the invoice tomorrow.", "Please keep the invoice for 240 euros and send it tomorrow."])
        let engine = CountingPolishEngine { _, _, _ in throw CancellationError() }
        let result = await PolishSpanPipeline.polish(regions: input, engine: engine)
        XCTAssertEqual(engine.calls, 1)
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertEqual(result.text, SpeechTranscriptMerger.merge(input))
    }

    func testCoherentJapaneseAndKoreanKeepIdentifiersAndUnicode() {
        for text in ["APIとbuild_240の設定を確認します。", "ﾐｰﾃｨﾝｸﾞの予定を確認します。", "오늘 漢字 자료를 확인하고 회의 일정을 정합니다."] {
            let spans = PolishSpanDetector.spans(in: text)
            XCTAssertFalse(PolishSpanDetector.looksMixedScript(text), text)
            XCTAssertEqual(spans.count, 1, text)
            XCTAssertTrue(spans.first?.polishable == true, text)
            XCTAssertEqual(spans.map(\.text).joined(), text)
        }
    }

    func testOneAudioRegionKeepsGenuineClauseSwitches() {
        for text in ["我们今天需要检查这张发票，明日の予定を確認します。", "Please send the invoice before our meeting tomorrow, 明日の予定を確認します。"] {
            let spans = PolishSpanDetector.translationSpans(in: text)
            XCTAssertEqual(spans.map(\.text).joined(), text)
            XCTAssertGreaterThan(Set(spans.compactMap(\.languageCode).map { $0.split(separator: "-").first.map(String.init)! }).count, 1, text)
        }
        let exact = "  明日の予定を確認します。\t\n\nPlease send the invoice — Cafe\u{301}.  "
        XCTAssertEqual(Array(PolishSpanDetector.spans(in: exact).map(\.text).joined().utf8), Array(exact.utf8))
        XCTAssertEqual(PolishSpanDetector.translationSpans(in: "APIを更新").map(\.text), ["APIを更新"])
    }

    func testStaleValidatedRegionCannotSendMixedSpeechToOneCleanupCall() async {
        let raw = "Please send the invoice 明日の予定を確認します"
        let engine = CountingPolishEngine { text, _, _ in
            XCTAssertNotEqual(text, raw, "one audio region is not one language")
            return text
        }
        let region = SpeechRegionTranscript(region: SpeechRegion(startSample: 0, endSample: 16000), text: raw,
            detectedLanguage: "en", validatedLanguage: "en")
        let result = await PolishSpanPipeline.polish(regions: [region], engine: engine)
        XCTAssertEqual(result.text, raw)
    }

    func testShortCapitalizedSentenceStillReceivesGrammarCorrection() async {
        let engine = CountingPolishEngine { text, _, _ in
            text.replacingOccurrences(of: "He go to work.", with: "He goes to work.")
        }
        let region = SpeechRegionTranscript(region: SpeechRegion(startSample: 0, endSample: 16000),
            text: "He go to work.", detectedLanguage: "en", validatedLanguage: "en")
        let result = await PolishSpanPipeline.polish(regions: [region], engine: engine)
        XCTAssertGreaterThan(engine.calls, 0)
        XCTAssertEqual(result.text, "He goes to work.")
    }

    func testFixturesScoreArtifactRemovalAndMixedPreservation() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "multilingual-cleanup", withExtension: "json", subdirectory: "Fixtures"
        ))
        let fixtures = try PolishCleanupEvaluation.loadFixtures(from: url)
        XCTAssertEqual(Set(fixtures.map(\.id)).count, fixtures.count)
        for fixture in fixtures {
            let scores = PolishCleanupEvaluation.score(fixture)
            XCTAssertTrue(scores.artifactFree, fixture.id)
            XCTAssertTrue(scores.mixedPreserved, fixture.id)
            XCTAssertTrue(scores.floorMatch, "\(fixture.id) floor=\(PolishPostpass.cleanupFloor(fixture.raw, language: nil))")
            XCTAssertTrue(scores.polishableMatch, fixture.id)
        }
    }

    func testMixedScriptSentenceIsNotPolishable() {
        let text = "Ich schicke dir the invoice tomorrow und 我晚上再确认。"
        XCTAssertTrue(PolishSpanDetector.looksMixedScript(text))
        let spans = PolishSpanDetector.spans(in: text)
        XCTAssertFalse(spans.contains(where: \.polishable))
    }

    func testGermanDictationIsPolishableAfterArtifactStrip() {
        let raw = "(snow crunching) So grundsätzlich habe ich jetzt einen Termin 15 Uhr. und heute dich dafür einladen."
        let floor = PolishPostpass.cleanupFloor(raw, language: nil)
        let spans = PolishSpanDetector.spans(in: floor)
        XCTAssertTrue(spans.contains(where: \.polishable))
        XCTAssertFalse(floor.contains("snow crunching"))
        XCTAssertTrue(floor.contains("einladen"))
    }

    func testSpanPipelineDoesNotSendMixedScriptToTheEngine() async {
        let engine = CountingPolishEngine { _, _, _ in
            XCTFail("mixed-script span must stay on the floor")
            return "translated"
        }
        let raw = "Ich schicke dir the invoice tomorrow und 我晚上再确认。"
        let result = await PolishSpanPipeline.polish(raw: raw, engine: engine)
        XCTAssertEqual(engine.calls, 0)
        XCTAssertEqual(result.text, raw)
        XCTAssertEqual(result.polishedSpanCount, 0)
        XCTAssertEqual(result.outcome, .skipped)
    }

    func testSpanPipelinePolishesMonolingualGermanSequentially() async {
        let engine = CountingPolishEngine { raw, _, _ in
            raw.replacingOccurrences(
                of: "So grundsätzlich habe ich jetzt einen Termin 15 Uhr.",
                with: "Ich habe jetzt einen Termin um 15 Uhr."
            ).replacingOccurrences(
                of: "und heute dich dafür einladen.",
                with: "Und heute lade ich dich dafür ein."
            )
        }
        let raw = "(snow crunching) So grundsätzlich habe ich jetzt einen Termin 15 Uhr. und heute dich dafür einladen."
        let result = await PolishSpanPipeline.polish(raw: raw, engine: engine)
        XCTAssertGreaterThanOrEqual(engine.calls, 1)
        XCTAssertFalse(result.text.contains("snow crunching"))
        XCTAssertFalse(result.text.contains("einladen"))
        XCTAssertTrue(result.text.contains("Ich habe jetzt einen Termin um 15 Uhr"))
        XCTAssertTrue(result.text.contains("lade ich dich dafür ein"))
        XCTAssertEqual(result.outcome, .success)
    }

    func testSkipEngineKeepsTheDeterministicFloor() async {
        let engine = CountingPolishEngine { _, _, _ in
            XCTFail("duration gate must skip the engine")
            return ""
        }
        let raw = "uh i i think we should ship it"
        let result = await PolishSpanPipeline.polish(raw: raw, engine: engine, skipEngine: true)
        XCTAssertEqual(engine.calls, 0)
        XCTAssertEqual(result.text, PolishPostpass.cleanupFloor(raw, language: nil))
        XCTAssertEqual(result.outcome, .skippedShort)
    }

    func testLanguageBoundaryGuardrailRejectsTranslatedCJK() {
        XCTAssertFalse(PolishGuardrail.preservesLanguageBoundaries(
            raw: "Ich schicke dir the invoice tomorrow und 我晚上再确认。",
            polished: "Ich schicke dir the invoice tomorrow und I will confirm tonight."
        ))
        XCTAssertTrue(PolishGuardrail.preservesLanguageBoundaries(
            raw: "Ich schicke dir the invoice tomorrow und 我晚上再确认。",
            polished: "Ich schicke dir the invoice tomorrow und 我晚上再确认。"
        ))
        XCTAssertTrue(PolishGuardrail.preservesLanguageBoundaries(
            raw: "Please send the invoice tomorrow.",
            polished: "Please send the invoice tomorrow."
        ))
    }

    func testEnglishRestatementFloorDropsSupersededTime() async {
        let raw = "Hey Jack I got like a appointment at 2am, oh sorry, it's 4am Um, yeah. So basically I got a poem at 4 a. m. Can you come by please?"
        let engine = CountingPolishEngine { text, _, _ in text }
        let result = await PolishSpanPipeline.polish(raw: raw, engine: engine)
        XCTAssertFalse(result.text.contains("2am"))
        XCTAssertTrue(result.text.contains("poem"), "A different statement at the same time must survive")
        XCTAssertTrue(result.text.contains("4am"))
        XCTAssertTrue(result.text.contains("Can you come by please"))
        XCTAssertGreaterThanOrEqual(engine.calls, 1)
        XCTAssertEqual(result.outcome, .success)
    }

    func testLatinCodeSwitchSameSentenceIsPolishable() async {
        let raw = "Ich schicke dir the invoice tomorrow."
        XCTAssertFalse(PolishSpanDetector.looksMixedScript(raw))
        let engine = CountingPolishEngine { text, _, _ in text }
        let result = await PolishSpanPipeline.polish(raw: raw, engine: engine)
        XCTAssertGreaterThanOrEqual(engine.calls, 1)
        XCTAssertTrue(result.text.contains("Ich schicke dir"))
        XCTAssertTrue(result.text.contains("invoice"))
        XCTAssertEqual(result.outcome, .success)
    }

    func testRegionAwarePipelineRevalidatesMixedRegions() async {
        let engine = CountingPolishEngine { text, _, _ in
            text + "!"
        }
        let regions = [
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 0, endSample: 100),
                text: "Mach bitte einen Termin for next Tuesday",
                detectedLanguage: "de",
                validatedLanguage: "de"
            ),
            SpeechRegionTranscript(
                region: SpeechRegion(startSample: 100, endSample: 200),
                text: "你好，can you send me die Rechnung bitte?",
                detectedLanguage: "zh",
                validatedLanguage: nil,
                overlapsPreviousRegion: false
            )
        ]

        let result = await PolishSpanPipeline.polish(regions: regions, engine: engine)

        XCTAssertEqual(engine.calls, 0)
        XCTAssertTrue(result.text.contains("Mach bitte einen Termin for next Tuesday"))
        XCTAssertTrue(result.text.contains("你好，can you send me die Rechnung bitte?"))
        XCTAssertEqual(result.polishedSpanCount, 0)
    }

    func testSpanAwareFlagDefaultsOn() {
        let defaults = UserDefaults(suiteName: "polish-span-aware-tests")!
        defaults.removePersistentDomain(forName: "polish-span-aware-tests")
        XCTAssertTrue(PolishSpanPipeline.isEnabled(in: defaults))
        defaults.set(false, forKey: SharedKeys.polishSpanAwareMultilingual)
        XCTAssertFalse(PolishSpanPipeline.isEnabled(in: defaults))
        defaults.set(true, forKey: SharedKeys.polishSpanAwareMultilingual)
        XCTAssertTrue(PolishSpanPipeline.isEnabled(in: defaults))
    }
}

private final class CountingPolishEngine: PolishEngineProtocol, @unchecked Sendable {
    let identifier = "test-counting"
    let announcesProcessingStage = false
    private let handler: (String, SupportedLanguage, PolishMode) throws -> String
    private let maximumInputCharacters: Int?
    private(set) var calls = 0
    private let lock = NSLock()

    init(maximumInputCharacters: Int? = nil,
         handler: @escaping (String, SupportedLanguage, PolishMode) throws -> String) {
        self.maximumInputCharacters = maximumInputCharacters
        self.handler = handler
    }

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        lock.withLock { calls += 1 }
        return try handler(raw, targetLanguage, mode)
    }

    func contextFit(input: String, targetLanguage: SupportedLanguage, mode: PolishMode) -> PolishContextFit {
        if let limit = maximumInputCharacters, input.count > limit {
            return .exceeds(estimatedTokens: input.count, budgetTokens: limit)
        }
        return .fits
    }
}
