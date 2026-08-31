// DictusCore/Tests/DictusCoreTests/DictationErrorChannelTests.swift
// The failure-reason channel: that reading it leaves it alone, and that a new dictation
// is the only thing that takes it away (#320).
//
// The non-destructive read is the part that cannot be checked from either target: it is a
// property of the pair of readers, and the keyboard extension is the one thing in this
// repo nothing ever executes in CI. The test that matters is the one below that reads
// twice.
import XCTest
@testable import DictusCore

final class DictationErrorChannelTests: XCTestCase {

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroup.identifier)
    }

    override func setUp() {
        super.setUp()
        DictationErrorChannel.clear()
    }

    override func tearDown() {
        DictationErrorChannel.clear()
        super.tearDown()
    }

    // MARK: - Round trip

    func testNothingIsStoredOnAFreshAppGroup() {
        XCTAssertNil(DictationErrorChannel.current)
    }

    func testARecordedReasonReadsBack() {
        DictationErrorChannel.record("Micro indisponible. Relancez l'application.")

        XCTAssertEqual(DictationErrorChannel.current, "Micro indisponible. Relancez l'application.")
    }

    /// The app writes through the channel; anything reading the shared key directly —
    /// a diagnostic dump, a future surface — has to see the same value.
    func testTheReasonLandsOnTheSharedKey() {
        DictationErrorChannel.record("Micro indisponible. Relancez l'application.")

        XCTAssertEqual(defaults?.string(forKey: SharedKeys.lastError),
                       "Micro indisponible. Relancez l'application.")
    }

    func testOneReasonAtATime() {
        DictationErrorChannel.record("Micro indisponible. Relancez l'application.")
        DictationErrorChannel.record("Dictation could not start. Tap the microphone again.")

        XCTAssertEqual(DictationErrorChannel.current,
                       "Dictation could not start. Tap the microphone again.",
                       "The channel holds the current reason, not a history")
    }

    // MARK: - The read does not consume (#320)

    /// The bug this issue exists for: the keyboard read the key and removed it in the same
    /// breath, so the app's failure screen had nothing left to show and asserted a cause it
    /// had not established.
    func testReadingTwiceReturnsTheSameReason() {
        DictationErrorChannel.record("Micro indisponible. Relancez l'application.")

        let firstSurface = DictationErrorChannel.current
        let secondSurface = DictationErrorChannel.current

        XCTAssertEqual(firstSurface, "Micro indisponible. Relancez l'application.")
        XCTAssertEqual(secondSurface, firstSurface,
                       "Neither surface may consume the reason on behalf of the other")
    }

    func testReadingLeavesTheSharedKeyInPlace() {
        DictationErrorChannel.record("Micro indisponible. Relancez l'application.")

        _ = DictationErrorChannel.current

        XCTAssertNotNil(defaults?.object(forKey: SharedKeys.lastError),
                        "A read must not remove the key")
    }

    // MARK: - Invalidation

    func testClearingRemovesTheReason() {
        DictationErrorChannel.record("Micro indisponible. Relancez l'application.")

        DictationErrorChannel.clear()

        XCTAssertNil(DictationErrorChannel.current)
        XCTAssertNil(defaults?.object(forKey: SharedKeys.lastError),
                     "Clearing removes the key rather than storing an empty string")
    }

    func testClearingWithNothingStoredIsHarmless() {
        DictationErrorChannel.clear()

        XCTAssertNil(DictationErrorChannel.current)
    }

    /// What a new dictation does, in order: clear, then fail again. The second failure's
    /// reason is the one that survives, and a failure that records nothing leaves nothing.
    func testANewAttemptDoesNotResurfaceThePreviousReason() {
        DictationErrorChannel.record("Micro indisponible. Relancez l'application.")

        DictationErrorChannel.clear()

        XCTAssertNil(DictationErrorChannel.current,
                     "A `.failed` with no reason recorded must not show the previous attempt's")
    }

    func testDispositionRoundTripsIndependentlyOfLocalizedMessage() {
        DictationErrorChannel.record("Microphone access is off.", disposition: .requiresApp)

        XCTAssertEqual(DictationErrorChannel.currentDisposition, .requiresApp)
        XCTAssertEqual(DictationErrorChannel.current, "Microphone access is off.")
    }

    func testClearRemovesDispositionWithTheReason() {
        DictationErrorChannel.record("Recording too short", disposition: .recoverableRetry)

        DictationErrorChannel.clear()

        XCTAssertNil(DictationErrorChannel.currentDisposition)
    }

    func testDispositionMapsToUserAction() {
        XCTAssertEqual(DictationFailureAction.forDisposition(.recoverableRetry), .retry)
        XCTAssertEqual(DictationFailureAction.forDisposition(.requiresApp), .openApp)
        XCTAssertEqual(DictationFailureAction.forDisposition(nil), .retry)
    }

    func testFallbackRequiresExactSessionGenerationAndRequestedStatus() {
        XCTAssertTrue(DictationFailureAction.fallbackMayOpen(expectedSessionID: "a", currentSessionID: "a", expectedGeneration: 4, currentGeneration: 4, status: .requested))
        XCTAssertFalse(DictationFailureAction.fallbackMayOpen(expectedSessionID: "a", currentSessionID: "b", expectedGeneration: 4, currentGeneration: 4, status: .requested))
        XCTAssertFalse(DictationFailureAction.fallbackMayOpen(expectedSessionID: "a", currentSessionID: "a", expectedGeneration: 4, currentGeneration: 5, status: .requested))
        XCTAssertFalse(DictationFailureAction.fallbackMayOpen(expectedSessionID: "a", currentSessionID: "a", expectedGeneration: 4, currentGeneration: 4, status: .failed))
    }

    func testStrandedColdStartUsesRetryDisposition() {
        DictationErrorChannel.record("Tap the microphone again.")
        XCTAssertEqual(DictationErrorChannel.currentDisposition, .recoverableRetry)
        XCTAssertEqual(DictationFailureAction.forDisposition(DictationErrorChannel.currentDisposition), .retry)
    }

    func testRecoverableFailureResetsBeforeRetry() {
        XCTAssertEqual(
            DictationFailureAction.recoveryTransition(for: .recoverableRetry, urlOpened: true),
            .resetAndRetry
        )
    }

    func testRequiresAppOpensWithoutStartingOrStoppingRecording() {
        XCTAssertEqual(
            DictationFailureAction.recoveryTransition(for: .requiresApp, urlOpened: true),
            .openApp
        )
    }

    func testFailedURLOpenRetainsFailedActionableState() {
        XCTAssertEqual(
            DictationFailureAction.recoveryTransition(for: .requiresApp, urlOpened: false),
            .retainFailed
        )
    }

    func testFallbackCallbackCannotAffectChangedSessionOrGeneration() {
        XCTAssertFalse(DictationFailureAction.fallbackMayOpen(expectedSessionID: "old", currentSessionID: "new", expectedGeneration: 1, currentGeneration: 1, status: .requested))
        XCTAssertFalse(DictationFailureAction.fallbackMayOpen(expectedSessionID: "old", currentSessionID: "old", expectedGeneration: 1, currentGeneration: 2, status: .requested))
    }

    func testFallbackCallbackRequiresExactSessionGenerationAndRequestedStatus() {
        XCTAssertTrue(DictationFailureAction.fallbackMayOpen(expectedSessionID: "same", currentSessionID: "same", expectedGeneration: 2, currentGeneration: 2, status: .requested))
    }
}
