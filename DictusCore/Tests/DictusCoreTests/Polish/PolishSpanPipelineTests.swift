import XCTest
@testable import DictusCore

final class PolishSpanPipelineTests: XCTestCase {
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
    private let handler: (String, SupportedLanguage, PolishMode) -> String
    private(set) var calls = 0
    private let lock = NSLock()

    init(handler: @escaping (String, SupportedLanguage, PolishMode) -> String) {
        self.handler = handler
    }

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        lock.lock()
        calls += 1
        lock.unlock()
        return handler(raw, targetLanguage, mode)
    }
}
