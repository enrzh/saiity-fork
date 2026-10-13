import XCTest
@testable import SyllivraKernel

final class RestructuringOwnershipTests: XCTestCase {
    func testAbandonedSessionCannotReportAndAnAppRequestIgnoresKeyboardCancel() {
        let sessions = DictationSessionController()
        sessions.beginSession()
        let generation = sessions.current
        let keyboard = DictationLanguageRequest(
            mode: .autoDetect,
            translationTarget: nil,
            sessionID: "session",
            generation: 1,
            clientIdentifier: "keyboard-1"
        )
        XCTAssertTrue(sessions.mayReportOutcome(
            session: generation,
            what: "result",
            cancelRequested: false,
            currentRequest: keyboard,
            persistedRequest: keyboard
        ))
        XCTAssertFalse(sessions.mayReportOutcome(
            session: generation,
            what: "result",
            cancelRequested: true,
            currentRequest: keyboard,
            persistedRequest: keyboard
        ))

        sessions.abandonSession()
        XCTAssertFalse(sessions.mayReportOutcome(
            session: generation,
            what: "result",
            cancelRequested: false,
            currentRequest: keyboard,
            persistedRequest: keyboard
        ))

        sessions.beginSession()
        let app = DictationLanguageRequest(
            mode: .autoDetect,
            translationTarget: nil,
            sessionID: "session",
            generation: 2,
            clientIdentifier: "app-home"
        )
        XCTAssertTrue(sessions.mayReportOutcome(
            session: sessions.current,
            what: "result",
            cancelRequested: true,
            currentRequest: app,
            persistedRequest: keyboard
        ))
    }

    func testDeliveryStorePublishesReadyTextWithoutClearingHistoryPolicy() {
        let suite = "restructuring-delivery-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let request = DictationLanguageRequest(
            mode: .autoDetect,
            translationTarget: nil,
            sessionID: "session",
            generation: 3,
            clientIdentifier: "keyboard-1"
        )

        DictationDeliveryStore.publishReady(text: "hello", request: request, to: defaults)

        XCTAssertEqual(defaults.string(forKey: SharedKeys.lastTranscription), "hello")
        XCTAssertEqual(defaults.string(forKey: SharedKeys.dictationStatus), DictationStatus.ready.rawValue)
        XCTAssertGreaterThan(defaults.double(forKey: SharedKeys.lastTranscriptionTimestamp), 0)
        XCTAssertEqual(DictationDelivery.consume(for: request, from: defaults), "hello")
    }

    func testTranscriptionKeepsMixedSpeechAndAddsASeparatorToSingleLanguageText() {
        let mixed = TranscriptionPipeline.assemble(
            cleaned: "Schick mir bitte the updated invoice tomorrow",
            grammarLanguage: nil,
            insertAsIs: true
        )
        XCTAssertEqual(mixed.body, mixed.formatted)
        XCTAssertFalse(mixed.formatted.hasSuffix(". "))

        let sentence = TranscriptionPipeline.assemble(
            cleaned: "Send the invoice",
            grammarLanguage: .english,
            insertAsIs: false
        )
        XCTAssertEqual(sentence.formatted, sentence.body + ". ")

        let finished = TranscriptionPipeline.formatted("Already done.", insertAsIs: false)
        XCTAssertEqual(finished, "Already done. ")
    }

    func testEmojiCategoryOffsetIgnoresSubpixelMotionAndClampsNegative() {
        var surface = KeyboardSurfaceState()
        XCTAssertFalse(surface.setOffset(0.4))
        XCTAssertEqual(surface.offset, 0)
        XCTAssertTrue(surface.setOffset(2))
        XCTAssertEqual(surface.offset, 2)
        XCTAssertTrue(surface.setOffset(-4))
        XCTAssertEqual(surface.offset, 0)
        XCTAssertFalse(surface.setSelectionIndex(0))
        XCTAssertFalse(surface.setSelectionIndex(-2))
        XCTAssertEqual(surface.selectionIndex, 0)
        XCTAssertTrue(surface.setSelectionIndex(4))
        XCTAssertEqual(surface.selectionIndex, 4)
        surface.select(at: 3)
        XCTAssertEqual(surface.selectionIndex, 3)
        XCTAssertFalse(surface.setExpanded(false))
        XCTAssertTrue(surface.setExpanded(true))
    }

    func testInputRouterRequiresTheVisibleController() {
        XCTAssertTrue(KeyboardInputRouter.canRoute(
            isAttached: true,
            isOnScreen: true,
            activeControllerID: "a",
            controllerID: "a"
        ))
        XCTAssertFalse(KeyboardInputRouter.canRoute(
            isAttached: true,
            isOnScreen: false,
            activeControllerID: "a",
            controllerID: "a"
        ))
        XCTAssertFalse(KeyboardInputRouter.canRoute(
            isAttached: true,
            isOnScreen: true,
            activeControllerID: "b",
            controllerID: "a"
        ))
    }

    func testRecoveryOpenUsesThePrepareURLAndTheExistingDebounce() {
        XCTAssertEqual(
            KeyboardDictationBridge.recoveryURL()?.absoluteString,
            "saiity://dictate?source=keyboard&intent=prepare"
        )
        let opened = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(KeyboardDictationBridge.shouldOpen(
            lastOpen: opened,
            now: opened.addingTimeInterval(0.74)
        ))
        XCTAssertTrue(KeyboardDictationBridge.shouldOpen(
            lastOpen: opened,
            now: opened.addingTimeInterval(0.75)
        ))
    }

    func testLifecycleReadingReportsAMissingHeartbeatAsUnknownAge() {
        let missing = KeyboardLifecycleMonitor.reading(
            statusRaw: DictationStatus.recording.rawValue,
            heartbeat: nil,
            localSessionStartedAt: 10,
            now: 20
        )
        XCTAssertEqual(missing.heartbeatAgeMs, -1)
        XCTAssertEqual(missing.status, .recording)

        let aged = KeyboardLifecycleMonitor.reading(
            statusRaw: DictationStatus.idle.rawValue,
            heartbeat: 19.5,
            localSessionStartedAt: nil,
            now: 20
        )
        XCTAssertEqual(aged.heartbeatAgeMs, 500)
    }

    func testEmojiPagesKeepRecentsFullWidthAndDoNotMixCategories() {
        let pages = EmojiSurfaceModel.pages(
            recents: ["😀"],
            categories: [
                EmojiSurfaceCategory(id: "smileys", name: "Smileys", icon: "face.smiling", emojis: Array(repeating: "😀", count: 9))
            ],
            emojiColumnCount: 8
        )
        XCTAssertEqual(pages.first?.id, "recents")
        XCTAssertEqual(pages.first?.columns, 8)
        XCTAssertEqual(pages.first?.items.map(\.emoji), ["😀"])
        let categoryPages = pages.filter { $0.categoryID == "smileys" }
        XCTAssertEqual(categoryPages.count, 1)
        XCTAssertEqual(categoryPages[0].items.count, 9)
        XCTAssertTrue(categoryPages[0].id.hasPrefix("emoji_smileys_page_"))
        XCTAssertEqual(EmojiSurfaceModel.pageColumnCount(itemCount: 5, emojiColumnCount: 8), 2)
        XCTAssertEqual(EmojiSurfaceModel.rowHeight(gridHeight: 100, rowSpacing: 2, gridVerticalInset: 4), 21.5)
    }
}
