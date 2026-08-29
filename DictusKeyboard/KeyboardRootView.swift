// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import Combine
import DictusCore

/// Root SwiftUI view for the keyboard extension chrome (toolbar + full-area
/// presentations).
///
/// This voice-only SwiftUI view renders:
/// - ToolbarView (always visible when not recording)
/// - RecordingOverlay (replaces keyboard area during recording)
/// - EmojiPickerView (shown below the toolbar)
///
/// Which of those it renders is decided by a single `KeyboardAreaMode` read from
/// KeyboardState (#271) — the same value KeyboardViewController switches on for
/// the layout, so the two layers cannot drift apart.
///
/// All visible keyboard controls are part of this SwiftUI voice surface.
struct KeyboardRootView: View {
    let controllerID: String
    @ObservedObject private var state = KeyboardState.shared
    @ObservedObject private var waveformDriver = KeyboardWaveformDriver.shared
    @State private var instanceID = String(UUID().uuidString.prefix(8))
    @State private var pressStarted = false

    /// Whether the Pro entry is hidden from the panel bar.
    ///
    /// WHY @State refreshed on open rather than an observed ProStatusManager:
    /// the extension reads Pro status from the App Group, and a subscription
    /// cannot be bought while the keyboard is the frontmost surface — so a read
    /// each time the panel opens is both sufficient and cheaper than keeping an
    /// ObservableObject alive in a 50 MB process.
    @State private var isProActive = false

    /// WHY @Environment here: openURL is the SwiftUI way to open URLs.
    /// Keyboard extensions cannot access UIApplication.shared, but SwiftUI's
    /// openURL environment action works because it goes through the responder
    /// chain. We capture it here and inject it into KeyboardState via .onAppear.
    @Environment(\.openURL) private var openURL

    /// Toolbar height within the 220pt voice surface.
    private let toolbarHeight: CGFloat = 52

    /// What this view presents.
    ///
    /// The mode is owned by KeyboardState; what this adds is the presenter check
    /// on `.recording` only. iOS caches UIInputViewController instances and their
    /// KeyboardRootViews keep receiving updates long after they leave the window
    /// (#128 / #134) — a stale view that rendered the overlay produced the
    /// duplicate grey panel in #116.
    ///
    /// WHY the pickers are deliberately NOT gated the same way, keeping the
    /// pre-#271 split: `.recording` is pushed from another process and can arrive
    /// while no controller owns the keyboard (`activeID=none`, #260), so it needs
    /// an owner to be worth drawing. A picker is opened by a key the user just
    /// touched on the visible keyboard; gating it on ownership would blank the
    /// keyboard area for the whole #260 window instead of merely delaying an
    /// overlay.
    ///
    /// That window is now closed from the other side: an area whose owner was
    /// deallocated is marked reclaimable, and the controller that is actually in a
    /// window claims it on the next status change (#260). This check is what makes
    /// the claim visible — ownership moving to our controllerID is what flips this
    /// from `.keys` to `.recording`.
    ///
    /// The legacy `activeControllerID == nil` fallback that used to mask #128 is
    /// deliberately not reinstated: with #128 fixed, stale controllers are dormant.
    private var presentedMode: KeyboardAreaMode {
        let mode = state.areaMode
        guard mode == .recording else { return mode }
        guard state.activeControllerID == controllerID, state.isKeyboardVisible else {
            return .keys
        }
        return mode
    }

    /// The toolbar as it renders above a full-area presentation.
    ///
    /// The suggestion slots stay empty: voice input does not expose a typing grid, so
    /// there is no word being typed to suggest for. Tapping the mic needs no
    /// dismissal call — `.recording` supersedes whatever fills the area.
    ///
    /// `isPanelOpen` picks between the two presentations of the same toolbar:
    /// the dictation cockpit, and the panel header that replaces the mic with the
    /// gear (#241).
    private func fullAreaToolbar(isPanelOpen: Bool = false) -> some View {
        ToolbarView(
            hasFullAccess: state.controller?.hasFullAccess ?? false,
            dictationStatus: state.dictationStatus,
            onMicTap: { state.startRecording() },
            statusMessage: state.statusMessage,
            messageProbeRootViewID: instanceID,
            messageProbeControllerID: controllerID,
            showsPolishUnavailable: state.polishUnavailable,
            // Undo survives opening the emoji picker (#266): browsing emoji is not
            // typing, and the insertion is still the tail of the field. The panel
            // presentation ignores these — its bar has no centre slot.
            showsDictationUndo: state.dictationUndoAvailable,
            onDictationUndoTap: { state.performDictationUndo() },
            isPanelOpen: isPanelOpen,
            onPanelToggle: { togglePanel() },
            onSettingsTap: { leavePanel { state.openDictusApp(intent: "settings") } },
            isProActive: isProActive,
            onProTap: { leavePanel { state.openDictusApp(intent: "pro") } }
        )
        .frame(height: toolbarHeight)
    }

    /// Close the panel, then run whatever takes the user out of the keyboard.
    ///
    /// WHY (#241 device feedback): the panel is a menu, not a place. Both entries
    /// in its bar send the user to DictusApp, and coming back to a keyboard still
    /// showing the menu they left is disorienting — the task that opened it is
    /// over. Resetting before leaving also means the restore in
    /// `KeyboardViewController.viewWillAppear` has nothing to put back.
    private func leavePanel(_ action: @escaping () -> Void) {
        state.presentAreaMode(.keys)
        action()
    }

    /// Open or close the hamburger panel.
    ///
    /// The mode change is the only state involved — `KeyboardState` owns it and
    /// both layers read it (#271), so no flag is duplicated here.
    ///
    /// WHY the mode change itself is deliberately NOT animated: the branches of
    /// the `switch` below are the single child of a VStack, so a transition on
    /// the branch keeps the outgoing and incoming views alive together and the
    /// VStack stacks them — the outgoing bar above the incoming one. Two stacked
    /// bars is the exact artefact this design was reshaped to avoid, and a
    /// transient one is no better. The bar therefore swaps instantly, ☰ to ✕ in
    /// place, and the fade lives inside the panel body where it stacks nothing.
    ///
    /// Nothing here animates geometry either: the hosting height and bottom
    /// anchor move synchronously in UIKit, in the same turn as the mode change,
    /// deliberately (#99, #142).
    private func togglePanel() {
        isProActive = ProStatusManager.isProActiveStatic
        state.togglePanelPresentation()
    }

    var body: some View {
        GeometryReader { proxy in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AUTO")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(.thinMaterial, in: Capsule())
                        Spacer()
                        utilityButton(
                            systemName: "globe",
                            accessibilityLabel: "Switch keyboard",
                            identifier: "switch-keyboard"
                        ) {
                            state.controller?.advanceToNextInputMode()
                        }
                    }
                    .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.controlSize), alignment: .leading)

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        Text(dictationTitle)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Image(systemName: dictationSymbol)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(dictationColor)
                            .symbolEffect(.pulse, isActive: state.dictationStatus == .recording)
                            .dictusGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .frame(width: 148, height: 94)
                        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    guard !pressStarted else { return }
                                    pressStarted = true
                                    state.startRecording()
                                }
                                .onEnded { _ in
                                    defer { pressStarted = false }
                                    guard state.dictationStatus == .requested
                                            || state.dictationStatus == .recording
                                    else { return }
                                    state.requestStop()
                                }
                        )
                        .accessibilityIdentifier("dictate-button")
                        .accessibilityLabel("Hold to dictate")
                        .accessibilityValue(dictationTitle)

                        Text(state.statusMessage ?? " ")
                            .font(.caption2)
                            .foregroundStyle(state.dictationStatus == .failed ? .red : .secondary)
                            .lineLimit(1)
                            .frame(height: 14)
                    }
                    .frame(width: 160)

                    Spacer(minLength: 0)

                    VStack(spacing: CGFloat(VoiceOnlyKeyboardPolicy.railSpacing)) {
                        utilityButton(
                            systemName: "delete.backward",
                            accessibilityLabel: "Delete backward",
                            identifier: "delete-backward"
                        ) {
                            state.controller?.textDocumentProxy.deleteBackward()
                        }
                        utilityButton(
                            systemName: "return",
                            accessibilityLabel: "Insert return",
                            identifier: "return-key"
                        ) {
                            state.controller?.textDocumentProxy.insertText("\n")
                        }
                        utilityButton(
                            systemName: "at",
                            accessibilityLabel: "Insert at sign",
                            identifier: "at-key"
                        ) {
                            state.controller?.textDocumentProxy.insertText("@")
                        }
                        utilityButton(
                            systemName: "keyboard.chevron.compact.down",
                            accessibilityLabel: "Dismiss keyboard",
                            identifier: "dismiss-keyboard"
                        ) {
                            state.controller?.dismissKeyboard()
                        }
                    }
                    .frame(width: CGFloat(VoiceOnlyKeyboardPolicy.controlSize))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, CGFloat(VoiceOnlyKeyboardPolicy.verticalPadding))
            .frame(
                maxWidth: .infinity,
                minHeight: CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeight),
                maxHeight: CGFloat(VoiceOnlyKeyboardPolicy.surfaceHeight)
            )
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var dictationTitle: String {
        switch state.dictationStatus {
        case .idle, .ready: return "Hold to dictate"
        case .requested: return "Getting ready..."
        case .recording: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .processing: return "Cleaning up..."
        case .failed: return "Try again"
        }
    }

    private var dictationSymbol: String {
        switch state.dictationStatus {
        case .recording: return "waveform"
        case .requested, .transcribing, .processing: return "ellipsis"
        case .failed: return "arrow.clockwise"
        case .idle, .ready: return "mic.fill"
        }
    }

    private var dictationColor: Color {
        switch state.dictationStatus {
        case .recording: return .blue
        case .failed: return .orange
        default: return .primary
        }
    }

    private func utilityButton(
        systemName: String,
        accessibilityLabel: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

}
