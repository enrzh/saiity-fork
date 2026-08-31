import XCTest
@testable import DictusCore

final class DictationLanguageRequestTests: XCTestCase {
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
        XCTAssertEqual(readiness.readyTargets(for: asr.sourceLanguage), [.english])
        XCTAssertEqual(readiness.selectableTargets(for: asr.sourceLanguage), [.english, .german])
        XCTAssertFalse(readiness.selectableTargets(for: asr.sourceLanguage).contains(.spanish))
        XCTAssertEqual(
            readiness.status(for: .english, sourceLanguage: asr.sourceLanguage),
            .installedReady
        )
        XCTAssertEqual(
            readiness.status(for: .german, sourceLanguage: asr.sourceLanguage),
            .supportedNeedsDownload
        )
        XCTAssertEqual(
            readiness.menuLabel(for: .german, sourceLanguage: asr.sourceLanguage),
            "Translate to Deutsch (Download required)"
        )
        XCTAssertEqual(
            readiness.accessibilityLabel(for: .german, sourceLanguage: asr.sourceLanguage),
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
            TranslationTargetReadiness.load(from: defaults)?.selectableTargets(for: nil),
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
            currentSessionID: "session-1",
            currentGeneration: 4,
            currentClientIdentifier: "client-1"
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
            currentSessionID: "session-1",
            currentGeneration: 4,
            currentClientIdentifier: "client-1"
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
            currentSessionID: "session-2",
            currentGeneration: 5,
            currentClientIdentifier: "client-2"
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
