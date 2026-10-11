import XCTest
@testable import DictusCore

final class DictationLanguageRequestTests: XCTestCase {
    func testAutomaticSourceCannotPromiseAnInstalledTranslationPair() {
        let readiness = TranslationTargetReadiness(source: "auto", installedTargets: ["en"], supportedTargets: ["en", "zh-Hans"])
        XCTAssertEqual(readiness.status(for: .english, sourceCode: nil), .checking)
        XCTAssertEqual(readiness.readyTargets(forSourceCode: nil), [])
        XCTAssertEqual(readiness.selectableTargets(forSourceCode: nil), [.english, .chineseSimplified])
    }

    func testCombinedTranslationPreservesSeparatorsRepetitionAndRejectsPartialSuccess() {
        let clauses = ["Bonjour.\t\n", "Bonjour."]
        let original = clauses.joined()
        XCTAssertEqual(TranslationOutcome.combined(original: original, clauses: clauses,
            outcomes: [.translated("Hello.\t\n"), .translated("Hello.")], target: .english), .translated("Hello.\t\nHello."))
        XCTAssertEqual(TranslationOutcome.combined(original: original, clauses: clauses,
            outcomes: [.translated("Hello.\t\n"), .fallback("Bonjour.", reason: .unavailable)], target: .english),
            .fallback(original, reason: .unavailable))
        XCTAssertEqual(TranslationOutcome.combined(original: original, clauses: clauses,
            outcomes: [.translated("Hello.\t\n"), .translated("明日の予定を確認します。")], target: .english),
            .fallback(original, reason: .rejectedOutput))
    }
    func testTranslationRejectsWrongLanguageAndUntranslatedClauses() {
        for output in ["Merci.", "明日の予定を確認します。", "Please check the invoice. 明日の予定を確認します。", "我们今天需要检查这张发票。"] {
            let original = "Veuillez vérifier la facture avant la réunion de demain."
            let outcome = TranslationOutcome.resolved(original: original, translated: output,
                clientIdentifierMatches: true, target: .english)
            XCTAssertEqual(outcome.resolvedText, original, output)
        }
    }

    func testTranslationKeepsAmountCurrencyAssociationAndIdentifiers() {
        for (original, output) in [
            ("Payez €10 et $20.", "Pay €20 and $10."),
            ("Pay CHF 25.", "Pay CAD 25."),
            ("Veuillez confirmer build_240 demain.", "Please confirm release_240 tomorrow."),
            ("行きません。", "I will go."),
            ("不要付款。", "Pay now.")
        ] {
            XCTAssertEqual(TranslationOutcome.resolved(original: original, translated: output,
                clientIdentifierMatches: true, target: .english).resolvedText, original, original)
        }
        XCTAssertEqual(TranslationOutcome.resolved(original: "يرجى دفع ١٬٢٥٠ €.", translated: "Please pay €1,250.",
            clientIdentifierMatches: true, target: .english), .translated("Please pay €1,250."))
    }

    func testTranslationDoesNotReorderDateOrClockComponents() {
        for (original, changed) in [("Rendez-vous le 12/10/2026 à 09:30.", "Meet on 10/12/2026 at 09:30."),
                                    ("Rendez-vous à 12:30.", "Meet at 30:12.")] {
            XCTAssertEqual(TranslationOutcome.resolved(original: original, translated: changed,
                clientIdentifierMatches: true, target: .english).resolvedText, original)
        }
        XCTAssertEqual(TranslationOutcome.resolved(original: "Rendez-vous le 12/10/2026 à 09:30.",
            translated: "Meet on 12/10/2026 at 09:30.", clientIdentifierMatches: true, target: .english),
            .translated("Meet on 12/10/2026 at 09:30."))
    }

    func testTranslationAcceptsChineseNegationVariantsAndClauseLocales() {
        XCTAssertEqual(TranslationOutcome.numericFacts(in: "Pay €25.", language: "en"),
                       TranslationOutcome.numericFacts(in: "支付25欧元。", language: "zh-Hans"))
        let source = "我們今天無法完成全部付款請稍後再試。"
        let result = "我们今天无法完成全部付款请稍后再试。"
        XCTAssertEqual(TranslationOutcome.resolved(original: source, translated: result,
            clientIdentifierMatches: true, target: .chineseSimplified), .translated(result))
        let german = "Bitte überweisen Sie 1.000 Euro."
        let english = "Please transfer 1000 euros."
        XCTAssertEqual(TranslationOutcome.combined(original: german, clauses: [german],
            outcomes: [.translated(english)], target: .english), .translated(english))
        XCTAssertEqual(TranslationOutcome.resolved(original: "Pay €25.", translated: "支付25欧元。",
            clientIdentifierMatches: true, target: .chineseSimplified), .translated("支付25欧元。"))
        let omitted = "Veuillez envoyer la facture à Alice et annuler la livraison."
        XCTAssertEqual(TranslationOutcome.resolved(original: omitted, translated: "Please send the invoice to Alice.",
            clientIdentifierMatches: true, target: .english).resolvedText, omitted)
        XCTAssertEqual(TranslationOutcome.resolved(original: "请支付25欧元。", translated: "请支付52欧元。",
            clientIdentifierMatches: true, target: .chineseSimplified).resolvedText, "请支付25欧元。")
        XCTAssertEqual(TranslationOutcome.resolved(original: "今日は元気です。", translated: "I feel fine today.",
            clientIdentifierMatches: true, target: .english), .translated("I feel fine today."))
    }

    func testTranslationFallbackAssemblyKeepsTheExactOriginal() {
        let original = "a escola\t\nCafe\u{301} — API_240"
        let assembled = TranscriptionPipeline.assemble(cleaned: original, grammarLanguage: .english,
            insertAsIs: true, preserveOriginal: true)
        XCTAssertEqual(Array(assembled.body.utf8), Array(original.utf8))
        XCTAssertEqual(Array(assembled.formatted.utf8), Array(original.utf8))
    }

    func testTranslationAcceptsPreservedNamesIdentifiersAndLocalizedNumbers() {
        for (original, output) in [
            ("Veuillez appeler Paris et confirmer API_240.", "Please call Paris and confirm API_240."),
            ("Payez 25,50 € à Zoë le 2026-10-12.", "Pay €25.50 to Zoë on 2026-10-12."),
            ("Ne payez pas la facture.", "Do not pay the invoice."),
            ("請檢查這張發票。", "请检查这张发票。"),
            ("Veuillez confirmer ٢٥٫٥٠ €.", "Please confirm €25.50.")
        ] {
            let target: TranslationLanguage = original.contains("請") ? .chineseSimplified : .english
            XCTAssertEqual(TranslationOutcome.resolved(original: original, translated: output,
                clientIdentifierMatches: true, target: target), .translated(output), original)
        }
        let original = "請檢查這張發票。"
        XCTAssertEqual(TranslationOutcome.resolved(original: original, translated: original,
            clientIdentifierMatches: true, target: .chineseSimplified).resolvedText, original)
        let echo = TranslationOutcome.resolved(original: original, translated: original,
            clientIdentifierMatches: true, target: .chineseSimplified)
        if case .translated = echo { XCTFail("Traditional output was labelled Simplified") }
    }
    func testTranslationCannotSilentlyChangeOrDropFacts() {
        for (original, translated) in [
            ("Envoyez 25 euros demain.", "Send 52 euros tomorrow."),
            ("Livraison le 2026-10-12.", "Delivery on 2026-12-10."),
            ("Payez €25.", "Pay $25."),
            ("Ne payez pas la facture.", "Pay the invoice."),
            ("Envoyez la facture. Confirmez ensuite la livraison.", "Send the invoice.")
        ] {
            let outcome = TranslationOutcome.resolved(original: original, translated: translated, clientIdentifierMatches: true)
            XCTAssertEqual(outcome.resolvedText, original, original)
            if case .translated = outcome { XCTFail("Unsafe output was labelled translated: \(original)") }
        }
        XCTAssertEqual(TranslationOutcome.resolved(original: "Envoyez 25 euros demain.", translated: "Send 25 euros tomorrow.",
                                                   clientIdentifierMatches: true), .translated("Send 25 euros tomorrow."))
    }


    func testMissingRequestUsesAutomaticTranscriptionPreference() {
        let suiteName = "dictus.plan.missing-request-auto-tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(TranscriptionLanguageMode.autoStoredValue, forKey: SharedKeys.transcriptionLanguage)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            DictationLanguageRequest.load(from: defaults).mode,
            .autoDetect,
            "a direct app dictation must honor the Auto setting when no keyboard request exists"
        )
    }

    func testMissingRequestDefaultsToAutomaticWhenPreferenceIsAbsent() {
        let suiteName = "dictus.plan.missing-request-default-tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            DictationLanguageRequest.load(from: defaults).mode,
            .autoDetect,
            "a fresh direct app dictation must not inherit the keyboard language"
        )
    }

    func testUnboundRequestAlwaysUsesAutomaticTranscription() {
        let request = DictationLanguageRequest(mode: .followKeyboard, translationTarget: nil)

        XCTAssertEqual(
            request.modeForNextDictation(defaultingTo: .autoDetect),
            .autoDetect
        )
    }

    func testBoundRequestAlsoUsesAutomaticTranscription() {
        let request = DictationLanguageRequest(
            mode: .followKeyboard,
            translationTarget: nil,
            sessionID: "session-1",
            generation: 1,
            clientIdentifier: "client-1"
        )

        XCTAssertEqual(
            request.modeForNextDictation(defaultingTo: .autoDetect),
            .autoDetect
        )
    }

    func testOnlyWhisperMultilingualAutoDetectDisplaysAUTO() {
        XCTAssertEqual(
            ASRCapability.forModelIdentifier(
                "openai_whisper-small",
                mode: .autoDetect,
                keyboardLanguage: .french
            ).displaySourceCode,
            "AUTO"
        )
        XCTAssertEqual(
            ASRCapability.forModelIdentifier(
                "parakeet-tdt-0.6b-v3",
                mode: .autoDetect,
                keyboardLanguage: .french
            ).displaySourceCode,
            "--"
        )
        for mode in [TranscriptionLanguageMode.autoDetect, .followKeyboard, .explicit(.german)] {
            let capability = ASRCapability.forModelIdentifier(
                "parakeet-tdt-0.6b-v3",
                mode: mode,
                keyboardLanguage: .french
            )
            XCTAssertNil(capability.sourceLanguage)
            XCTAssertEqual(capability.displaySourceCode, "--")
        }
        XCTAssertEqual(
            ASRCapability.forModelIdentifier(
                "unknown-model",
                mode: .followKeyboard,
                keyboardLanguage: .french
            ).displaySourceCode,
            "--"
        )
        XCTAssertEqual(
            ASRCapability(supportsAutomaticInputLanguage: false, sourceLanguage: .french).displaySourceCode,
            "FR"
        )
        XCTAssertEqual(
            ASRCapability.forModelIdentifier(
                "openai_whisper-small",
                mode: .followKeyboard,
                keyboardLanguage: .french
            ).displaySourceCode,
            "FR"
        )
        XCTAssertEqual(
            ASRCapability.forModelIdentifier(
                "openai_whisper-small",
                mode: .explicit(.german),
                keyboardLanguage: .french
            ).displaySourceCode,
            "DE"
        )
    }

    func testReadinessSeparatesInstalledAndSupportedFixedFrenchTargets() {
        let asr = ASRCapability(supportsAutomaticInputLanguage: false, sourceLanguage: .french)
        let readiness = TranslationTargetReadiness(
            source: "fr",
            installedTargets: ["en"],
            supportedTargets: ["en", "de"]
        )
        XCTAssertEqual(readiness.readyTargets(forSourceCode: asr.sourceLanguage?.rawValue), [.english])
        XCTAssertEqual(readiness.selectableTargets(forSourceCode: asr.sourceLanguage?.rawValue), [.english, .german])
        XCTAssertFalse(readiness.selectableTargets(forSourceCode: asr.sourceLanguage?.rawValue).contains(.spanish))
        XCTAssertEqual(
            readiness.status(for: .english, sourceCode: asr.sourceLanguage?.rawValue),
            .installedReady
        )
        XCTAssertEqual(
            readiness.status(for: .german, sourceCode: asr.sourceLanguage?.rawValue),
            .supportedNeedsDownload
        )
        XCTAssertEqual(
            readiness.menuLabel(for: .german, sourceCode: asr.sourceLanguage?.rawValue),
            "Translate to Deutsch (Download required)"
        )
        XCTAssertEqual(
            readiness.accessibilityLabel(for: .german, sourceCode: asr.sourceLanguage?.rawValue),
            "Translate to Deutsch, download required"
        )
    }

    func testReadinessSnapshotIsAbsentUntilTheAppWritesIt() {
        let suiteName = "dictus.plan.readiness-tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(TranslationTargetReadiness.load(from: defaults))
        TranslationTargetReadiness(
            source: "auto",
            installedTargets: ["en"],
            supportedTargets: ["en", "de"]
        ).persist(to: defaults)

        XCTAssertEqual(
            TranslationTargetReadiness.load(from: defaults)?.selectableTargets(forSourceCode: nil),
            [.english, .german]
        )
    }

    func testRequestRoundTripsModeAndTargetThroughDefaults() {
        let suiteName = "dictus.plan.request-tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let request = DictationLanguageRequest(
            mode: .explicit(.german),
            translationTarget: .english,
            sessionID: "session-1",
            generation: 4,
            clientIdentifier: "client-1",
            resolvedSourceLanguage: .german
        )
        request.persist(to: defaults)

        XCTAssertEqual(DictationLanguageRequest.load(from: defaults), request)
        XCTAssertNotNil(defaults.data(forKey: DictationLanguageRequest.appGroupKey))
        XCTAssertNil(defaults.object(forKey: DictationLanguageRequest.appGroupKey + ".mode"))
        XCTAssertNil(defaults.object(forKey: DictationLanguageRequest.appGroupKey + ".target"))
    }

    func testLegacyRequestMigratesOnlyWhenItsFieldsAreWellFormed() {
        let defaults = UserDefaults(suiteName: "dictus.plan.legacy-request-tests")!
        defaults.removePersistentDomain(forName: "dictus.plan.legacy-request-tests")
        defer { defaults.removePersistentDomain(forName: "dictus.plan.legacy-request-tests") }

        defaults.set("de", forKey: DictationLanguageRequest.appGroupKey + ".mode")
        defaults.set("en", forKey: DictationLanguageRequest.appGroupKey + ".target")
        let migrated = DictationLanguageRequest.load(from: defaults)
        XCTAssertEqual(migrated.mode, .explicit(.german))
        XCTAssertEqual(migrated.translationTarget, .english)
        XCTAssertFalse(migrated.isBound)

        defaults.set(4, forKey: DictationLanguageRequest.appGroupKey + ".generation")
        XCTAssertFalse(DictationLanguageRequest.load(from: defaults).isBound)
    }

    func testMalformedBlobFailsClosedAndBindingClearPreservesPreferences() throws {
        let defaults = UserDefaults(suiteName: "dictus.plan.request-integrity-tests")!
        defaults.removePersistentDomain(forName: "dictus.plan.request-integrity-tests")
        defer { defaults.removePersistentDomain(forName: "dictus.plan.request-integrity-tests") }

        defaults.set(Data("{\"mode\":\"auto\"}".utf8), forKey: DictationLanguageRequest.appGroupKey)
        let malformed = DictationLanguageRequest.load(from: defaults)
        XCTAssertEqual(malformed.mode, .followKeyboard)
        XCTAssertNil(malformed.translationTarget)
        XCTAssertFalse(malformed.isBound)

        let mixed = DictationLanguageRequest(
            mode: .autoDetect,
            translationTarget: .english
        ).withResolvedSourceLanguage(.french)
        defaults.set(try JSONEncoder().encode(mixed), forKey: DictationLanguageRequest.appGroupKey)
        XCTAssertEqual(
            DictationLanguageRequest.load(from: defaults).mode,
            .followKeyboard
        )

        let bound = DictationLanguageRequest(
            mode: .autoDetect,
            translationTarget: .english,
            sessionID: "session-1",
            generation: 4,
            clientIdentifier: "client-1"
        )
        let unbound = bound.unbound()
        unbound.persist(to: defaults)
        XCTAssertEqual(DictationLanguageRequest.load(from: defaults), unbound)
        XCTAssertNil(unbound.sessionID)
        XCTAssertNil(unbound.generation)
        XCTAssertNil(unbound.clientIdentifier)
        XCTAssertEqual(unbound.mode, .autoDetect)
        XCTAssertEqual(unbound.translationTarget, .english)
    }

    func testRequestBindingRejectsStaleSessionAndClient() {
        let request = DictationLanguageRequest(
            mode: .explicit(.german),
            translationTarget: .english,
            sessionID: "session-1",
            generation: 4,
            clientIdentifier: "client-1"
        )

        XCTAssertTrue(request.matches(sessionID: "session-1", generation: 4, clientIdentifier: "client-1"))
        XCTAssertFalse(request.matches(sessionID: "session-2", generation: 4, clientIdentifier: "client-1"))
        XCTAssertFalse(request.matches(sessionID: "session-1", generation: 5, clientIdentifier: "client-1"))
        XCTAssertFalse(request.matches(sessionID: "session-1", generation: 4, clientIdentifier: "client-2"))

        let rebound = request.bound(sessionID: "session-2", generation: 5, clientIdentifier: "client-2")
        XCTAssertEqual(rebound.mode, .explicit(.german))
        XCTAssertEqual(rebound.translationTarget, .english)
    }

    func testTranslationOutcomeUsesOriginalForUnavailableEmptyAndMismatchedResponses() {
        XCTAssertEqual(
            TranslationOutcome.resolved(original: "Bonjour", translated: "Hello", clientIdentifierMatches: true),
            .translated("Hello")
        )
        XCTAssertEqual(
            TranslationOutcome.resolved(original: "Bonjour", translated: "", clientIdentifierMatches: true),
            .fallbackOriginal("Bonjour", reason: .emptyResponse)
        )
        XCTAssertEqual(
            TranslationOutcome.resolved(original: "Bonjour", translated: "Hello", clientIdentifierMatches: false),
            .fallbackOriginal("Bonjour", reason: .mismatchedClient)
        )
        XCTAssertEqual(
            TranslationOutcome.fallback("Bonjour", reason: .unavailable).resolvedText,
            "Bonjour"
        )
    }

    func testFinalizationOrderRequiresAuthoritativeThenTranslationThenReadyThenAck() {
        XCTAssertTrue(DictationFinalizationStep.isValid([
            .authoritativeTranscript, .translation, .ready, .publish, .insertionAcknowledged
        ]))
        XCTAssertFalse(DictationFinalizationStep.isValid([
            .authoritativeTranscript, .ready, .translation, .insertionAcknowledged
        ]))
        XCTAssertFalse(DictationFinalizationStep.isValid([
            .authoritativeTranscript, .insertionAcknowledged
        ]))
    }

    func testFinalizationDecisionDrivesSuccessAndFallbackWithoutError() {
        let request = DictationLanguageRequest(
            mode: .explicit(.french),
            translationTarget: .english,
            sessionID: "session-1",
            generation: 4,
            clientIdentifier: "client-1"
        )
        let success = DictationFinalizationDecision.make(
            transcript: "Bonjour",
            outcome: .translated("Hello"),
            request: request,
            currentRequest: request
        )
        XCTAssertEqual(success.finalText, "Hello")
        XCTAssertTrue(success.shouldPublish)
        XCTAssertNil(success.errorMessage)
        XCTAssertEqual(success.steps, [
            .authoritativeTranscript, .translation, .ready, .publish, .insertionAcknowledged
        ])

        let fallback = DictationFinalizationDecision.make(
            transcript: "Bonjour",
            outcome: .fallback("Bonjour", reason: .unavailable),
            request: request,
            currentRequest: request
        )
        XCTAssertEqual(fallback.finalText, "Bonjour")
        XCTAssertTrue(fallback.shouldPublish)
        XCTAssertNil(fallback.errorMessage)
    }

    func testFinalizationDecisionDropsStaleRequestBeforeReadyOrPublish() {
        let request = DictationLanguageRequest(
            mode: .explicit(.french),
            translationTarget: .english,
            sessionID: "session-1",
            generation: 4,
            clientIdentifier: "client-1"
        )
        let decision = DictationFinalizationDecision.make(
            transcript: "Bonjour",
            outcome: .translated("Hello"),
            request: request,
            currentRequest: DictationLanguageRequest(
                mode: .explicit(.french),
                translationTarget: .english,
                sessionID: "session-2",
                generation: 5,
                clientIdentifier: "client-2"
            )
        )
        XCTAssertNil(decision.finalText)
        XCTAssertFalse(decision.shouldPublish)
        XCTAssertEqual(decision.steps, [])
        XCTAssertNil(decision.errorMessage)
    }

    func testCancellationContinuationDecisionResumesExactlyOnce() {
        var continuation = DictationCancellationContinuation()
        XCTAssertTrue(continuation.resume())
        XCTAssertFalse(continuation.resume())
        XCTAssertEqual(continuation.resumeCount, 1)
    }

    func testStaleIdentityAfterAvailabilityAwaitDoesNotInvokeTranslation() async {
        let request = DictationLanguageRequest(
            mode: .explicit(.french),
            translationTarget: .english,
            sessionID: "session-1",
            generation: 4,
            clientIdentifier: "client-1"
        )
        var currentSessionID = "session-1"
        let currentGeneration = 4
        let currentClientIdentifier = "client-1"
        var translationInvocationCount = 0

        XCTAssertTrue(request.matches(
            sessionID: currentSessionID,
            generation: currentGeneration,
            clientIdentifier: currentClientIdentifier
        ))
        await Task.yield()
        currentSessionID = "session-2"

        guard request.matches(
            sessionID: currentSessionID,
            generation: currentGeneration,
            clientIdentifier: currentClientIdentifier
        ) else { return }
        translationInvocationCount += 1

        XCTAssertEqual(translationInvocationCount, 0)
    }
}
