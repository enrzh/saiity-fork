// DictusKeyboard/KeyboardState.swift
import Foundation
import UIKit
import UniformTypeIdentifiers
import Combine
import DictusCore

/// Observes cross-process state changes from DictusApp via Darwin notifications.
/// Reads actual data from App Group UserDefaults after each notification.
///
/// Phase 3 additions:
/// - waveformEnergy/recordingElapsed for recording overlay visualization
/// - requestStop()/requestCancel() to send commands back to DictusApp
/// - Auto-insert transcription into active text field via textDocumentProxy
/// - Haptic feedback on recording lifecycle events
class KeyboardState: ObservableObject {
    /// Shift-key double-tap clock. Owned here so a SwiftUI rebuild of the
    /// letter page during the first tap cannot forget the second tap.
    var lastShiftTapDate = Date.distantPast
    static let shared = KeyboardState()
    private let instanceID = String(UUID().uuidString.prefix(8))

    private static func loadLanguageRequest(
        from defaults: UserDefaults = AppGroup.defaults
    ) -> DictationLanguageRequest {
        let request = DictationLanguageRequest.load(from: defaults)
        return DictationLanguageRequest(
            mode: request.modeForNextDictation(
                defaultingTo: TranscriptionLanguageMode(
                    storedValue: defaults.string(forKey: SharedKeys.transcriptionLanguage)
                )
            ),
            translationTarget: request.translationTarget,
            sessionID: request.sessionID,
            generation: request.generation,
            clientIdentifier: request.clientIdentifier,
            resolvedSourceLanguage: request.resolvedSourceLanguage
        )
    }

    /// The dictation this keyboard process currently owns, if any.
    ///
    /// WHY the `didSet` (#261): `sessionStartedAt` below has to be in step with this
    /// at every instant, and this property is assigned from six places. The same
    /// funnel argument as `dictationStatus` and `ownership` applies -- a property
    /// observer is the only path none of them can bypass, so the two cannot drift.
    private(set) var activeSessionID: String? {
        didSet {
            guard oldValue != activeSessionID else { return }
            sessionStartedAt = activeSessionID == nil ? nil : Date()
        }
    }

    /// When the session above started, in this process.
    ///
    /// This is what stops a heartbeat left behind by an *earlier* dictation from being
    /// read as evidence about the current one (#261). It is in-process by nature: the
    /// App Group cannot carry it, because a value there would outlive the process that
    /// wrote it and reintroduce the very problem.
    private(set) var sessionStartedAt: Date?

    /// WHY didSet and not a sync call at each write site: this property is
    /// assigned from a dozen places (Darwin refresh, mic tap, cancel, watchdog
    /// reset, transcription insert, and both of its retry paths). A property
    /// observer is the only funnel none of them can bypass, so the area mode
    /// below can never drift out of step with the dictation lifecycle.
    @Published var dictationStatus: DictationStatus = .idle {
        didSet {
            syncAreaModeWithStatus()
            // The keyboard's dictation transitions are logged here and nowhere
            // else (#255).
            //
            // They used to be emitted from observers — `statusChanged` from
            // AnimatedMicButton, overlayShown/overlayHidden from
            // KeyboardRootView — i.e. once per live view. iOS keeps ~9 of those
            // alive, so one transition was written ~9 times and a reader counted
            // 9 transitions where 1 happened.
            //
            // The same funnel argument as the area mode above applies: this
            // property is assigned from a dozen places and the observer is the
            // only one none of them can bypass. `refreshFromDefaults` is not:
            // `markRequested` writes `.requested` directly, which is why
            // `idle → requested` was, before this, recorded *only* by the
            // per-instance mic button line.
            //
            // The guard reproduces `.onChange` semantics exactly: didSet also
            // fires on writes that leave the value unchanged, `.onChange` does not.
            if oldValue != dictationStatus {
                PersistentLog.log(.statusChanged(
                    from: oldValue.rawValue,
                    to: dictationStatus.rawValue,
                    source: "keyboardState"
                ))
                if dictationStatus.ownsKeyboardArea {
                    PersistentLog.log(.overlayShown(status: dictationStatus.rawValue))
                } else {
                    PersistentLog.log(.overlayHidden(status: dictationStatus.rawValue))
                }
            }
            // Third thing the funnel carries (#309): the stage the overlay draws.
            // Unconditional, because the hold below is what decides whether a write
            // that changed nothing is worth acting on -- and because a re-adoption of
            // the same status is exactly what must not restart a floor already running.
            advanceDisplayedStatus(to: dictationStatus)
            // Fourth (#320): forgetting which error this surface has already shown.
            // Any status that is not `.failed` means a new attempt or a reset, so the
            // next `.failed` is a new failure and deserves the toolbar again -- even if
            // it says the same sentence. The funnel argument applies here too:
            // `markRequested` writes `.requested` without going through
            // `refreshFromDefaults`, so a reset placed there would be bypassed.
            if dictationStatus != .failed {
                presentedErrorMessage = nil
            }
            if dictationStatus != .requested && dictationStatus != .recording {
                cancelDictationReleaseTail()
            }
        }
    }

    /// The app error this keyboard has already put on its toolbar.
    ///
    /// WHY it is needed at all (#320): `DictationErrorChannel` is no longer consumed on
    /// read, and `refreshFromDefaults` runs on every Darwin status post and on every
    /// controller appearance. Without a record of what was shown, a `.failed` status
    /// sitting in the App Group would re-raise the same three-second message each time.
    /// Per instance on purpose -- the extension is torn down and rebuilt constantly, and
    /// a keyboard the user opens fresh after a failure should still be told why.
    private var presentedErrorMessage: String?

    /// The dictation stage the recording overlay is drawing (#309).
    ///
    /// Equal to `dictationStatus` except for up to
    /// `TranscribingStageHold.minimumDisplayDuration` after a transcription that
    /// returned faster than the eye can read it. Read by the overlay's label and by
    /// the waveform driver, and by nothing else: the area mode below, the watchdog,
    /// the liveness predicate and every ownership decision keep reading the real
    /// status, so a held stage can never delay the overlay appearing or disappearing.
    ///
    /// The mechanics are at the bottom of this file.
    @Published private(set) var displayedDictationStatus: DictationStatus = .idle
    @Published private(set) var keyboardPreferenceRevision: UInt = 0

    /// The rule behind the property above. Pure and tested in DictusCore.
    private var transcribingHold = TranscribingStageHold()

    /// Fires when a held stage becomes drawable. At most one is ever in flight.
    private var transcribingHoldTimer: Timer?

    /// What the keyboard area is presenting: the voice surface or recording
    /// overlay. Single source of truth for both the
    /// SwiftUI root view and the UIKit view controller (#271).
    ///
    /// WHY this is not `@Published`: `@Published` notifies in `willSet`, while the
    /// property still holds the OLD value. KeyboardViewController reacts to a mode
    /// change by forcing `layoutIfNeeded()` — deliberately, so the hosting
    /// constraint is in place before SwiftUI draws (#99, #142). But a forced UIKit
    /// layout makes UIHostingController run its SwiftUI update pass right there,
    /// inside the `willSet`: the body reads the old mode, renders it, and marks
    /// itself clean. A status change survives that, because the next status
    /// (`requested → recording → transcribing`) notifies again and the view
    /// catches up.
    ///
    /// Notifying from `didSet` instead means every observer — the controller's
    /// sink and SwiftUI alike — reads the value that is actually stored.
    private(set) var areaMode: KeyboardAreaMode = .keys {
        didSet {
            objectWillChange.send()
            areaModeSubject.send(areaMode)
        }
    }

    /// Backs `areaModePublisher`. A subject rather than `@Published`'s projected
    /// publisher for the `didSet` reason above.
    private let areaModeSubject = PassthroughSubject<KeyboardAreaMode, Never>()

    /// Emits the keyboard area mode after every assignment, including assignments
    /// that leave the value unchanged — re-applying the layout on each dictation
    /// status write is how a keyboard returning from suspension re-synchronises.
    ///
    /// Unlike `@Published`, this does not replay the current value on subscribe:
    /// `viewWillAppear` applies `areaMode` explicitly, which covers that.
    var areaModePublisher: AnyPublisher<KeyboardAreaMode, Never> {
        areaModeSubject.eraseToAnyPublisher()
    }

    @Published var lastTranscription: String?

    /// The language/translation choice captured for the next dictation.
    @Published private(set) var languageRequest = KeyboardState.loadLanguageRequest()

    /// The red line the toolbar shows above the keys: a dictation error from the app,
    /// or the interruption notice the keyboard raises itself (#261).
    ///
    /// WHY the `didSet` and not a log line at each write site: this is assigned from
    /// seven places across three lifecycles, and the open question about it is
    /// whether the user ever *saw* one — an answer that cannot be assembled from
    /// call sites that each report only themselves. The same funnel argument as
    /// `dictationStatus` and `ownership` above: a property observer is the only path
    /// none of them can bypass. Writers go through `assignStatusMessage(_:reason:)`
    /// so the observer has a reason to record; a write that skipped it would still be
    /// logged, as `reason=unspecified`, rather than silently inheriting the last one.
    ///
    /// The observer only logs. Nothing here changes when a message is set, how long
    /// it lives, or what it says.
    @Published var statusMessage: String? {
        didSet {
            // Advanced before the guard, and before anything else here, so it counts
            // writes rather than changes (#342): a message re-raised with the exact
            // same text is still a new message and deserves a full three seconds, and
            // the guard below would swallow it. The funnel argument applies to the
            // token for the same reason it applies to the log line -- a writer that
            // skipped `assignStatusMessage` would otherwise leave a stale clear armed.
            messageLifetime.advance()
            guard oldValue != statusMessage else { return }
            logStatusMessageTransition(from: oldValue)
            statusMessageReason = Self.unspecifiedMessageReason
        }
    }

    /// What asked for the pending `statusMessage` write. Read and reset by the
    /// observer above.
    private var statusMessageReason = KeyboardState.unspecifiedMessageReason
    private static let unspecifiedMessageReason = "unspecified"

    /// Which message currently holds the toolbar, so a clear scheduled three seconds
    /// ago can only take down the message it was scheduled for (#342). Advanced by the
    /// observer above; read by `presentStatusMessage`. The rule is tested in DictusCore.
    private var messageLifetime = StatusMessageLifetime()

    /// How many live views have reported putting the current message on screen.
    /// Reset when a message is assigned, reported when it ends: `displayedCount=0`
    /// on a `dictationMessageCleared` line means nobody could have read it.
    private var statusMessageDisplayCount = 0

    /// Whether DictusApp has stopped calling the polish engine for the rest of its
    /// process (#315).
    ///
    /// WHY it is not a `statusMessage`: that path carries a three-second timer
    /// (the one behind #342), and this condition can last the whole app process —
    /// twelve minutes of unbroken refusals were measured on device. A state that
    /// outlives its own announcement is not a message. So this is a second display
    /// path: no timer, no dismissal, just a value read from the App Group and
    /// rendered whenever the toolbar has room. #313 owns making that layer
    /// coherent; nothing here waits on it.
    ///
    /// Read on every refresh rather than observed: the flag only ever changes
    /// during a dictation, and `refreshFromDefaults()` runs on the `statusChanged`
    /// that dictation posts, and again whenever a controller appears.
    @Published private(set) var polishUnavailable = false

    @Published var waveformEnergy: [Float] = []
    @Published var recordingElapsed: Double = 0

    /// True during the short release tail after the user lifts the dictate
    /// button. Audio is still owned by DictusApp until the delayed stop request
    /// fires, while the keyboard can immediately show that processing is being
    /// prepared.
    @Published private(set) var isFinishingRecording = false

    /// Darwin notifications can arrive in bursts while the extension is waking.
    /// Keep at most one main-queue read pending and skip payloads already decoded.
    private let waveformReadLock = NSLock()
    private var waveformReadScheduled = false
    private var lastDecodedWaveformData: Data?

    /// True when the app must be foregrounded to warm the downloaded model before
    /// another background keyboard dictation can start.
    @Published private(set) var appNeedsModelPreparation = false

    /// True when the service cannot be reached from the keyboard and DictusApp must
    /// be foregrounded. This is separate from model preparation so a ready model is
    /// not mistaken for a running app or Live Activity.
    @Published private(set) var appNeedsServiceRecovery = false

    /// Combined action state consumed by the UIKit hit layer and SwiftUI label.
    @Published private(set) var appNeedsAppAction = false
    /// Home Screen "Keyboard dictation" preference. Missing values stay on.
    @Published private(set) var keyboardDictationEnabled: Bool = {
        let defaults = AppGroup.defaults
        return defaults.object(forKey: SharedKeys.serviceEnabled) == nil
            || defaults.bool(forKey: SharedKeys.serviceEnabled)
    }()
    @Published var accessoryDictationActive = false
    /// A foreground handoff cancels the UIKit touch, not the recording request.
    /// Published so the recovery button can acknowledge the tap immediately even
    /// before iOS finishes switching away from the keyboard extension.
    @Published var isOpeningForDictation = false

    /// True when the host field advertises iOS's one-time-code content type.
    @Published private(set) var isOneTimeCodeField = false
    /// Number/phone/OTP fields open the 3×4 number pad instead of ABC.
    @Published private(set) var hostPrefersNumberPad = false
    @Published private(set) var hostNumberPadStyle: HostFieldPolicy.NumberPadStyle = .digits
    @Published private(set) var hostLetterFieldKeys: HostFieldPolicy.LetterFieldKeys = .standard
    @Published private(set) var hostPrefersSymbolPage = false
    /// True when `.numberPad` was opened because the host field asked for a pad,
    /// so leaving that field can restore letters or the dictation board.
    private var autoPresentedNumberPad = false
    private var autoPresentedSymbolPage = false
    /// Unused pasteboard preview. Kept so appear/disappear can clear it without
    /// reading UIPasteboard. Paste still goes through an explicit tap.
    @Published private(set) var clipboardSuggestion: SuggestionLaneClipboardItem?

    /// Emits readiness changes for UIKit controls that cannot observe the
    /// SwiftUI object directly. The controller schedules its layout on the
    /// next main-queue turn because @Published emits from willSet.
    var modelPreparationPublisher: AnyPublisher<Bool, Never> {
        $appNeedsAppAction.eraseToAnyPublisher()
    }

    /// Which controller owns the keyboard area, and whether an ownerless area is
    /// still reclaimable (#260). Single source of truth for the two published
    /// properties below, which are what every consumer actually reads.
    ///
    /// WHY the two properties are kept rather than replaced: `activeControllerID`
    /// and `isKeyboardVisible` are read from SwiftUI (`KeyboardRootView`), from the
    /// view controller's layout guard and from half the device-log probes. Deriving
    /// them here keeps all of that untouched — and keeps them impossible to write
    /// out of step with each other, which is how the two-flag version drifted.
    private(set) var ownership: KeyboardOwnership = .none {
        didSet {
            guard oldValue != ownership else { return }
            activeControllerID = ownership.controllerID
            isKeyboardVisible = ownership.isVisible
            if ownership.isReclaimable {
                nudgeAttachedControllersToReclaim()
            }
        }
    }

    /// Tracks whether the keyboard extension is currently visible on screen.
    ///
    /// Derived from `ownership`: true only while a live controller owns the area.
    /// An owner deallocated mid-dictation leaves this false — the pixels on screen
    /// then belong to a controller nothing can talk to (#260).
    @Published private(set) var isKeyboardVisible: Bool = false

    /// The controller allowed to present the recording overlay, or nil when the
    /// keyboard area has no owner. Derived from `ownership`.
    @Published private(set) var activeControllerID: String?

    /// Reference to the keyboard controller for text insertion.
    /// WHY weak: KeyboardState is owned by KeyboardRootView (via @StateObject),
    /// and the controller owns the hosting view. A strong reference would create
    /// a retain cycle: controller -> view -> state -> controller.
    weak var controller: UIInputViewController?

    /// Opening a URL must use the currently visible controller. iOS can retain a
    /// detached UIInputViewController, so a weak controller property alone is not
    /// a reliable routing authority for the recovery button.
    var openContainingApp: ((URL, @escaping (Bool) -> Void) -> Void)? {
        (controller as? KeyboardViewController)?.openContainingApp
    }

    /// UIKit suggestion-lane category scrubber reports an index; SwiftUI maps it
    /// onto the emoji picker's category jump.
    var onSelectEmojiCategory: ((Int) -> Void)?
    @Published private(set) var emojiCategoryJumpIndex = 0
    @Published private(set) var emojiCategoryJumpToken = UUID()
    @Published private(set) var emojiCategorySelectionIndex = 0

    func selectEmojiCategory(at index: Int) {
        var surface = currentSurface
        surface.select(at: index)
        emojiCategorySelectionIndex = surface.selectionIndex
        emojiCategoryJumpIndex = index
        emojiCategoryJumpToken = UUID()
        onSelectEmojiCategory?(index)
    }

    func setEmojiCategorySelectionIndex(_ index: Int) {
        var surface = currentSurface
        guard surface.setSelectionIndex(index) else { return }
        emojiCategorySelectionIndex = surface.selectionIndex
    }

    private var currentSurface: KeyboardSurfaceState {
        KeyboardSurfaceState(selectionIndex: emojiCategorySelectionIndex)
    }

    /// The active model's actual input-language detection capability.
    /// Translation readiness is deliberately not inferred here.
    var asrCapability: ASRCapability {
        ASRCapability.forModelIdentifier(
            defaults.string(forKey: SharedKeys.activeModel),
            mode: languageRequest.mode,
            keyboardLanguage: SupportedLanguage.active,
            outputMode: TranscriptionOutputMode.active
        )
    }

    var translationReadiness: TranslationTargetReadiness? {
        TranslationTargetReadiness.load(from: defaults)
    }

    private var currentTranslationReadiness: TranslationTargetReadiness? {
        let sourceCode = asrCapability.sourceLanguage?.rawValue
        guard let readiness = translationReadiness,
              readiness.matchesSourceCode(sourceCode) else { return nil }
        return readiness
    }

    var translationTargets: [TranslationLanguage] {
        let sourceCode = asrCapability.sourceLanguage?.rawValue
        let ready = currentTranslationReadiness?.selectableTargets(forSourceCode: sourceCode) ?? []
        if !ready.isEmpty { return ready }
        return TranslationLanguage.allCases.filter { $0.code != sourceCode }
    }

    func translationTargetStatus(_ target: TranslationLanguage) -> TranslationTargetStatus {
        currentTranslationReadiness?.status(
            for: target,
            sourceCode: asrCapability.sourceLanguage?.rawValue
        ) ?? .checking
    }

    func translationTargetMenuLabel(_ target: TranslationLanguage) -> String {
        currentTranslationReadiness?.menuLabel(
            for: target,
            sourceCode: asrCapability.sourceLanguage?.rawValue
        )
            ?? "Translate to \(target.displayName) (Checking availability)"
    }

    func translationTargetAccessibilityLabel(_ target: TranslationLanguage) -> String {
        currentTranslationReadiness?.accessibilityLabel(
            for: target,
            sourceCode: asrCapability.sourceLanguage?.rawValue
        )
            ?? "Translate to \(target.displayName), checking availability"
    }

    var selectedTranslationTarget: TranslationLanguage? {
        languageRequest.translationTarget
    }

    func selectTranscription() {
        let request = DictationLanguageRequest(
            mode: TranscriptionLanguageMode.active,
            translationTarget: nil
        )
        request.persist(to: defaults)
        languageRequest = request
    }

    func selectTranslation(_ target: TranslationLanguage) {
        let request = DictationLanguageRequest(
            mode: TranscriptionLanguageMode.active,
            translationTarget: target
        )
        request.persist(to: defaults)
        languageRequest = request
    }

    @Published private(set) var typingLanguage = SupportedLanguage.active
    @Published private(set) var typingLanguageIsAutomatic = false

    func refreshTypingLanguage() {
        let language = SupportedLanguage.active
        let isAutomatic = KeyboardLanguageSelection.load(from: defaults) == .automatic
        if language != typingLanguage {
            SuggestionState.shared.setLanguage(language.rawValue)
        }
        typingLanguage = language
        typingLanguageIsAutomatic = isAutomatic
    }

    func selectTypingLanguage(_ language: SupportedLanguage) {
        SupportedLanguage.activate(language)
        refreshTypingLanguage()
    }

    func selectAutomaticTypingLanguage() {
        KeyboardLanguageSelection.automatic.persist(to: defaults)
        let resolved = KeyboardLanguageSelection.resolve(locale: .current, defaults: defaults)
        defaults.set(resolved.rawValue, forKey: SharedKeys.language)
        refreshTypingLanguage()
    }

    func selectKeyboardLayout(_ layout: LayoutType) {
        KeyboardLayoutPreference.setGlobalLayout(layout)
        objectWillChange.send()
    }

    /// Opens through the currently visible keyboard extension context.
    /// SwiftUI's openURL action is a fallback when the extension context rejects
    /// the handoff.
    func openURLFromExtension(_ url: URL, completion: @escaping (Bool) -> Void) {
        if let extensionContext = controller?.extensionContext {
            let fallback = openContainingApp
            extensionContext.open(url) { succeeded in
                guard !succeeded, let fallback else {
                    completion(succeeded)
                    return
                }
                fallback(url, completion)
            }
            return
        }
        guard let openContainingApp else {
            completion(false)
            return
        }
        openContainingApp(url, completion)
    }

    /// Refreshes the host-field metadata used by the keyboard UI.
    /// `applyArea` is false while `viewWillAppear` is about to choose the
    /// opening surface, so a number field is not presented twice.
    func refreshHostInputTraits(from proxy: UITextDocumentProxy, applyArea: Bool = true) {
        isOneTimeCodeField = HostInputTraits.isOneTimeCodeField(for: proxy)
        let prefers = HostInputTraits.prefersNumberPad(for: proxy)
        let previouslyPreferred = hostPrefersNumberPad
        hostPrefersNumberPad = prefers
        hostNumberPadStyle = HostInputTraits.numberPadStyle(for: proxy) ?? .digits
        hostLetterFieldKeys = HostInputTraits.letterFieldKeys(for: proxy)
        let previouslySymbols = hostPrefersSymbolPage
        hostPrefersSymbolPage = HostInputTraits.prefersSymbolPage(for: proxy)
        guard applyArea else { return }
        applyHostNumberPadArea(previouslyPreferred: previouslyPreferred)
        applyHostSymbolPage(previouslyPreferred: previouslySymbols)
    }

    /// Opening surface after the keyboard appears. Number fields open the 3×4
    /// pad; otherwise the saved dictation/keyboard preference.
    func presentPreferredOpeningArea() {
        let mode: KeyboardAreaMode
        if hostPrefersNumberPad {
            mode = .numberPad
        } else if hostPrefersSymbolPage {
            mode = .panel
        } else {
            mode = KeyboardAreaMode.openingMode(
                prefersNumberPad: false,
                defaultMode: DefaultKeyboardMode.active
            )
        }
        autoPresentedNumberPad = mode == .numberPad
        autoPresentedSymbolPage = mode == .panel
        presentArea(mode, registerUserDismissal: false)
    }

    /// 123 from the dictation board, letter keyboard, or emoji page. Numeric
    /// fields reopen the 3×4 pad; other fields still open symbols.
    func presentNumbersArea() {
        presentArea(KeyboardAreaMode.numbersMode(prefersNumberPad: hostPrefersNumberPad))
    }

    /// Pasteboard text is read only when the user taps Paste. Automatic reads
    /// (timers, appear retries, host-trait refresh) show the system clipboard
    /// banner and are not used.
    func refreshClipboardSuggestion(force: Bool = false) {
        _ = force
        pasteboardChangeCount = Int.min
        if clipboardSuggestion != nil {
            clipboardSuggestion = nil
        }
    }

    func startClipboardMonitoring() {
        refreshClipboardSuggestion()
    }

    func stopClipboardMonitoring() {
        refreshClipboardSuggestion()
    }

    /// Reads every text representation the pasteboard may be holding.
    /// The values themselves are not logged.
    static func readPasteboardText(from board: UIPasteboard) -> String? {
        if let resolved = SuggestionLaneClipboardItem.resolvedText(
            string: board.hasStrings ? board.string : nil,
            strings: board.hasStrings ? board.strings : nil,
            urlString: board.hasURLs ? board.url?.absoluteString : nil
        ) {
            return resolved
        }
        let types = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]
        for type in types {
            guard let data = board.data(forPasteboardType: type),
                  let string = String(data: data, encoding: .utf8) else {
                continue
            }
            if let resolved = SuggestionLaneClipboardItem.resolvedText(
                string: string,
                strings: nil,
                urlString: nil
            ) {
                return resolved
            }
        }
        return nil
    }

    /// A failed attempt needs the app when its model or service must be brought
    /// foreground. The remaining failures are safe to retry in this keyboard.
    var failedRequiresApp: Bool {
        guard dictationStatus == .failed else { return false }
        return DictationFailureAction.forDisposition(DictationErrorChannel.currentDisposition) == .openApp
    }

    /// Open the app without creating another recording request.
    func openDictusForRecovery() {
        // One press can deliver touch-down twice while the handoff is running.
        // A missing URL callback must not leave the button dead.
        if isOpeningForDictation,
           Date().timeIntervalSince(lastModelPreparationOpenDate) > 1.2 {
            isOpeningForDictation = false
        }
        guard !isOpeningForDictation else { return }
        lastModelPreparationOpenDate = Date()
        guard let url = KeyboardDictationBridge.recoveryURL() else {
            lastModelPreparationOpenDate = .distantPast
            HapticFeedback.actionRefused()
            presentStatusMessage(
                "Unable to open sAiity. Try again.",
                reason: "recoveryURLFailed",
                timeoutReason: "recoveryURLFailed-timeout"
            )
            return
        }
        isOpeningForDictation = true
        HapticFeedback.dictationPressBegan()
        presentStatusMessage(
            "Opening sAiity…",
            reason: "recovery-opening",
            timeoutReason: "recovery-opening-timeout"
        )
        logProbe("openDictusForRecovery", details: "url=\(url.absoluteString)")
        // extensionContext.open is ignored unless it runs inside the touch.
        // A later turn is not a user gesture, so the tap looked dead.
        openDictusURL(url)
    }

    /// Same preference as Home's "Keyboard dictation" toggle. The app applies
    /// the session change when it receives the Darwin ping.
    func setKeyboardDictationEnabled(_ enabled: Bool) {
        guard keyboardDictationEnabled != enabled else { return }
        KeyboardDictationService.setEnabled(enabled, in: defaults)
        keyboardDictationEnabled = enabled
        HapticFeedback.keyTapped()
        refreshFromDefaults()
        if enabled, appNeedsAppAction { openDictusForRecovery() }
    }

    private let defaults = AppGroup.defaults

    /// Watchdog timer that periodically checks for stale active states.
    /// WHY: If the app crashes or a Darwin notification is lost, the keyboard
    /// could get stuck showing the recording overlay forever. The watchdog
    /// detects this by checking if waveform data has stopped updating for 5s
    /// while status is still .recording or .transcribing.
    private var watchdogTimer: Timer?
    private var dictationReleaseTimer: Timer?

    /// Tracks when waveform energy was last refreshed from App Group.
    /// Used by the watchdog to detect stale states (no updates for 5s).
    private var lastWaveformUpdate: Date = Date()

    /// When set, the watchdog uses a longer threshold (15s) to account for
    /// the app→keyboard transition during cold start. The app needs time to
    /// stabilize audio recording and start posting waveform updates.
    /// Cleared automatically when recording ends (status becomes idle).
    private var coldStartGraceEnd: Date?
    private var pasteboardChangeCount = Int.min

    private init() {
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardState",
            instanceID: instanceID,
            action: "init",
            details: ""
        ))
        // Read initial state from App Group
        TranscriptionLanguagePolicy.persistProductDefaults(to: defaults)
        refreshFromDefaults()

        // Observe Darwin notifications for real-time updates
        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.statusChanged
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.logProbe("receivedDarwinStatusChanged")
                self?.refreshFromDefaults()
            }
        }

        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.transcriptionReady
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.logProbe("receivedDarwinTranscriptionReady")
                self?.handleTranscriptionReady()
            }
        }

        // Observe waveform updates from DictusApp during recording (~5Hz).
        // DictusApp writes JSON-encoded [Float] to SharedKeys.waveformEnergy
        // and elapsed seconds to SharedKeys.recordingElapsedSeconds, then posts
        // this notification. The keyboard reads the values for the overlay UI.
        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.waveformUpdate
        ) { [weak self] in
            self?.scheduleWaveformRead()
        }

        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.modelReadinessChanged
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.logProbe("receivedDarwinModelReadinessChanged")
                self?.refreshFromDefaults()
            }
        }

        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.keyboardPreferencesChanged
        ) { [weak self] in
            DispatchQueue.main.async {
                HapticFeedback.refreshEnabledState()
                self?.keyboardPreferenceRevision &+= 1
                SuggestionState.shared.refreshPreferences()
            }
        }

        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessProbeRequested) { [weak self] in
            DispatchQueue.main.async { (self?.controller as? KeyboardViewController)?.publishFullAccessHandshake(force: true) }
        }

        DarwinNotificationCenter.addObserver(
            for: DarwinNotificationName.keyboardVocabularyChanged
        ) {
            DispatchQueue.main.async {
                SuggestionState.shared.refreshVocabulary()
            }
        }

    }

    deinit {
        logProbe("deinit")
        stopWatchdog()
        transcribingHoldTimer?.invalidate()
        dictationReleaseTimer?.invalidate()
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.statusChanged)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.transcriptionReady)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.waveformUpdate)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.modelReadinessChanged)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.keyboardPreferencesChanged)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.keyboardFullAccessProbeRequested)
        DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.keyboardVocabularyChanged)
    }

    // MARK: - Watchdog

    /// Prevents re-entrant calls to forceResetToIdle().
    /// WHY: forceResetToIdle posts a statusChanged notification, which triggers
    /// refreshFromDefaults on the next run loop. If the watchdog timer fires
    /// again before that run loop pass (e.g., stacked timer events), a second
    /// forceResetToIdle call would post a duplicate notification.
    private var isResettingToIdle = false

    /// Force-reset all dictation state to idle.
    /// Called by the watchdog timer or stale-state detection on keyboard appear.
    /// Writes to App Group so the app side sees the reset too.
    ///
    /// WHY it clears the shared recording keys as well as the status (#261): this
    /// used to write `idle` and leave the heartbeat, the waveform and the cold-start
    /// flag exactly as the abandoned session left them. A heartbeat that outlives the
    /// session it belonged to is then read against the *next* one — on device
    /// (2026-08-03) a corpse left here at 14:36:51 was judged against a session that
    /// started at 14:37:02 and killed it. Whatever gives up on a dictation has to
    /// leave the App Group describing no dictation at all.
    ///
    /// `stopRequested` / `cancelRequested` are deliberately untouched: those are
    /// commands in flight, not state, and clearing them here would race a caller that
    /// posts one immediately before resetting.
    func forceResetToIdle() {
        guard !isResettingToIdle else { return }
        isResettingToIdle = true
        cancelDictationReleaseTail()
        isOpeningForDictation = false
        sessionGeneration += 1
        defer { isResettingToIdle = false }

        stopWatchdog()
        dictationStatus = .idle
        waveformEnergy = []
        lastDecodedWaveformData = nil
        recordingElapsed = 0
        assignStatusMessage(nil, reason: "forceResetToIdle")
        activeSessionID = nil
        DictationLanguageRequest.load(from: defaults).unbound().persist(to: defaults)
        // Write to App Group so app side sees the reset
        defaults.set(DictationStatus.idle.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.removeObject(forKey: SharedKeys.recordingHeartbeat)
        defaults.removeObject(forKey: SharedKeys.waveformEnergy)
        defaults.removeObject(forKey: SharedKeys.recordingElapsedSeconds)
        defaults.set(false, forKey: SharedKeys.coldStartActive)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    /// Start a repeating 1s timer that checks for stale active states.
    /// WHY 5s threshold: Waveform updates arrive at ~5Hz during recording.
    /// If 5 seconds pass without any update while status is still active,
    /// the app has likely crashed or been killed by iOS.
    /// During cold start grace period, uses 15s threshold instead.
    private func startWatchdog() {
        stopWatchdog()
        lastWaveformUpdate = Date()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // The shared predicate, not a literal list: it is an exhaustive switch
            // over `DictationStatus`, so a status added later cannot quietly stop
            // being watched. That is how `.processing` (#267) got here.
            guard DictationSessionLivenessPolicy.isActive(self.dictationStatus) else {
                self.stopWatchdog()
                return
            }
            // A heartbeat that stopped is positive evidence that the app is gone, and
            // it can pre-empt the 15 s cold-start grace below (#261) -- that grace was
            // written for an app slow to start posting waveform data, not for one that
            // has died, and waiting it out is what let a phantom session run for ~34 s.
            //
            // It also beats the 5 s path, but only because the recording threshold is
            // deliberately 4 s. The first shipped version used 8 s and therefore never
            // fired: both ages start at the same instant, so a threshold above the
            // watchdog's own is unreachable — the reset below lands first and the guard
            // above then stops the timer. That is defect 1 of the device run in one
            // sentence, and it is why the two numbers are now coupled on purpose.
            if self.reconcileIfOrphaned(source: "keyboard-watchdog") { return }

            // During cold start, the app transitions foreground→background while
            // setting up audio. Waveform data may not flow for ~10s. Use 15s threshold.
            let inGracePeriod = self.coldStartGraceEnd.map { Date() < $0 } ?? false
            let threshold: TimeInterval
            if inGracePeriod {
                threshold = 15.0
            } else {
                switch self.dictationStatus {
                case .transcribing: threshold = 30.0
                case .processing: threshold = 60.0
                default: threshold = 5.0
                }
            }
            if Date().timeIntervalSince(self.lastWaveformUpdate) > threshold {
                // Before resetting, check the audio-thread heartbeat.
                // WHY: In background, iOS throttles the main thread so waveform
                // Darwin notifications may not arrive. But the audio thread keeps
                // writing a heartbeat directly to App Group. If the heartbeat is
                // fresh, the app IS still recording — don't kill the overlay.
                //
                // Only recording gets this extension. After capture ends the engine
                // can keep a warm-idle heartbeat while the main-actor transcribe
                // task is frozen in the background, which would otherwise reset
                // this timer forever and leave "Cleaning up..." on screen.
                let heartbeat = self.defaults.double(forKey: SharedKeys.recordingHeartbeat)
                if self.dictationStatus == .recording,
                   heartbeat > 0, Date().timeIntervalSince1970 - heartbeat < threshold {
                    self.lastWaveformUpdate = Date()
                    return
                }
                // This test has decided; it does not consult the predicate again, and
                // must not — its own thresholds are what proved themselves on device.
                // What changes here is only the outcome: the reset is no longer local
                // and silent. It clears the shared state too and says something, so a
                // watchdog win and a predicate win are the same event to the user, and
                // leave the same state behind for the next dictation.
                //
                // `watchdogReset` is still logged, so this line keeps meaning what it
                // means in every log written before this change.
                PersistentLog.log(.watchdogReset(source: "keyboard", staleState: self.dictationStatus.rawValue))
                let heartbeatAgeMs = heartbeat > 0
                    ? Int((Date().timeIntervalSince1970 - heartbeat) * 1000)
                    : -1
                self.reconcileAbandonedDictation(
                    source: "keyboard-watchdog-stale",
                    staleStatus: self.dictationStatus,
                    heartbeatAgeMs: heartbeatAgeMs
                )
            }
        }
    }

    /// Invalidate and nil the watchdog timer.
    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    /// Keeps the presented mode in step with the dictation lifecycle.
    ///
    /// This is where "starting a dictation dismisses the emoji picker" lives: an
    /// explicit transition to `.recording`, rather than the SwiftUI `onChange`
    /// side effect it used to be. Assigned unconditionally — including when the
    /// resolved mode is unchanged — because the layout used to be re-applied on
    /// every status write, and that repetition is load-bearing: it is how a
    /// keyboard returning from suspension re-synchronises its hosting geometry.
    private func syncAreaModeWithStatus() {
        areaMode = KeyboardAreaMode.resolving(status: dictationStatus, current: areaMode)
    }

    private func applyHostNumberPadArea(previouslyPreferred: Bool) {
        guard !dictationStatus.ownsKeyboardArea else { return }
        if hostPrefersNumberPad && !previouslyPreferred {
            autoPresentedNumberPad = true
            presentArea(.numberPad, registerUserDismissal: false)
            return
        }
        if hostPrefersNumberPad {
            return
        }
        guard previouslyPreferred, autoPresentedNumberPad, areaMode == .numberPad else {
            autoPresentedNumberPad = false
            return
        }
        autoPresentedNumberPad = false
        presentArea(
            KeyboardAreaMode.openingMode(
                prefersNumberPad: false,
                defaultMode: DefaultKeyboardMode.active
            ),
            registerUserDismissal: false
        )
    }

    private func applyHostSymbolPage(previouslyPreferred: Bool) {
        guard !dictationStatus.ownsKeyboardArea, !hostPrefersNumberPad else { return }
        if hostPrefersSymbolPage && !previouslyPreferred {
            autoPresentedSymbolPage = true
            presentArea(.panel, registerUserDismissal: false)
            return
        }
        if hostPrefersSymbolPage { return }
        guard previouslyPreferred, autoPresentedSymbolPage, areaMode == .panel else {
            autoPresentedSymbolPage = false
            return
        }
        autoPresentedSymbolPage = false
        presentArea(
            KeyboardAreaMode.openingMode(
                prefersNumberPad: false,
                defaultMode: DefaultKeyboardMode.active
            ),
            registerUserDismissal: false
        )
    }

    func presentArea(_ mode: KeyboardAreaMode, registerUserDismissal: Bool = true) {
        guard !dictationStatus.ownsKeyboardArea else { return }
        if registerUserDismissal, hostPrefersNumberPad, mode != .numberPad {
            autoPresentedNumberPad = false
        }
        if registerUserDismissal, hostPrefersSymbolPage, mode != .panel {
            autoPresentedSymbolPage = false
        }
        areaMode = mode
    }

    func closeArea() {
        guard !dictationStatus.ownsKeyboardArea else { return }
        if hostPrefersNumberPad {
            autoPresentedNumberPad = false
        }
        if hostPrefersSymbolPage {
            autoPresentedSymbolPage = false
        }
        areaMode = .keys
    }

    // MARK: - Recording commands (keyboard -> app)

    /// Press-and-hold began on the dictate control (UIKit overlay or SwiftUI fallback).
    func handleMicPressBegan() {
        cancelDictationReleaseTail()
        // Model state is written by the app process. Read it immediately before
        // deciding whether this tap records or opens the app, so a missed Darwin
        // delivery can never leave the button stuck on a stale label.
        refreshFromDefaults()
        switch dictationStatus {
        case .idle, .ready:
            if appNeedsAppAction {
                PersistentLog.log(.keyboardMicTapped)
                openDictusForRecovery()
            } else {
                HapticFeedback.recordingStarted()
                startRecording()
            }
        case .failed:
            if failedRequiresApp {
                openDictusForRecovery()
            } else {
                HapticFeedback.recordingStarted()
                startRecording()
            }
        case .transcribing, .processing:
            // The current round is still authoritative. Cancel it rather than
            // starting a second dictation while Whisper or cleanup is running.
            cancelActiveDictation()
        case .requested, .recording:
            return
        }
    }

    /// Cancel an active dictation from the microphone control without waiting for
    /// the normal recording-release path. This also covers transcription and
    /// cleanup, where `requestStop()` correctly does nothing by design.
    func cancelActiveDictation() {
        refreshFromDefaults()
        guard DictationSessionLivenessPolicy.isActive(dictationStatus) else { return }
        requestCancel()
        HapticFeedback.recordingStopped()
    }

    /// Press-and-hold ended on the dictate control.
    func handleMicPressEnded() {
        refreshFromDefaults()
        guard dictationStatus == .requested || dictationStatus == .recording else { return }
        // The audio tail is intentionally delayed to preserve the final word;
        // feedback should stay anchored to the user's finger lift.
        HapticFeedback.recordingStopped()
        scheduleDictationReleaseTail()
    }

    /// Keep the microphone open briefly after release so the final spoken word
    /// is not lost to a finger lifting slightly before speech ends.
    private func scheduleDictationReleaseTail() {
        guard dictationReleaseTimer == nil else { return }
        isFinishingRecording = true
        let timer = Timer(
            timeInterval: KeyboardDeletion.dictationReleaseTailDuration,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.dictationReleaseTimer = nil
            guard self.dictationStatus == .requested || self.dictationStatus == .recording else {
                self.isFinishingRecording = false
                return
            }
            self.isFinishingRecording = false
            self.requestStop()
        }
        dictationReleaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// A new hold within the tail continues the same recording session.
    private func cancelDictationReleaseTail() {
        dictationReleaseTimer?.invalidate()
        dictationReleaseTimer = nil
        isFinishingRecording = false
    }

    /// Request DictusApp to stop recording and begin transcription.
    /// Uses the Darwin notification + Bool flag pattern: write the flag first,
    /// then post the notification so the app reads the flag when it handles the notification.
    func requestStop() {
        cancelDictationReleaseTail()
        logProbe("requestStop", details: sessionDetails())

        if dictationStatus == .requested {
            defaults.synchronize()
            let sharedStatus = defaults.string(forKey: SharedKeys.dictationStatus)
                .flatMap(DictationStatus.init(rawValue:)) ?? .requested
            if DictationStopAction.resolve(status: sharedStatus, isRecording: sharedStatus == .recording) == .cancel {
                requestCancel()
                return
            }
        }

        // A stop tapped by a keyboard that never started this dictation (#261). The
        // line is written whatever comes next, because two taps used to produce
        // nothing at all -- neither on screen nor in the log -- and that silence is
        // what made the reported incident unreadable.
        if activeSessionID == nil {
            let reading = dictationLiveness()
            logProbe(
                "requestStopWithoutSession",
                details: "storedStatus=\(reading.status?.rawValue ?? "nil") liveness=\(reading.verdict.rawValue)"
            )
            // Reset locally only on the evidence, not on the missing id alone: iOS
            // rebuilds this extension routinely, and a keyboard rebuilt mid-dictation
            // has no session id while the app records perfectly happily. Dropping the
            // overlay there would abandon a live transcription.
            if reconcileIfOrphaned(source: "keyboard-stop") { return }
        }

        defaults.set(true, forKey: SharedKeys.stopRequested)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.stopRecording)
    }

    /// Request DictusApp to cancel recording and discard audio.
    /// Resets local keyboard state immediately for instant UI feedback,
    /// while the Darwin notification tells the app to clean up its side.
    func requestCancel() {
        cancelDictationReleaseTail()
        isOpeningForDictation = false
        logProbe("requestCancel", details: sessionDetails())
        sessionGeneration += 1
        DictationDelivery.clear(in: defaults)
        DictationLanguageRequest.load(from: defaults).unbound().persist(to: defaults)
        defaults.set(DictationStatus.idle.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.set(true, forKey: SharedKeys.cancelRequested)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.cancelRecording)

        // Reset local state immediately for responsive UI
        dictationStatus = .idle
        waveformEnergy = []
        lastDecodedWaveformData = nil
        recordingElapsed = 0
        assignStatusMessage(nil, reason: "requestCancel")
        activeSessionID = nil
        DictationLanguageRequest.load(from: defaults).unbound().persist(to: defaults)
    }

    // MARK: - State observation

    /// Read current state from App Group UserDefaults.
    /// Starts/stops the watchdog timer based on the new status.
    func refreshFromDefaults() {
        logProbe("refreshFromDefaults", details: "storedStatus=\(defaults.string(forKey: SharedKeys.dictationStatus) ?? "nil") visible=\(isKeyboardVisible) \(sessionDetails())")
        languageRequest = Self.loadLanguageRequest(from: defaults)
        refreshModelPreparationState()
        refreshTypingLanguage()

        // Read BEFORE the reconcile guard below (#315): that guard returns early
        // on an abandoned dictation, and the polish state has nothing to do with
        // whether this one was abandoned. A state that can last the whole app
        // process must not be skipped by an unrelated exit.
        polishUnavailable = PolishAvailabilityChannel.isUnavailable

        // Before adopting what the App Group says, check that somebody is still
        // writing it (#261). This is the read a rebuilt extension performs from its
        // own `init`, so an app terminated mid-dictation is caught here -- at the
        // first read, not after a watchdog grace. Reconciling already wrote `idle`,
        // so there is nothing left to adopt.
        if reconcileIfOrphaned(source: "keyboard-refresh") { return }

        if let rawStatus = defaults.string(forKey: SharedKeys.dictationStatus),
           let status = DictationStatus(rawValue: rawStatus) {
            let oldStatus = dictationStatus
            // The statusChanged line this used to emit here now comes from
            // dictationStatus's didSet (#255), which fires for this write and for
            // the ones that never went through this method.
            dictationStatus = status

            // Start/restart watchdog on any active state transition, stop when leaving.
            // WHY restart (not just start): transitioning .requested → .recording
            // must reset lastWaveformUpdate. Without this, the watchdog fires
            // immediately because it still has the timestamp from markRequested().
            //
            // `.transcribing → .processing` (#267) is one such transition: it
            // restarts the watchdog, which is what gives the LLM stage its own
            // fresh 5 s window instead of inheriting the transcription's.
            if DictationSessionLivenessPolicy.isActive(status) {
                if !DictationSessionLivenessPolicy.isActive(oldStatus) || status != oldStatus {
                    startWatchdog()
                }
                // During cold start, the app is transitioning between foreground/background.
                // Waveform data may not flow for several seconds. Activate grace period
                // so the watchdog uses a longer threshold (15s instead of 5s).
                if defaults.bool(forKey: SharedKeys.coldStartActive) {
                    coldStartGraceEnd = Date().addingTimeInterval(15)
                    lastWaveformUpdate = Date()
                }
                // Force-read waveform on keyboard reappear to unstick frozen animations.
                // WHY: When the extension is suspended (app in foreground), Darwin
                // notifications are lost. readWaveformData() updates @Published props
                // which forces SwiftUI to re-render the overlay.
                readWaveformData()
            } else {
                stopWatchdog()
                coldStartGraceEnd = nil
                if status == .idle || status == .ready || status == .failed {
                    activeSessionID = nil
                    // Read and display the app's error message. The read is
                    // deliberately non-destructive (#320): the app's own failure
                    // screen reads the same channel, and consuming it here left that
                    // screen with nothing to say but a hardcoded sentence about the
                    // model download. What this surface owns is its own toolbar line,
                    // which the timeout below clears; `presentedErrorMessage` is what
                    // keeps a later refresh from raising the same one again.
                    if status == .failed,
                       let errorMsg = DictationErrorChannel.current,
                       errorMsg != presentedErrorMessage {
                        presentedErrorMessage = errorMsg
                        presentStatusMessage(
                            errorMsg,
                            reason: "appError",
                            timeoutReason: "appError-timeout"
                        )
                    }
                }
            }

            // Force SwiftUI re-render when status hasn't changed but we're returning
            // from suspension (e.g., swipe-back during cold start recording).
            // WHY: If oldStatus == status == .recording, SwiftUI skips re-render
            // because no @Published value changed. objectWillChange forces it.
            if isKeyboardVisible && oldStatus == status && DictationSessionLivenessPolicy.isActive(status) {
                objectWillChange.send()
            }
        }
    }

    /// Read waveform energy and elapsed time from App Group.
    /// Called when DictusApp posts waveformUpdate notification during recording.
    /// Updates lastWaveformUpdate so the watchdog knows data is still flowing.
    private func readWaveformData() {
        // Only a live capture produces waveform ticks. Re-arming the timestamp
        // from stale App Group buffers during transcribing/cleanup is what kept
        // the overlay stuck on those stages.
        if dictationStatus == .recording {
            lastWaveformUpdate = Date()
        }

        // Read elapsed seconds, but do not publish when the value did not change.
        let elapsed = defaults.double(forKey: SharedKeys.recordingElapsedSeconds)
        if elapsed != recordingElapsed {
            recordingElapsed = elapsed
        }

        // Read waveform energy: JSON-encoded [Float] array
        if let data = defaults.data(forKey: SharedKeys.waveformEnergy) {
            guard data != lastDecodedWaveformData else { return }
            do {
                let energy = try JSONDecoder().decode([Float].self, from: data)
                lastDecodedWaveformData = data
                // Log transitions between empty/populated energy data
                if waveformEnergy.isEmpty != energy.isEmpty {
                    PersistentLog.log(.waveformEnergyTransition(
                        fromCount: waveformEnergy.count,
                        toCount: energy.count,
                        status: dictationStatus.rawValue
                    ))
                }
                if waveformEnergy != energy {
                    waveformEnergy = energy
                }
            } catch {
                // JSON decode failure — keep existing waveform data
                if #available(iOS 14.0, *) {
                    DictusLogger.keyboard.warning("Failed to decode waveform energy: \(error, privacy: .public)")
                }
            }
        }
    }

    /// Coalesce cross-process waveform notifications into one main-thread read.
    private func scheduleWaveformRead() {
        waveformReadLock.lock()
        guard !waveformReadScheduled else {
            waveformReadLock.unlock()
            return
        }
        waveformReadScheduled = true
        waveformReadLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readWaveformData()
            self.waveformReadLock.lock()
            self.waveformReadScheduled = false
            self.waveformReadLock.unlock()
        }
    }

    /// Handle transcription ready notification: auto-insert text into active field.
    ///
    /// Phase 3 behavior: instead of displaying transcription in a banner,
    /// insert it directly into the text field via textDocumentProxy.insertText().
    /// This matches the standard iOS dictation UX — user speaks, text appears at cursor.
    private func handleTranscriptionReady() {
        logProbe("handleTranscriptionReady", details: sessionDetails())
        refreshFromDefaults()
        let request = DictationLanguageRequest.load(from: defaults)
        guard !consumeTranscription(for: request) else { return }
        // Propagation can lag. Capture the identity so this callback cannot
        // consume a newer session after cancellation or a quick retry.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            _ = self?.consumeTranscription(for: request)
        }
    }

    private func refreshModelPreparationState() {
        defaults.synchronize()
        let rawLoadState = defaults.string(forKey: SharedKeys.modelLoadState)
            ?? ModelLoadState.idle.rawValue
        var loadState = ModelLoadState(rawValue: rawLoadState) ?? .idle
        let timestamp = defaults.double(forKey: SharedKeys.modelLoadStateTimestamp)
        let loadStartedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil

        // A previous app process can die between `.loading` and its terminal
        // state. Clear that orphaned marker here so the keyboard recovers on its
        // next appearance instead of presenting a dead "Open sAiity" control.
        if loadState == .loading,
           !KeyboardModelPreparationPolicy.isLoadingStateFresh(
               modelLoadState: loadState,
               modelLoadStartedAt: loadStartedAt
           ) {
            defaults.set(ModelLoadState.idle.rawValue, forKey: SharedKeys.modelLoadState)
            defaults.removeObject(forKey: SharedKeys.modelLoadStateTimestamp)
            defaults.synchronize()
            loadState = .idle
            DarwinNotificationCenter.post(DarwinNotificationName.modelReadinessChanged)
            logProbe("staleModelLoadStateReset", details: "startedAt=\(timestamp)")
        }
        let phase = defaults.string(forKey: SharedKeys.appScenePhase)
            .flatMap(AppScenePhaseMarker.init(rawValue:)) ?? .unknown
        let persistedModelReady = defaults.bool(forKey: SharedKeys.modelReady)
        let activeModel = defaults.string(forKey: SharedKeys.activeModel)
        let downloadedModels = KeyboardModelPreparationPolicy.downloadedModelIDs(
            from: defaults.object(forKey: SharedKeys.downloadedModels)
        )
        let modelReady = KeyboardModelPreparationPolicy.effectiveModelReady(
            modelReady: persistedModelReady,
            activeModel: activeModel,
            downloadedModels: downloadedModels
        )
        let needsModelPreparation = KeyboardModelPreparationPolicy.shouldOpenApp(
            modelReady: modelReady,
            modelLoadState: loadState,
            appPhase: phase,
            modelLoadStartedAt: loadStartedAt
        )
        appNeedsModelPreparation = needsModelPreparation

        let serviceEnabled = defaults.object(forKey: SharedKeys.serviceEnabled) == nil
            || defaults.bool(forKey: SharedKeys.serviceEnabled)
        if keyboardDictationEnabled != serviceEnabled {
            keyboardDictationEnabled = serviceEnabled
        }
        let heartbeat = defaults.double(forKey: SharedKeys.appProcessHeartbeat)
        let appHeartbeat = heartbeat > 0 ? heartbeat : nil
        let liveActivityPresent = defaults.bool(forKey: SharedKeys.liveActivityPresent)
        let activityTimestamp = defaults.double(forKey: SharedKeys.liveActivityUpdatedAt)
        let liveActivityUpdatedAt = activityTimestamp > 0 ? activityTimestamp : nil
        let audioReady = defaults.bool(forKey: SharedKeys.keyboardAudioReady)

        // Heartbeats are recovery hints, not proof of microphone readiness.
        // Direct holds require the explicitly enabled background audio session;
        // Darwin notifications cannot launch or unsuspend a cold audio process.
        let serviceNeedsRecovery = DictationServiceLivenessPolicy.shouldOfferRecovery(
            modelReady: modelReady,
            serviceEnabled: serviceEnabled,
            appProcessHeartbeat: appHeartbeat,
            liveActivityPresent: liveActivityPresent,
            liveActivityUpdatedAt: liveActivityUpdatedAt,
            audioReady: audioReady
        )
        let needsServiceRecovery = serviceNeedsRecovery
        appNeedsServiceRecovery = needsServiceRecovery
        // A ready model does not imply a usable background microphone. Include
        // service recovery so the keyboard cannot offer a dead hold after an
        // idle release, interruption, or engine teardown.
        appNeedsAppAction = needsModelPreparation || !serviceEnabled || needsServiceRecovery
    }

    @discardableResult
    private func consumeTranscription(for request: DictationLanguageRequest) -> Bool {
        guard isKeyboardVisible, let controller,
              controller.isViewLoaded, controller.view.window != nil,
              request.hasSameIdentity(as: DictationLanguageRequest.load(from: defaults)),
              var result = DictationDelivery.consumeResult(for: request, from: defaults) else { return false }
        result.timings?.mark("deliveryConsumed")
        insertTranscription(result.text, timings: result.timings, originalText: result.originalText)
        return true
    }

    /// Insert a transcription into the host field and return the keyboard to idle.
    ///
    /// WHY this is a single function called from two places: `handleTranscriptionReady`
    /// has two insertion sites — the direct one and the 100 ms retry that absorbs the
    /// App Group propagation race — and they used to hold two copies of this block.
    /// Anything the keyboard has to remember about an insertion (#266: what it was, so
    /// it can be undone) has to be remembered on both, and the retry path is the one
    /// that loses the race, so a copy that forgets it would fail intermittently and
    /// only on slow devices. One funnel, no copy to forget.
    ///
    /// The App Group key is deliberately NOT read here: the caller clears it before
    /// calling, which is what stops a redelivered Darwin notification from inserting
    /// the same text twice.
    private func insertTranscription(_ transcription: String, timings: DictationRuntimeMetrics? = nil,
                                     originalText: String? = nil) {
        cancelDictationReleaseTail()
        guard let proxy = controller?.textDocumentProxy else { return }
        proxy.insertText(transcription)
        var timings = timings
        timings?.mark("proxyInserted")
        timings?.log()
        SuggestionState.shared.clear(resetLanguage: false)
        PersistentLog.log(.keyboardTextInserted)
        HapticFeedback.textInserted()

        // Reset state to idle.
        // WHY explicit stopWatchdog: refreshFromDefaults() in the caller may have read
        // .transcribing from App Group (before .ready propagated), starting the
        // watchdog. Setting dictationStatus = .idle here bypasses refreshFromDefaults
        // so the watchdog wouldn't self-stop until its next 1s tick. Stopping
        // explicitly prevents false-positive watchdog resets.
        stopWatchdog()
        dictationStatus = .idle
        waveformEnergy = []
        lastDecodedWaveformData = nil
        recordingElapsed = 0
        assignStatusMessage(nil, reason: "textInserted")
        lastTranscription = nil
        activeSessionID = nil

        // Offer the undo control for this insertion, and only this one. Armed after
        // the idle reset above because that reset is what ends the dictation session
        // the undo belongs to.
        armDictationUndo(transcription, originalText: originalText)
    }

    // MARK: - Dictation undo (#266)

    /// The exact string the last dictation inserted, while undoing it is still on
    /// offer. Nil means there is nothing to undo.
    ///
    /// WHY it is held in memory here rather than re-read from the App Group: the
    /// value is removed from shared storage *before* insertion, deliberately, so a
    /// redelivered Darwin notification cannot insert it twice. By the time the user
    /// could ask to undo, the only remaining copy of what was inserted is this one.
    ///
    /// WHY on the shared state object and not on a controller: iOS destroys and
    /// rebuilds `UIInputViewController` instances constantly — around nine per
    /// dictation (#281) — so a record held by a controller would vanish with it.
    /// What that costs is the risk of a record outliving the field it belongs to,
    /// which is what the invalidations below and the tail check exist to prevent.
    private var dictationUndoText: String?
    private var dictationOriginalText: String?
    private var dictationUndoDocumentID: UUID?
    private var dictationUndoContextAfter: String?

    /// Only preview a result still verified against the field that received it.
    var currentDictationPreview: String? {
        guard dictationUndoAvailable, dictationStatus == .idle || dictationStatus == .ready,
              let text = dictationUndoText, let proxy = controller?.textDocumentProxy,
              let documentID = HostInputTraits.documentIdentifier(for: proxy), documentID == dictationUndoDocumentID,
              proxy.selectedText?.isEmpty != false,
              proxy.documentContextAfterInput == dictationUndoContextAfter,
              case .ok(_, _, false) = DictationUndo.verify(context: proxy.documentContextBeforeInput, insertedText: text)
        else { return nil }
        return String(text.prefix(240))
    }

    /// Whether the toolbar should offer the undo control.
    ///
    /// Set only after the insertion has been verified against the live document, so
    /// a host that reports no usable context never shows a control that could not
    /// act (fail closed).
    @Published private(set) var dictationUndoAvailable = false

    /// Expires the offer a few seconds after the insertion.
    private var dictationUndoTimer: Timer?

    /// True while a deletion burst is in flight. Blocks a new dictation from
    /// starting into a field that is still being rewritten.
    private var isUndoingDictation = false

    /// Called after a dictation insertion has been undone, so the controller can
    /// drop suggestions computed from text that no longer exists.
    var onDictationUndone: (() -> Void)?

    /// How long the offer stands.
    ///
    /// WHY 8 seconds: long enough to read a sentence and decide it is wrong, short
    /// enough that the control is gone before the user has moved on and forgotten
    /// what it refers to. The issue asks for "a few seconds"; this is a judgement
    /// call, not a measurement.
    private static let dictationUndoTimeout: TimeInterval = 8

    /// `deleteBackward()` calls issued per main-queue turn.
    ///
    /// WHY chunked at all: every call is an IPC round trip to the host, and a
    /// two-minute dictation is hundreds of them. Issued in one synchronous loop
    /// they block the main thread long enough for a slow host to visibly freeze.
    /// Yielding between chunks lets the host process what it has been given.
    private static let dictationUndoChunkSize = 40

    /// Offer to undo `transcription`, if the document still agrees it was inserted.
    ///
    /// WHY the first check is deferred by one main-queue turn: `insertText` and the
    /// proxy's view of the document are not guaranteed to be in step within the same
    /// turn, and a check that runs too early reads the field as it was *before* the
    /// insertion and refuses. One hop costs a frame nobody sees.
    private func armDictationUndo(_ transcription: String, originalText: String? = nil) {
        guard let documentID = HostInputTraits.documentIdentifier(for: controller?.textDocumentProxy) else {
            invalidateDictationUndo(reason: "document-unavailable")
            return
        }
        dictationUndoText = transcription
        dictationOriginalText = originalText
        dictationUndoDocumentID = documentID
        dictationUndoContextAfter = controller?.textDocumentProxy.documentContextAfterInput
        dictationUndoAvailable = false
        dictationUndoTimer?.invalidate()
        dictationUndoTimer = Timer.scheduledTimer(
            withTimeInterval: Self.dictationUndoTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.invalidateDictationUndo(reason: "timeout")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.dictationUndoText == transcription else { return }
            switch DictationUndo.verify(
                context: self.controller?.textDocumentProxy.documentContextBeforeInput,
                insertedText: transcription
            ) {
            case .ok(let deleteCount, let verifiedCount, let windowTruncated):
                self.dictationUndoAvailable = true
                self.logProbe(
                    "dictationUndoArmed",
                    details: "deleteCount=\(deleteCount) verified=\(verifiedCount) truncated=\(windowTruncated)"
                )
            case .failed(let reason):
                self.invalidateDictationUndo(reason: "arm-\(reason)")
            }
        }
    }

    /// Re-check the offer against the live document.
    ///
    /// WHY this re-verifies instead of clearing outright: the host reports a text
    /// change for the keyboard's *own* insertion too, so a hook that cleared blindly
    /// would cancel the offer in the same breath as making it — on some hosts, at
    /// some speeds. Re-checking has the behaviour the issue asks for (the offer dies
    /// on the first keystroke, a caret move or a host rewrite) without depending on
    /// which changes a given host chooses to report.
    ///
    /// WHY it stands down until the offer is armed: the change reports triggered by
    /// the insertion itself can arrive before the proxy's context catches up with
    /// it, and a check run against that stale context refuses. Arming already
    /// verifies, one main-queue turn after the insertion, and the user cannot type
    /// inside that turn — so there is nothing for this to protect there.
    ///
    /// WHY only a proven mismatch drops the offer, and not every refusal:
    /// "the field is no longer ours" and "nothing could be read just now" are
    /// different facts, and only the first is evidence. Device capture in Messages
    /// (2026-08-02) showed the second killing a valid offer two seconds after it
    /// was armed: iOS had just swapped controllers, the freshly attached one had
    /// not settled, and its proxy returned no context yet — so `no-context`
    /// invalidated an offer nothing had invalidated. Controller churn is routine
    /// here (#281), so this was not a one-off.
    ///
    /// Keeping the offer alive on an unreadable document costs nothing, because
    /// this is not the check that authorises a deletion: `performDictationUndo`
    /// re-verifies at the instant of the tap and fails closed on exactly these
    /// reasons. The worst case is a button that stays on screen for its few
    /// seconds and refuses when tapped, which is the behaviour a host that lies
    /// about its context earns anyway.
    func revalidateDictationUndo() {
        guard dictationUndoAvailable, let transcription = dictationUndoText else { return }
        if let proxy = controller?.textDocumentProxy,
           HostInputTraits.documentIdentifier(for: proxy) != dictationUndoDocumentID || proxy.selectedText?.isEmpty == false
            || proxy.documentContextAfterInput != dictationUndoContextAfter {
            // Refresh the passive preview without changing recovery's existing refusal policy.
            objectWillChange.send()
        }
        if case .failed(let reason) = DictationUndo.verify(
            context: controller?.textDocumentProxy.documentContextBeforeInput,
            insertedText: transcription
        ), DictationUndo.provesTheFieldChanged(reason) {
            invalidateDictationUndo(reason: "revalidate-\(reason)")
        }
    }

    /// Drop the offer. The record is destroyed, not merely hidden: a hidden record
    /// is one bug away from deleting text it no longer owns.
    func invalidateDictationUndo(reason: String) {
        guard dictationUndoText != nil else { return }
        dictationUndoText = nil
        dictationOriginalText = nil
        dictationUndoDocumentID = nil
        dictationUndoContextAfter = nil
        dictationUndoAvailable = false
        dictationUndoTimer?.invalidate()
        dictationUndoTimer = nil
        logProbe("dictationUndoInvalidated", details: "reason=\(reason)")
    }

    /// Remove the last dictation insertion from the host field.
    ///
    /// The check runs again here, against the document as it is at this instant.
    /// The one performed when the control appeared proves nothing about now: a host
    /// that rewrites text without reporting it leaves a stale offer on screen, and
    /// this is where that is caught. A refusal deletes nothing.
    func performDictationUndo() {
        guard let transcription = dictationUndoText, !isUndoingDictation else { return }
        guard let proxy = controller?.textDocumentProxy else {
            invalidateDictationUndo(reason: "perform-no-proxy")
            return
        }

        guard let documentID = HostInputTraits.documentIdentifier(for: proxy), documentID == dictationUndoDocumentID,
              proxy.selectedText?.isEmpty != false,
              proxy.documentContextAfterInput == dictationUndoContextAfter else {
            invalidateDictationUndo(reason: "perform-field-changed")
            return
        }

        switch DictationUndo.verify(
            context: proxy.documentContextBeforeInput,
            insertedText: transcription
        ) {
        case .failed(let reason):
            HapticFeedback.actionRefused()
            invalidateDictationUndo(reason: "perform-\(reason)")
        case .ok(let deleteCount, let verifiedCount, let windowTruncated):
            guard !windowTruncated else {
                HapticFeedback.actionRefused()
                return
            }
            logProbe(
                "dictationUndoStarted",
                details: "deleteCount=\(deleteCount) verified=\(verifiedCount) truncated=\(windowTruncated)"
            )
            isUndoingDictation = true
            // The offer is spent the moment it is taken. Clearing first also means
            // a second tap during the burst finds nothing to act on.
            invalidateDictationUndo(reason: "performed")
            deleteInsertedText(transcription, remaining: deleteCount, proxy: proxy)
        }
    }

    /// Lives in the existing output-language menu; no extra input layer or lane.
    func dictationResultMenuItems() -> [UIMenuElement] {
        guard dictationUndoAvailable else { return [] }
        var actions: [UIMenuElement] = []
        if let original = dictationOriginalText, let delivered = dictationUndoText,
           original.trimmingCharacters(in: .whitespacesAndNewlines) != delivered.trimmingCharacters(in: .whitespacesAndNewlines) {
            actions.append(UIAction(title: "Copy original", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = original
            })
            if canRestoreOriginal {
                actions.append(UIAction(title: "Restore original", image: UIImage(systemName: "arrow.uturn.backward")) { [weak self] _ in
                    self?.restoreOriginalDictation()
                })
            }
        }
        if let proxy = controller?.textDocumentProxy, let inserted = dictationUndoText,
           let documentID = HostInputTraits.documentIdentifier(for: proxy), documentID == dictationUndoDocumentID,
           case .ok(_, _, false) = DictationUndo.verify(context: proxy.documentContextBeforeInput, insertedText: inserted) {
            actions.append(UIAction(title: "Undo dictation", image: UIImage(systemName: "delete.left")) { [weak self] _ in
                self?.performDictationUndo()
            })
        }
        return [UIMenu(title: "Last dictation", options: .displayInline, children: actions)]
    }

    private var canRestoreOriginal: Bool {
        guard dictationUndoAvailable, !isUndoingDictation, dictationStatus == .idle,
              let proxy = controller?.textDocumentProxy,
              let documentID = HostInputTraits.documentIdentifier(for: proxy), documentID == dictationUndoDocumentID,
              proxy.selectedText?.isEmpty != false,
              proxy.documentContextAfterInput == dictationUndoContextAfter,
              let inserted = dictationUndoText, dictationOriginalText != nil else { return false }
        return DictationUndo.originalRestorationCount(context: proxy.documentContextBeforeInput, insertedText: inserted) != nil
    }

    func restoreOriginalDictation() {
        guard canRestoreOriginal, let proxy = controller?.textDocumentProxy,
              let inserted = dictationUndoText, let original = dictationOriginalText,
              let count = DictationUndo.originalRestorationCount(context: proxy.documentContextBeforeInput, insertedText: inserted) else {
            HapticFeedback.actionRefused()
            return
        }
        // ponytail: one main-turn replacement, capped at 200 graphemes; longer
        // transcripts use Copy original + Undo until chunked restoration is measured.
        let replacement = original + (inserted.hasSuffix(" ") && !original.hasSuffix(" ") ? " " : "")
        guard let documentID = HostInputTraits.documentIdentifier(for: proxy) else { return }
        let prefix = String((proxy.documentContextBeforeInput ?? "").dropLast(count))
        invalidateDictationUndo(reason: "restored-original")
        for remaining in stride(from: count, to: 0, by: -1) {
            guard HostInputTraits.documentIdentifier(for: controller?.textDocumentProxy) == documentID,
                  proxy.documentContextBeforeInput?.hasSuffix(String(inserted.prefix(remaining))) == true else {
                HapticFeedback.actionRefused()
                return
            }
            proxy.deleteBackward()
        }
        guard HostInputTraits.documentIdentifier(for: controller?.textDocumentProxy) == documentID,
              (proxy.documentContextBeforeInput ?? "") == prefix else {
            HapticFeedback.actionRefused()
            return
        }
        proxy.insertText(replacement)
        SuggestionState.shared.clear(resetLanguage: false)
        onDictationUndone?()
        armDictationUndo(replacement)
        HapticFeedback.textInserted()
    }

    func interruptDictationUndoForTyping() {
        guard isUndoingDictation else { return }
        isUndoingDictation = false
        logProbe("dictationUndoAborted", details: "reason=user-input")
    }

    /// Issue the deletion in chunks, yielding to the main queue between them.
    ///
    /// WHY the remainder is still checked between chunks, but no longer *required*:
    ///
    /// The first design re-proved the remainder before every chunk and stopped when
    /// it could not, on the assumption that the proxy's window slides back over the
    /// document as the deletion consumes it. Three device captures in Notes
    /// (2026-08-02) disproved that assumption arithmetically. The window measured
    /// 491, 496 and 490 graphemes when each burst started, and 11, 16 and 10 when it
    /// stopped — in each case exactly the starting window minus the 480 graphemes
    /// removed. The host serves one cached window and trims it; it never refetches.
    /// A caret round trip, tried as a way to invalidate that cache, changed nothing.
    ///
    /// So the requirement could not be met by any host that behaves this way, and
    /// its cost was the feature itself: a 4752-grapheme undo removed 480 and left
    /// 4272 behind, on precisely the length that makes holding backspace painful.
    ///
    /// What remains is the distinction that actually carries the safety, the same
    /// one `revalidateDictationUndo` draws. A refusal that PROVES the field changed
    /// — the document was legible and does not end with the remainder — stops the
    /// burst. A refusal that only means the document could not be read does not:
    /// absence of proof is not evidence, and treating it as such is what broke the
    /// long case. The remaining exposure is a host that silently accepted less text
    /// than it was handed, e.g. a length-limited field, where the recorded count
    /// then reaches past what was inserted. Narrow, visible when it happens, and
    /// weighed against a feature that otherwise does not work at all past ~500
    /// characters.
    ///
    /// The count itself is the hard bound and always was: it is the length of the
    /// string this keyboard handed to `insertText`, never a guess, so the burst
    /// cannot delete more than one dictation put there.
    ///
    /// The proxy is captured once, at the start. iOS can attach a new controller
    /// mid-burst, and `controller` is a shared reference that the new one takes
    /// over; re-reading it each turn would redirect the rest of the deletion at
    /// whatever field that controller is looking at.
    ///
    /// Aborts if a dictation has started in the meantime. `startRecording` refuses
    /// to start one while a burst is in flight, so this is the second line of
    /// defence rather than the first — but the app can also drive the status from
    /// its own side, and a burst that kept deleting into a fresh recording would
    /// eat text this undo never inserted.
    private func deleteInsertedText(
        _ insertedText: String,
        remaining: Int,
        proxy: UITextDocumentProxy
    ) {
        guard isUndoingDictation else { return }
        guard let documentID = HostInputTraits.documentIdentifier(for: proxy),
              documentID == HostInputTraits.documentIdentifier(for: controller?.textDocumentProxy) else {
            isUndoingDictation = false
            logProbe("dictationUndoAborted", details: "reason=field-changed")
            return
        }
        guard remaining > 0 else {
            isUndoingDictation = false
            SuggestionState.shared.clear(resetLanguage: false)
            onDictationUndone?()
            logProbe("dictationUndoCompleted")
            return
        }
        guard dictationStatus == .idle, activeSessionID == nil else {
            isUndoingDictation = false
            logProbe(
                "dictationUndoAborted",
                details: "reason=dictation-started remaining=\(remaining) \(sessionDetails())"
            )
            return
        }

        let batch = min(remaining, Self.dictationUndoChunkSize)
        for _ in 0..<batch {
            proxy.deleteBackward()
        }
        let left = remaining - batch

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard left > 0 else {
                self.deleteInsertedText(insertedText, remaining: 0, proxy: proxy)
                return
            }
            let context = proxy.documentContextBeforeInput
            if case .failed(let reason) = DictationUndo.verify(
                context: context,
                insertedText: String(insertedText.prefix(left))
            ), DictationUndo.provesTheFieldChanged(reason) {
                self.isUndoingDictation = false
                // `context` says how much the host was willing to show at the moment
                // it stopped us, which is what tells a genuine rewrite apart from a
                // window that had run dry (#266 device captures).
                self.logProbe(
                    "dictationUndoAborted",
                    details: "reason=\(reason) remaining=\(left) context=\(context?.count ?? -1)"
                )
                return
            }
            self.deleteInsertedText(insertedText, remaining: left, proxy: proxy)
        }
    }

    // MARK: - Keyboard visibility tracking

    /// Called when a controller becomes the active visible keyboard owner.
    ///
    /// Unconditional: the controller iOS just brought on screen is the keyboard,
    /// whatever came before. This is also what ends an awaiting-reclaim window in
    /// the common case — the successor iOS builds after an app switch simply takes
    /// the area over (#260).
    func registerControllerAppearance(controllerID: String) {
        logProbe(
            "registerControllerAppearance",
            details: "controllerID=\(controllerID) previousOwner=\(activeControllerID ?? "none") ownership=\(ownership.logDescription) wasVisible=\(isKeyboardVisible) \(sessionDetails())"
        )
        ownership = ownership.appearing(controllerID: controllerID)

        // Refresh state from App Group — picks up status changes that
        // happened while the keyboard extension was suspended.
        refreshFromDefaults()
        handleTranscriptionReady()
    }

    /// Called when a controller disappears. Only the current owner may hide the keyboard.
    func registerControllerDisappearance(controllerID: String) {
        let ownsVisibility = activeControllerID == controllerID
        logProbe(
            "registerControllerDisappearance",
            details: "controllerID=\(controllerID) owner=\(activeControllerID ?? "none") ownsVisibility=\(ownsVisibility) wasVisible=\(isKeyboardVisible) \(sessionDetails())"
        )

        // The keyboard the insertion was made from is going away, so the field it
        // was made into is no longer in front of the user (#266). Only the owner
        // counts here: under churn, instances iOS is about to throw away report
        // disappearing too, and letting one of those drop the record would make the
        // offer vanish at random.
        if ownsVisibility {
            invalidateDictationUndo(reason: "keyboard-dismissed")
        }

        ownership = ownership.disappearing(controllerID: controllerID)
    }

    /// Called when a controller is deallocated (#260).
    ///
    /// WHY this is not `registerControllerDisappearance`: a deallocation is not a
    /// dismissal. Ownership is last-writer-wins on appearance, so under churn the
    /// live keyboard's ownership is routinely overwritten by an instance iOS is
    /// about to throw away — and when the old code let that instance release the
    /// area on its way out, the keyboard the user was looking at was left unable
    /// to present anything, with no path back: its `viewWillAppear` had already
    /// run. That is `activeID=none`, and it lasted seconds.
    ///
    /// The area is marked reclaimable instead. That marker reads as ownerless and
    /// invisible, exactly like the release it replaces, so nothing downstream
    /// changes; what it adds is that a controller still on screen may claim the
    /// area through `claimOwnership`.
    ///
    /// Logs only when ownership actually moves: `deinit` runs on every one of the
    /// ~9 instances a churn cycle destroys, and the ids differ, so an
    /// unconditional line would defeat `PersistentLog`'s duplicate collapsing and
    /// spend the #255 budget on non-events.
    func registerControllerDeallocation(controllerID: String) {
        let next = ownership.deallocating(controllerID: controllerID)
        guard next != ownership else { return }
        logProbe(
            "registerControllerDeallocation",
            details: "controllerID=\(controllerID) ownership=\(ownership.logDescription) next=\(next.logDescription) \(sessionDetails())"
        )
        ownership = next
    }

    /// Let the controller iOS is showing claim an area whose owner was
    /// deallocated (#260).
    ///
    /// `isOnScreen` must come from UIKit window attachment, not from bookkeeping:
    /// it is the only thing separating the live keyboard from the cached instances
    /// iOS never tells to disappear (#128), and both reach this on the same path.
    /// Returns whether the caller now owns the keyboard area.
    ///
    /// WHY this deliberately does NOT call `refreshFromDefaults`: it is called from
    /// inside the area-mode subscription, and refreshing writes `dictationStatus`,
    /// whose `didSet` publishes the mode again — a re-entrant emission while the
    /// first one is still applying its layout. The status is current anyway: the
    /// emission that brought us here came from that very write.
    @discardableResult
    func claimOwnership(controllerID: String, isOnScreen: Bool) -> Bool {
        guard let next = ownership.claiming(controllerID: controllerID, isOnScreen: isOnScreen) else {
            logRefusedClaimOnce(controllerID: controllerID, isOnScreen: isOnScreen)
            return false
        }
        logProbe(
            "claimOwnership",
            details: "controllerID=\(controllerID) previous=\(ownership.logDescription) \(sessionDetails())"
        )
        ownership = next
        return true
    }

    /// The marker a refused claim was last logged against, so the line below is
    /// written once per episode rather than once per controller.
    private var loggedClaimRefusalFor: String?

    /// Record that a reclaimable area went unclaimed because the controller asking
    /// was not on screen (#260).
    ///
    /// This exists to make the fail-closed liveness test falsifiable on device. If
    /// window attachment turns out to be unreliable for a `UIInputViewController`,
    /// the symptom is this line with no `claimedOwnerlessArea` after it — an
    /// explicit signal rather than an absence to be inferred.
    ///
    /// Once per marker: every one of the ~9 cached controllers reacts to the same
    /// emission, and #255 exists because lines that multiply by instance count
    /// make a log unreadable.
    private func logRefusedClaimOnce(controllerID: String, isOnScreen: Bool) {
        guard case .awaitingReclaim(let previous) = ownership,
              loggedClaimRefusalFor != previous else { return }
        loggedClaimRefusalFor = previous
        logProbe(
            "claimRefusedOffScreen",
            details: "controllerID=\(controllerID) previousOwner=\(previous) hasWindow=\(isOnScreen) \(sessionDetails())"
        )
    }

    /// Ask a controller still on screen to look at an area that just became
    /// reclaimable, instead of waiting for the next dictation status change (#260).
    ///
    /// WHY this is needed at all: a controller claims an ownerless area from
    /// `applyAreaMode`, which only runs when the area mode is published — i.e. on a
    /// status write. If the owner is deallocated in the middle of a recording, the
    /// next write is the `transcribing` transition, so the keyboard would sit in
    /// its typing layout for the rest of the utterance.
    ///
    /// Only while a dictation owns the area: `.recording` is the one mode gated on
    /// ownership, so re-publishing anything else would make every attached
    /// controller redo its layout for no possible change.
    ///
    /// WHY asynchronously: this is reached from the outgoing owner's `deinit`,
    /// which then goes on to tear down its hosting controller and view hierarchy.
    /// Applying layout on a *different* controller from inside that stack is the
    /// kind of re-entrancy this file has regressed on before (#142, #128, #166).
    /// One main queue hop puts the work after the deallocation has finished.
    ///
    /// It does nothing when every controller has already been detached — the
    /// subscription is cancelled in `viewDidDisappear`. Nothing can be done for the
    /// keyboard then: there is no live controller left to draw with.
    private func nudgeAttachedControllersToReclaim() {
        guard areaMode == .recording else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.ownership.isReclaimable, self.areaMode == .recording else { return }
            self.logProbe(
                "reclaimNudge",
                details: "ownership=\(self.ownership.logDescription) mode=\(self.areaMode.rawValue) \(self.sessionDetails())"
            )
            self.areaModeSubject.send(self.areaMode)
        }
    }

    /// Timestamp of last mic tap — used for debouncing.
    /// WHY 1.5s debounce: After a recording completes (transcription inserted),
    /// there's a brief window where the overlay hides and the mic button appears.
    /// Accidental double-taps or frustrated rapid-tapping during this transition
    /// cause sub-1-second recordings that Parakeet rejects, triggering a cascade
    /// of errors. 1.5s matches the natural human rhythm between dictation sessions.
    private var lastMicTapDate = Date.distantPast
    private var lastModelPreparationOpenDate = Date.distantPast
    private var sessionGeneration = 0

    /// Start recording: set local state, then signal DictusApp.
    ///
    /// iOS keyboard extensions cannot capture microphone audio. DictusApp owns
    /// capture and inference; the keyboard only sends start/stop requests.
    ///
    /// Flow:
    /// 1. Set local state to .requested (recording overlay appears immediately)
    /// 2. Post startRecording Darwin notification to the enabled audio session.
    /// 3. If the app does not acknowledge, show an explicit recovery action.
    ///
    /// Holds never switch apps. Session preparation is a separate tap action.
    func startRecording() {
        isOpeningForDictation = false
        if dictationStatus == .failed {
            guard DictationFailureAction.recoveryTransition(
                for: DictationErrorChannel.currentDisposition, urlOpened: true
            ) == .resetAndRetry else { return }
            forceResetToIdle()
            DictationErrorChannel.clear()
            lastMicTapDate = Date.distantPast
            sessionGeneration += 1
        }

        // An undo burst is still rewriting the field (#266). Starting a dictation
        // now would have the two interleave: the burst deletes on every main-queue
        // turn, and the transcription it would be deleting into is not the one it
        // was verified against. The burst is short; the user taps again.
        //
        // WHY this comes before the debounce: a refused tap must not count as a
        // tap. Charging it to the debounce window would make the mic dead for
        // 1.5 s after a burst that lasted a fraction of that, and the second tap —
        // the one this refusal is telling the user to make — would be the one
        // rejected.
        guard !isUndoingDictation else {
            logProbe("micTapRejectedDuringUndo", details: sessionDetails())
            HapticFeedback.actionRefused()
            return
        }

        // Debounce: reject taps within 1.5s of the last tap.
        let now = Date()
        guard now.timeIntervalSince(lastMicTapDate) >= 1.5 else {
            PersistentLog.log(.rapidTapRejected)
            return
        }
        // A new dictation ends the previous one's undo offer, whatever comes of it.
        invalidateDictationUndo(reason: "new-dictation")

        // A model load is a prepare-only state, but a hold-to-dictate gesture
        // must remain local to the keyboard. Expose the explicit recovery action
        // without launching the containing app from the recording path.
        // We synchronize defaults first because cross-process writes from DictusApp
        // can lag a few ms behind the actual state change.
        if isModelLoading() {
            PersistentLog.log(.keyboardMicTapped)
            PersistentLog.log(.dictationDeferred(reason: "model load in flight before session start"))
            failKeyboardStart()
            return
        }

        defaults.synchronize()
        if !defaults.bool(forKey: SharedKeys.keyboardAudioReady) {
            PersistentLog.log(.keyboardMicTapped)
            PersistentLog.log(.dictationDeferred(reason: "keyboard audio session not ready"))
            failKeyboardStart()
            return
        }

        activeSessionID = String(UUID().uuidString.prefix(8))
        sessionGeneration += 1
        guard let requestSessionID = activeSessionID else { return }
        let requestGeneration = sessionGeneration
        let existingRequest = DictationLanguageRequest.load(from: defaults)
        let requestMode = existingRequest.modeForNextDictation(
            defaultingTo: TranscriptionLanguageMode.active
        )
        let resolvedSourceLanguage = ASRCapability.forModelIdentifier(
            defaults.string(forKey: SharedKeys.activeModel),
            mode: requestMode,
            keyboardLanguage: SupportedLanguage.active,
            outputMode: TranscriptionOutputMode.active
        ).sourceLanguage
        let request = DictationLanguageRequest(
            mode: requestMode,
            translationTarget: existingRequest.translationTarget,
            sessionID: requestSessionID,
            generation: requestGeneration,
            clientIdentifier: UUID().uuidString,
            resolvedSourceLanguage: resolvedSourceLanguage
        )
        request.persist(to: defaults)
        DictationDelivery.clear(in: defaults)
        defaults.set(false, forKey: SharedKeys.stopRequested)
        defaults.set(false, forKey: SharedKeys.cancelRequested)
        languageRequest = Self.loadLanguageRequest(from: defaults)
        logProbe("startRecording", details: sessionDetails())

        PersistentLog.log(.keyboardMicTapped)
        markRequested()
        // Only a request that reached the shared `.requested` state counts as a tap.
        lastMicTapDate = now

        // The model can begin loading after the first check while this tap is
        // being handed to DictusApp. Re-check immediately before posting the
        // recording request so a model swap cannot race into a recording.
        if isModelLoading() {
            requestCancel()
            PersistentLog.log(.dictationDeferred(reason: "model load raced after markRequested"))
            failKeyboardStart()
            return
        }

        defaults.synchronize()
        if !defaults.bool(forKey: SharedKeys.keyboardAudioReady) {
            requestCancel()
            PersistentLog.log(.dictationDeferred(reason: "keyboard audio session lost after markRequested"))
            failKeyboardStart()
            return
        }

        DarwinNotificationCenter.post(DarwinNotificationName.startRecording)

        // A stale readiness marker must not switch apps during a hold. Allow
        // time for the background process to acknowledge, then offer recovery.
        let darwinPostTime = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            self.refreshFromDefaults()
            let elapsedMs = Int(Date().timeIntervalSince(darwinPostTime) * 1000)
            if DictationFailureAction.fallbackMayOpen(
                expectedSessionID: requestSessionID,
                currentSessionID: self.activeSessionID,
                expectedGeneration: requestGeneration,
                currentGeneration: self.sessionGeneration,
                status: self.dictationStatus
            ) {
                PersistentLog.log(.coldStartDarwinFallback(
                    elapsedMs: elapsedMs,
                    status: self.dictationStatus.rawValue
                ))
                self.failKeyboardStart()
            }
        }
    }

    private func failKeyboardStart() {
        requestCancel()
        refreshModelPreparationState()
        appNeedsAppAction = true
        presentStatusMessage("Enable keyboard dictation in sAiity, then return here.",
                             reason: "keyboard-session-unavailable", timeoutReason: "keyboard-session-unavailable-timeout")
    }

    /// Open Dictus without creating a recording request. The user explicitly
    /// starts dictation with a second tap once preparation has completed (#262).
    private func openModelPreparation() {
        // The preparation action can arrive through both touchDown and
        // primaryActionTriggered on a keyboard host. Coalesce that pair so a
        // single tap opens one app handoff.
        guard Date().timeIntervalSince(lastModelPreparationOpenDate) >= 1 else { return }
        lastModelPreparationOpenDate = Date()
        guard let url = KeyboardDictationBridge.recoveryURL() else {
            return
        }
        openDictusURL(url)
    }

    /// Re-read the shared state at each handoff boundary because the app can
    /// start a model swap after the keyboard's previous snapshot.
    private func isModelLoading() -> Bool {
        defaults.synchronize()
        let rawState = defaults.string(forKey: SharedKeys.modelLoadState)
            ?? ModelLoadState.idle.rawValue
        guard let state = ModelLoadState(rawValue: rawState), state == .loading else {
            return false
        }
        let timestamp = defaults.double(forKey: SharedKeys.modelLoadStateTimestamp)
        let startedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        return KeyboardModelPreparationPolicy.isLoadingStateFresh(
            modelLoadState: state,
            modelLoadStartedAt: startedAt
        )
    }

    /// Single source of truth for "the board offers to open sAiity" instead of
    /// the dictate control.
    ///
    /// Two gates used to disagree. The label consulted only `appNeedsAppAction`
    /// while the UIKit action also honoured `failedRequiresApp`, so a failed
    /// session that needed the app rendered "Hold to dictate" and then opened
    /// the app on press — the control advertised one verb and performed
    /// another. Label and action now read this one flag, so they cannot drift.
    ///
    /// A live session always wins: `ownsKeyboardArea` is true while requested or
    /// recording, and the recovery control must never displace cancel.
    var showsRecoveryAction: Bool {
        guard !dictationStatus.ownsKeyboardArea else { return false }
        return appNeedsAppAction || failedRequiresApp
    }

    /// Label for whichever control currently occupies the board's primary slot.
    var primaryBoardActionLabel: String {
        if showsRecoveryAction { return "Open sAiity to prepare dictation" }
        switch dictationStatus {
        case .requested: return "Cancel dictation preparation"
        case .recording: return isFinishingRecording ? "Finishing dictation" : "Finish dictation"
        case .transcribing: return "Cancel transcription"
        case .processing: return "Cancel cleanup"
        case .idle, .ready, .failed: return "Hold to dictate"
        }
    }

    var dictationBoardStateTitle: String {
        switch dictationStatus {
        case .requested: return "Getting ready"
        case .recording: return isFinishingRecording ? "Finishing" : "Listening"
        case .transcribing: return "Transcribing"
        case .processing: return "Cleaning up"
        case .failed: return "Dictation interrupted"
        case .idle, .ready:
            if !keyboardDictationEnabled { return "Dictation is off" }
            if showsRecoveryAction { return "Prepare dictation" }
            return currentDictationPreview == nil ? "Ready to dictate" : "Text inserted"
        }
    }

    var recoveryBoardTitle: String {
        if isOpeningForDictation { return "Opening sAiity…" }
        if dictationStatus == .failed, statusMessage != nil { return "Try again" }
        return "Open sAiity"
    }

    var dictationBoardTitle: String {
        switch dictationStatus {
        case .idle, .ready, .failed: return "Hold to dictate"
        case .requested, .transcribing, .processing: return "Cancel"
        case .recording: return isFinishingRecording ? "Finishing…" : "Finish"
        }
    }

    var dictationBoardSymbol: String {
        switch dictationStatus {
        case .recording: return isFinishingRecording ? "ellipsis" : "waveform"
        case .requested: return "ellipsis"
        case .transcribing, .processing: return "xmark"
        case .failed, .idle, .ready: return "mic.fill"
        }
    }

    var dictationActionLabel: String { primaryBoardActionLabel }

    /// Defer recording without leaving a requested state behind in the keyboard.
    private func deferRecordingForModelPreparation(reason: String = "keyboard opened sAiity for model preparation") {
        PersistentLog.log(.dictationDeferred(reason: reason))
        openModelPreparation()
    }

    /// Use the extension context and fail closed when the handoff is unavailable.
    private func openDictusURL(_ url: URL) {
        guard openContainingApp != nil || controller?.extensionContext != nil else {
            isOpeningForDictation = false
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardState",
                instanceID: instanceID,
                action: "extensionURLFailedClosed",
                details: "missing extension context"
            ))
            presentStatusMessage("Unable to open sAiity. Try again.", reason: "recoveryURLFailed", timeoutReason: "recoveryURLFailed-timeout")
            return
        }
        openURLFromExtension(url) { [weak self] succeeded in
            DispatchQueue.main.async {
                #if DEBUG
                // The handoff result is the difference between "the tap never
                // arrived" and "the tap arrived and iOS refused the open". Those
                // need completely different fixes, so record the outcome.
                PersistentLog.log(.diagnosticProbe(
                    component: "TouchPath",
                    instanceID: self?.instanceID ?? "nil",
                    action: "openURL",
                    details: "succeeded=\(succeeded) url=\(url.absoluteString) hasContext=\(self?.controller?.extensionContext != nil)"
                ))
                #endif
                guard let self, !succeeded else { return }
                self.isOpeningForDictation = false
                self.lastModelPreparationOpenDate = .distantPast
                self.presentStatusMessage("iOS could not open sAiity. Open it from the Home Screen to start dictation.", reason: "recoveryURLFailed", timeoutReason: "recoveryURLFailed-timeout")
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyboardState", instanceID: self.instanceID,
                    action: "extensionURLFailedClosed", details: "extensionContext.open returned false"
                ))
            }
        }
    }

    /// Write "requested" status to App Group before triggering URL.
    func markRequested() {
        logProbe("markRequested", details: sessionDetails())
        defaults.set(DictationStatus.requested.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
        dictationStatus = .requested
        startWatchdog()
    }

    private func sessionDetails() -> String {
        let sessionID = activeSessionID ?? "none"
        return "sessionID=\(sessionID) status=\(dictationStatus.rawValue) energyCount=\(waveformEnergy.count)"
    }

    private func logProbe(_ action: String, details: String = "") {
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardState",
            instanceID: instanceID,
            action: action,
            details: details
        ))
    }

    private func waveformStatsDetails(_ values: [Float]) -> String {
        guard !values.isEmpty else { return "count=0" }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let spread = maxValue - minValue
        let first = values.first ?? 0
        let middle = values[values.count / 2]
        let last = values.last ?? 0
        return String(
            format: "count=%d min=%.3f max=%.3f spread=%.3f first=%.3f mid=%.3f last=%.3f",
            values.count,
            minValue,
            maxValue,
            spread,
            first,
            middle,
            last
        )
    }
}

// MARK: - Orphaned dictation reconciliation (#261)

/// WHY these live in an extension rather than in the class body: `KeyboardState` is
/// already at SwiftLint's `type_body_length` budget, and this block is a coherent
/// unit that reads as one. Same device as `DictationCoordinator`'s engine-init
/// extension, and for the same reason. Being in the same file keeps access to the
/// class's private members, so nothing had to be widened to make room.
private extension KeyboardState {

    /// What the App Group says about the dictation, and what that means.
    struct DictationLivenessReading {
        let verdict: DictationSessionLiveness
        let status: DictationStatus?
        /// Age of the heartbeat in milliseconds, or -1 when there was none to read.
        let heartbeatAgeMs: Int
    }

    /// Ask the shared state whether a live process is still behind it.
    ///
    /// Reads the App Group directly rather than `dictationStatus`, because the point
    /// is to audit what was *written* -- a keyboard rebuilt after the app died has no
    /// in-memory status of its own yet.
    func dictationLiveness() -> DictationLivenessReading {
        let raw = defaults.double(forKey: SharedKeys.recordingHeartbeat)
        let reading = KeyboardLifecycleMonitor.reading(
            statusRaw: defaults.string(forKey: SharedKeys.dictationStatus),
            heartbeat: raw > 0 ? raw : nil,
            localSessionStartedAt: sessionStartedAt?.timeIntervalSince1970
        )
        return DictationLivenessReading(
            verdict: reading.verdict,
            status: reading.status,
            heartbeatAgeMs: reading.heartbeatAgeMs
        )
    }

    /// Reconcile only if the shared state proves the writing process is gone (#261).
    ///
    /// Used where nothing else has made a determination: the first read after the
    /// extension is rebuilt, and the watchdog tick, where this is what lets a stale
    /// heartbeat pre-empt the 15 s cold-start grace.
    ///
    /// Returns whether it acted, so callers can skip the work they were about to do.
    @discardableResult
    func reconcileIfOrphaned(source: String) -> Bool {
        let reading = dictationLiveness()
        guard reading.verdict == .orphaned, let status = reading.status else { return false }
        reconcileAbandonedDictation(
            source: source,
            staleStatus: status,
            heartbeatAgeMs: reading.heartbeatAgeMs
        )
        return true
    }

    /// Give up on the current dictation, leave both sides consistent, and tell the
    /// user (#261).
    ///
    /// WHY the keyboard does this itself rather than waiting for the app: when iOS
    /// terminates DictusApp mid-dictation, nothing relaunches it. The overlay used to
    /// keep pretending to record until the watchdog expired, and the watchdog then
    /// reset in silence -- which is what left the user tapping a stop button that did
    /// nothing and losing a long voice note with no explanation.
    ///
    /// WHY it posts a **cancel** and not a stop: the first version posted a stop, on
    /// the argument that it would cost nothing if nobody was listening and salvage the
    /// recording if somebody was. The device disagreed (2026-08-03). A false positive
    /// is by definition the case where somebody *is* listening, so the cost lands
    /// exactly where the insurance was meant to pay out: the app took the stop, found
    /// `sampleCount=0`, and turned a recoverable UI desync into a failed dictation.
    /// A cancel discards and returns the app to `.idle` instead, which is the clean
    /// state the next mic tap needs. Doing nothing at all was the other candidate and
    /// was rejected: it would leave the app stuck in `.recording`, where
    /// `startDictation`'s duplicate guard refuses every subsequent tap.
    ///
    /// WHY the cancel is posted for a stale `recording` and not a stale `transcribing`:
    /// cancelling a recording nobody is capturing costs nothing, but `cancelDictation`
    /// also cancels the in-flight transcription task. Reaching this during
    /// `transcribing` does not prove the transcriber is dead — only that the audio
    /// engine stopped writing, and those are independent (tapping Power in the Dynamic
    /// Island does exactly that). Posting a cancel there would destroy text that would
    /// otherwise still arrive: `handleTranscriptionReady` inserts it irrespective of
    /// the keyboard's local status. The app has its own 30 s transcription watchdog for
    /// the case where the transcriber really is stuck, so nothing is left unattended.
    func reconcileAbandonedDictation(
        source: String,
        staleStatus: DictationStatus,
        heartbeatAgeMs: Int
    ) {
        PersistentLog.log(.dictationStateReconciled(
            source: source,
            staleStatus: staleStatus.rawValue,
            heartbeatAgeMs: heartbeatAgeMs
        ))

        if staleStatus == .recording {
            defaults.set(true, forKey: SharedKeys.cancelRequested)
            defaults.synchronize()
            DarwinNotificationCenter.post(DarwinNotificationName.cancelRecording)
        }

        // Clears the local status, the session id and the message, writes `idle` and
        // drops the shared recording keys, then posts `statusChanged` -- so the overlay
        // is gone on the next run loop pass rather than on the next watchdog tick.
        forceResetToIdle()

        // Said after the reset, because `forceResetToIdle` clears the message. The
        // wording is "interrupted", not "crashed": from the user's side that is both
        // truer and less alarming, and it is what they need to know -- the recording
        // is gone and the next tap starts fresh.
        presentStatusMessage(
            String(localized: "Recording interrupted. Please try again."),
            reason: "reconciled-\(source)",
            timeoutReason: "reconciled-timeout"
        )
    }
}

// MARK: - Status message trail (#261)

/// Instrumentation for the toolbar message's whole life: set, displayed, ended.
///
/// WHY it exists: the sharpened acceptance criterion for #261 is "stop the recording
/// *and say something*", and until now nothing in the exported log recorded whether
/// anything was said. The message is assigned on a singleton, but iOS keeps several
/// `KeyboardViewController` instances alive at once (~9 during a dictation, #281), so
/// "assigned" and "on screen in front of the user" are different facts and only the
/// first one was observable. A single "I set the message" line would reproduce that
/// ambiguity exactly, which is why set and displayed are separate events.
///
/// Cost: one line when a message is assigned, one per view that renders it, one when
/// it ends. The message changes a handful of times per session, so this is
/// proportional to the message and not to the render loop — nothing here fires per
/// frame or per render tick.
extension KeyboardState {

    /// Assign the toolbar message and name what asked for it.
    ///
    /// The reason travels in a property rather than a parameter because the observer
    /// that logs it is on `statusMessage` itself, which is what makes it impossible
    /// for a writer to escape the trail.
    func assignStatusMessage(_ message: String?, reason: String) {
        statusMessageReason = reason
        statusMessage = message
    }

    /// Put a message on the toolbar and take it down again once it has had its time.
    ///
    /// WHY the token rather than a bare `asyncAfter` (#342): the pending clear used to
    /// capture nothing, so it cleared whatever was current when it fired. Two mic taps
    /// two seconds apart were enough to lose the second message after one second, and
    /// to name `appError-timeout` on a clear that took down a `reconciled` message. The
    /// token is read here and checked in the closure, so a clear can only ever take
    /// down the message it was scheduled for. Nothing is logged when it declines: the
    /// `set` and `cleared` pair already bracket every message's life, and #255 makes a
    /// line that says "I did nothing" a cost rather than a neutral.
    ///
    /// WHY every timed message goes through one function: it is the same argument
    /// `assignStatusMessage` makes for itself above. A future site that schedules its
    /// own clear would reintroduce the bug in full, and there would be nothing to stop
    /// it -- here there is no reason to write one.
    func presentStatusMessage(_ message: String, reason: String, timeoutReason: String) {
        assignStatusMessage(message, reason: reason)
        let token = messageLifetime.current
        DispatchQueue.main.asyncAfter(deadline: .now() + StatusMessageLifetime.displayDuration) { [weak self] in
            guard let self, self.messageLifetime.mayClear(token) else { return }
            self.assignStatusMessage(nil, reason: timeoutReason)
        }
    }

    /// Record a message assignment or its end. Called only from `statusMessage`'s
    /// observer, so every write reaches it.
    ///
    /// A message replacing another emits both lines, so `set` and `cleared` always
    /// pair up and a reader can bracket each message's life without inference.
    func logStatusMessageTransition(from oldValue: String?) {
        let reason = statusMessageReason
        if oldValue != nil {
            PersistentLog.log(.dictationMessageCleared(
                reason: statusMessage == nil ? reason : "replaced",
                displayedCount: statusMessageDisplayCount
            ))
        }
        statusMessageDisplayCount = 0
        guard statusMessage != nil else { return }
        PersistentLog.log(.dictationMessageSet(
            reason: reason,
            owner: activeControllerID ?? "none",
            visible: isKeyboardVisible
        ))
    }

    /// Called by the toolbar when the message enters the view hierarchy.
    ///
    /// This is the line that answers "was the user told". Compare its `rootView` and
    /// `controller` against `owner`: a view that rendered the message while it did not
    /// own the keyboard area drew into a tree nobody was looking at, which is the
    /// maintainer's hypothesis stated as a grep.
    func noteStatusMessageDisplayed(rootView: String, controller: String) {
        statusMessageDisplayCount += 1
        PersistentLog.log(.dictationMessageDisplayed(
            rootView: rootView,
            controller: controller,
            owner: activeControllerID ?? "none",
            visible: isKeyboardVisible
        ))
    }

    /// Called by the toolbar when the message leaves the view hierarchy.
    ///
    /// Fine grain, so a probe rather than an event: this fires when the message is
    /// cleared and also when the toolbar itself goes away (a controller torn down, or
    /// the recording overlay taking the area), and the surrounding lines are what
    /// tell those apart.
    func noteStatusMessageHidden(rootView: String, controller: String) {
        logProbe(
            "statusMessageHidden",
            details: "rootView=\(rootView) controllerID=\(controller) owner=\(activeControllerID ?? "none") visible=\(isKeyboardVisible)"
        )
    }
}

// MARK: - The stage the overlay draws (#309)

/// Keeps `displayedDictationStatus` in step with `dictationStatus`, with a floor
/// under how briefly `.transcribing` may be shown.
///
/// WHY the hold is owned here and not by `KeyboardRootView`: iOS keeps around nine of
/// those alive at once (#255, #281). One timer per view would be nine timers racing on
/// one transition, and the eight views that do not own the keyboard area draw nothing
/// anyway. One per process, in the object that already owns the status, is also what
/// makes a single derived value feed both the label and the animation -- split them and
/// the transcription sine ends up under a "Traitement..." label for the length of a
/// hold, which is a worse artefact than the flash this removes.
///
/// WHY a keyboard rebuilt mid-hold is right to show `.processing` at once: the new
/// process starts at `.idle` and reads `.processing` from the App Group, having never
/// drawn `.transcribing`. There is no flash to suppress, because the stage that would
/// have flashed was never on screen. Do not "fix" this by carrying the hold across the
/// App Group -- nothing here ever synthesises a stage.
extension KeyboardState {

    /// Move `displayedDictationStatus` toward `status`, honouring the floor.
    ///
    /// Called from `dictationStatus`'s observer, which is the only path every writer
    /// goes through -- the same funnel argument the area mode and the status message
    /// rest on.
    func advanceDisplayedStatus(to status: DictationStatus) {
        switch transcribingHold.apply(status, now: Date()) {
        case .unchanged:
            break
        case .draw(let drawn):
            cancelTranscribingHoldTimer()
            displayedDictationStatus = drawn
        case .hold(let held, let interval):
            cancelTranscribingHoldTimer()
            logProbe(
                "transcribingHoldArmed",
                details: "pending=\(held.rawValue) holdMs=\(Int(interval * 1000))"
            )
            transcribingHoldTimer = Timer.scheduledTimer(
                withTimeInterval: interval,
                repeats: false
            ) { [weak self] _ in
                self?.releaseTranscribingHold()
            }
        }
    }

    /// The floor has elapsed. Draws whatever was waiting, and nothing at all when a
    /// terminal status preempted it in the meantime.
    func releaseTranscribingHold() {
        transcribingHoldTimer = nil
        guard case .draw(let drawn) = transcribingHold.release(now: Date()) else { return }
        logProbe("transcribingHoldReleased", details: "drawn=\(drawn.rawValue)")
        displayedDictationStatus = drawn
    }

    func cancelTranscribingHoldTimer() {
        transcribingHoldTimer?.invalidate()
        transcribingHoldTimer = nil
    }
}
