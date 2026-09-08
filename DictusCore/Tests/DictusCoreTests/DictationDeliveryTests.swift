import XCTest
@testable import DictusCore

final class DictationDeliveryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "DictationDeliveryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func request(_ id: String = "first", generation: Int = 1) -> DictationLanguageRequest {
        DictationLanguageRequest(mode: .autoDetect, translationTarget: nil)
            .bound(sessionID: id, generation: generation, clientIdentifier: "keyboard")
    }

    func testColdStartResultSurvivesKeyboardRecreationAndIsConsumedOnce() {
        let original = request()
        original.persist(to: defaults)
        DictationDelivery.publish("Hello", for: original, to: defaults)
        let restored = DictationLanguageRequest.load(from: defaults)
        XCTAssertEqual(DictationDelivery.consume(for: restored, from: defaults), "Hello")
        XCTAssertNil(DictationDelivery.consume(for: restored, from: defaults))
    }

    func testCancellationRejectsResultThatArrivesAfterUnbinding() {
        let original = request()
        original.unbound().persist(to: defaults)
        DictationDelivery.publish("Cancelled", for: original, to: defaults)
        XCTAssertNil(DictationDelivery.consume(for: DictationLanguageRequest.load(from: defaults), from: defaults))
    }

    func testFailureThenRetryRejectsOldResultAndAcceptsNewSession() {
        let retry = request("retry", generation: 3)
        retry.persist(to: defaults)
        DictationDelivery.publish("Old", for: request(), to: defaults)
        XCTAssertNil(DictationDelivery.consume(for: retry, from: defaults))
        DictationDelivery.publish("New", for: retry, to: defaults)
        XCTAssertEqual(DictationDelivery.consume(for: retry, from: defaults), "New")
        XCTAssertNil(DictationDelivery.consume(for: retry, from: defaults))
    }

    func testDelayedCallbackCannotConsumeTheNextSessionsResult() {
        let next = request("next", generation: 2)
        DictationDelivery.publish("Next", for: next, to: defaults)
        XCTAssertNil(DictationDelivery.consume(for: request(), from: defaults))
        XCTAssertEqual(DictationDelivery.consume(for: next, from: defaults), "Next")
    }

    func testRepeatedNotificationAfterPropagationDelayConsumesOnce() {
        XCTAssertNil(DictationDelivery.consume(for: request(), from: defaults))
        DictationDelivery.publish("Delayed", for: request(), to: defaults)
        let insertions = (0..<5).compactMap { _ in DictationDelivery.consume(for: request(), from: defaults) }
        XCTAssertEqual(insertions, ["Delayed"])
    }

    func testUnboundAppResultCannotBeInsertedInAnUnrelatedKeyboard() {
        DictationDelivery.publish("In app only", for: request().unbound(), to: defaults)
        XCTAssertNil(DictationDelivery.consume(for: request().unbound(), from: defaults))
    }

    func testSameWordsInTwoDistinctSessionsAreBothDelivered() {
        for index in 1...2 {
            let current = request("session-\(index)", generation: index)
            DictationDelivery.publish("Yes", for: current, to: defaults)
            XCTAssertEqual(DictationDelivery.consume(for: current, from: defaults), "Yes")
        }
    }

    func testClearDropsPendingResultAndLegacyText() {
        DictationDelivery.publish("Pending", for: request(), to: defaults)
        DictationDelivery.clear(in: defaults)
        XCTAssertNil(DictationDelivery.consume(for: request(), from: defaults))
        XCTAssertNil(defaults.string(forKey: SharedKeys.lastTranscription))
    }

    func testQuickReleaseDuringStartupCancelsRatherThanTranscribesEmptyAudio() {
        XCTAssertEqual(DictationStopAction.resolve(status: .requested, isRecording: false), .cancel)
        XCTAssertEqual(DictationStopAction.resolve(status: .idle, isRecording: false), .ignore)
        XCTAssertEqual(DictationStopAction.resolve(status: .recording, isRecording: true), .transcribe)
    }

    func testDuplicateStopsDuringFinalizationAreIgnored() {
        for status in [DictationStatus.transcribing, .processing, .ready, .failed] {
            XCTAssertEqual(DictationStopAction.resolve(status: status, isRecording: false), .ignore)
        }
    }

    func testAppGenerationIsIndependentOfKeyboardRequestGeneration() {
        var app = DictationSessionGeneration(current: 40)
        let keyboardRequest = request(generation: 2)
        app.beginSession()
        XCTAssertTrue(app.mayReport(from: 41, request: keyboardRequest, currentRequest: keyboardRequest))
        app.abandonSession()
        XCTAssertFalse(app.mayReport(from: 41, request: keyboardRequest, currentRequest: keyboardRequest))
        XCTAssertFalse(app.mayReport(from: 42, request: keyboardRequest, currentRequest: request("retry", generation: 3)))
    }
}
