import XCTest
@testable import DictusCore

final class EmojiHoldArbitrationTests: XCTestCase {
    func testIneligibleTouchFailsImmediatelyAndUnblocksThePan() {
        var hold = EmojiHoldArbitration(movementAllowance: 8)
        hold.beginTouch(eligible: false)
        XCTAssertEqual(hold.phase, .failed)
        XCTAssertFalse(hold.isTracking)
        hold.move(distance: 40)
        XCTAssertEqual(hold.phase, .failed)
    }

    func testNonvariantReleaseFailsInsteadOfInsertingAHold() {
        var hold = EmojiHoldArbitration(movementAllowance: 8)
        hold.beginTouch(eligible: false)
        hold.endTouch()
        XCTAssertEqual(hold.phase, .failed)
    }

    func testJitterBeforeRecognitionFailsTheHold() {
        var hold = EmojiHoldArbitration(movementAllowance: 8)
        hold.beginTouch(eligible: true)
        hold.move(distance: 3)
        XCTAssertEqual(hold.phase, .possible)
        hold.move(distance: 12)
        XCTAssertEqual(hold.phase, .failed)
    }

    func testRecognizedHoldKeepsOwnershipOutsideThePopup() {
        var hold = EmojiHoldArbitration(movementAllowance: 8)
        hold.beginTouch(eligible: true)
        hold.recognize()
        XCTAssertEqual(hold.phase, .began)
        hold.move(distance: 200)
        XCTAssertEqual(hold.phase, .changed)
        hold.endTouch()
        XCTAssertEqual(hold.phase, .ended)
    }

    func testCancellationEndsAnActiveHoldWithoutAnInsertPhase() {
        var hold = EmojiHoldArbitration(movementAllowance: 8)
        hold.beginTouch(eligible: true)
        hold.recognize()
        hold.cancelTouch()
        XCTAssertEqual(hold.phase, .cancelled)
    }

    func testTwentyConsecutiveBlankSwipesEachFailTheHold() {
        for _ in 0..<20 {
            var hold = EmojiHoldArbitration(movementAllowance: 8)
            hold.beginTouch(eligible: false)
            hold.move(distance: 30)
            XCTAssertEqual(hold.phase, .failed)
        }
    }
}

final class IsolatedDeadlineTests: XCTestCase {
    func testCancellationIgnoringWorkReturnsOnTheDeadline() async {
        let started = Date()
        var published = false
        let outcome = await IsolatedDeadline.race(seconds: 0.05) { () -> Int in
            _ = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
                    published = true
                    continuation.resume(returning: 1)
                }
            }
            return 1
        }
        let elapsed = Date().timeIntervalSince(started)
        guard case .timedOut = outcome else {
            return XCTFail("expected timeout, got a finished race")
        }
        XCTAssertLessThan(elapsed, 0.25)
        XCTAssertFalse(published)
    }

    func testSuccessErrorAndASecondRaceDoNotOverlapTheFirst() async throws {
        let success = await IsolatedDeadline.race(seconds: 1) { 7 }
        guard case .success(let value) = success else { return XCTFail("expected success") }
        XCTAssertEqual(value, 7)

        let failure = await IsolatedDeadline.race(seconds: 1) { () -> Int in
            throw IsolatedDeadlineProbeError.broken
        }
        guard case .failure = failure else { return XCTFail("expected failure") }

        let blocked = await IsolatedDeadline.race(seconds: 0.05) { () -> Int in
            try await Task.sleep(nanoseconds: 400_000_000)
            return 3
        }
        guard case .timedOut(let release) = blocked else { return XCTFail("expected timeout") }
        let secondStarted = Date()
        await release()
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(secondStarted), 0.2)
    }

    func testParentCancellationDoesNotWaitForTheDeadline() async {
        let started = Date()
        let task = Task {
            await IsolatedDeadline.race(seconds: 30) { () -> Int in
                _ = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        continuation.resume(returning: 1)
                    }
                }
                return 1
            }
        }
        task.cancel()
        let outcome = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        guard case .cancelled = outcome else {
            return XCTFail("expected cancellation, not a 30s wait")
        }
    }
}

private enum IsolatedDeadlineProbeError: Error {
    case broken
}

final class PolishCacheAdmissionTests: XCTestCase {
    func testShortAndLongClipsDoNotShareAResult() {
        var cache = PolishResultCache()
        let key = sampleKey(engine: "whisper", mode: "auto", style: "balanced")
        let short = resolve(cache: &cache, duration: 0.4, key: key, engineRan: true, output: "floor")
        XCTAssertEqual(short.output, "floor")
        XCTAssertEqual(short.engineCalls, 1)
        let longFirst = resolve(cache: &cache, duration: 3, key: key, engineRan: true, output: "model")
        XCTAssertEqual(longFirst.output, "model")
        XCTAssertEqual(longFirst.engineCalls, 1)
        let longHit = resolve(cache: &cache, duration: 3, key: key, engineRan: true, output: "model-again")
        XCTAssertEqual(longHit.output, "model")
        XCTAssertEqual(longHit.engineCalls, 0)
        let shortAfter = resolve(cache: &cache, duration: 0.2, key: key, engineRan: false, output: "floor-again")
        XCTAssertEqual(shortAfter.output, "floor-again")
        XCTAssertEqual(shortAfter.engineCalls, 1)
    }

    func testPolicyDimensionsAndFailuresDoNotReuseTheWrongResult() {
        var cache = PolishResultCache()
        let whisper = sampleKey(engine: "whisper", mode: "auto", style: "balanced")
        let parakeet = sampleKey(engine: "parakeet", mode: "auto", style: "balanced")
        let explicit = sampleKey(engine: "whisper", mode: "fr", style: "balanced")
        let formal = sampleKey(engine: "whisper", mode: "auto", style: "formal")
        _ = resolve(cache: &cache, duration: 3, key: whisper, engineRan: true, output: "w")
        let otherEngine = resolve(cache: &cache, duration: 3, key: parakeet, engineRan: true, output: "p")
        XCTAssertEqual(otherEngine.output, "p")
        XCTAssertEqual(otherEngine.engineCalls, 1)
        let otherLanguage = resolve(cache: &cache, duration: 3, key: explicit, engineRan: true, output: "fr")
        XCTAssertEqual(otherLanguage.engineCalls, 1)
        let otherStyle = resolve(cache: &cache, duration: 3, key: formal, engineRan: true, output: "formal")
        XCTAssertEqual(otherStyle.engineCalls, 1)

        var failed = PolishResultCache()
        let skipped = resolve(cache: &failed, duration: 3, key: whisper, engineRan: false, output: "raw")
        XCTAssertEqual(skipped.output, "raw")
        let retry = resolve(cache: &failed, duration: 3, key: whisper, engineRan: true, output: "cleaned")
        XCTAssertEqual(retry.output, "cleaned")
        XCTAssertEqual(retry.engineCalls, 1)

        var cancelledCache = PolishResultCache()
        let cancelled = resolve(
            cache: &cancelledCache, duration: 3, key: whisper,
            engineRan: true, cancelled: true, output: "partial"
        )
        XCTAssertEqual(cancelled.output, "partial")
        let afterCancel = resolve(cache: &cancelledCache, duration: 3, key: whisper, engineRan: true, output: "retry")
        XCTAssertEqual(afterCancel.engineCalls, 1)
        XCTAssertEqual(afterCancel.output, "retry")

        var fallback = PolishResultCache()
        let startedThenFailed = resolve(
            cache: &fallback, duration: 3, key: whisper,
            engineRan: false, output: "deterministic floor"
        )
        XCTAssertEqual(startedThenFailed.output, "deterministic floor")
        let retryAfterFailure = resolve(cache: &fallback, duration: 3, key: whisper, engineRan: true, output: "model")
        XCTAssertEqual(retryAfterFailure.engineCalls, 1)
        XCTAssertEqual(retryAfterFailure.output, "model")
    }

    private func sampleKey(engine: String, mode: String, style: String) -> PolishResultCache.Key {
        PolishResultCache.Key(
            raw: "same words",
            engine: engine,
            target: nil,
            spanAware: false,
            writingStyle: style,
            modelIdentifier: engine == "parakeet" ? "parakeet" : "whisper-small",
            transcriptionMode: mode,
            outputMode: mode == "auto" ? "multilingual" : "single",
            keyboardLanguage: "en"
        )
    }

    private func resolve(
        cache: inout PolishResultCache,
        duration: TimeInterval,
        key: PolishResultCache.Key,
        engineRan: Bool,
        cancelled: Bool = false,
        output: String
    ) -> (output: String, engineCalls: Int) {
        let eligible = PolishResultCache.Admission.isEligible(recordingDuration: duration, minimumDuration: 2)
        if eligible, let cached = cache.value(for: key) {
            return (cached, 0)
        }
        let calls = 1
        if PolishResultCache.Admission.shouldStore(eligible: eligible, succeeded: engineRan, cancelled: cancelled) {
            cache.insert(output, for: key)
        }
        return (output, calls)
    }
}

final class KeyboardDictationServiceTests: XCTestCase {
    func testMissingPreferenceIsEnabledAndDistinctFromAudioReadiness() {
        let defaults = UserDefaults(suiteName: "stabilization.service.\(UUID().uuidString)")!
        XCTAssertTrue(KeyboardDictationService.isEnabled(in: defaults))
        defaults.set(false, forKey: SharedKeys.keyboardAudioReady)
        XCTAssertTrue(KeyboardDictationService.isEnabled(in: defaults))
        defaults.set(false, forKey: SharedKeys.serviceEnabled)
        XCTAssertFalse(KeyboardDictationService.isEnabled(in: defaults))
        defaults.set(true, forKey: SharedKeys.serviceEnabled)
        XCTAssertTrue(KeyboardDictationService.isEnabled(in: defaults))
    }
}

final class HistoryDiagnosticRetentionTests: XCTestCase {
    func testDisablingHistoryDropsTranscriptFieldsAndKeepsMetadata() {
        let defaults = UserDefaults(suiteName: "stabilization.history.\(UUID().uuidString)")!
        LastDictationIssueReport.store(
            LastDictationIssueSnapshot(
                appVersion: "1.0.0",
                buildNumber: "149",
                modelIdentifier: "whisper-small",
                engineName: "whisper",
                outputMode: "multilingual",
                transcriptionMode: "auto",
                stage: "failed",
                errorSummary: "model failed",
                recordingDurationMs: 1200,
                rawText: "secret raw",
                cleanedText: "secret cleaned"
            ),
            in: defaults
        )
        RecentDictations.disable(in: defaults)
        let loaded = LastDictationIssueReport.load(from: defaults)
        XCTAssertNil(loaded?.rawText)
        XCTAssertNil(loaded?.cleanedText)
        XCTAssertEqual(loaded?.errorSummary, "model failed")
        XCTAssertEqual(loaded?.recordingDurationMs, 1200)
        XCTAssertEqual(loaded?.modelIdentifier, "whisper-small")
    }
}
