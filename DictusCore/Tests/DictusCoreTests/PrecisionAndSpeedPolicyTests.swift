import XCTest
@testable import DictusCore

final class PrecisionAndSpeedPolicyTests: XCTestCase {
    func testAudioQualityDistinguishesQuietAndClippedInput() {
        let quiet = SpeechAudioQuality.analyze(Array(repeating: Float(0.01), count: 16_000))
        XCTAssertEqual(quiet.condition, .quiet)
        XCTAssertGreaterThan(quiet.recommendedGain, 1)

        let clipped = SpeechAudioQuality.analyze(Array(repeating: Float(1), count: 16_000))
        XCTAssertEqual(clipped.condition, .clipped)
        XCTAssertEqual(clipped.recommendedGain, 1)
    }

    func testLanguageEvidenceMatchesExpectedScriptAndAllowsMixedSpeech() {
        let German = SpeechLanguageEvidence.analyze(
            text: "Mach bitte einen Termin",
            detectedLanguage: "de"
        )
        XCTAssertEqual(German.score, 1)
        XCTAssertFalse(German.isMixedScript)

        let mixed = SpeechLanguageEvidence.analyze(
            text: "你好 send die Rechnung",
            detectedLanguage: "zh"
        )
        XCTAssertEqual(mixed.expectedScript, .han)
        XCTAssertTrue(mixed.isMixedScript)
        XCTAssertGreaterThan(mixed.score, 0.7)
    }

    func testLanguageEvidenceRejectsShortOrIncompatibleDetections() {
        let short = SpeechLanguageEvidence.analyze(
            text: "invoice",
            detectedLanguage: "en"
        )
        XCTAssertNil(short.validatedLanguageCode)

        let mixed = SpeechLanguageEvidence.analyze(
            text: "你好 please send the invoice",
            detectedLanguage: "en"
        )
        XCTAssertNil(mixed.validatedLanguageCode)
    }

    func testJapaneseHanAndKanaAreOneCompatibleScriptFamily() {
        let evidence = SpeechLanguageEvidence.analyze(
            text: "明日の予定を確認します",
            detectedLanguage: "ja"
        )
        XCTAssertEqual(evidence.validatedLanguageCode, "ja")
    }

    func testGainDoesNotAmplifyNoisyOrClippedInput() {
        let noisy = Array(repeating: Float(0.03), count: 16_000)
        XCTAssertEqual(SpeechAudioGain.gain(for: noisy[...]), 1)
    }

    func testPolishCacheIsBoundedAndRefreshesRecency() {
        var cache = PolishResultCache(capacity: 2)
        let first = PolishResultCache.Key(raw: "one", engine: "local", target: nil, spanAware: true)
        let second = PolishResultCache.Key(raw: "two", engine: "local", target: nil, spanAware: true)
        let third = PolishResultCache.Key(raw: "three", engine: "local", target: nil, spanAware: true)
        cache.insert("1", for: first)
        cache.insert("2", for: second)
        XCTAssertEqual(cache.value(for: first), "1")
        cache.insert("3", for: third)
        XCTAssertNil(cache.value(for: second))
        XCTAssertEqual(cache.value(for: first), "1")
    }

    func testPredictionCacheReturnsOnlyTheLatestBoundedEntries() {
        let cache = NextCharacterPredictionCache(capacity: 1)
        cache.insert(NextCharacterProbabilities(["a": 1]), for: "first")
        XCTAssertNotNil(cache.value(for: "first"))
        cache.insert(NextCharacterProbabilities(["b": 1]), for: "second")
        XCTAssertNil(cache.value(for: "first"))
        XCTAssertEqual(cache.value(for: "second")?["b"], 1)
    }

    func testWarmLatencyStoreUsesAnExponentialSmoothingSample() {
        let defaults = UserDefaults(suiteName: "PrecisionAndSpeedPolicyTests")!
        defaults.removePersistentDomain(forName: "PrecisionAndSpeedPolicyTests")
        ModelWarmLatencyStore.record(100, for: "small", in: defaults)
        ModelWarmLatencyStore.record(50, for: "small", in: defaults)
        XCTAssertEqual(ModelWarmLatencyStore.load(from: defaults)["small"], 90)
        defaults.removePersistentDomain(forName: "PrecisionAndSpeedPolicyTests")
    }
}
