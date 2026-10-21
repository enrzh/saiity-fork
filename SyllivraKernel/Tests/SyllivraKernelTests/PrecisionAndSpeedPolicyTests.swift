import XCTest
@testable import SyllivraKernel

final class PrecisionAndSpeedPolicyTests: XCTestCase {
    func testLanguageEvidenceKeepsTheReasonForASameScriptSwitch() {
        let mixed = SpeechLanguageEvidence.analyze(
            text: "Bitte schicken Sie die Rechnung morgen please send the address before our meeting tomorrow",
            detectedLanguage: "de")
        XCTAssertTrue(mixed.hasLanguageSwitch)
        XCTAssertFalse(mixed.isMixedScript)
        XCTAssertNil(mixed.validatedLanguageCode)

        let english = SpeechLanguageEvidence.analyze(text: "Please send the invoice tomorrow.", detectedLanguage: "en")
        XCTAssertFalse(english.hasLanguageSwitch)
        XCTAssertEqual(english.validatedLanguageCode, "en")
    }

    func testLanguageEvidenceResolvesLocalGrammarInsteadOfContradictoryAudioTag() {
        for (text, hint, expected) in [
            ("明日の予定を確認します", "zh", "ja"),
            ("我们今天需要检查这张发票并讨论会议安排", "ja", "zh"),
            ("ﾐｰﾃｨﾝｸﾞの予定を確認します", "zh", "ja"),
            ("오늘 漢字 자료를 확인하고 회의 일정을 정합니다", "zh", "ko"),
            ("APIとbuild_240の設定を確認します", "ja", "ja"),
            ("שלום אנחנו צריכים לבדוק את החשבונית מחר", "ar", "he"),
            ("يرجى التحقق من الفاتورة قبل الاجتماع غدا", "he", "ar"),
            ("Ovo je poruka na srpskom jeziku za naš sastanak", "sr-Latn", "sr"),
            ("हमें कल बैठक से पहले इस बिल की जाँच करनी है", "hi", "hi"),
            ("আমাদের আগামীকাল সভার আগে এই বিলটি পরীক্ষা করতে হবে", "bn", "bn"),
            ("நாளை கூட்டத்திற்கு முன் இந்த ரசீதை சரிபார்க்க வேண்டும்", "ta", "ta"),
            ("กรุณาตรวจสอบใบแจ้งหนี้ก่อนการประชุมในวันพรุ่งนี้", "th", "th")
        ] {
            let evidence = SpeechLanguageEvidence.analyze(text: text, detectedLanguage: hint)
            XCTAssertEqual(evidence.validatedLanguageCode?.split(separator: "-").first.map(String.init), expected, text)
        }
    }

    func testSharedScriptAndUnknownFragmentsStayUncertain() {
        for (text, hint) in [("東京大阪京都神戸", "zh"), ("API build_240", "en"),
                             ("invoice", "en"), ("字幕", "ja"), ("123", "de"),
                             ("добро", "ru"), ("a escola", "en")] {
            XCTAssertNil(SpeechLanguageEvidence.analyze(text: text, detectedLanguage: hint).validatedLanguageCode, text)
        }
        let original = "Cafe\u{301} — API_240\n字幕"
        _ = SpeechLanguageEvidence.analyze(text: original, detectedLanguage: nil)
        XCTAssertEqual(Array(original.utf8), Array("Cafe\u{301} — API_240\n字幕".utf8))
        let serbian = SpeechLanguageEvidence.analyze(text: "Ово је порука на српском језику за наш састанак", detectedLanguage: "sr-Cyrl")
        XCTAssertEqual(serbian.observedScripts, [.cyrillic])
        XCTAssertNil(serbian.validatedLanguageCode, "A contradictory shared-script vote must stay uncertain")
    }

    func testContradictoryArabicFamilyEvidenceUsesAutomaticSource() {
        let text = "ما باید این فاکتور را پیش از جلسه بررسی کنیم"
        XCTAssertNil(SpeechLanguageEvidence.sourceLanguage(in: text, hint: "ar"))
        XCTAssertNil(SpeechLanguageEvidence.sourceLanguage(in: text, hint: "fa"), "This platform reads the Persian phrase as Urdu; keep the contradiction uncertain")
        XCTAssertNil(SpeechLanguageEvidence.sourceLanguage(in: text))
    }

    func testChineseJapaneseSwitchCannotValidateOneRegionAsJapanese() {
        let text = "我们今天需要检查这张发票，明日の予定を確認します。"
        XCTAssertNil(SpeechLanguageEvidence.analyze(text: text, detectedLanguage: "ja").validatedLanguageCode)
        XCTAssertNil(SpeechLanguageEvidence.analyze(text: "Please send the invoice 明日の予定を確認します", detectedLanguage: "en").validatedLanguageCode)
        for text in ["明天上午开会안녕하세요", "明天上午开会よろしくお願いします"] {
            XCTAssertNil(SpeechLanguageEvidence.analyze(text: text, detectedLanguage: "zh").validatedLanguageCode, text)
        }
        XCTAssertEqual(SpeechLanguageEvidence.sourceLanguage(in: "DO NOT PAY THE INVOICE", hint: "en"), "en")
    }

    func testStrongSameScriptClausesCannotValidateAsOneLanguage() {
        let original = "Bitte schicken Sie die Rechnung morgen please send the address before our meeting tomorrow"
        XCTAssertNil(SpeechLanguageEvidence.sourceLanguage(in: original, hint: "de"))
        let spans = PolishSpanDetector.translationSpans(in: original, sourceHint: "de")
        XCTAssertEqual(spans.map(\.text).joined(), original)
        XCTAssertTrue(spans.contains { SpeechLanguageEvidence.baseCode($0.languageCode) == "de" })
        XCTAssertTrue(spans.contains { SpeechLanguageEvidence.baseCode($0.languageCode) == "en" })
    }

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

    func testWarmLatencyStoreUsesAnExponentialSmoothingSample() {
        let defaults = UserDefaults(suiteName: "PrecisionAndSpeedPolicyTests")!
        defaults.removePersistentDomain(forName: "PrecisionAndSpeedPolicyTests")
        ModelWarmLatencyStore.record(100, for: "small", in: defaults)
        ModelWarmLatencyStore.record(50, for: "small", in: defaults)
        XCTAssertEqual(ModelWarmLatencyStore.load(from: defaults)["small"], 90)
        defaults.removePersistentDomain(forName: "PrecisionAndSpeedPolicyTests")
    }
}
