// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import Combine
import DictusCore

/// VoiceOver activation is a toggle, independent of physical touch-down/up.
private final class DictationMicButton: UIButton {
    var onAccessibilityActivate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?() ?? false
    }
}

class KeyboardViewController: UIInputViewController,
    LongPressCursorMovementDelegate,
    GiellaKeyboardViewDelegate {
    let controllerID = String(UUID().uuidString.prefix(8))

    private var hostingController: UIHostingController<KeyboardRootView>?
    private var actionControlsView: UIView?
    private var atButton: UIButton?
    private var emojiButton: UIButton?
    private var numberButton: UIButton?
    private var deleteButton: UIButton?
    private var returnButton: UIButton?
    private var dismissButton: UIButton?
    private var letterModeButton: UIButton?
    private var micButton: UIButton?
    private var spaceButton: UIButton?
    private var spaceCursorController: LongPressCursorMovementController?
    private var giellaKeyboard: GiellaKeyboardView?
    private var giellaLayoutType: LayoutType?
    private var giellaAccessoryOrder: KeyboardAccessoryOrder?
    private var giellaLeadingConstraint: NSLayoutConstraint?
    private var giellaTrailingConstraint: NSLayoutConstraint?
    private var giellaTopConstraint: NSLayoutConstraint?
    private var giellaBottomConstraint: NSLayoutConstraint?
    private var lastShiftTapDate = Date.distantPast
    private var deleteRepeatTimer: Timer?
    private var deleteHoldRecognizer: UILongPressGestureRecognizer?
    private var areaModeCancellable: AnyCancellable?

    private struct ThemeCacheKey: Equatable {
        let style: UIUserInterfaceStyle
        let idiom: UIUserInterfaceIdiom
        let isLandscape: Bool
        let isPad: Bool
    }

    private var lastThemeCacheKey: ThemeCacheKey?
    private var lastLayoutSize: CGSize?
    private var lastLayoutHeight: CGFloat?
    private var lastLayoutMode: KeyboardAreaMode?
    private var lastLayoutAccessoryOrder: KeyboardAccessoryOrder?

    private final class PassthroughControlsView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0 && subview.isUserInteractionEnabled {
                let localPoint = subview.convert(point, from: self)
                if let hit = subview.hitTest(localPoint, with: event) {
                    return hit
                }
            }
            return nil
        }
    }

    /// Explicit height constraint on inputView to prevent layout issues after app switch.
    /// WHY: Without this, iOS may not recalculate the keyboard height correctly when the
    /// extension is brought back to foreground after a URL scheme app switch. The system
    /// keyboard row bleeds through and the recording overlay gets compressed.
    private var heightConstraint: NSLayoutConstraint?

    private var previousInputViewHeight: Double?
    private var stableInputViewHeightPasses = 0

    /// Height constraint for the SwiftUI hosting view (toolbar + recording overlay).
    /// The voice surface uses the native input height scaled by `surfaceHeightScale`.
    private var hostingHeightConstraint: NSLayoutConstraint?

    /// Layout ownership: SwiftUI owns symbol/emoji content; UIKit owns the
    /// voice-page hit controls and their bottom anchor.
    private var hostingBottomToKeyboardTop: NSLayoutConstraint?

    /// Explicit full-surface anchor used by mode transitions.
    private var hostingBottomToInputBottom: NSLayoutConstraint?

    /// Whether viewWillAppear has fired at least once. Guards the Combine handler
    /// from changing hosting height before the controller is registered with KeyboardState.
    /// WHY: During cold start, the Combine subscription fires in viewDidLoad with a
    /// `.recording` mode, but SwiftUI still presents `.keys` (activeControllerID doesn't
    /// match). Expanding the hosting view at this point shows the toolbar in a full-height
    /// area, displacing it to the middle of the screen.
    private var hasAppeared = false

    /// Whether iOS currently has us on screen: set in viewWillAppear, cleared in
    /// viewDidDisappear. Unlike `hasAppeared`, which latches, this tracks the
    /// present tense.
    ///
    /// Half of the liveness test for claiming an ownerless keyboard area (#260);
    /// `isOnScreen` below is the other half and the one that carries the weight.
    private var isAttached = false

    /// Whether our view hierarchy is actually in a window right now.
    ///
    /// This is the test that decides whether we may claim an ownerless keyboard
    /// area (#260), and it is deliberately fail-closed. Every controller that can
    /// reach a claim has appeared, had its ownership overwritten by a later
    /// appearance, and not been told it disappeared — which describes the live
    /// keyboard whose ownership a dying instance took with it, and equally the
    /// cached instances iOS never notifies (#128). `isAttached` cannot tell them
    /// apart, because it is only written in `viewWillAppear` and
    /// `viewDidDisappear` and a stale controller never gets the latter. Window
    /// attachment can: detaching is what removes the view from the window.
    ///
    /// If this were permissive, a stale controller would *acquire* the area rather
    /// than merely be skipped — it would expand its own hosting to full height
    /// while the on-screen tree still rendered the keys, and lock the live
    /// controller out, since a claim is single-shot. That is the #116 shape, and
    /// strictly worse than the bug being fixed. If it is instead too strict — if
    /// iOS keeps no window on the controller we think is showing — the claim never
    /// fires and behaviour is exactly what it was before #260. `hasWindow=` is
    /// logged on every attempt so a device log settles which it is.
    ///
    /// Both `view` and `inputView` are checked because this controller assigns its
    /// own `inputView`, and either may be the one iOS parents into the keyboard
    /// window. `viewIfLoaded` rather than `view`: asking for the view would load
    /// it, and a controller whose view was never loaded is not on screen anyway.
    /// The two halves are named in `KeyboardLifecycleProbe`'s
    /// `UIInputViewController` extension so the probes that report them cannot
    /// drift from the predicate that acts on them; this line is the only place
    /// they are composed.
    private var isOnScreen: Bool {
        isViewInWindow || isInputViewInWindow
    }

    /// Whether this instance was counted into `KeyboardLifecycleProbe`'s live
    /// census, so `deinit` decrements exactly once and only for instances that
    /// incremented. `deinit` runs for every instance, `viewDidLoad` only for those
    /// whose view is loaded, and an uncounted decrement would drift `live=` — the
    /// one number the next #281 capture is meant to be readable from. No such
    /// instance appears in any of the four device logs analysed (52 controllers,
    /// zero deinits without a viewDidLoad), so this guards a case that is possible
    /// rather than one that is observed.
    private var didCountIntoLiveCensus = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.layer.backgroundColor = UIColor.clear.cgColor
        // The extension owns dictation through its centered press-and-hold control.
        // Prevent iOS from adding a second system microphone key below our surface.
        hasDictationKey = true
        publishFullAccessHandshake()
        PersistentLog.source = "KBD"
        let memEntry = MemoryFootprint.residentMB()
        // live= is the #281 headline probe: healthy cold starts peak at 2 live
        // controllers, both #281 occurrences peak at 3. See KeyboardLifecycleProbe.
        didCountIntoLiveCensus = true
        let liveOnLoad = KeyboardLifecycleProbe.controllerDidLoad()
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidLoad",
            details: "controllerClass=\(String(describing: type(of: self))) memMB=\(memEntry) live=\(liveOnLoad)"
        ))

        #if DEBUG
        let result = AppGroupDiagnostic.run()
        if #available(iOS 14.0, *) {
            DictusLogger.keyboard.debug(
                "Diagnostic: canWrite=\(result.canWrite, privacy: .public) canRead=\(result.canRead, privacy: .public)"
            )
        }
        #endif

        // Create a KeyboardInputView (UIInputView + UIInputViewAudioFeedback)
        // and assign it as the controller's inputView. This is the critical step
        // that makes playInputClick() work: iOS checks that the UIInputViewController's
        // inputView conforms to UIInputViewAudioFeedback and returns true from
        // enableInputClicksWhenVisible. Without this assignment, click sounds are silent.
        let kbInputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        // Do NOT set translatesAutoresizingMaskIntoConstraints = false on the inputView.
        // iOS manages the inputView's frame via autoresizing masks -- disabling them
        // causes the view to collapse to zero width.
        // Reassert this after UIKit has constructed the keyboard-style input view;
        // otherwise the style can leave an opaque rectangular layer behind the
        // inset SwiftUI surface.
        kbInputView.isOpaque = false
        kbInputView.layer.backgroundColor = UIColor.clear.cgColor

        // KeyboardInputView owns the single semantic native backdrop.

        // --- 2. Create SwiftUI hosting for the voice surface ---
        // Pass weak callbacks rather than the controller itself. This keeps the
        // SwiftUI root owned by hosting without making a stale controller the
        // routing authority after iOS rebuilds the keyboard.
        let rootView = KeyboardRootView(
            controllerID: controllerID,
            routeText: { [weak self] text in self?.routeProxyText(text) },
            routeCommand: { [weak self] command in self?.routeProxyCommand(command) },
            routeCursorMovement: { [weak self] movement in self?.didMoveCursor(movement) }
        )
        let hosting = UIHostingController(rootView: rootView)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "hostingCreated",
            details: "hosting=\(ObjectIdentifier(hosting).debugDescription)"
        ))

        // Critical: retain the hosting controller or it gets deallocated
        self.hostingController = hosting

        // Disable safe area regions so SwiftUI content uses the full hosting bounds.
        // WHY: Keyboard extensions can have unexpected safe area insets from the system.
        // Note: Do NOT set layoutMargins/directionalLayoutMargins to zero — this
        // triggers layout recalculation that causes the keyboard height to shrink
        // when top-row key popups extend above bounds.
        if #available(iOS 16.4, *) {
            hosting.safeAreaRegions = []
        }

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        hosting.view.isOpaque = false
        hosting.view.layer.backgroundColor = UIColor.clear.cgColor
        // Hide hosting view until viewWillAppear has applied the correct state.
        // During cold start, there's a gap between viewDidLoad (hosting created with
        // toolbar content) and viewWillAppear (constraint + SwiftUI state synchronized).
        // Without this, the toolbar briefly renders in an expanded hosting view,
        // displacing FR/mic to the middle of the screen.
        hosting.view.isHidden = true

        // The voice surface owns the entire input view.
        kbInputView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        installLetterKeyboard(in: kbInputView)
        installVoiceActionControls(in: kbInputView)

        // --- 5. Set up Auto Layout constraints ---
        // Use the device-aware native height from the first layout pass rather
        // than making the hosting view start at a fixed 216pt height. UIKit can
        // still refine the input view's bounds after attachment, and the live
        // recalculation below remains authoritative.
        let initialHeight = computeKeyboardHeight(for: KeyboardState.shared.areaMode)
        let hostingHeight = hosting.view.heightAnchor.constraint(equalToConstant: initialHeight)
        // Priority 999 (just below .required): ensures our explicit height always wins over
        // UIHostingController's intrinsic content size (compression resistance = 750).
        // At .defaultHigh (750), the constraint was ambiguous with SwiftUI's own sizing,
        // causing the hosting view to get stuck at wrong heights after recording overlay dismiss.
        hostingHeight.priority = UILayoutPriority(999)
        self.hostingHeightConstraint = hostingHeight

        // Prevent SwiftUI content from fighting the height constraint.
        // WHY: UIHostingController sets compression resistance at .defaultHigh (750).
        // When content switches between the voice toolbar and recording surface,
        // the stale intrinsic size can compete with our constraint at equal priority.
        // NOTE: Only lower compression resistance, NOT content hugging — the hosting view
        // must be able to EXPAND to full height during recording overlay.
        hosting.view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let hostingBottomIdle = hosting.view.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor)
        let hostingBottomExpanded = hosting.view.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor)
        hostingBottomIdle.isActive = true
        hostingBottomExpanded.isActive = false
        self.hostingBottomToKeyboardTop = hostingBottomIdle
        self.hostingBottomToInputBottom = hostingBottomExpanded

        NSLayoutConstraint.activate([
            // Voice surface hosting — bottom anchor swapped at runtime
            // (see hostingBottomToKeyboardTop / hostingBottomToInputBottom)
            hosting.view.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
            hostingHeight
        ])

        // --- 6. Defer the height constraint to viewDidLayoutSubviews first run ---
        // #92: installing this constraint in viewDidLoad fights iOS's
        // priority-1000 UIView-Encapsulated-Layout-Height during the entry
        // animation, producing a visible "keyboard grows then shrinks"
        // transient (956 → 504 → 276 over ~150ms).
        //
        // Upstream giellakbd-ios installs its height constraint in
        // viewDidLayoutSubviews first run, dispatched async to the main queue,
        // with the comment: "If this is removed, iPhone 5s glitches before
        // finding the correct height." Adding the constraint AFTER iOS has
        // completed its initial layout pass lets our 999-priority constraint
        // win without fighting the encapsulated-layout-height directly.
        //
        // Constraint creation moved to installInputViewHeightConstraint().

        // Attempt to prevent top-row key popup clipping. iOS may re-enforce
        // clipsToBounds -- if so, this is a known limitation of third-party keyboard extensions.
        kbInputView.clipsToBounds = false
        hosting.view.clipsToBounds = false

        // Assign as the controller's inputView -- this activates audio feedback
        self.inputView = kbInputView
        hostingHeightConstraint?.constant = computeKeyboardHeight(for: KeyboardState.shared.areaMode)
        hostingBottomToKeyboardTop?.isActive = false
        hostingBottomToInputBottom?.isActive = true

        // Memory after all viewDidLoad allocations.
        let memExit = MemoryFootprint.residentMB()
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidLoad_exit",
            details: "memMB=\(memExit) delta=\(memExit - memEntry)"
        ))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        publishFullAccessHandshake()

        // CRITICAL: Disable touch delay on system gesture recognizers.
        // iOS attaches gesture recognizers to the keyboard's UIWindow that have
        // delaysTouchesBegan=true (for system gesture disambiguation at screen edges).
        // This causes edge key touches to be delayed ~100ms, making haptic/popup fire
        // on touchUp instead of touchDown, and long-press accent to fail on outer edges.
        // The original giellakbd-ios uses this exact same technique.
        disableWindowGestureDelay()

        // Issue #116 diagnostic: snapshot state at entry BEFORE any mutation.
        let entryStatus = KeyboardState.shared.dictationStatus.rawValue
        let entryStoredStatus = AppGroup.defaults.string(forKey: SharedKeys.dictationStatus) ?? "nil"
        let entryColdStart = AppGroup.defaults.bool(forKey: SharedKeys.coldStartActive)
        let entryBounds = inputView?.bounds.size ?? .zero
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewWillAppear_entry",
            details: "animated=\(animated) status=\(entryStatus) storedStatus=\(entryStoredStatus) coldStart=\(entryColdStart) inputBounds=\(Int(entryBounds.width))x\(Int(entryBounds.height)) hostingConst=\(hostingHeightConstraint?.constant ?? -1) heightConst=\(heightConstraint?.constant ?? -1) memMB=\(MemoryFootprint.residentMB())"
        ))
        PersistentLog.log(.keyboardDidAppear)
        KeyboardState.shared.registerControllerAppearance(controllerID: controllerID)
        // Point KeyboardState's weak controller ref at the currently-visible controller
        // so call sites in KeyboardRootView and KeyboardState can access textDocumentProxy.
        // Previously set from KeyboardRootView.onAppear, which held a strong ref → #134.
        KeyboardState.shared.controller = self
        // Model readiness and the app scene phase can change while this cached
        // keyboard controller is off-screen. Refresh before laying out the mic
        // action so the button does not keep a stale "Open sAiity" state.
        KeyboardState.shared.refreshFromDefaults()
        hasAppeared = true
        isAttached = true
        updateActionAvailability()
        refreshLetterKeyboardIfNeeded()
        giellaKeyboard?.page = .normal

        // Opening the keyboard always returns to the dictation board.
        if !KeyboardState.shared.dictationStatus.ownsKeyboardArea {
            KeyboardState.shared.closeArea()
        }

        // (Re)subscribe to the keyboard area mode here, not in viewDidLoad.
        // WHY: iOS caches UIInputViewController instances across app-switches and
        // rarely deallocates them, so stale controllers would keep mutating
        // hostingHeightConstraint on every mode change (issue #128). By subscribing
        // in viewWillAppear and cancelling in viewDidDisappear, only the currently
        // visible controller is reactive. Assignment is idempotent — the previous
        // AnyCancellable is released on reassignment, which cancels its subscription.
        observeKeyboardAreaMode()

        // Force height recalculation when keyboard reappears (e.g., after app switch).
        // Without this, the inputView may retain a stale height from before the switch.
        let oldHeight = heightConstraint?.constant ?? -1
        let newHeight = computeKeyboardHeight(for: KeyboardState.shared.areaMode)
        hostingHeightConstraint?.constant = newHeight
        heightConstraint?.constant = newHeight
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "heightRecalc_viewWillAppear",
            details: "old=\(oldHeight) new=\(newHeight) hSizeClass=\(traitCollection.horizontalSizeClass.rawValue) vSizeClass=\(traitCollection.verticalSizeClass.rawValue)"
        ))

        // Apply the current keyboard area mode now that we're registered.
        // During cold start, applyAreaMode was skipped (hasAppeared was false).
        // Registration precedes the geometry update so the constraint and SwiftUI
        // content change together.
        let statusBeforeHandle = KeyboardState.shared.dictationStatus.rawValue

        applyAreaMode(KeyboardState.shared.areaMode)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewWillAppear_afterHandle",
            details: "statusBefore=\(statusBeforeHandle) statusAfter=\(KeyboardState.shared.dictationStatus.rawValue) mode=\(KeyboardState.shared.areaMode.rawValue) hostingConst=\(hostingHeightConstraint?.constant ?? -1)"
        ))

        // Show hosting view now that constraints and SwiftUI state are synchronized.
        // Was hidden in viewDidLoad to prevent cold start flash (toolbar in full-height hosting).
        hostingController?.view.isHidden = false

        // Force synchronous layout AFTER unhiding (#99). During cold start, the status
        // can transition .recording → .idle between handleDictationStatusChange and this
        // unhide. The constraint is updated but the visual frame is stale without this.
        inputView?.layoutIfNeeded()

        // Set initial shift state based on the text field's autocapitalization setting.
        // WHY here and not viewDidLoad: The textDocumentProxy is not fully connected
        // until the view is about to appear. Calling in viewDidLoad would read stale data.

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "registeredAppearance",
            details: ""
        ))

        // Cold start return detection: log for diagnostics.
        // DON'T clear coldStartActive here -- KeyboardState.refreshFromDefaults() reads it
        // to activate the watchdog grace period (15s instead of 5s). The app's .background
        // handler clears it when the transition is complete.
        if AppGroup.defaults.bool(forKey: SharedKeys.coldStartActive) {
            DictusLogger.keyboard.info("Keyboard returned from cold start, recording should be active")
        }

        #if DEBUG
        if #available(iOS 14.0, *) {
            DictusLogger.keyboard.debug("viewWillAppear -- refreshing mode")
        }
        #endif
    }

    private func publishFullAccessHandshake() {
        // The app cannot inspect iOS' Full Access toggle. The extension can,
        // so publish this real handshake as early and repeatedly as iOS loads it.
        AppGroup.defaults.set(hasFullAccess, forKey: SharedKeys.onboardingFullAccessVerified)
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.onboardingFullAccessHandshakeDate)
        AppGroup.defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardFullAccessChanged)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Issue #116 diagnostic: snapshot final frames after layout settles.
        // We log both sizes and constraint constants so we can detect priority mismatches
        // where iOS imposed a different height than we asked for.
        logLayoutSnapshot(action: "viewDidAppear_settled")

        // #281: record which text field we settled into. Emitted here rather than
        // from viewWillAppear because reading the proxy costs a synchronous round
        // trip to the host app, and viewWillAppear is the timing-sensitive path the
        // failure sits on. Both #281 captures show every doomed controller reaching
        // viewDidAppear, so this loses no occurrence. One line per controller.
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "inputContext_settled",
            details: "\(inputContextProbeDetails) live=\(KeyboardLifecycleProbe.liveCount)"
        ))

        // Issue #129 investigation: viewDidAppear fires BEFORE iOS finishes the
        // keyboard entry animation, so bounds captured here may still be
        // transient. Schedule deferred snapshots to confirm whether 504pt is
        // actually the final, user-visible size — or just a mid-animation value
        // that iOS later resolves to our requested 276pt constraint.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.logLayoutSnapshot(action: "layoutSnapshot_500ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.logLayoutSnapshot(action: "layoutSnapshot_1000ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.logLayoutSnapshot(action: "layoutSnapshot_2000ms")
        }
    }

    /// First-run flag for viewDidLayoutSubviews. Used by upstream
    /// giellakbd-ios pattern (#92): install the input view height constraint
    /// after iOS finishes its initial layout pass, not in viewDidLoad.
    private var isFirstLayoutPass = true

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let liveHeight = computeKeyboardHeight(for: KeyboardState.shared.areaMode)
        let mode = KeyboardState.shared.areaMode
        let size = inputView?.bounds.size ?? .zero
        let needsSurfaceLayout = lastLayoutSize != size
            || lastLayoutHeight != liveHeight
            || lastLayoutMode != mode
            || lastLayoutAccessoryOrder != KeyboardAccessoryOrder.current
        if needsSurfaceLayout {
            hostingHeightConstraint?.constant = liveHeight
            heightConstraint?.constant = liveHeight
            layoutVoiceActionControls(surfaceHeight: liveHeight)
            layoutLetterKeyboard(surfaceHeight: liveHeight)
            lastLayoutSize = size
            lastLayoutHeight = liveHeight
            lastLayoutMode = mode
            lastLayoutAccessoryOrder = KeyboardAccessoryOrder.current
        }
        if isFirstLayoutPass {
            isFirstLayoutPass = false
            // Defer constraint installation to the next runloop turn so we
            // don't mutate constraints inside iOS's own layout pass. Upstream
            // comment: "If this is removed, iPhone 5s glitches before finding
            // the correct height."
            DispatchQueue.main.async { [weak self] in
                self?.installInputViewHeightConstraint()
            }
        }
    }

    /// Installs the 999-priority height constraint on kbInputView. Called once
    /// (lazy) from the first viewDidLayoutSubviews via async dispatch. Adding
    /// the constraint here, AFTER iOS has completed its initial layout pass,
    /// lets us win against the encapsulated-layout-height (priority 1000)
    /// without the entry animation flashing at 504pt.
    private func installInputViewHeightConstraint() {
        guard heightConstraint == nil, let kbInputView = inputView else { return }
        let height = computeKeyboardHeight(for: KeyboardState.shared.areaMode)
        let constraint = kbInputView.heightAnchor.constraint(equalToConstant: height)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        self.heightConstraint = constraint
    }

    /// Swap hosting view's bottom anchor between idle and expanded positions.
    /// - Idle: hosting fills the scaled voice surface.
    /// - Expanded: hosting.bottom = kbInputView.bottom (fills the full
    ///   keyboard area, used when the recording overlay or emoji picker is
    ///   shown and the keyboard view is hidden).
    ///
    /// Without this swap, expanding the hosting height alone (with the idle
    /// bottom anchor still active) pushes hosting.top above kbInputView,
    /// leaving the overlay stuck off-screen — the bug in #92 follow-up.
    private func setHostingExpanded(_ expanded: Bool) {
        if expanded {
            hostingBottomToKeyboardTop?.isActive = false
            hostingBottomToInputBottom?.isActive = true
        } else {
            hostingBottomToInputBottom?.isActive = false
            hostingBottomToKeyboardTop?.isActive = true
        }
    }

    /// Emits the same layout snapshot we log in `viewDidAppear_settled`,
    /// reusable from deferred blocks to compare mid- vs post-animation sizes.
    ///
    /// It also carries the #260 claim predicate. That issue turns on one boolean —
    /// is `isOnScreen` true for the controller iOS is actually showing? — and the
    /// only path that answers it in code, `claimedOwnerlessArea`, needs the rare
    /// ownership race to fire before it logs anything. This line does not: it runs
    /// four times per controller on every recording, so an ordinary dictation
    /// settles the question with no race to reproduce. `onScreen=` is the predicate
    /// itself, read through `isOnScreen`; `hasWindow=` / `hasInputWindow=` say which
    /// of the two attachments iOS kept, which is what a redesign would need if the
    /// answer turns out to be `false`.
    private func logLayoutSnapshot(action: String) {
        let inputBounds = inputView?.bounds.size ?? .zero
        let hostingFrame = hostingController?.view.frame.size ?? .zero
        let viewBounds = view.bounds.size
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: action,
            details: "inputBounds=\(Int(inputBounds.width))x\(Int(inputBounds.height)) viewBounds=\(Int(viewBounds.width))x\(Int(viewBounds.height)) hostingFrame=\(Int(hostingFrame.width))x\(Int(hostingFrame.height)) hostingConst=\(hostingHeightConstraint?.constant ?? -1) heightConst=\(heightConstraint?.constant ?? -1) status=\(KeyboardState.shared.dictationStatus.rawValue) mode=\(KeyboardState.shared.areaMode.rawValue) onScreen=\(isOnScreen) \(windowAttachmentProbeDetails) memMB=\(MemoryFootprint.residentMB())"
        ))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil

        // We are off screen from here on, whether or not we keep ownership below
        // (#260): a detached controller must not adopt an ownerless dictation.
        isAttached = false

        // Restore system gesture recognizer delay (be a good citizen)
        restoreWindowGestureDelay()

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidDisappear",
            details: "animated=\(animated) memMB=\(MemoryFootprint.residentMB())"
                + " live=\(KeyboardLifecycleProbe.liveCount)"
                + " \(dismissalProbeDetails) \(inputContextProbeDetails)"
                // #281: whether DictusApp had already backgrounded when iOS tore
                // this controller down. The log's one-second resolution and its
                // interleaving of two processes make that ordering unrecoverable by
                // comparing timestamps, and it is the one thing the surviving
                // hypothesis — the swipe-back landing before iOS rotates in a
                // successor — needs to be true. Read from the App Group, so no IPC
                // round trip to the host app on a teardown path.
                + " \(AppScenePhaseProbe.describe())"
        ))
        PersistentLog.log(.keyboardDidDisappear)

        // Tear down the area mode subscription so this (now-detached) controller
        // no longer reacts when KeyboardState publishes. iOS caches
        // UIInputViewController and rarely releases it, so without this cleanup
        // 10+ stale controllers race on hostingHeightConstraint (issue #128).
        // viewWillAppear re-subscribes on reattach.
        areaModeCancellable?.cancel()
        areaModeCancellable = nil

        // Issue #142: skip registerControllerDisappearance during an active
        // dictation session. iOS calls viewDidDisappear on the keyboard right
        // before bringing DictusApp foreground for cold-start; an immediate
        // unregister would flip activeControllerID→nil and isKeyboardVisible
        // →false while hostingConst is still
        // 276pt. iOS's keyboard-down animation snapshot then captures that
        // inconsistent layout (toolbar centred in expanded hosting), freezing
        // it on screen for the duration of the transition.
        //
        // The successor controller's registerControllerAppearance overwrites
        // activeControllerID, so a clean handoff happens automatically. If the
        // keyboard is truly dismissed during recording (no successor), the area
        // becomes ownerless when we are deallocated — see
        // registerControllerDeallocation (#260).
        let status = KeyboardState.shared.dictationStatus
        if status.ownsKeyboardArea {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "skippedUnregister_activeSession",
                details: "status=\(status.rawValue) activeID=\(KeyboardState.shared.activeControllerID ?? "none")"
            ))
        } else {
            KeyboardState.shared.registerControllerDisappearance(controllerID: controllerID)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "registeredDisappearance",
                details: ""
            ))
        }

        // Darwin observers cleaned up by KeyboardState deinit
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // iOS sends this shortly before it's willing to jetsam the extension.
        // Logging it proves whether the grey-overlay freeze correlates with
        // a memory-pressure signal iOS actually gave us vs an out-of-the-blue kill.
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "didReceiveMemoryWarning",
            details: "memMB=\(MemoryFootprint.residentMB())"
        ))
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let hadColorChange = traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection)
        if hadColorChange || previousTraitCollection == nil {
            reassertTransparentSurfaceLayers()
            refreshLetterKeyboardIfNeeded()
            lastLayoutSize = nil
        }
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "traitCollectionDidChange",
            details: "prevStyle=\(previousTraitCollection?.userInterfaceStyle.rawValue ?? -1) newStyle=\(traitCollection.userInterfaceStyle.rawValue) hadColorChange=\(hadColorChange)"
                // #281: both occurrences show the style flipping to dark (2) on a
                // device in light mode, seconds before the teardown, and 15 clean
                // cold starts show no flip at all. onScreen says whether the flip
                // lands on an attached controller or a detached one.
                //
                // Named `onScreen=` since #260 because that is what it has always
                // been — the composed predicate, not the `view`-only half that
                // `hasWindow=` denotes on every other line. Captures from builds
                // before this one spell the same value `hasWindow=` here.
                //
                // Deliberately reads no textDocumentProxy property here. This
                // callback fires before viewWillAppear — see the host-connection
                // note at the needsInputModeSwitchKey read in viewDidLoad — so there
                // is no input session yet, and that is exactly where the
                // documentIdentifier read crashed the extension on every launch.
                // Bounded at 2-3 lines per controller.
                + " onScreen=\(isOnScreen)"
        ))
    }

    deinit {
        deleteRepeatTimer?.invalidate()
        // Issue #142 safety net, corrected by #260: viewDidDisappear skips
        // unregistration during an active dictation session to avoid a SwiftUI
        // race that produces a centred-toolbar artefact during cold-start
        // handoff, so a dismissed keyboard would otherwise leave ownership
        // pointing at a deallocated controller.
        //
        // This used to unregister outright whenever we still owned the area, on
        // the assumption that "no successor has registered yet" meant "the
        // keyboard was dismissed". That assumption is false under churn: ownership
        // is last-writer-wins on appearance, so the instance holding it is often
        // not the keyboard on screen, and releasing the area on its way out left
        // the controller that *is* on screen unable to present anything — with no
        // path back, since its viewWillAppear had already run.
        //
        // The area is marked reclaimable now. Every reader still sees an ownerless,
        // invisible keyboard exactly as it did before, so nothing downstream
        // changes; what the marker adds is that a controller still in a window may
        // claim the area (see applyAreaMode).
        KeyboardState.shared.registerControllerDeallocation(controllerID: controllerID)

        // Symmetric tear-down for the addChild()/didMove(toParent:) in viewDidLoad.
        // Without this, UIKit holds the hosting controller in `children` and SwiftUI may
        // keep its observation graph alive past our own deinit, perpetuating the
        // KeyboardRootView zombies seen receiving activeControllerChanged broadcasts in
        // logs (#134).
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil

        // live=0 on this line marks the exact moment the extension has no
        // controller left, which is the start of the #281 window (#281).
        let liveAfter = didCountIntoLiveCensus
            ? KeyboardLifecycleProbe.controllerDidDeinit()
            : KeyboardLifecycleProbe.liveCount
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "deinit",
            details: "memMB=\(MemoryFootprint.residentMB()) live=\(liveAfter)"
        ))
    }

    // MARK: - Keyboard Height

    /// Match the native keyboard's device-aware input height, then apply the
    /// shared sAiity scale so the dictation board is 10% taller than stock.
    private func computeNativeKeyboardHeight() -> CGFloat {
        let deviceContext = DeviceContext.current
        let nativeHeight = KeyboardHeightProvider.height(
            for: deviceContext,
            traitCollection: traitCollection
        )
        return nativeHeight * CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeightScale)
    }

    private func computeKeyboardHeight() -> CGFloat {
        let nativeHeight = computeNativeKeyboardHeight()
        let inputViewHeight = inputView?.bounds.height ?? 0
        let resolution = VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight(
            inputViewHeight: Double(inputViewHeight),
            controllerViewHeight: view.bounds.height > 0 ? Double(view.bounds.height) : nil,
            fallbackHeight: Double(nativeHeight) * 1.10,
            previousInputViewHeight: previousInputViewHeight,
            stableInputViewPasses: stableInputViewHeightPasses
        )
        previousInputViewHeight = resolution.observedInputViewHeight
        stableInputViewHeightPasses = resolution.stableInputViewPasses
        return CGFloat(resolution.height)
    }

    /// Every mode uses the scaled device-aware keyboard height.
    private func computeKeyboardHeight(for mode: KeyboardAreaMode) -> CGFloat {
        computeKeyboardHeight()
    }

    // MARK: - Keyboard Area Mode Observation

    /// Observe KeyboardState.areaMode to keep the UIKit side of the keyboard area
    /// in step with what SwiftUI renders: hosting height, hosting bottom anchor,
    /// and the voice surface's presentation state.
    ///
    /// WHY areaModePublisher and not $dictationStatus: the mode is recomputed in
    /// `dictationStatus`'s `didSet`, which runs *after* `$dictationStatus` has
    /// already published. A sink on the status would therefore read a stale mode.
    /// The mode's own publisher carries the value we need — and it emits from
    /// `didSet`, so the synchronous layout below cannot make SwiftUI render an
    /// already-superseded mode. See the note on `KeyboardState.areaMode`.
    ///
    /// WHY Combine instead of NotificationCenter: this needs no manual
    /// notification posts — and it is precisely the NotificationCenter round-trip
    /// that #271 removed.
    private func observeKeyboardAreaMode() {
        areaModeCancellable = KeyboardState.shared.areaModePublisher
            // No .receive(on: .main) — areaMode is only ever set on the main thread
            // (Darwin observer dispatches to main, key taps are UI actions).
            // Staying synchronous ensures the constraint change lands in the same
            // turn as the mode change, BEFORE SwiftUI draws. Without this, there's a
            // 1-frame delay where the overlay renders at its full voice height
            // before the hosting view expands to full height — causing the waveform
            // to flash at the top then drop to center.
            .sink { [weak self] mode in
                self?.applyAreaMode(mode)
            }
    }

    /// React to a keyboard-area mode change: check that we are the controller
    /// allowed to touch the layout, then apply it.
    ///
    /// The probe action names below are deliberately unchanged from the
    /// status-driven handler this replaced — #260 and #261 are open and quote
    /// `dictStatusChange_enter` / `dictStatusChange_skippedInactive` from device
    /// logs. `mode=` is additive.
    private func applyAreaMode(_ mode: KeyboardAreaMode) {
        // The subscription above is deliberately synchronous — no .receive(on: .main)
        // — and this method mutates Auto Layout constraints and view visibility, so
        // an emission from a background thread would corrupt UIKit state silently.
        // WHY assert and not dispatchPrecondition: the latter also traps in release,
        // and crashing a shipped keyboard is worse than the bug it would catch.
        assert(Thread.isMainThread, "applyAreaMode must run on the main thread — it mutates UIKit layout")

        // Issue #116 diagnostic: entry log (fires even when a guard trips).
        let status = KeyboardState.shared.dictationStatus.rawValue
        let oldHosting = hostingHeightConstraint?.constant ?? -1
        let activeID = KeyboardState.shared.activeControllerID ?? "none"
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "dictStatusChange_enter",
            details: "status=\(status) mode=\(mode.rawValue) hasAppeared=\(hasAppeared) oldHosting=\(oldHosting) activeID=\(activeID)"
        ))

        // Don't change hosting height until the controller is registered with
        // KeyboardState: an unregistered controller's KeyboardRootView still
        // presents `.keys`, so expanding now would show the toolbar displaced in a
        // full-height hosting view. viewWillAppear registers, then applies the mode
        // explicitly. The subscription is also created there, and areaModePublisher
        // does not replay on subscribe, so nothing should reach this before
        // viewWillAppear — the guard stays as a cheap invariant on that ordering.
        guard hasAppeared else { return }

        // #260: a dictation can be left with no owning controller at all.
        // Ownership is last-writer-wins on appearance, so under churn an instance
        // iOS is about to throw away can hold the area, and when it is deallocated
        // the keyboard the user is looking at is left unable to present the
        // overlay — ownership is what the guard below keys on, and nothing
        // re-registers us:
        // viewWillAppear already ran.
        //
        // KeyboardState marks such an area reclaimable rather than released, so
        // the controller iOS is showing can claim it here instead of waiting for
        // iOS to build a replacement — which in the captures took 2.5 s, or four
        // seconds and a manual trip to DictusApp.
        //
        // `isOnScreen` is what keeps this from being a licence for the stale
        // controllers the guard below exists to exclude; see its declaration.
        //
        // Only for `.recording`, matching that guard: the pickers are opened by a
        // key on the visible keyboard and are not gated on ownership.
        if mode == .recording, isAttached, KeyboardState.shared.activeControllerID != controllerID {
            let onScreen = isOnScreen
            let claimed = KeyboardState.shared.claimOwnership(
                controllerID: controllerID,
                isOnScreen: onScreen
            )
            if claimed {
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyboardViewController",
                    instanceID: controllerID,
                    action: "claimedOwnerlessArea",
                    details: "status=\(status) mode=\(mode.rawValue) previousActiveID=\(activeID) hasWindow=\(onScreen)"
                ))
            }
        }

        // Defense-in-depth for #128: iOS caches UIInputViewController and does not
        // reliably fire viewDidDisappear on stale instances (observed: controllers
        // responding to Darwin status changes for minutes after losing window
        // attachment, no viewDidDisappear event logged). The subscription-cancel
        // path in viewDidDisappear covers the well-behaved case; this guard
        // short-circuits stale controllers that iOS forgot to notify.
        //
        // It applies to `.recording` only, where UIKit geometry must agree with
        // the voice-only SwiftUI surface.
        guard mode != .recording || KeyboardState.shared.activeControllerID == controllerID else {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "dictStatusChange_skippedInactive",
                details: "status=\(status) mode=\(mode.rawValue) activeID=\(activeID)"
            ))
            return
        }

        applyLayout(for: mode)
    }

    /// The keyboard area's layout, one branch per mode.
    ///
    /// Every case sets all three things explicitly — hosting height, hosting
    /// bottom anchor — with no fallthrough. Before #271 this
    /// was a chain of negated guards where restoring the collapsed toolbar height
    /// was conditional on the emoji flag being false, so a full-area state that
    /// was not added to the chain collapsed while still rendering.
    ///
    /// Each branch applies one resolved live height to both UIKit and SwiftUI.
    private func applyLayout(for mode: KeyboardAreaMode) {
        let oldHosting = hostingHeightConstraint?.constant ?? -1
        let status = KeyboardState.shared.dictationStatus.rawValue
        let liveHeight = computeKeyboardHeight(for: mode)
        setVoiceActionControlsHidden(mode == .panel || mode == .emoji)
        // The letter page is SwiftUI-owned. Keep the vendored renderer installed
        // for layout compatibility, but never let it compete for touches or pixels.
        giellaKeyboard?.isHidden = true

        switch mode {
        case .keys:
            heightConstraint?.constant = liveHeight
            hostingHeightConstraint?.constant = liveHeight
            setHostingExpanded(true)
            hostingController?.view.isHidden = false
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_idle",
                details: "old=\(oldHosting) new=\(liveHeight) status=\(status) mode=\(mode.rawValue)"
            ))

        case .letters:
            heightConstraint?.constant = liveHeight
            hostingHeightConstraint?.constant = liveHeight
            setHostingExpanded(true)
            hostingController?.view.isHidden = false
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_letters",
                details: "old=\(oldHosting) new=\(liveHeight) status=\(status) mode=\(mode.rawValue)"
            ))

        case .emoji:
            heightConstraint?.constant = liveHeight
            hostingHeightConstraint?.constant = liveHeight
            setHostingExpanded(true)
            hostingController?.view.isHidden = false
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_emoji",
                details: "old=\(oldHosting) new=\(liveHeight) status=\(status) mode=emoji"
            ))

        case .panel:
            heightConstraint?.constant = liveHeight
            hostingHeightConstraint?.constant = liveHeight
            setHostingExpanded(true)
            hostingController?.view.isHidden = false
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "numberLayerShown",
                details: "page=symbols1 status=\(status) mode=\(mode.rawValue)"
            ))

        case .recording:
            heightConstraint?.constant = liveHeight
            hostingHeightConstraint?.constant = liveHeight
            setHostingExpanded(true)
            hostingController?.view.isHidden = false
            setVoiceActionControlsHidden(false)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_recording",
                details: "old=\(oldHosting) new=\(liveHeight) status=\(status) mode=\(mode.rawValue)"
            ))
        }

        // Mode changes happen outside viewDidLayoutSubviews. Refresh the action
        // hit areas immediately so the visible surface and UIKit controls switch
        // together before the next render pass.
        layoutVoiceActionControls()
        inputView?.setNeedsLayout()
        inputView?.layoutIfNeeded()
    }

    // MARK: - UIKit action controls

    /// The letter grid is UIKit-owned so key hit testing, long-press variants and
    /// cursor movement stay on the same low-latency path as the vendored keyboard.
    private func installLetterKeyboard(in inputView: UIView) {
        let theme = Theme.current(for: traitCollection)
        let keyboard = GiellaKeyboardView(
            definition: KeyboardLayouts.current(),
            theme: theme
        )
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.delegate = self
        keyboard.isHidden = true
        inputView.addSubview(keyboard)

        let leading = keyboard.leadingAnchor.constraint(equalTo: inputView.leadingAnchor)
        let trailing = keyboard.trailingAnchor.constraint(equalTo: inputView.trailingAnchor)
        let top = keyboard.topAnchor.constraint(equalTo: inputView.topAnchor)
        let bottom = keyboard.bottomAnchor.constraint(equalTo: inputView.bottomAnchor)
        NSLayoutConstraint.activate([leading, trailing, top, bottom])

        giellaKeyboard = keyboard
        giellaLayoutType = LayoutType.active
        giellaAccessoryOrder = KeyboardAccessoryOrder.current
        giellaLeadingConstraint = leading
        giellaTrailingConstraint = trailing
        giellaTopConstraint = top
        giellaBottomConstraint = bottom
        lastThemeCacheKey = currentThemeCacheKey()
    }

    private func refreshLetterKeyboardIfNeeded() {
        guard let inputView else { return }
        let requestedLayout = LayoutType.active
        let requestedAccessoryOrder = KeyboardAccessoryOrder.current
        let themeKey = currentThemeCacheKey()
        guard giellaLayoutType != requestedLayout || giellaAccessoryOrder != requestedAccessoryOrder else {
            if lastThemeCacheKey != themeKey {
                giellaKeyboard?.updateTheme(theme: Theme.current(for: traitCollection))
                lastThemeCacheKey = themeKey
            }
            return
        }

        giellaKeyboard?.delegate = nil
        giellaKeyboard?.removeFromSuperview()
        [giellaLeadingConstraint, giellaTrailingConstraint, giellaTopConstraint, giellaBottomConstraint]
            .compactMap { $0 }
            .forEach { $0.isActive = false }
        giellaKeyboard = nil
        installLetterKeyboard(in: inputView)
        layoutLetterKeyboard()
    }

    private func currentThemeCacheKey() -> ThemeCacheKey {
        let device = DeviceContext.current
        return ThemeCacheKey(
            style: traitCollection.userInterfaceStyle,
            idiom: traitCollection.userInterfaceIdiom,
            isLandscape: device.isLandscape,
            isPad: device.isPad
        )
    }

    private func layoutLetterKeyboard(surfaceHeight: CGFloat? = nil) {
        guard let inputView,
              let keyboard = giellaKeyboard,
              inputView.bounds.width > 0 else { return }
        let resolvedHeight = surfaceHeight ?? computeKeyboardHeight(for: KeyboardState.shared.areaMode)
        let layout = VoiceOnlyKeyboardPolicy.layout(
            for: Double(inputView.bounds.width),
            surfaceHeight: Double(max(1, resolvedHeight)),
            controlOrder: KeyboardAccessoryOrder.current
        )
        let frame = layout.letterKeyboardFrame
        guard !frame.isEmpty else {
            keyboard.isHidden = true
            return
        }
        giellaLeadingConstraint?.constant = frame.minX
        giellaTrailingConstraint?.constant = -(inputView.bounds.width - frame.maxX)
        giellaTopConstraint?.constant = frame.minY
        giellaBottomConstraint?.constant = -(resolvedHeight - frame.maxY)
        keyboard.isHidden = true
    }

    private func reassertTransparentSurfaceLayers() {
        view.backgroundColor = .clear
        view.isOpaque = false
        view.layer.backgroundColor = UIColor.clear.cgColor
        hostingController?.view.backgroundColor = .clear
        hostingController?.view.isOpaque = false
        hostingController?.view.layer.backgroundColor = UIColor.clear.cgColor
        actionControlsView?.backgroundColor = .clear
        actionControlsView?.isOpaque = false
        actionControlsView?.layer.backgroundColor = UIColor.clear.cgColor
        giellaKeyboard?.backgroundColor = .clear
        giellaKeyboard?.isOpaque = false
    }

    /// Transparent UIKit controls sit over the SwiftUI glyphs. UIKit owns the
    /// action and pressed state; SwiftUI only renders the visual surface.
    private func installVoiceActionControls(in inputView: UIView) {
        let controls = PassthroughControlsView(frame: inputView.bounds)
        controls.backgroundColor = .clear
        controls.isOpaque = false
        controls.layer.backgroundColor = UIColor.clear.cgColor
        controls.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            controls.topAnchor.constraint(equalTo: inputView.topAnchor),
            controls.bottomAnchor.constraint(equalTo: inputView.bottomAnchor)
        ])
        actionControlsView = controls

        atButton = makeKeyboardActionButton(identifier: "at-key", label: "Insert at sign") { [weak self] in
            self?.routeProxyCommand(.at)
        }
        emojiButton = makeKeyboardActionButton(identifier: "emoji-picker", label: "Open emoji picker") { [weak self] in
            self?.presentArea(.emoji)
        }
        numberButton = makeKeyboardActionButton(identifier: "number-layer", label: "Open symbols keyboard") { [weak self] in
            guard let self else { return }
            if KeyboardState.shared.areaMode == .emoji {
                KeyboardState.shared.closeArea()
            } else if KeyboardState.shared.areaMode == .panel {
                closeNumberPanel()
            } else {
                self.presentArea(.panel)
            }
        }
        deleteButton = makeKeyboardActionButton(identifier: "delete-backward", label: "Delete backward") { [weak self] in
            self?.routeProxyCommand(.delete)
        }
        let deleteHold = UILongPressGestureRecognizer(target: self, action: #selector(handleDeleteHold(_:)))
        deleteHold.minimumPressDuration = 0.35
        deleteHold.cancelsTouchesInView = false
        deleteButton?.addGestureRecognizer(deleteHold)
        deleteHoldRecognizer = deleteHold
        returnButton = makeKeyboardActionButton(identifier: "return-key", label: "Insert return") { [weak self] in
            self?.routeProxyCommand(.returnKey)
        }
        dismissButton = makeKeyboardActionButton(identifier: "dismiss-keyboard", label: "Dismiss keyboard") { [weak self] in
            self?.handleDismissKeyboard()
        }
        letterModeButton = makeKeyboardActionButton(identifier: "letter-mode", label: "Open letter keyboard") { [weak self] in
            self?.presentArea(.letters)
        }
        micButton = makeKeyboardActionButton(identifier: "dictate-button", label: "Hold to dictate", installPrimaryAction: false) { }
        micButton?.addTarget(self, action: #selector(handleMicTouchDown), for: .touchDown)
        micButton?.addTarget(self, action: #selector(handleMicTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        micButton?.addTarget(self, action: #selector(handleMicTap), for: .touchUpInside)
        // A preparation tap is a regular button activation, not a recording
        // hold. Keep a primary-action fallback because some iOS keyboard hosts
        // deliver that event more reliably than touchDown to extension views.
        micButton?.addTarget(self, action: #selector(handleMicPrimaryAction), for: .primaryActionTriggered)
        (micButton as? DictationMicButton)?.onAccessibilityActivate = {
            let state = KeyboardState.shared
            switch state.dictationStatus {
            case .requested, .recording:
                state.handleMicPressEnded()
            case .idle, .ready, .failed:
                state.handleMicPressBegan()
            case .transcribing, .processing:
                return false
            }
            return true
        }
        micButton?.accessibilityHint = String(localized: "Double-tap to start or stop dictation.")
        spaceButton = makeKeyboardActionButton(identifier: "space-key", label: "Space") { [weak self] in
            self?.routeProxyCommand(.space)
        }
        let cursorGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleSpaceCursorGesture(_:)))
        cursorGesture.minimumPressDuration = 0.3
        cursorGesture.cancelsTouchesInView = true
        spaceButton?.addGestureRecognizer(cursorGesture)
        let cursorController = LongPressCursorMovementController()
        cursorController.delegate = self
        spaceCursorController = cursorController
        [atButton, emojiButton, numberButton, micButton, spaceButton,
         deleteButton, returnButton, letterModeButton, dismissButton].compactMap { $0 }.forEach {
            controls.addSubview($0)
        }
        setVoiceActionControlsHidden(true)
    }

    func makeKeyboardActionButton(
        identifier: String,
        label: String,
        minimumHeight: CGFloat = VoiceOnlyKeyboardPolicy.bottomActionHitHeight,
        installPrimaryAction: Bool = true,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = identifier == "dictate-button" ? DictationMicButton(type: .system) : UIButton(type: .system)
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        button.accessibilityTraits = [.button]
        button.configuration = .plain()
        button.configuration?.contentInsets = .zero
        button.configuration?.baseForegroundColor = .label
        // Size comes from explicit frames in layoutVoiceActionControls.
        // A heightAnchor here would opt the control into Auto Layout and pin it
        // to the creation frame, which drops hold-to-dictate hits.
        button.translatesAutoresizingMaskIntoConstraints = true
        button.backgroundColor = .clear
        button.tintColor = .label
        button.setTitleColor(.label, for: .normal)
        button.layer.cornerRadius = VoiceOnlyKeyboardPolicy.controlSize / 2
        button.configurationUpdateHandler = { control in
            if control.isHighlighted || !control.isEnabled {
                // UIKit owns hit testing only; the shared SwiftUI surface owns visuals.
                control.backgroundColor = .clear
            } else {
                control.backgroundColor = .clear
            }
        }
        if installPrimaryAction {
            button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        }
        _ = minimumHeight
        return button
    }

    private func setVoiceActionControlsHidden(_ hidden: Bool) {
        guard let controls = actionControlsView else { return }
        controls.isHidden = hidden
    }

    private func handleDismissKeyboard() {
        dismissKeyboard()
    }

    private func updateActionAvailability() {
        dismissButton?.isEnabled = isAttached
        dismissButton?.accessibilityValue = isAttached ? "Available" : "Unavailable"
    }

    private func layoutVoiceActionControls(surfaceHeight: CGFloat? = nil) {
        guard let controls = actionControlsView, controls.bounds.width > 0 else { return }
        let mode = KeyboardState.shared.areaMode
        let width = controls.bounds.width
        let resolvedHeight = surfaceHeight ?? computeKeyboardHeight(for: mode)
        let layout = VoiceOnlyKeyboardPolicy.layout(
            for: Double(width),
            surfaceHeight: Double(max(1, resolvedHeight)),
            controlOrder: KeyboardAccessoryOrder.current
        )
        let allButtons = [atButton, emojiButton, numberButton, micButton, spaceButton,
                          deleteButton, returnButton, letterModeButton, dismissButton]
            .compactMap { $0 }
        allButtons.forEach {
            $0.isHidden = true
            $0.isEnabled = false
            $0.isUserInteractionEnabled = false
        }

        // SwiftUI owns every auxiliary page. UIKit remains interactive only for
        // the small letter-page mic and dismiss overlays; keeping the panel's
        // transparent container hidden lets its SwiftUI spacebar receive the
        // native-style cursor drag gesture.
        let isAuxiliary = mode == .panel || mode == .emoji
        controls.isHidden = isAuxiliary
        controls.isUserInteractionEnabled = !isAuxiliary

        guard !isAuxiliary else {
            [atButton, emojiButton, numberButton, micButton, spaceButton,
             deleteButton, returnButton, letterModeButton, dismissButton]
                .compactMap { $0 }
                .forEach {
                    $0.isHidden = true
                    $0.isEnabled = false
                    $0.isUserInteractionEnabled = false
                }
            return
        }

        if mode == .letters {
            micButton?.isHidden = layout.letterMicFrame.isEmpty
            micButton?.isEnabled = !layout.letterMicFrame.isEmpty
            micButton?.isUserInteractionEnabled = !layout.letterMicFrame.isEmpty
            micButton?.frame = layout.letterMicFrame
            micButton?.accessibilityValue = KeyboardState.shared.dictationStatus.recordingLabel
            micButton?.accessibilityLabel = KeyboardState.shared.dictationActionLabel
            micButton?.accessibilityHint = KeyboardState.shared.appNeedsModelPreparation
                ? "Opens sAiity and prepares the dictation model."
                : "Double-tap to start or stop dictation."
            dismissButton?.isHidden = layout.letterDismissFrame.isEmpty
            dismissButton?.isEnabled = !layout.letterDismissFrame.isEmpty
            dismissButton?.isUserInteractionEnabled = !layout.letterDismissFrame.isEmpty
            dismissButton?.frame = layout.letterDismissFrame
            [micButton, dismissButton].compactMap { $0 }.forEach {
                $0.layer.cornerRadius = $0.bounds.height / 2
            }
            if let inputView { inputView.bringSubviewToFront(controls) }
            return
        }

        let leftRailVisible = layout.leftRailWidth > 0
        let rightRailVisible = layout.rightRailWidth > 0
        let voiceMicFrameAvailable = !layout.dictateFrame.isEmpty
        atButton?.isHidden = !leftRailVisible
        emojiButton?.isHidden = !leftRailVisible
        numberButton?.isHidden = !leftRailVisible
        micButton?.isHidden = (mode != .keys && mode != .recording) || !voiceMicFrameAvailable
        spaceButton?.isHidden = (mode != .keys && mode != .recording) || layout.spaceFrame.isEmpty
        letterModeButton?.isHidden = mode != .keys || layout.keyboardModeFrame.isEmpty
        deleteButton?.isHidden = !rightRailVisible
        returnButton?.isHidden = !rightRailVisible
        dismissButton?.isHidden = !rightRailVisible
        [atButton, emojiButton, numberButton, micButton, spaceButton, deleteButton, returnButton, letterModeButton, dismissButton]
            .compactMap { $0 }
            .forEach {
                $0.isEnabled = !$0.isHidden
                $0.isUserInteractionEnabled = !$0.isHidden
            }
        atButton?.frame = layout.leftUtilityFrames.at
        emojiButton?.frame = layout.leftUtilityFrames.emoji
        numberButton?.frame = layout.leftUtilityFrames.number
        micButton?.frame = layout.dictateFrame
        micButton?.accessibilityValue = KeyboardState.shared.dictationStatus.recordingLabel
        micButton?.accessibilityLabel = KeyboardState.shared.dictationActionLabel
        micButton?.accessibilityHint = KeyboardState.shared.appNeedsModelPreparation
            ? "Opens sAiity and prepares the dictation model."
            : "Double-tap to start or stop dictation."
        spaceButton?.frame = layout.spaceFrame
        deleteButton?.frame = layout.deleteFrame
        returnButton?.frame = layout.returnFrame
        letterModeButton?.frame = layout.keyboardModeFrame
        dismissButton?.frame = layout.dismissFrame
        [atButton, emojiButton, numberButton, micButton, spaceButton, deleteButton, returnButton, letterModeButton, dismissButton]
            .compactMap { $0 }
            .forEach { $0.layer.cornerRadius = $0.bounds.height / 2 }
        spaceButton?.layer.cornerRadius = (spaceButton?.bounds.height ?? 0) / 2
        micButton?.layer.cornerRadius = (micButton?.bounds.height ?? 0) / 2
        if let inputView { inputView.bringSubviewToFront(controls) }
    }

    @objc private func handleMicTouchDown() {
        // Preparation is a tap-to-open action. Waiting for touch-up lets the
        // keyboard host finish the control activation before NSExtensionContext
        // hands the app URL to iOS.
        guard !KeyboardState.shared.appNeedsModelPreparation else { return }
        KeyboardState.shared.handleMicPressBegan()
    }

    @objc private func handleMicTouchUp() {
        guard !KeyboardState.shared.appNeedsModelPreparation else { return }
        KeyboardState.shared.handleMicPressEnded()
    }

    @objc private func handleMicTap() {
        guard KeyboardState.shared.appNeedsModelPreparation else { return }
        KeyboardState.shared.handleMicPressBegan()
    }

    @objc private func handleMicPrimaryAction() {
        guard KeyboardState.shared.appNeedsModelPreparation else { return }
        KeyboardState.shared.handleMicPressBegan()
    }

    /// Match the native keyboard's spacebar trackpad behavior. A short tap is
    /// still handled by the UIButton action; once this recognizer begins it
    /// cancels that action and forwards horizontal movement to the text proxy.
    @objc private func handleSpaceCursorGesture(_ recognizer: UILongPressGestureRecognizer) {
        guard let spaceButton, let spaceCursorController else { return }
        let point = recognizer.location(in: spaceButton)
        switch recognizer.state {
        case .began:
            spaceCursorController.touchesBegan(point)
        case .changed:
            spaceCursorController.touchesMoved(point)
        case .ended, .cancelled:
            spaceCursorController.touchesEnded(point)
        default:
            break
        }
    }

    @objc private func handleDeleteHold(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            deleteRepeatTimer?.invalidate()
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.routeProxyCommand(.delete)
            }
            deleteRepeatTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .ended, .cancelled, .failed:
            deleteRepeatTimer?.invalidate()
            deleteRepeatTimer = nil
        default:
            break
        }
    }

    private func closeNumberPanel() {
        KeyboardState.shared.closeArea()
    }

    private func presentArea(_ mode: KeyboardAreaMode) {
        KeyboardState.shared.presentArea(mode)
    }

    func routeProxyCommand(_ command: KeyboardCommand) {
        let ownerAvailable = isAttached && isOnScreen
            && KeyboardState.shared.activeControllerID == controllerID
        guard ownerAvailable else {
            DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "proxyCommandRejected",
                details: "command=\(String(describing: command)) ownerAvailable=false"
            ))
            return
        }
        Self.routeProxyCommand(
            command,
            enabled: ownerAvailable,
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) }
        )
    }

    func routeProxyText(_ text: String) {
        let ownerAvailable = isAttached && isOnScreen
            && KeyboardState.shared.activeControllerID == controllerID
        guard ownerAvailable else {
            DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "proxyTextRejected",
                details: "textLength=\(text.count) ownerAvailable=false"
            ))
            return
        }
        textDocumentProxy.insertText(text)
    }

    static func routeProxyCommand(
        _ command: KeyboardCommand,
        enabled: Bool,
        deleteBackward: @escaping () -> Void,
        insertText: @escaping (String) -> Void
    ) {
        command.perform(
            ifEnabled: enabled,
            deleteBackward: deleteBackward,
            insertText: insertText
        )
    }

    // MARK: - Vendored keyboard owner

    func didTriggerKey(_ key: KeyDefinition) {
        switch key.type {
        case .input(let value, _):
            if value == KeyboardLayouts.emojiKeyGlyph {
                presentArea(.emoji)
            } else {
                routeProxyText(value)
                if giellaKeyboard?.page == .shifted {
                    giellaKeyboard?.page = .normal
                }
            }
        case .backspace:
            routeProxyCommand(.delete)
        case .returnkey:
            routeProxyCommand(.returnKey)
        case .spacebar:
            routeProxyCommand(.space)
        case .symbols:
            presentArea(.panel)
        case .shift:
            toggleLetterShift()
        case .keyboardMode:
            presentArea(.letters)
        case .shiftSymbols, .spacer, .caps, .splitKeyboard,
             .normalKeyboard, .sideKeyboardLeft, .sideKeyboardRight,
             .comma, .fullStop, .tab:
            break
        }
    }

    func didSwipeKey(_ key: KeyDefinition) {
        didTriggerKey(key)
    }

    func didTriggerDoubleTap(forKey key: KeyDefinition) {
        guard case .shift = key.type else { return }
        giellaKeyboard?.page = .capslock
        lastShiftTapDate = .distantPast
    }

    func didTriggerHoldKey(_ key: KeyDefinition) {
        if case .backspace = key.type {
            routeProxyCommand(.delete)
        }
    }

    func didMoveCursor(_ movement: Int) {
        let ownerAvailable = isAttached && isOnScreen
            && KeyboardState.shared.activeControllerID == controllerID
        guard ownerAvailable else {
            DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "cursorRejected",
                details: "movement=\(movement) ownerAvailable=false"
            ))
            return
        }
        textDocumentProxy.adjustTextPosition(byCharacterOffset: movement)
    }

    private func toggleLetterShift() {
        guard let keyboard = giellaKeyboard else { return }
        let now = Date()
        if now.timeIntervalSince(lastShiftTapDate) < 0.35 {
            keyboard.page = .capslock
            lastShiftTapDate = .distantPast
            return
        }

        lastShiftTapDate = now
        switch keyboard.page {
        case .normal:
            keyboard.page = .shifted
        case .shifted, .capslock:
            keyboard.page = .normal
        case .symbols1, .symbols2:
            break
        }
    }

    func longpress(movedCursor movement: Int) {
        didMoveCursor(movement)
    }

    func longpressDidCancel() { }

    // MARK: - Text Change

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Re-check the dictation undo offer against the changed document (#266).
        // Deliberately a re-check and not a clear: the keyboard's own insertion is
        // itself a text change, so clearing here would cancel the offer at the
        // moment it is made.
        KeyboardState.shared.revalidateDictationUndo()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        // A caret the user moved is a caret the insertion is no longer behind (#266).
        KeyboardState.shared.revalidateDictationUndo()
    }

    // MARK: - Window Gesture Delay

    /// Hashes of gesture recognizers we disabled, so we can restore them on disappear.
    private var disabledGestureHashes = Set<Int>()

    /// Disable `delaysTouchesBegan` on all UIWindow gesture recognizers.
    ///
    /// WHY: iOS attaches system gesture recognizers to the keyboard's UIWindow with
    /// `delaysTouchesBegan = true`. These recognizers check for system gestures (swipe-back,
    /// Control Center) before delivering touches to the keyboard. This adds ~100ms delay
    /// on edge key touches, causing haptic/popup to fire on touchUp instead of touchDown
    /// and long-press accent popup to fail on outer edge of edge keys.
    ///
    /// This is the same technique used by the original giellakbd-ios keyboard.
    private func disableWindowGestureDelay() {
        guard let window = view.window,
              let recognizers = window.gestureRecognizers else { return }
        for recognizer in recognizers where recognizer.delaysTouchesBegan {
            recognizer.delaysTouchesBegan = false
            disabledGestureHashes.insert(recognizer.hash)
        }
    }

    /// Restore `delaysTouchesBegan` on gesture recognizers we previously disabled.
    private func restoreWindowGestureDelay() {
        guard let window = view.window,
              let recognizers = window.gestureRecognizers else { return }
        for recognizer in recognizers where disabledGestureHashes.contains(recognizer.hash) {
            recognizer.delaysTouchesBegan = true
        }
        disabledGestureHashes.removeAll()
    }

}
