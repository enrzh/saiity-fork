// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import Combine
import DictusCore

/// Keyboard action controls use a small hit slop because the accessory lane sits
/// against the host keyboard's edge. The visual frame remains unchanged.
private class KeyboardActionButton: UIButton {
    var hitExpansion: CGFloat = 8
    /// Dictation uses its own semantic press haptic; all other action buttons
    /// can share the native-feeling key tick from this touch owner.
    var emitsHapticOnTouchDown = true

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        #if DEBUG
        PersistentLog.log(.diagnosticProbe(component: "NativeButton", instanceID: accessibilityIdentifier ?? "button",
                                         action: "touchDown", details: "hasFace=\(existingKeyboardFace != nil) frame=\(frame)"))
        #endif
        if emitsHapticOnTouchDown {
            HapticFeedback.playInputClick()
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -hitExpansion, dy: -hitExpansion).contains(point)
    }
}

/// VoiceOver activation is a toggle, independent of physical touch-down/up.
private final class DictationMicButton: KeyboardActionButton {
    var onAccessibilityActivate: (() -> Bool)?
    var onTouchDown: (() -> Void)?
    var onTouchUp: (() -> Void)?
    var onTouchCancelled: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardHitTrace",
            instanceID: "dictate-button",
            action: "touchesBegan",
            details: "frame=\(frame) enabled=\(isEnabled) hidden=\(isHidden) inWindow=\(window != nil)"
        ))
        onTouchDown?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardHitTrace",
            instanceID: "dictate-button",
            action: "touchesEnded",
            details: "frame=\(frame) enabled=\(isEnabled) hidden=\(isHidden)"
        ))
        onTouchUp?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardHitTrace",
            instanceID: "dictate-button",
            action: "touchesCancelled",
            details: "frame=\(frame) enabled=\(isEnabled) hidden=\(isHidden)"
        ))
        onTouchCancelled?()
    }

    override func accessibilityActivate() -> Bool {
        onAccessibilityActivate?() ?? false
    }
}

/// App recovery is a tap-down action, not a release/hold interpreted as dictation.
private final class KeyboardRecoveryButton: KeyboardActionButton {
    var onOpen: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        PersistentLog.log(.diagnosticProbe(component: "KeyboardRecovery", instanceID: "open-saiity-button",
                                         action: "touchDown", details: "enabled=\(isEnabled) window=\(window != nil)"))
        onOpen?()
    }

    override func accessibilityActivate() -> Bool {
        guard !isHidden, isEnabled, isUserInteractionEnabled else { return false }
        onOpen?()
        return true
    }
}

class KeyboardViewController: UIInputViewController,
    NextKeyboardHostDelegate {
    let controllerID = String(UUID().uuidString.prefix(8))

    private var hostingController: UIHostingController<KeyboardRootView>?
    /// Belongs to this cached controller, so dismissal cannot erase another
    /// keyboard's opener and reappearance does not depend on SwiftUI onAppear.
    var openContainingApp: ((URL, @escaping (Bool) -> Void) -> Void)?
    private var keyboardSurfaceView: KeyboardSurfaceView?
    /// One passive inset behind every page and its bottom bar.
    private let surfaceBackdrop = KeyboardNativeControlFace()
    private var actionControlsView: UIView?
    /// The single touch owner for the active key grid. It lives on the input view,
    /// not inside `actionControlsView`, because that overlay hides itself on the
    /// letter page and would take the owner down with it.
    /// Touch owner for the symbol and number pages.
    ///
    /// Letters do not use this either: they are drawn and owned by the new
    /// `KeyGridView`, which the controller mounts directly.
    /// The symbol and number surfaces still publish their geometry through
    /// `KeyGridTouchBus`, and that path is left alone here rather than being
    /// rewritten in the same change as the letter grid.
    private var keyGridOwner: KeyGridTouchOwner?
    /// The letter keyboard's grid: one UIKit view that draws the keys and hit-tests
    /// them from the same geometry.
    ///
    /// It is mounted on the input view, above the SwiftUI hosting view, and it is
    /// the only thing that owns letter touches while the letter page is showing.
    /// There is no global registry and no shared bus: the controller owns this
    /// instance, so a stale controller can only ever revoke its own.
    private var keyboardModeButton: UIButton?
    private var emojiButton: UIButton?
    private var numberButton: KeyboardKeyTouchControl?
    private var returnButton: UIButton?
    private var voiceBoardButton: UIButton?
    private var moreButton: UIButton?
    private var dictationResultCancellable: AnyCancellable?
    private var serviceToggle: UIButton?
    private var boardDeleteButton: KeyboardDeleteRepeatControl?
    private var emojiCategoryScrubber: EmojiCategoryScrubControl? { keyboardSurfaceView?.emojiCategory }
    private var micButton: UIButton?
    /// Separate hit owner for the app handoff, mutually exclusive with
    /// `micButton` and sharing its frame.
    private var recoveryButton: UIButton?
    private var spaceButton: SpaceTrackingButton.TrackingControl?
    private var cursorPreferredColumn: Int?
    private var lastCursorStepTime: TimeInterval = 0
    private var areaModeCancellable: AnyCancellable?
    private var keyboardPreferenceCancellable: AnyCancellable?
    private var typingLanguageCancellable: AnyCancellable?
    private var touchPredictionCancellable: AnyCancellable?
    private var emojiCategorySelectionCancellable: AnyCancellable?
    private var emojiCategoryJumpCancellable: AnyCancellable?
    private var modelPreparationCancellable: AnyCancellable?
    private var availabilityRefreshTimer: Timer?
    private var micTouchActive = false
    private var micHoldTimer: Timer?
    private var micHoldRecognized = false
    private var adaptiveContextGeneration: UInt = 0
    private var lastPublishedFullAccess: Bool?
    private var lastPublishedFullAccessProbe: String?

    private var lastLayoutSize: CGSize?
    private var lastLayoutHeight: CGFloat?
    private var lastWindowAccessoryHeight: CGFloat?
    private var lastLayoutMode: KeyboardAreaMode?
    private var lastLayoutAccessoryOrder: KeyboardAccessoryOrder?
    private var lastTypingLanguage: SupportedLanguage?
    private var lastTypingLayout: LayoutType?

    private final class PassthroughControlsView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            // This override does not call `super`, so UIKit's own eligibility
            // checks are bypassed: a hidden or non-interactive overlay would still
            // claim touches. That is how the `letter-mode` chrome button swallowed
            // taps aimed at the `123` key during the brief window where the board
            // is still switching to the letter surface. Restore the contract
            // `super` would have applied.
            guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
            let mic = subviews.first(where: { $0.accessibilityIdentifier == "dictate-button" })
            // The recovery mic is the visible primary action on the dictation
            // board. Route it before forwarding misses into SwiftUI so a stale
            // or overlapping hosted surface cannot consume the tap.
            if let toggle = subviews.first(where: { $0.accessibilityIdentifier == "dictation-service-toggle" }),
               !toggle.isHidden,
               toggle.isUserInteractionEnabled {
                let localPoint = toggle.convert(point, from: self)
                if toggle.point(inside: localPoint, with: event) {
                    return toggle.hitTest(localPoint, with: event) ?? toggle
                }
            }
            if let mic,
               !mic.isHidden,
               mic.isUserInteractionEnabled {
                let localPoint = mic.convert(point, from: self)
                // Route the explicit expanded frame instead of recursing through
                // UIButton.hitTest. UIKit can reject a transparent expanded hit
                // while the keyboard host is animating, before the button sees it.
                if mic.bounds.insetBy(dx: -20, dy: -20).contains(localPoint) {
                    return mic
                }
            }
            // The recovery control shares the mic's frame and is never visible at
            // the same time, so it gets identical routing priority.
            if let recovery = subviews.first(where: { $0.accessibilityIdentifier == "open-saiity-button" }),
               !recovery.isHidden,
               recovery.isUserInteractionEnabled {
                let localPoint = recovery.convert(point, from: self)
                if recovery.bounds.insetBy(dx: -20, dy: -20).contains(localPoint) {
                    return recovery
                }
            }
            // Voice controls own their visible rectangles. Emoji is hosted
            // directly, so blank pager space never passes through this overlay.
            for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0 && subview.isUserInteractionEnabled {
                let localPoint = subview.convert(point, from: self)
                if let hit = subview.hitTest(localPoint, with: event) {
                    return hit
                }
            }
            // Misses return to the input view's ordinary sibling hit testing.
            // Never forward into the full-size SwiftUI visual canvas.
            return nil
        }


    }

    /// Explicit height constraint on inputView to prevent layout issues after app switch.    /// WHY: Without this, iOS may not recalculate the keyboard height correctly when the
    /// extension is brought back to foreground after a URL scheme app switch. The system
    /// keyboard row bleeds through and the recording overlay gets compressed.
    private var heightConstraint: NSLayoutConstraint?

    private var previousInputViewHeight: Double?
    private var stableInputViewHeightPasses = 0

    /// Height constraint for the SwiftUI hosting view (toolbar + recording overlay).
    /// The voice surface uses the native input height.
    private var hostingHeightConstraint: NSLayoutConstraint?

    /// SwiftUI supplies visual chrome; UIKit owns all live keyboard input.
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
    private var proxyInsertionCount = 0
    private var proxyInsertionTotalMS: Double = 0
    private var proxyInsertionMaxMS: Double = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = true
        view.layer.backgroundColor = UIColor.clear.cgColor
        // The extension owns dictation through its centered press-and-hold control.
        // Prevent iOS from adding a second system microphone key below our surface.
        hasDictationKey = true
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
        kbInputView.clipsToBounds = false
        kbInputView.layer.masksToBounds = false
        kbInputView.layer.backgroundColor = UIColor.clear.cgColor

        // KeyboardInputView owns the single semantic native backdrop.

        // --- 2. Create SwiftUI hosting for the voice surface ---
        // Pass weak callbacks rather than the controller itself. This keeps the
        // SwiftUI root owned by hosting without making a stale controller the
        // routing authority after iOS rebuilds the keyboard.
        // The letter grid, mounted before the hosting view exists so the SwiftUI
        // tree can be handed a reference to it.
        //
        // It replaces the old shared touch owner for letters. That owner resolved
        // touches against geometry SwiftUI published through a process-wide bus,
        // which meant the keys that were drawn and the keys that could be pressed
        // were described by two different systems. Here a single view does both.
        //
        // That view is `NextKeyboardHost`'s, mounted later at zPosition 500. A
        // legacy letter grid used to be created here at zPosition 200 and handed to
        // the SwiftUI surface, which drew the same keys a second time underneath it.
        // Two grids describing one keyboard was the doubling: the lower one was drawn
        // over on every key, so it cost a fill and a hit-test layer per key and bought
        // nothing, and any disagreement between them showed up as a key that looked
        // right and did not answer.
        //
        // Both that grid and this hand-off are gone. The SwiftUI surface keeps the
        // bottom bar, the suggestion lane and the glass rim — the things that are not
        // keys — and the grid draws and hit-tests the keys, so there is one of each.
        let rootView = KeyboardRootView(
            controllerID: controllerID,
            routeText: { [weak self] text in self?.routeProxyText(text) },
            routeCommand: { [weak self] command in self?.routeProxyCommand(command) },
            routeWordDeletion: { [weak self] in self?.deletePreviousWord() },
            routeCursorMovement: { [weak self] step in self?.applyCursorStep(step) },
            routeCursorEnded: { [weak self] in self?.cursorPreferredColumn = nil },
            routePaste: { [weak self] in self?.pasteFromClipboard() },
            routeDismiss: { [weak self] in self?.dismissKeyboard() },
            installOpenURL: { [weak self] opener in self?.openContainingApp = opener }
        )
        let hosting = UIHostingController(rootView: rootView)
        hosting.view.isMultipleTouchEnabled = true
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
        // Per-key UIKit controls own input inside the hosted surface; this
        // overlay routes board actions and forwards misses to those controls.
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
        kbInputView.layer.masksToBounds = false
        hosting.view.clipsToBounds = false
        hosting.view.layer.masksToBounds = false

        // Assign as the controller's inputView -- this activates audio feedback
        self.inputView = kbInputView
        // Keep the root surface eligible for independent fingers. UIKit normally
        // enables this on views, but input views can be recreated and cached by
        // the host with different defaults.
        kbInputView.isMultipleTouchEnabled = true
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

        // Forget the layout memo so a returning keyboard re-applies its layout
        // even though the mode and height are unchanged. Without this the
        // idempotence guard in `applyLayout` would treat the second appearance as
        // already laid out and skip the work entirely.
        lastLayoutSize = nil
        lastLayoutHeight = nil
        lastLayoutMode = nil
        lastLayoutAccessoryOrder = nil

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
        // Captured before registration, which marks this controller visible.
        // A replacement built while the user is already typing must not reset
        // the page; see `shouldApplyOpeningPreference`.
        let applyOpeningPreference = KeyboardAreaMode.shouldApplyOpeningPreference(
            keyboardAlreadyVisible: KeyboardState.shared.isKeyboardVisible,
            appearingControllerID: controllerID,
            activeControllerID: KeyboardState.shared.activeControllerID
        )
        if !applyOpeningPreference {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "keptSurfaceAcrossControllerSwap",
                details: "mode=\(KeyboardState.shared.areaMode.rawValue) previous=\(KeyboardState.shared.activeControllerID ?? "none")"
            ))
        }
        // Point KeyboardState's weak controller ref at the currently-visible controller
        // so call sites in KeyboardRootView and KeyboardState can access textDocumentProxy.
        // Previously set from KeyboardRootView.onAppear, which held a strong ref → #134.
        KeyboardState.shared.controller = self
        KeyboardState.shared.registerControllerAppearance(controllerID: controllerID)
        KeyboardState.shared.isOpeningForDictation = false
        KeyboardState.shared.refreshHostInputTraits(from: textDocumentProxy, applyArea: false)
        KeyboardState.shared.startClipboardMonitoring()
        // Model readiness and the app scene phase can change while this cached
        // keyboard controller is off-screen. Refresh before laying out the mic
        // action so the button does not keep a stale "Open sAiity" state.
        KeyboardState.shared.refreshFromDefaults()
        HapticFeedback.refreshEnabledState()
        KeyboardVariantPreferences.reload()
        HapticFeedback.warmUp()
        hasAppeared = true
        isAttached = true

        // Opening uses the saved dictation/keyboard preference, except number
        // and phone fields which open the 3×4 number pad. Skipped when this
        // appearance is a controller swap of a keyboard that is already up.
        if applyOpeningPreference, !KeyboardState.shared.dictationStatus.ownsKeyboardArea {
            KeyboardState.shared.presentPreferredOpeningArea()
        }

        // (Re)subscribe to the keyboard area mode here, not in viewDidLoad.
        // WHY: iOS caches UIInputViewController instances across app-switches and
        // rarely deallocates them, so stale controllers would keep mutating
        // hostingHeightConstraint on every mode change (issue #128). By subscribing
        // in viewWillAppear and cancelling in viewDidDisappear, only the currently
        // visible controller is reactive. Assignment is idempotent — the previous
        // AnyCancellable is released on reassignment, which cancels its subscription.
        observeKeyboardAreaMode()
        lastTypingLanguage = SupportedLanguage.active
        lastTypingLayout = LayoutType.active
        keyboardPreferenceCancellable = KeyboardState.shared.$keyboardPreferenceRevision
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.isAttached, self.isOnScreen else { return }
                KeyboardVariantPreferences.reload()
                self.lastLayoutSize = nil
                self.nextKeyboardHost?.refreshKeyLayout()
                self.refreshVisibleKeyboardLayoutIfNeeded()
                self.nextKeyboardHost?.refreshAppearance()
                self.keyboardSurfaceView?.refreshAppearance()
                self.layoutVoiceActionControls()
                self.nextKeyboardHost?.updateHitPrediction(
                    SuggestionState.shared.adaptiveTouchPrediction,
                    enabled: KeyboardInteractionPreferences.adaptiveHitPredictionEnabled
                )
            }
        typingLanguageCancellable = KeyboardState.shared.$typingLanguage
            .dropFirst()
            .sink { [weak self] _ in self?.refreshVisibleKeyboardLayoutIfNeeded() }
        touchPredictionCancellable = SuggestionState.shared.$adaptiveTouchPrediction
            .sink { [weak self] prediction in
                guard let self, self.isAttached, self.isOnScreen else { return }
                self.nextKeyboardHost?.updateHitPrediction(
                    prediction,
                    enabled: KeyboardInteractionPreferences.adaptiveHitPredictionEnabled
                )
            }
        observeEmojiCategorySelection()
        observeEmojiCategoryJump()
        observeModelPreparationState()
        startAvailabilityRefreshTimer()
        micHoldTimer?.invalidate()
        micHoldTimer = nil
        micTouchActive = false
        micHoldRecognized = false

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
        // Apply the saved default after subscriptions and trait refresh. A
        // cached controller otherwise keeps the page from its previous host.
        // The same call must not run for a live swap: that is what put the
        // dictation board back over the letter keys mid-word.
        if applyOpeningPreference, !KeyboardState.shared.dictationStatus.ownsKeyboardArea {
            KeyboardState.shared.presentPreferredOpeningArea()
        }

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

    func publishFullAccessHandshake(force: Bool = false) {
        guard isAttached, isOnScreen, KeyboardState.shared.activeControllerID == controllerID else { return }
        let granted = hasFullAccess
        let probe = granted ? AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessProbe) : nil
        guard force || lastPublishedFullAccess != granted || lastPublishedFullAccessProbe != probe else { return }
        lastPublishedFullAccess = granted
        lastPublishedFullAccessProbe = probe
        // A keyboard without Full Access may be unable to write the App Group.
        // A direct notification can still tell the app to clear its old result.
        guard granted else {
            DarwinNotificationCenter.post(DarwinNotificationName.keyboardFullAccessDenied)
            return
        }
        AppGroup.defaults.set(true, forKey: SharedKeys.onboardingFullAccessVerified)
        if let probe {
            AppGroup.defaults.set(probe, forKey: SharedKeys.onboardingFullAccessAcknowledgedProbe)
        }
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.onboardingFullAccessHandshakeDate)
        AppGroup.defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.keyboardFullAccessChanged)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        publishFullAccessHandshake()

        // Issue #116 diagnostic: snapshot final frames after layout settles.
        // We log both sizes and constraint constants so we can detect priority mismatches
        // where iOS imposed a different height than we asked for.
        logLayoutSnapshot(action: "viewDidAppear_settled")
        KeyboardState.shared.startClipboardMonitoring()

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
            lastLayoutSize = size
            lastLayoutHeight = liveHeight
            lastLayoutMode = mode
            lastLayoutAccessoryOrder = KeyboardAccessoryOrder.current
        }
        if let controls = actionControlsView, let inputView {
            inputView.bringSubviewToFront(controls)
            if let surface = keyboardSurfaceView, !surface.isHidden {
                inputView.bringSubviewToFront(surface)
            }
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
    /// - Idle: hosting fills the native-height voice surface.
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
        let window = inputView?.window ?? viewIfLoaded?.window
        let micWindowFrame = micButton.flatMap { mic in
            window.map { mic.convert(mic.bounds, to: $0) }
        }
        let windowScreenFrame = window.map { $0.convert($0.bounds, to: $0.screen.coordinateSpace) }
        let inputScreenFrame = inputView.flatMap { input in
            input.window.map { input.convert(input.bounds, to: $0.screen.coordinateSpace) }
        }
        let micScreenFrame = micButton.flatMap { mic in
            mic.window.map { mic.convert(mic.bounds, to: $0.screen.coordinateSpace) }
        }
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: action,
            details: "inputBounds=\(Int(inputBounds.width))x\(Int(inputBounds.height)) viewBounds=\(Int(viewBounds.width))x\(Int(viewBounds.height)) hostingFrame=\(Int(hostingFrame.width))x\(Int(hostingFrame.height)) inputFrame=\(inputView?.frame ?? .zero) inputScreenFrame=\(inputScreenFrame ?? .zero) controlsFrame=\(actionControlsView?.frame ?? .zero) hostFrame=\(hostingController?.view.frame ?? .zero) windowFrame=\(window?.frame ?? .zero) windowScreenFrame=\(windowScreenFrame ?? .zero) micFrame=\(micButton?.frame ?? .zero) micWindowFrame=\(micWindowFrame ?? .zero) micScreenFrame=\(micScreenFrame ?? .zero) hostingConst=\(hostingHeightConstraint?.constant ?? -1) heightConst=\(heightConstraint?.constant ?? -1) status=\(KeyboardState.shared.dictationStatus.rawValue) mode=\(KeyboardState.shared.areaMode.rawValue) onScreen=\(isOnScreen) \(windowAttachmentProbeDetails) memMB=\(MemoryFootprint.residentMB())"
        ))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        KeyboardState.shared.stopClipboardMonitoring()
        if micTouchActive { handleMicTouchCancelled() }

        // We are off screen from here on, whether or not we keep ownership below
        // (#260): a detached controller must not adopt an ownerless dictation.
        isAttached = false
        adaptiveContextGeneration &+= 1
        if KeyboardState.shared.activeControllerID == controllerID {
            SuggestionState.shared.clearAdaptiveTouchPrediction()
        }

        if KeyboardState.shared.controller === self {
            KeyboardState.shared.controller = nil
        }

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
        // One line per session, not per touch. Per-touch tracing cost roughly twenty
        // file writes per keystroke, so the hot path now only increments two
        // counters; this reports the totals once, which is enough to tell "no
        // touches reached the keyboard" apart from "they arrived and every one
        // came back" — the distinction that per-event tracing was being used for
        // and that no amount of guessing has resolved.
        if let owner = keyGridOwner {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "gridSessionTotals",
                details: owner.sessionSummary()
            ))
        }
        PersistentLog.log(.keyboardDidDisappear)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController", instanceID: controllerID,
            action: "typingInsertions",
            details: "count=\(proxyInsertionCount) totalMs=\(String(format: "%.1f", proxyInsertionTotalMS)) maxMs=\(String(format: "%.1f", proxyInsertionMaxMS)) controllerLifetime=true"
        ))

        // Tear down the area mode subscription so this (now-detached) controller
        // no longer reacts when KeyboardState publishes. iOS caches
        // UIInputViewController and rarely releases it, so without this cleanup
        // 10+ stale controllers race on hostingHeightConstraint (issue #128).
        // viewWillAppear re-subscribes on reattach.
        areaModeCancellable?.cancel()
        areaModeCancellable = nil
        keyboardPreferenceCancellable?.cancel()
        keyboardPreferenceCancellable = nil
        typingLanguageCancellable?.cancel()
        typingLanguageCancellable = nil
        touchPredictionCancellable?.cancel()
        touchPredictionCancellable = nil
        emojiCategorySelectionCancellable?.cancel()
        emojiCategorySelectionCancellable = nil
        emojiCategoryJumpCancellable?.cancel()
        emojiCategoryJumpCancellable = nil
        keyboardSurfaceView?.cancelInteractions()
        modelPreparationCancellable?.cancel()
        modelPreparationCancellable = nil
        availabilityRefreshTimer?.invalidate()
        availabilityRefreshTimer = nil
        micHoldTimer?.invalidate()
        micHoldTimer = nil
        micTouchActive = false
        micHoldRecognized = false

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

    /// Match the native keyboard's device-aware input height.
    private func computeNativeKeyboardHeight() -> CGFloat {
        let deviceContext = DeviceContext.current
        let nativeHeight = KeyboardHeightProvider.height(
            for: deviceContext,
            traitCollection: traitCollection,
            rowCount: KeyboardLayouts.drawsDigitRow && KeyboardState.shared.areaMode == .letters ? 5 : nil
        )
        let width = view.bounds.width > 1
            ? view.bounds.width
            : CGFloat(VoiceOnlyKeyboardPolicy.nativePortraitReferenceWidth)
        let expansion = VoiceOnlyKeyboardPolicy.horizontalExpansionScale(for: Double(width))
        return nativeHeight
            * CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeightScale)
            * CGFloat(expansion)
    }

    private func computeKeyboardHeight() -> CGFloat {
        computeKeyboardHeight(for: KeyboardState.shared.areaMode)
    }

    /// Resolves the native keyboard surface first, then adds the prediction lane
    /// outside that surface for letter mode. UIKit reports the complete input view
    /// height, so remove the lane belonging to the previously laid-out mode before
    /// feeding the observed value back into the stability resolver.
    private func computeKeyboardHeight(for mode: KeyboardAreaMode) -> CGFloat {
        let nativeHeight = computeNativeKeyboardHeight()
        let previousMode = lastLayoutMode ?? mode
        let previousAccessoryHeight = lastWindowAccessoryHeight ?? CGFloat(keyboardWindowAccessoryHeight(for: previousMode))
        let observedInputViewHeight = inputView?.bounds.height ?? 0
        let inputViewHeight = max(0, observedInputViewHeight - previousAccessoryHeight)
        let resolution = VoiceOnlyKeyboardPolicy.resolvedSurfaceHeight(
            inputViewHeight: Double(inputViewHeight),
            controllerViewHeight: view.bounds.height > 0
                ? Double(max(0, view.bounds.height - previousAccessoryHeight)) : nil,
            fallbackHeight: Double(nativeHeight),
            previousInputViewHeight: previousInputViewHeight,
            stableInputViewPasses: stableInputViewHeightPasses
        )
        previousInputViewHeight = resolution.observedInputViewHeight
        stableInputViewHeightPasses = resolution.stableInputViewPasses
        return CGFloat(resolution.height) + CGFloat(keyboardWindowAccessoryHeight(for: mode))
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
        dictationResultCancellable = KeyboardState.shared.$dictationUndoAvailable
            .removeDuplicates()
            .combineLatest(KeyboardState.shared.$keyboardDictationEnabled.removeDuplicates())
            .combineLatest(KeyboardState.shared.$isFinishingRecording.removeDuplicates())
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in self?.layoutVoiceActionControls() }
            }
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

    private func observeEmojiCategorySelection() {
        emojiCategorySelectionCancellable = KeyboardState.shared.$emojiCategorySelectionIndex
            .sink { [weak self] index in
                self?.emojiCategoryScrubber?.setCurrentIndex(index)
            }
    }

    private func observeEmojiCategoryJump() {
        emojiCategoryJumpCancellable = KeyboardState.shared.$emojiCategoryJumpToken
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.isAttached, self.isOnScreen,
                      KeyboardState.shared.areaMode == .emoji else { return }
                self.keyboardSurfaceView?.emoji.selectCategory(at: KeyboardState.shared.emojiCategoryJumpIndex)
            }
    }

    /// Refresh the UIKit hit target and accessibility label as soon as the app
    /// finishes preparing the model while this controller remains cached.
    private func observeModelPreparationState() {
        modelPreparationCancellable = KeyboardState.shared.modelPreparationPublisher
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.hasAppeared, self.isAttached else { return }
                    self.layoutVoiceActionControls()
                }
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

        // The key-grid touch owner may only claim touches while a surface that uses
        // it is actually mounted.
        //
        // Releasing it was left to each surface's own `onDisappear`, which is the
        // wrong owner of that decision: SwiftUI teardown can lag a native page
        // change. A legacy claim must not outlive the surface that published it.
        //
        // The controller is the only party that reliably knows which surface is
        // showing, so it is the only party that may revoke the claim.
        let modeUsesKeyGrid = Self.nextKeyboardModes.contains(mode)
        if !modeUsesKeyGrid {
            KeyGridTouchBus.deactivate()
        }

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
        let liveHeight = computeKeyboardHeight(for: mode)

        // Assigning an Auto Layout constant is NOT a no-op even when the new value
        // equals the old one: it invalidates layout and forces a full re-layout of
        // the hosting view, which re-lays-out every SwiftUI key control.
        // `viewDidLayoutSubviews` has always guarded this; `applyLayout` did not,
        // and it is the path the availability timer drives — that timer calls
        // `refreshFromDefaults`, which republishes the area mode every two
        // seconds. So the keyboard rebuilt its own geometry under the user's
        // fingers twice a second, indefinitely, and a key whose control was
        // rebuilt mid-gesture silently stopped responding. The device trace shows
        // `hostingSet_letters` with `old` equal to `new` every two seconds, which
        // is the signature of exactly this.
        //
        // The memo is shared with `viewDidLayoutSubviews` so the two paths cannot
        // disagree about what the current layout is.
        guard lastLayoutMode != mode || lastLayoutHeight != liveHeight else {
            // The frame can stay fixed while Hold, Finish, Cancel or recovery
            // changes. Refresh native faces/owners without changing constraints.
            layoutVoiceActionControls(surfaceHeight: liveHeight)
            return
        }
        lastLayoutMode = mode
        lastLayoutHeight = liveHeight

        refreshAdaptiveTouchContext()
        let oldHosting = hostingHeightConstraint?.constant ?? -1
        let status = KeyboardState.shared.dictationStatus.rawValue
        setVoiceActionControlsHidden(mode == .panel || mode == .letters || mode == .numberPad)
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

        case .numberPad:
            heightConstraint?.constant = liveHeight
            hostingHeightConstraint?.constant = liveHeight
            setHostingExpanded(true)
            hostingController?.view.isHidden = false
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "numberPadShown",
                details: "status=\(status) mode=\(mode.rawValue)"
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

    private func suggestionLaneHeight(for mode: KeyboardAreaMode) -> Double {
        KeyboardInteractionPreferences.topBarHeight(for: mode)
    }

    private func keyboardWindowAccessoryHeight(for mode: KeyboardAreaMode) -> Double {
        KeyboardInteractionPreferences.windowAccessoryHeight
    }

    private var currentSuggestionLaneHeight: Double {
        suggestionLaneHeight(for: KeyboardState.shared.areaMode)
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
        actionControlsView?.clipsToBounds = false
        actionControlsView?.layer.masksToBounds = false
        actionControlsView?.layer.backgroundColor = UIColor.clear.cgColor
    }

    private func installVoiceActionControls(in inputView: UIView) {
        let controls = PassthroughControlsView(frame: inputView.bounds)
        controls.backgroundColor = .clear
        controls.isOpaque = false
        controls.isMultipleTouchEnabled = true
        controls.layer.backgroundColor = UIColor.clear.cgColor
        controls.layer.zPosition = 100
        controls.translatesAutoresizingMaskIntoConstraints = false
        inputView.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: inputView.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: inputView.trailingAnchor),
            controls.topAnchor.constraint(equalTo: inputView.topAnchor),
            controls.bottomAnchor.constraint(equalTo: inputView.bottomAnchor)
        ])
        actionControlsView = controls

        // The key grid's single touch owner.
        //
        // It is added to the input view itself, as a sibling of the voice-control
        // overlay, rather than inside that overlay. This is the whole reason the
        // letter grid was dead for four builds: the overlay hides itself whenever
        // the area mode is `.letters`, `.panel` or `.numberPad`, and a subview of
        // a hidden view is itself hidden, so an owner placed inside it never
        // received a touch on the letter page. The emoji page was unaffected
        // because its overlay is visible, which is the only reason the two pages
        // behaved differently from identical code.
        //
        // Mounted here, its visibility is independent of the voice chrome, and
        // `claimsRect` still limits it to the grid so it cannot swallow the space
        // and return keys in the bottom bar.
        let keyOwner = KeyGridTouchOwner(frame: inputView.bounds)
        keyOwner.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Below the letter grid. Both are mounted on the input view, and when the
        // letter page is showing the owner is hidden and deactivated rather than
        // left to compete for the same touches.
        keyOwner.layer.zPosition = 150
        inputView.addSubview(keyOwner)
        keyGridOwner = keyOwner
        KeyGridTouchBus.attach(keyOwner)

        surfaceBackdrop.accessibilityIdentifier = "keyboard-shared-inset"
        surfaceBackdrop.layer.zPosition = -1
        inputView.addSubview(surfaceBackdrop)
        let surface = KeyboardSurfaceView(frame: inputView.bounds)
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surface.layer.zPosition = 200
        surface.period.onInsert = { [weak self] in self?.routeProxyText($0) }
        surface.period.onDelete = { [weak self] in self?.routeProxyCommand(.delete) }
        surface.bottomBar.onNumbers = { KeyboardState.shared.presentNumbersArea() }
        surface.bottomBar.onLetters = { KeyboardState.shared.presentArea(.letters) }
        surface.bottomBar.onEmoji = { KeyboardState.shared.presentArea(.emoji) }
        surface.bottomBar.onDictation = { KeyboardState.shared.presentArea(.keys) }
        surface.bottomBar.onInsert = { [weak self] in self?.routeProxyText($0) }
        surface.bottomBar.onReturn = { [weak self] in self?.routeProxyCommand(.returnKey) }
        surface.bottomBar.spaceControl.onTap = { [weak self] in self?.routeProxyCommand(.space) }
        surface.bottomBar.spaceControl.onCursorBegan = {}
        surface.bottomBar.spaceControl.onCursorMoved = { [weak self] in self?.applyCursorStep($0) }
        surface.bottomBar.spaceControl.onCursorEnded = { [weak self] in self?.cursorPreferredColumn = nil }
        surface.emoji.onInsert = { [weak self] in self?.routeProxyText($0) }
        surface.emoji.onCategoryChanged = { [weak self] index in
            guard self?.controllerID == KeyboardState.shared.activeControllerID else { return }
            KeyboardState.shared.setEmojiCategorySelectionIndex(index)
        }
        surface.emojiDelete.onDelete = { [weak self] in self?.routeProxyCommand(.delete) }
        surface.emojiDelete.onDeleteWord = { [weak self] in self?.deletePreviousWord() }
        surface.emojiCategory.onIndexChanged = { index in
            KeyboardState.shared.selectEmojiCategory(at: index)
        }
        inputView.addSubview(surface)
        keyboardSurfaceView = surface

        keyboardModeButton = makeKeyboardActionButton(identifier: "letter-mode", label: "Open letter keyboard") { [weak self] in
            self?.presentArea(.letters)
        }
        emojiButton = makeKeyboardActionButton(identifier: "emoji-picker", label: "Open emoji picker") { [weak self] in
            self?.presentArea(.emoji)
        }
        let numbers = KeyboardKeyTouchControl()
        numbers.accessibilityIdentifier = "number-layer"
        numbers.accessibilityLabel = "Open symbols keyboard"
        numbers.isAccessibilityElement = true
        numbers.accessibilityTraits = .button
        numbers.configurePageSwitch(tap: { [weak self] in self?.presentNumbersArea() },
            hold: { [weak self] in self?.presentArea(.letters) }, holdLabel: "Open letter keyboard")
        numberButton = numbers
        returnButton = makeKeyboardActionButton(identifier: "return-key", label: "Insert return") { [weak self] in
            self?.routeProxyCommand(.returnKey)
        }
        voiceBoardButton = makeKeyboardActionButton(
            identifier: "return-to-dictation-board",
            label: "Back to dictation"
        ) { [weak self] in
            KeyboardState.shared.closeArea()
            _ = self
        }
        micButton = makeKeyboardActionButton(identifier: "dictate-button", label: "Hold to dictate", installPrimaryAction: false) { }
        if let micButton = micButton as? DictationMicButton {
            micButton.onTouchDown = { [weak self] in self?.handleMicTouchDown() }
            micButton.onTouchUp = { [weak self] in self?.handleMicTouchUp() }
            micButton.onTouchCancelled = { [weak self] in self?.handleMicTouchCancelled() }
        }
        (micButton as? DictationMicButton)?.onAccessibilityActivate = {
            let state = KeyboardState.shared
            switch state.dictationStatus {
            case .requested, .recording:
                state.handleMicPressEnded()
            case .idle, .ready, .failed:
                // The recovery control owns the app handoff now. Dictation never
                // silently opens the app, so this only ever finishes a session.
                state.handleMicPressEnded()
            case .transcribing, .processing:
                return false
            }
            return true
        }
        micButton?.accessibilityHint = String(localized: "Press and hold to dictate. Release to finish.")
        // Separate owner for the app handoff. It occupies the same frame as the
        // mic and exactly one of the two is ever visible, so the slot keeps a
        // single hit target and neither control has to interpret the other's
        // state.
        recoveryButton = makeKeyboardActionButton(
            identifier: "open-saiity-button",
            label: "Open sAiity to prepare dictation",
            installPrimaryAction: false
        ) { [weak self] in
            self?.openDictusForRecovery()
        }
        (recoveryButton as? KeyboardRecoveryButton)?.onOpen = { [weak self] in self?.openDictusForRecovery() }
        recoveryButton?.accessibilityHint = String(localized: "Opens sAiity so dictation can be prepared.")
        let space = SpaceTrackingButton.TrackingControl()
        space.accessibilityIdentifier = "space-key"
        space.accessibilityLabel = "Space"
        space.accessibilityTraits = .button
        space.onTap = { [weak self] in
            self?.routeProxyCommand(.space)
        }
        space.onCursorMoved = { [weak self] in self?.applyCursorStep($0) }
        space.onCursorEnded = { [weak self] in self?.cursorPreferredColumn = nil }
        spaceButton = space
        serviceToggle = makeKeyboardActionButton(identifier: "dictation-service-toggle", label: "Keyboard dictation") {
            let state = KeyboardState.shared
            state.setKeyboardDictationEnabled(!state.keyboardDictationEnabled)
        }
        let more = KeyboardActionButton(type: .custom)
        more.accessibilityIdentifier = "keyboard-more"
        more.accessibilityLabel = "More keyboard actions"
        more.showsMenuAsPrimaryAction = true
        more.changesSelectionAsPrimaryAction = false
        more.backgroundColor = .clear
        more.isExclusiveTouch = false
        more.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.keyboardMoreMenuItems() ?? [])
            }
        ])
        moreButton = more
        let boardDelete = KeyboardDeleteRepeatControl()
        boardDelete.onDelete = { [weak self] in self?.routeProxyCommand(.delete) }
        boardDelete.onDeleteWord = { [weak self] in self?.deletePreviousWord() }
        boardDeleteButton = boardDelete
        [keyboardModeButton, emojiButton, numberButton, micButton, recoveryButton,
         spaceButton, returnButton, voiceBoardButton, moreButton, boardDeleteButton]
            .compactMap { $0 }.forEach {
            controls.addSubview($0)
        }
        if let serviceToggle {
            controls.addSubview(serviceToggle)
        }
        setVoiceActionControlsHidden(true)
    }

    /// Rebuilt when the native menu opens so field-specific actions stay current.
    func keyboardMoreMenuItems() -> [UIMenuElement] {
        let state = KeyboardState.shared
        let paste = UIAction(title: state.isOneTimeCodeField ? "Insert one-time code" : "Paste",
                             image: UIImage(systemName: "doc.on.clipboard")) { [weak self] _ in self?.pasteFromClipboard() }
        let dismiss = UIAction(title: "Dismiss keyboard", image: UIImage(systemName: "keyboard.chevron.compact.down")) { [weak self] _ in
            self?.handleDismissTouchDown()
        }
        let language = UIMenu(title: "Output language", image: UIImage(systemName: "character.bubble"),
                              children: LanguageMenuButton.menuItems())
        return state.dictationResultMenuItems() + [UIMenu(options: .displayInline, children: [paste, language, dismiss])]
    }

    func makeKeyboardActionButton(
        identifier: String,
        label: String,
        minimumHeight: CGFloat = VoiceOnlyKeyboardPolicy.bottomActionHitHeight,
        installPrimaryAction: Bool = true,
        action: @escaping () -> Void
    ) -> UIButton {
        let button: KeyboardActionButton
        if identifier == "dictate-button" { button = DictationMicButton(type: .system) }
        else if identifier == "open-saiity-button" { button = KeyboardRecoveryButton(type: .system) }
        else { button = KeyboardActionButton(type: .system) }
        if identifier == "dictate-button" {
            button.emitsHapticOnTouchDown = false
        }
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        button.accessibilityTraits = [.button]
        button.configuration = .plain()
        button.configuration?.contentInsets = .zero
        button.configuration?.baseForegroundColor = .label
        button.isMultipleTouchEnabled = true
        button.isExclusiveTouch = false
        // Size comes from explicit frames in layoutVoiceActionControls.
        // A heightAnchor here would opt the control into Auto Layout and pin it
        // to the creation frame, which drops hold-to-dictate hits.
        button.translatesAutoresizingMaskIntoConstraints = true
        button.backgroundColor = .clear
        button.tintColor = .label
        button.setTitleColor(.label, for: .normal)
        button.adjustsImageWhenHighlighted = false
        button.layer.cornerRadius = VoiceOnlyKeyboardPolicy.controlSize / 2
        // The passive face clips its own material; the hit target must not crop it.
        button.layer.masksToBounds = false
        button.configurationUpdateHandler = { control in
            control.existingKeyboardFace?.setPressed(control.isHighlighted)
        }
        if installPrimaryAction {
            button.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        }
        if identifier == "dictate-button" {
            button.hitExpansion = 20
        }
        _ = minimumHeight
        return button
    }

    private func setVoiceActionControlsHidden(_ hidden: Bool) {
        guard let controls = actionControlsView else { return }
        controls.isHidden = hidden
    }

    /// A keyboard extension can stay cached while DictusApp is opened and
    /// backgrounded again. Poll the small App Group readiness contract while
    /// visible so the mic label and hit target do not remain on a stale recovery
    /// state after the app has finished preparing its model.
    private func startAvailabilityRefreshTimer() {
        availabilityRefreshTimer?.invalidate()
        availabilityRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.isAttached, self.hasAppeared else { return }
            KeyboardState.shared.refreshFromDefaults()
            self.publishFullAccessHandshake()
            self.layoutVoiceActionControls()
        }
        if let availabilityRefreshTimer {
            RunLoop.main.add(availabilityRefreshTimer, forMode: .common)
        }
    }

    private func layoutVoiceActionControls(surfaceHeight: CGFloat? = nil) {
        guard let inputView, let controls = actionControlsView, controls.bounds.width > 0 else { return }
        let mode = KeyboardState.shared.areaMode
        let width = controls.bounds.width
        let requestedHeight = surfaceHeight ?? computeKeyboardHeight(for: mode)
        // Hosts can give a field a shorter keyboard. Lay out in that actual
        // height instead of shifting the 32pt accessory lane above its bounds.
        let resolvedHeight = inputView.bounds.height > 0
            ? min(requestedHeight, inputView.bounds.height) : requestedHeight
        let layout = VoiceOnlyKeyboardPolicy.layout(
            for: Double(width),
            surfaceHeight: Double(max(1, resolvedHeight)),
            controlOrder: KeyboardAccessoryOrder.current,
            topAccessoryHeight: currentSuggestionLaneHeight,
            compactChrome: !KeyboardInteractionPreferences.topBarEnabled
        )
        func inputFrame(_ frame: CGRect) -> CGRect {
            layout.inputFrame(frame, inputViewHeight: inputView.bounds.height)
        }
        surfaceBackdrop.configureInset(layout, inputHeight: inputView.bounds.height)
        // Keep subtracting the old lane until the host actually applies the new
        // window height. Repeated layout passes must not grow a hidden lane back.
        if abs(inputView.bounds.height - requestedHeight) < 0.5 {
            lastWindowAccessoryHeight = CGFloat(KeyboardInteractionPreferences.windowAccessoryHeight)
        }
        keyboardSurfaceView?.frame = inputView.bounds
        keyboardSurfaceView?.show(mode, layout: layout, inputHeight: inputView.bounds.height,
                                  fieldKeys: KeyboardState.shared.hostLetterFieldKeys)
        let isEmoji = mode == .emoji
        let isAuxiliary = mode == .panel || mode == .emoji || mode == .letters || mode == .numberPad
        let voiceBoardMode = mode == .keys || mode == .recording
        let showsTopBar = voiceBoardMode || KeyboardInteractionPreferences.topBarEnabled

        // The new keyboard grid. Mounted here, in the same place the frame is
        // computed, so the rectangle it draws into and the rectangle it resolves
        // touches in are literally the same `CGRect`.
        //
        // It owns the character rows. The shared bottom bar supplies its own
        // controls, including the period's native-mounted target.
        switch mode {
        case .letters:
            mountNextKeyboard(mode: .letters, layout: layout)
        case .panel:
            mountNextKeyboard(mode: .symbols, layout: layout)
        case .numberPad:
            mountNextKeyboard(
                mode: .numberPad(KeyboardState.shared.hostNumberPadStyle),
                layout: layout
            )
        default:
            unmountNextKeyboard()
        }

        // Material changes must never change input ownership. The transparent
        // UIKit controls remain the hit layer for both visual materials.
        let uikitOwnsVoiceChrome = voiceBoardMode

        // The overlay is a transparent hit layer, so hiding it is the only thing
        // that stops its buttons from eating touches meant for the visible surface.
        //
        // This used to force `isHidden = false` unconditionally, which undid the
        // `setVoiceActionControlsHidden` call `applyLayout` had just made for the
        // letter page. The result was invisible chrome buttons sitting on top of
        // the letter grid: a tap on the top row was swallowed by
        // `return-to-dictation-board` and switched the user straight back to the
        // dictation board, so the keyboard looked like it ignored every press.
        // Visibility has to follow the same rule as the controls inside it.
        // One native accessory owner on every page. Only visible controls claim
        // rectangles; misses pass through to the native grid, pager or bottom bar.
        let overlayVisible = true
        controls.isHidden = !overlayVisible
        controls.isUserInteractionEnabled = overlayVisible
        // The legacy bus must not claim any page drawn by NextKeyboardHost.
        // A stale symbol rectangle can otherwise win the hit test above the
        // visible grid and make a letter, number, or symbol key seem dead.
        let nextGridOwnsInput = Self.nextKeyboardModes.contains(mode)
        keyGridOwner?.isHidden = nextGridOwnsInput
        keyGridOwner?.isUserInteractionEnabled = !nextGridOwnsInput
        if nextGridOwnsInput {
            KeyGridTouchBus.deactivate()
        }
        let leftRailVisible = layout.leftRailWidth > 0
        let rightRailVisible = layout.rightRailWidth > 0
        let micVisible = uikitOwnsVoiceChrome && !layout.dictateFrame.isEmpty
        // Exactly one primary control owns this slot. `showsRecoveryAction` is the
        // single gate, so the hit owner can never contradict the SwiftUI face
        // that is mounted beside it.
        let recoveryVisible = micVisible && KeyboardState.shared.showsRecoveryAction
        let dictateVisible = micVisible && !recoveryVisible
        micButton?.frame = inputFrame(layout.dictateFrame)
        micButton?.isHidden = !dictateVisible
        micButton?.isEnabled = dictateVisible
        micButton?.isUserInteractionEnabled = dictateVisible
        recoveryButton?.frame = inputFrame(layout.dictateFrame)
        recoveryButton?.isHidden = !recoveryVisible
        recoveryButton?.isEnabled = recoveryVisible
        recoveryButton?.isUserInteractionEnabled = recoveryVisible
        keyboardModeButton?.isHidden = !uikitOwnsVoiceChrome || !leftRailVisible
        emojiButton?.isHidden = !uikitOwnsVoiceChrome || !leftRailVisible
        numberButton?.isHidden = !uikitOwnsVoiceChrome || !leftRailVisible
        spaceButton?.isHidden = !uikitOwnsVoiceChrome || layout.spaceFrame.isEmpty
        returnButton?.isHidden = !uikitOwnsVoiceChrome || !rightRailVisible
        voiceBoardButton?.isHidden = !isAuxiliary || !showsTopBar
        moreButton?.isHidden = !showsTopBar
        boardDeleteButton?.isHidden = !uikitOwnsVoiceChrome || !rightRailVisible
        let serviceToggleFrame = isAuxiliary ? layout.accessoryServiceToggleFrame : layout.dictationServiceToggleFrame
        let serviceToggleVisible = showsTopBar && (uikitOwnsVoiceChrome || isAuxiliary) && !serviceToggleFrame.isEmpty
        serviceToggle?.isHidden = !serviceToggleVisible
        serviceToggle?.isEnabled = serviceToggleVisible
        serviceToggle?.isUserInteractionEnabled = serviceToggleVisible
        serviceToggle?.accessibilityTraits = KeyboardState.shared.keyboardDictationEnabled ? [.button, .selected] : [.button]
        // Keep the keyboard hosting view registered with UIKit. Only the
        // SwiftUI visual content is non-hittable; native siblings own input.
        hostingController?.view.isUserInteractionEnabled = true
        hostingController?.view.layer.zPosition = 0
        controls.layer.zPosition = 100
        [keyboardModeButton, emojiButton, numberButton, spaceButton, returnButton, voiceBoardButton, moreButton, boardDeleteButton]
            .compactMap { $0 }
            .forEach {
                $0.isEnabled = !$0.isHidden
                $0.isUserInteractionEnabled = !$0.isHidden
            }
        keyboardModeButton?.frame = inputFrame(layout.chromeLettersFrame)
        emojiButton?.frame = inputFrame(layout.chromeEmojiFrame)
        numberButton?.frame = inputFrame(layout.chromeNumbersFrame)
        numberButton?.holdDuration = KeyboardDeletion.holdRecognitionDuration
        micButton?.accessibilityValue = KeyboardState.shared.dictationStatus.recordingLabel
        micButton?.accessibilityLabel = KeyboardState.shared.primaryBoardActionLabel
        recoveryButton?.accessibilityLabel = KeyboardState.shared.primaryBoardActionLabel
        micButton?.accessibilityHint = KeyboardState.shared.appNeedsAppAction
            ? "Tap to open sAiity and prepare dictation. Press and hold to dictate."
            : "Press and hold to dictate. Release to finish."
        spaceButton?.frame = inputFrame(layout.spaceFrame)
        returnButton?.frame = inputFrame(layout.chromeReturnFrame)
        voiceBoardButton?.frame = inputFrame(layout.accessoryDictationBoardFrame)
        moreButton?.frame = inputFrame(CGRect(
            x: VoiceOnlyKeyboardPolicy.accessoryEdgeInset,
            y: 0,
            width: VoiceOnlyKeyboardPolicy.languageVisualWidth,
            height: VoiceOnlyKeyboardPolicy.suggestionLaneHeight
        ))
        if let serviceToggle {
            serviceToggle.frame = inputFrame(serviceToggleFrame)
            serviceToggle.accessibilityLabel = KeyboardState.shared.keyboardDictationEnabled
                ? "Disable keyboard dictation" : "Enable keyboard dictation"
            serviceToggle.accessibilityValue = KeyboardState.shared.keyboardDictationEnabled ? "On" : "Off"
            serviceToggle.accessibilityHint = "Turns keyboard dictation on or off."
        }
        boardDeleteButton?.frame = inputFrame(layout.boardDeleteFrame)
        // A layout pass during a drag must not reset its selected cell.
        if emojiCategoryScrubber?.isTracking != true {
            emojiCategoryScrubber?.setCurrentIndex(KeyboardState.shared.emojiCategorySelectionIndex)
        }
        [keyboardModeButton, emojiButton, numberButton, micButton, spaceButton, returnButton, voiceBoardButton, moreButton]
            .compactMap { $0 }
            .forEach { $0.layer.cornerRadius = $0.bounds.height / 2 }
        spaceButton?.layer.cornerRadius = (spaceButton?.bounds.height ?? 0) / 2
        micButton?.layer.cornerRadius = (micButton?.bounds.height ?? 0) / 2
        updateNativeControlFaces()
        inputView.bringSubviewToFront(controls)
        if let surface = keyboardSurfaceView, !surface.isHidden {
            inputView.bringSubviewToFront(surface)
        }
        // UIKit hit testing uses subview order, not CALayer.zPosition. Publish
        // input owners explicitly after their frames and visibility are ready.
        (inputView as? KeyboardInputView)?.nativeTouchOwners = [
            nextKeyboardHost?.gridView, keyboardSurfaceView, controls
        ].compactMap { $0 }
    }

    @objc private func handleMicTouchDown() {
        let state = KeyboardState.shared
        // Preserve the state the user actually saw. A readiness refresh can
        // complete in the same run-loop turn and otherwise turn a recovery tap
        // into a short, unrecognized hold.
        let wasShowingRecovery = state.showsRecoveryAction
        state.refreshFromDefaults()
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardHitTrace",
            instanceID: controllerID,
            action: "handleMicTouchDown",
            details: "wasShowingRecovery=\(wasShowingRecovery) needsAppAction=\(state.appNeedsAppAction) failedRequiresApp=\(state.failedRequiresApp) status=\(state.dictationStatus.rawValue)"
        ))
        // Readiness may change mid-touch. Recovery opens immediately; recording
        // still waits for the shared hold threshold so a tap cannot start audio.
        guard !micTouchActive else { return }
        micTouchActive = true
        // Feedback is the touch. Opening the app is checked after that, so a
        // refused URL cannot make the press itself feel dead.
        HapticFeedback.playInputClick()
        micButton?.isHighlighted = true
        state.accessoryDictationActive = state.areaMode == .letters || state.areaMode == .emoji || state.areaMode == .panel || state.areaMode == .numberPad
        micHoldRecognized = false
        if state.dictationStatus.isCancellationStage {
            // A second touch is an explicit cancel while the current round is
            // starting, transcribing, or being cleaned up. Do this on touchDown
            // so cancellation does not wait for the hold recognizer.
            state.cancelActiveDictation()
            // Keep ownership until release. Otherwise touch-up's recovery
            // fallback could open the app immediately after cancelling.
            micButton?.isHighlighted = false
            state.accessoryDictationActive = false
            layoutVoiceActionControls()
            return
        }
        if wasShowingRecovery || state.showsRecoveryAction {
            // Recovery is a tap action. Waiting for the speaking hold threshold
            // made the visible "Open sAiity" control feel unresponsive.
            openDictusForRecovery()
            return
        }
        // Ready-state dictation starts with the finger. The old hold timer made
        // a real press feel late and was easy to miss in a three-second hold.
        self.micHoldRecognized = true
        state.handleMicPressBegan()
    }

    @objc private func handleDismissTouchDown() {
        dismissKeyboard()
    }

    @objc private func handleMicTouchUp() {
        let state = KeyboardState.shared
        // A foreground handoff can consume touch-up. If UIKit delivered only
        // the end of a recovery touch, still honor the visible action once.
        guard micTouchActive else {
            state.refreshFromDefaults()
            if !state.isOpeningForDictation && (state.appNeedsAppAction || state.failedRequiresApp) {
                openDictusForRecovery()
            }
            return
        }
        micHoldTimer?.invalidate()
        micHoldTimer = nil
        micTouchActive = false
        micButton?.isHighlighted = false
        if micHoldRecognized {
            state.handleMicPressEnded()
        }
        micHoldRecognized = false
        state.accessoryDictationActive = false
        layoutVoiceActionControls()
    }

    @objc private func handleMicTouchCancelled() {
        // iOS cancels the physical touch when our foreground handoff hides the
        // keyboard. That is not a user release and must not cancel the request.
        if KeyboardState.shared.isOpeningForDictation {
            micHoldTimer?.invalidate()
            micHoldTimer = nil
            micTouchActive = false
            micHoldRecognized = false
            micButton?.isHighlighted = false
            return
        }
        handleMicTouchUp()
    }

    private func openDictusForRecovery() {
        KeyboardState.shared.openDictusForRecovery()
        layoutVoiceActionControls()
    }

    private func updateNativeControlFaces() {
        let hasResult = KeyboardState.shared.dictationUndoAvailable
        moreButton?.accessibilityValue = hasResult ? "Last dictation available" : nil
        let state = KeyboardState.shared
        let fieldKeys = HostInputTraits.letterFieldKeys(for: textDocumentProxy)
        returnButton?.accessibilityLabel = fieldKeys.returnTitle
        for (button, text, symbol) in [
            (keyboardModeButton, "ABC", nil), (numberButton, "123", nil),
            (emojiButton, nil, "face.smiling"),
            (returnButton, fieldKeys.returnTitle == "return" ? nil : fieldKeys.returnTitle,
             fieldKeys.returnTitle == "return" ? "return" : nil),
            (voiceBoardButton, nil, "mic.fill"),
            (moreButton, nil, "ellipsis")
        ] as [(UIControl?, String?, String?)] {
            guard let button, !button.isHidden else { continue }
            let compactCommand = button === keyboardModeButton || button === numberButton || button === emojiButton
            let size = compactCommand
                ? CGSize(width: VoiceOnlyKeyboardPolicy.bottomBarVisualHeight, height: VoiceOnlyKeyboardPolicy.bottomBarVisualHeight)
                : button === returnButton ? VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: button.bounds.size)
                : VoiceOnlyKeyboardPolicy.commandVisualSize(for: button.bounds.size)
            let accessory = button === voiceBoardButton || button === moreButton
            let submit = button === returnButton && fieldKeys.returnTitle != "return"
            button.keyboardFace.configure(text: text, symbol: symbol, visualSize: size,
                radius: accessory ? size.height / 2 : CommandKeyStyle.cornerRadius,
                tint: submit ? .saiityAction : nil,
                foreground: submit ? .saiityOnAction : button === voiceBoardButton ? .saiityAction : .label,
                textPointSize: CommandKeyStyle.textSize,
                textWeight: accessory ? .medium : .semibold, role: accessory ? .accessory : .control,
                holdSymbol: button === numberButton && !KeyboardInteractionPreferences.topBarEnabled ? "keyboard" : nil)
        }
        if let spaceButton, !spaceButton.isHidden {
            spaceButton.keyboardFace.configure(
                visualSize: CGSize(width: spaceButton.bounds.width, height: VoiceOnlyKeyboardPolicy.bottomBarVisualHeight),
                radius: CommandKeyStyle.cornerRadius, textWeight: .regular, role: .input)
        }
        if let boardDeleteButton, !boardDeleteButton.isHidden {
            boardDeleteButton.keyboardFace.configure(symbol: CommandKeyStyle.deleteSymbolName,
                visualSize: VoiceOnlyKeyboardPolicy.bottomBarVisualSize(for: boardDeleteButton.bounds.size))
        }
        if let serviceToggle, !serviceToggle.isHidden {
            let enabled = state.keyboardDictationEnabled
            let accessory = state.areaMode != .keys && state.areaMode != .recording
            let size = VoiceOnlyKeyboardPolicy.commandVisualSize(for: serviceToggle.bounds.size)
            serviceToggle.keyboardFace.configure(symbol: enabled ? "power.circle.fill" : "power", visualSize: size,
                radius: accessory ? size.height / 2 : CommandKeyStyle.cornerRadius,
                foreground: enabled ? .saiityAction : .secondaryLabel, role: .accessory)
        }
        if let micButton, !micButton.isHidden {
            let style = KeyboardDictationFaceStyle(status: state.dictationStatus, finishing: state.isFinishingRecording)
            micButton.keyboardFace.configure(text: state.dictationBoardTitle, symbol: state.dictationBoardSymbol,
                visualSize: micButton.bounds.size, radius: micButton.bounds.height / 2,
                primary: true, tint: style.fill, foreground: style.foreground,
                symbolForeground: style.symbolForeground)
        }
        if let recoveryButton, !recoveryButton.isHidden {
            let style = KeyboardDictationFaceStyle(status: .idle)
            recoveryButton.keyboardFace.configure(text: state.recoveryBoardTitle,
                symbol: state.isOpeningForDictation ? "ellipsis" : "arrow.up.right.square.fill",
                visualSize: recoveryButton.bounds.size, radius: recoveryButton.bounds.height / 2,
                primary: true, tint: style.fill, foreground: style.foreground,
                symbolForeground: style.symbolForeground)
        }
    }

    private func closeNumberPanel() {
        KeyboardState.shared.closeArea()
    }

    private func presentNumbersArea() {
        KeyboardState.shared.presentNumbersArea()
    }

    private func presentArea(_ mode: KeyboardAreaMode) {
        KeyboardState.shared.presentArea(mode)
    }

    // MARK: - New keyboard

    /// The rebuilt key grid, when the user is on a page it owns.
    ///
    /// Owned by the controller and created with it, never registered globally. A
    /// controller iOS has cached and then discarded tears this down with itself,
    /// which is the structural difference from the shared touch bus it replaces.
    private var nextKeyboardHost: NextKeyboardHost?

    /// The pages the new grid draws, so the SwiftUI tree can stand aside.
    static let nextKeyboardModes: Set<KeyboardAreaMode> = [.letters, .panel, .numberPad]

    private func mountNextKeyboard(
        mode: NextKeyboardHost.Page,
        layout: VoiceOnlyKeyboardPolicy.Layout
    ) {
        guard let inputView else { return }
        let host = nextKeyboardHost ?? {
            let created = NextKeyboardHost()
            created.delegate = self
            nextKeyboardHost = created
            return created
        }()
        // Above the hosted SwiftUI content and the voice-control overlay. The
        // overlay is transparent input, so anything above it wins the touch.
        host.gridView.layer.zPosition = 500
        let frame = NextKeyboardHost.gridFrame(
            for: layout,
            surfaceHeight: layout.surfaceFrame.height,
            page: mode
        )
        let commandRowCenterY: CGFloat? = {
            if case .numberPad = mode { return nil }
            return layout.inputFrame(layout.boardDeleteFrame,
                                     inputViewHeight: inputView.bounds.height).midY
        }()
        host.mount(in: inputView,
                   frame: layout.inputFrame(frame, inputViewHeight: inputView.bounds.height),
                   page: mode, commandRowCenterY: commandRowCenterY)
        host.updateHitPrediction(
            SuggestionState.shared.adaptiveTouchPrediction,
            enabled: KeyboardInteractionPreferences.adaptiveHitPredictionEnabled
        )
    }

    private func unmountNextKeyboard() {
        nextKeyboardHost?.unmount()
    }

    private func refreshVisibleKeyboardLayoutIfNeeded() {
        guard isAttached, isOnScreen else { return }
        let language = SupportedLanguage.active
        let layout = LayoutType.active
        guard language != lastTypingLanguage || layout != lastTypingLayout else { return }
        lastTypingLanguage = language
        lastTypingLayout = layout
        nextKeyboardHost?.refreshKeyLayout()
        refreshAdaptiveTouchContext()
    }

    // MARK: - New keyboard host

    func nextKeyboardHost(_ host: NextKeyboardHost, perform command: KeyboardCommand) {
        routeProxyCommand(command)
    }

    func nextKeyboardHost(_ host: NextKeyboardHost, insert text: String) {
        routeProxyText(text)
    }

    func nextKeyboardHostDidRequestLetters(_ host: NextKeyboardHost) {
        KeyboardState.shared.presentArea(.letters)
    }

    func nextKeyboardHostDidRequestSymbols(_ host: NextKeyboardHost) {
        presentNumbersArea()
    }

    func nextKeyboardHostDidRequestEmoji(_ host: NextKeyboardHost) {
        KeyboardState.shared.presentArea(.emoji)
    }

    func nextKeyboardHostDidRequestDictation(_ host: NextKeyboardHost) {
        KeyboardState.shared.presentArea(.keys)
    }

    func nextKeyboardHostDidRequestWordDeletion(_ host: NextKeyboardHost) {
        deletePreviousWord()
    }

    func nextKeyboardHost(_ host: NextKeyboardHost, didSelectSymbolPage id: String) {
        // The host has already switched its own page; the state only needs to know
        // the area is still the symbol panel.
        if KeyboardState.shared.areaMode != .panel {
            KeyboardState.shared.presentArea(.panel)
        }
    }

    func routeProxyCommand(_ command: KeyboardCommand) {
        KeyboardState.shared.interruptDictationUndoForTyping()
        let ownerAvailable = KeyboardInputRouter.canRoute(
            isAttached: isAttached,
            isOnScreen: isOnScreen,
            activeControllerID: KeyboardState.shared.activeControllerID,
            controllerID: controllerID
        )
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
        nextKeyboardHost?.gridView.commitPendingCharacter()
        defer { refreshAdaptiveTouchContext() }
        if command == .space {
            guard ownerAvailable else {
                DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
                return
            }
            SuggestionState.shared.handleSpace(proxy: textDocumentProxy)
            return
        }
        Self.routeProxyCommand(
            command,
            enabled: ownerAvailable,
            deleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) }
        )
    }

    func routeProxyText(_ text: String) {
        KeyboardState.shared.interruptDictationUndoForTyping()
        let ownerAvailable = KeyboardInputRouter.canRoute(
            isAttached: isAttached,
            isOnScreen: isOnScreen,
            activeControllerID: KeyboardState.shared.activeControllerID,
            controllerID: controllerID
        )
        guard ownerAvailable else {
            DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "proxyTextRejected",
                details: "textLength=\(text.count) ownerAvailable=false attached=\(isAttached) onScreen=\(isOnScreen) active=\(KeyboardState.shared.activeControllerID ?? "none") self=\(controllerID)"
            ))
            return
        }
        nextKeyboardHost?.gridView.commitPendingCharacter()
        let insertionStart = CFAbsoluteTimeGetCurrent()
        textDocumentProxy.insertText(text)
        let insertionMS = (CFAbsoluteTimeGetCurrent() - insertionStart) * 1_000
        proxyInsertionCount += 1
        proxyInsertionTotalMS += insertionMS
        proxyInsertionMaxMS = max(proxyInsertionMaxMS, insertionMS)
        // Keep stalled-host evidence without formatting/writing a log per key.
        if insertionMS >= 16 {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController", instanceID: controllerID,
                action: "proxyTextInserted_slow",
                details: "textLength=\(text.count) insertMs=\(String(format: "%.1f", insertionMS))"
            ))
        }
        SuggestionState.shared.noteTypedCharacter(text)
        refreshAdaptiveTouchContext()
    }

    /// Clear the previous word's targets immediately, then coalesce proxy reads
    /// outside touch dispatch. The host can withhold context; nil stays static.
    private func refreshAdaptiveTouchContext() {
        guard KeyboardState.shared.activeControllerID == controllerID else { return }
        adaptiveContextGeneration &+= 1
        let generation = adaptiveContextGeneration
        guard isAttached, isOnScreen, KeyboardState.shared.areaMode == .letters else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.adaptiveContextGeneration == generation,
                  self.isAttached, self.isOnScreen,
                  KeyboardState.shared.activeControllerID == self.controllerID,
                  KeyboardState.shared.areaMode == .letters else { return }
            let totalStart = CFAbsoluteTimeGetCurrent()
            let policy = HostInputTraits.policy(for: self.textDocumentProxy)
            let afterPolicy = CFAbsoluteTimeGetCurrent()
            SuggestionState.shared.hostPolicy = policy
            let context = policy.suggestionsAllowed
                ? self.textDocumentProxy.documentContextBeforeInput.map { String($0.suffix(240)) }
                : nil
            let afterContext = CFAbsoluteTimeGetCurrent()
            SuggestionState.shared.updateAdaptiveTouchPrediction(context: context)
            let afterPredict = CFAbsoluteTimeGetCurrent()
        }
    }

    /// Reads the general pasteboard only after an explicit user tap. The inserted
    /// value is kept unchanged so OTPs and multilingual clipboard text are not
    /// normalized by the keyboard.
    private func pasteFromClipboard() {
        let ownerAvailable = isAttached && isOnScreen
            && KeyboardState.shared.activeControllerID == controllerID
        guard ownerAvailable else {
            HapticFeedback.actionRefused()
            return
        }
        guard let value = KeyboardState.readPasteboardText(from: .general), !value.isEmpty else {
            HapticFeedback.actionRefused()
            KeyboardState.shared.presentStatusMessage(
                "Clipboard is empty.",
                reason: "clipboardEmpty",
                timeoutReason: "clipboardEmpty-timeout"
            )
            return
        }
        routeProxyText(value)
        HapticFeedback.playInputClick()
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

    /// Delete the token immediately before the caret using the same policy as
    /// every SwiftUI keyboard surface. The first ordinary tap remains a single
    /// `deleteBackward()` through `KeyboardCommand.delete`.
    func deletePreviousWord() {
        KeyboardState.shared.interruptDictationUndoForTyping()
        let ownerAvailable = isAttached && isOnScreen
            && KeyboardState.shared.activeControllerID == controllerID
        guard ownerAvailable else {
            DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "wordDeletionRejected",
                details: "ownerAvailable=false"
            ))
            return
        }
        nextKeyboardHost?.gridView.commitPendingCharacter()
        let length = KeyboardDeletion.previousWordLength(
            in: textDocumentProxy.documentContextBeforeInput
        )
        guard length > 0 else { return }
        for _ in 0..<length {
            textDocumentProxy.deleteBackward()
        }
        refreshAdaptiveTouchContext()
    }

    // MARK: - Vendored keyboard owner

    func didTriggerKey(_ key: KeyDefinition) {
        switch key.type {
        case .input(let value, _):
            if value == KeyboardLayouts.emojiKeyGlyph {
                presentArea(.emoji)
            } else {
                routeProxyText(value)
            }
        case .backspace:
            routeProxyCommand(.delete)
        case .returnkey:
            routeProxyCommand(.returnKey)
        case .spacebar:
            routeProxyCommand(.space)
        case .symbols:
            presentNumbersArea()
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
        KeyboardState.shared.lastShiftTapDate = .distantPast
    }

    func didTriggerHoldKey(_ key: KeyDefinition) {
        if case .backspace = key.type {
            deletePreviousWord()
        }
    }

    func applyCursorStep(_ step: KeyboardCursorStep) {
        KeyboardState.shared.interruptDictationUndoForTyping()
        guard !step.isEmpty else { return }
        let ownerAvailable = isAttached && isOnScreen
            && KeyboardState.shared.activeControllerID == controllerID
        guard ownerAvailable else {
            DictationErrorChannel.record("Keyboard input is unavailable. Please reopen the keyboard.", disposition: .requiresApp)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "cursorRejected",
                details: "characters=\(step.characters) lines=\(step.lines) ownerAvailable=false"
            ))
            return
        }
        nextKeyboardHost?.gridView.commitPendingCharacter()
        if step.characters != 0 || step.lines != 0 {
            let now = Date.timeIntervalSinceReferenceDate
            if now - lastCursorStepTime > 0.5 {
                cursorPreferredColumn = nil
            }
            lastCursorStepTime = now
            let offset = KeyboardCursorTrackpad.visualOffset(
                beforeInput: textDocumentProxy.documentContextBeforeInput,
                afterInput: textDocumentProxy.documentContextAfterInput,
                columns: step.characters,
                rows: step.lines,
                wrap: cursorSoftWrapWidth(),
                preferredColumn: &cursorPreferredColumn
            )
            if offset != 0 {
                // One proxy call keeps fast drags responsive; feedback still
                // follows every character crossed by the resolved movement.
                textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
                if step.lines == 0 {
                    for _ in 0..<abs(offset) {
                        HapticFeedback.cursorMoved()
                    }
                } else {
                    HapticFeedback.cursorMoved()
                }
                refreshAdaptiveTouchContext()
            }
        }
    }

    /// Approximate characters per visual line so vertical drags can cross
    /// wrapped paragraphs, not only hard newlines. Single-line field types
    /// stay unwrapped so Y cannot jump inside an email or URL.
    private func cursorSoftWrapWidth() -> Int {
        switch textDocumentProxy.keyboardType {
        case .emailAddress, .URL, .numberPad, .phonePad, .decimalPad,
             .asciiCapableNumberPad, .webSearch:
            return 0
        default:
            break
        }
        let width = max(view.bounds.width, view.window?.bounds.width ?? 0)
        if width < KeyboardCursorTrackpad.pointsPerCharacter {
            return 40
        }
        return max(16, Int((width - 24) / KeyboardCursorTrackpad.pointsPerCharacter))
    }

    private func toggleLetterShift() {
        let now = Date()
        if now.timeIntervalSince(KeyboardState.shared.lastShiftTapDate) < KeyboardShiftState.doubleTapWindow {
            KeyboardState.shared.lastShiftTapDate = .distantPast
            return
        }

        KeyboardState.shared.lastShiftTapDate = now
    }

    func longpress(movedCursor step: KeyboardCursorStep) {
        applyCursorStep(step)
    }

    func longpressDidCancel() { }

    // MARK: - Text Change

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        KeyboardState.shared.refreshHostInputTraits(from: textDocumentProxy)
        SuggestionState.shared.reconcilePendingAutocorrection(proxy: textDocumentProxy)
        refreshAdaptiveTouchContext()
        // Re-check the dictation undo offer against the changed document (#266).
        // Deliberately a re-check and not a clear: the keyboard's own insertion is
        // itself a text change, so clearing here would cancel the offer at the
        // moment it is made.
        KeyboardState.shared.revalidateDictationUndo()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        KeyboardState.shared.refreshHostInputTraits(from: textDocumentProxy)
        SuggestionState.shared.noteSelectionChanged(proxy: textDocumentProxy)
        refreshAdaptiveTouchContext()
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
