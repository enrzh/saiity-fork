// DictusApp/Onboarding/GlobeKeyTutorialPage.swift
// Stage 4: real keyboard switch and first dictation.
import SwiftUI
import UIKit
import DictusCore

struct GlobeKeyTutorialPage: View {
    let onComplete: () -> Void
    let onReturnToSetup: () -> Void

    /// WHY @EnvironmentObject coordinator:
    /// The user may dictate during this tutorial via the Dictus keyboard, which
    /// goes through DictationCoordinator. If we don't reset the coordinator before
    /// completing onboarding, HomeView will show the "last transcription card"
    /// from this test dictation — which is not the desired landing screen.
    @EnvironmentObject var coordinator: DictationCoordinator

    @State private var dictusKeyboardActive = false
    @State private var textFieldContent = ""
    @State private var firstDictationVerified = false
    @State private var awaitingInsertion = false
    @State private var accessibilityAnnouncement = ""
    @AppStorage(SharedKeys.onboardingFullAccessVerified, store: AppGroup.defaults) private var fullAccessVerified = false
    @State private var dictationFailed = false
    @State private var fullAccessRequired = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(dictusKeyboardActive ? "Dictate a short phrase" : "Switch to sAiity", systemImage: dictusKeyboardActive ? "mic" : "globe")
                .font(.title2.weight(.semibold))
            Text(dictusKeyboardActive ? "Tap the microphone in the sAiity keyboard. Your words should appear below." : "Tap and hold the globe key, then choose sAiity.")
                .font(.body).foregroundStyle(.secondary)
            KeyboardDetectingTextField(text: $textFieldContent, placeholder: "Your dictated text will appear here", autoFocus: true, onKeyboardChange: handleKeyboardChange)
                .frame(minHeight: 150, maxHeight: 260)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Dictation result")
            if firstDictationVerified {
                OnboardingSuccessView(onComplete: finishOnboarding)
                    .frame(minHeight: 180)
            } else {
                if fullAccessRequired {
                    Text("Full Access required. Switch on Allow Full Access for sAiity in Settings, then return to the keyboard.")
                        .font(.caption).foregroundStyle(.red)
                    HStack {
                        Button("Open Settings", action: openSettings).buttonStyle(.borderedProminent)
                        Button("Return to setup", action: onReturnToSetup).buttonStyle(.bordered)
                    }
                }
                Text(accessibilityAnnouncement.isEmpty ? "Waiting for a real dictation insertion" : accessibilityAnnouncement)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Dictation status")
                if dictationFailed {
                    Button("Return to setup", action: onReturnToSetup)
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 20)
        .onAppear { observeTranscriptionReady() }
        .onDisappear {
            DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.transcriptionReady)
            DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.statusChanged)
        }
        .onChange(of: textFieldContent) { _, newValue in
            guard awaitingInsertion, !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard fullAccessVerified else { return }
            firstDictationVerified = true
            awaitingInsertion = false
            accessibilityAnnouncement = "First dictation inserted. Setup is complete."
            UIAccessibility.post(notification: .announcement, argument: accessibilityAnnouncement)
            PersistentLog.log(.onboardingGlobeTutorialTextDetected)
        }
    }

    private func handleKeyboardChange(_ isDictus: Bool) {
        dictusKeyboardActive = isDictus
        guard isDictus else { return }
        fullAccessVerified = AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified)
        guard fullAccessVerified else {
            fullAccessRequired = true
            dictationFailed = true
            accessibilityAnnouncement = "Full Access required before dictation can start."
            UIAccessibility.post(notification: .announcement, argument: accessibilityAnnouncement)
            return
        }
        fullAccessRequired = false
        accessibilityAnnouncement = "sAiity keyboard is active. Tap the microphone to dictate."
        UIAccessibility.post(notification: .announcement, argument: accessibilityAnnouncement)
        PersistentLog.log(.onboardingDictusKeyboardActivated)
    }

    private func observeTranscriptionReady() {
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.transcriptionReady) {
            DispatchQueue.main.async {
                guard dictusKeyboardActive else { return }
                fullAccessVerified = AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified)
                guard fullAccessVerified else {
                    fullAccessRequired = true
                    dictationFailed = true
                    accessibilityAnnouncement = "Full Access required before dictation can start."
                    return
                }
                textFieldContent = ""
                awaitingInsertion = true
                accessibilityAnnouncement = "Dictation received. Waiting for insertion."
                UIAccessibility.post(notification: .announcement, argument: accessibilityAnnouncement)
            }
        }
        DarwinNotificationCenter.addObserver(for: DarwinNotificationName.statusChanged) {
            DispatchQueue.main.async {
                guard AppGroup.defaults.string(forKey: SharedKeys.dictationStatus) == DictationStatus.failed.rawValue else { return }
                dictationFailed = true
                accessibilityAnnouncement = "Dictation failed. Return to setup to check keyboard access and model readiness."
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Final cleanup before dismissing onboarding.
    ///
    /// WHY reset the coordinator here:
    /// If the user dictated during the globe key tutorial, the DictationCoordinator
    /// holds the last transcription in `lastResult`. Without clearing it, HomeView
    /// displays a "last transcription card" as soon as the user lands on the main
    /// screen — which is not the expected fresh Home state.
    private func finishOnboarding() {
        coordinator.lastResult = nil
        coordinator.resetStatus()
        onComplete()
    }
}

// MARK: - KeyboardSwitchAnimation

/// Animated 4-frame illustration showing the globe key → keyboard picker → sAiity flow.
///
/// WHY real SwiftUI elements instead of simplified rectangles:
/// The previous version used abstract rectangles for keys which didn't look like iOS.
/// This version uses real text labels for AZERTY keys, proper spacing, and native
/// materials — matching the approach used in KeyboardSetupPage (Animation A) where
/// real Toggle components made the fake Settings card convincing.
///
/// The animation loops through 4 states:
/// Frame 0: Normal English keyboard
/// Frame 1: Picker appears with the current keyboard
/// Frame 2: Picker with sAiity highlighted (user's target)
/// Frame 3: sAiity keyboard visible (with branding on spacebar)
private struct KeyboardSwitchAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationFrame = 0
    @State private var globePressed = false
    @State private var animationTimer: Timer?

    private let frameDurations: [TimeInterval] = [1.5, 1.5, 1.5, 2.0]

    private let row0 = ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"]
    private let row1 = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]
    private let row2 = ["Z", "X", "C", "V", "B", "N", "M"]

    /// Display name for the system keyboard in the picker.
    private let systemKeyboardName = "English (US)"

    /// Display name for the space bar in non-Dictus frames.
    private let spaceLabel = "space"

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Base keyboard illustration
            fakeKeyboard(isDictus: animationFrame == 3)

            // Picker overlay for frames 1-2
            if animationFrame == 1 || animationFrame == 2 {
                fakeKeyboardPicker(dictusHighlighted: animationFrame == 2)
                    .padding(.leading, 8)
                    .padding(.bottom, 44)
                    .transition(
                        reduceMotion
                            ? .identity
                            : .opacity.combined(with: .scale(scale: 0.9, anchor: .bottomLeading))
                    )
            }
        }
        .animation(
            AccessibilityMotionPolicy.permitsAnimation(reduceMotion: reduceMotion)
                ? .easeInOut(duration: 0.3)
                : nil,
            value: animationFrame
        )
        .animation(
            AccessibilityMotionPolicy.permitsAnimation(reduceMotion: reduceMotion)
                ? .easeInOut(duration: 0.15)
                : nil,
            value: globePressed
        )
        .onAppear {
            if !reduceMotion {
                startAnimation()
            }
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    // MARK: - Fake Keyboard

    /// Realistic keyboard using actual SwiftUI text labels.
    /// Non-interactive (allowsHitTesting(false)).
    /// WHY isDictus branches the layout:
    /// - isDictus == false: native iOS keyboard with standard globe/mic at bottom
    /// - isDictus == true: sAiity keyboard with toolbar (EN label + blue mic pill)
    ///   replicating the real sAiity keyboard design
    private func fakeKeyboard(isDictus: Bool) -> some View {
        VStack(spacing: 5) {
            // sAiity keyboard has a toolbar at the top (EN label + blue mic pill)
            if isDictus {
                dictusToolbar
                    .padding(.bottom, 2)
            }

            // Row 0: A Z E R T Y U I O P (or Q W E R T Y U I O P)
            HStack(spacing: 4) {
                ForEach(row0, id: \.self) { key in
                    keyCell(key)
                }
            }

            // Row 1
            HStack(spacing: 4) {
                ForEach(row1, id: \.self) { key in
                    keyCell(key)
                }
            }

            // Row 2: shift + letters + delete
            HStack(spacing: 4) {
                Image(systemName: "shift")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(keyCapsule(dark: true))

                ForEach(row2, id: \.self) { key in
                    keyCell(key)
                }

                Image(systemName: "delete.left")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(keyCapsule(dark: true))
            }

            // Row 3: 123 + emoji + space + return
            HStack(spacing: 4) {
                Text("123")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(keyCapsule(dark: true))

                Text("😊")
                    .font(.body)
                    .frame(width: 36, height: 36)
                    .background(keyCapsule(dark: true))

                // Space bar
                Text(spaceLabel)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(keyCapsule(dark: false))

                Image(systemName: "return")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(width: 64, height: 36)
                    .background(keyCapsule(dark: true))
            }

            // Bottom row: globe + mic (only shown on the native keyboard, not on Dictus)
            // WHY hidden on Dictus: Dictus has its own toolbar at the top with the mic pill.
            if !isDictus {
                HStack {
                    // Globe icon — highlighted when "pressed" during the animation transition
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                        .foregroundStyle(globePressed ? Color.primary : Color.secondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(globePressed ? 0.18 : 0))
                        )

                    Spacer()

                    Image(systemName: "mic")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .allowsHitTesting(false)
    }

    /// Dictus keyboard toolbar: language indicator on the left + blue mic pill on the right.
    /// Matches the real Dictus keyboard design.
    private var dictusToolbar: some View {
        HStack {
            // Language label
            Text("EN")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            // Blue mic pill — matches real Dictus mic button
            Image(systemName: "mic.fill")
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                )
        }
        .padding(.horizontal, 8)
    }

    /// A single keyboard key cell.
    private func keyCell(_ letter: String) -> some View {
        Text(letter)
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(keyCapsule(dark: false))
    }

    /// Key background capsule — light for letter keys, darker for function keys.
    private func keyCapsule(dark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.primary.opacity(dark ? 0.08 : 0.05))
    }

    // MARK: - Fake Keyboard Picker

    /// Keyboard picker popup matching iOS style.
    private func fakeKeyboardPicker(dictusHighlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pickerRow("Keyboard Settings...", dimmed: true)
            Divider().opacity(0.2)
            pickerRow(systemKeyboardName, highlighted: !dictusHighlighted)
            Divider().opacity(0.2)
            pickerRow("Emoji")
            Divider().opacity(0.2)
            pickerRow("sAiity", highlighted: dictusHighlighted, accent: dictusHighlighted)

            // Keyboard type icons (dock/split/full)
            HStack(spacing: 12) {
                ForEach(["keyboard.onehanded.left", "keyboard", "keyboard.onehanded.right"], id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThickMaterial)
        )
    }

    private func pickerRow(_ text: String, dimmed: Bool = false, highlighted: Bool = false, accent: Bool = false) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(accent ? .accentColor : (dimmed ? .secondary : .primary))
            .fontWeight(highlighted || accent ? .medium : .regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlighted ? Color.primary.opacity(0.1) : (accent ? Color.accentColor.opacity(0.12) : Color.clear))
                    .padding(.horizontal, 4)
            )
    }

    // MARK: - Animation Timer

    private func startAnimation() {
        animationFrame = 0
        globePressed = false
        scheduleNextFrame()
    }

    private func scheduleNextFrame() {
        let duration = frameDurations[animationFrame]

        // WHY globe press timing:
        // During frame 0 (normal keyboard), press the globe ~0.3s before
        // the picker appears, so the user sees the "click" happening before
        // the picker opens. The globe stays pressed while the picker is shown
        // (frames 1-2) and releases when we return to frame 3 (Dictus active).
        if animationFrame == 0 {
            // Schedule globe press ~0.3s before picker appears
            DispatchQueue.main.asyncAfter(deadline: .now() + duration - 0.3) {
                globePressed = true
            }
        }

        animationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            animationFrame = (animationFrame + 1) % 4
            // Release globe press when we transition to frame 3 (Dictus keyboard)
            // and also ensure it's false when we loop back to frame 0
            if animationFrame == 3 || animationFrame == 0 {
                globePressed = false
            }
            scheduleNextFrame()
        }
    }
}

// MARK: - KeyboardDetectingTextField

/// UIKit text view wrapper that detects keyboard input mode changes.
///
/// WHY UITextView (not UITextField):
/// UITextField is single-line only — long dictated text overflows horizontally
/// and gets clipped. UITextView supports multi-line editing with automatic
/// wrapping, which matches user expectations for dictation output.
///
/// WHY UIViewRepresentable instead of SwiftUI TextEditor:
/// We need access to the UITextView's `textInputMode` property to detect when
/// the user switches to the Dictus keyboard (via long-press globe). SwiftUI's
/// TextEditor doesn't expose this. This wrapper:
/// 1. Observes UITextInputMode.currentInputModeDidChangeNotification
/// 2. Reads the UITextView's textInputMode.identifier
/// 3. Calls onKeyboardChange(isDictus:) when the active keyboard changes
private struct KeyboardDetectingTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var autoFocus: Bool = false
    let onKeyboardChange: (Bool) -> Void

    func makeUIView(context: Context) -> PlaceholderTextView {
        let textView = PlaceholderTextView()
        textView.placeholder = placeholder
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = .label
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        // Remove default inner padding so text aligns to the top-left
        textView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences

        // Listen for keyboard switches
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.inputModeDidChange(_:)),
            name: UITextInputMode.currentInputModeDidChangeNotification,
            object: nil
        )

        // Auto-focus immediately to bring up the keyboard without delay.
        if autoFocus {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }

        return textView
    }

    func updateUIView(_ textView: PlaceholderTextView, context: Context) {
        if textView.text != text {
            textView.text = text
            textView.refreshPlaceholder()
        }
    }

    static func dismantleUIView(_ textView: PlaceholderTextView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: KeyboardDetectingTextField
        weak var textView: PlaceholderTextView?

        init(_ parent: KeyboardDetectingTextField) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            self.textView = textView as? PlaceholderTextView
            checkInputMode(for: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            (textView as? PlaceholderTextView)?.refreshPlaceholder()
        }

        @objc func inputModeDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            checkInputMode(for: textView)
        }

        private func checkInputMode(for textView: UITextView) {
            guard let inputMode = textView.textInputMode else {
                reportInputMode(identifier: nil, primaryLanguage: nil)
                return
            }

            reportInputMode(
                identifier: inputMode.value(forKey: "identifier") as? String,
                primaryLanguage: inputMode.primaryLanguage
            )
        }

        private func reportInputMode(identifier: String?, primaryLanguage: String?) {
            let isDictus = KeyboardSetupStatus.isDictusKeyboardIdentifier(identifier)
            let activeIdentifiers = UITextInputMode.activeInputModes
                .compactMap { $0.value(forKey: "identifier") as? String }
                .joined(separator: ",")

            PersistentLog.log(.diagnosticProbe(
                component: "OnboardingKeyboard",
                instanceID: "input-mode",
                action: "inputModeObserved",
                details: "identifier=\(identifier ?? "nil") primaryLanguage=\(primaryLanguage ?? "nil") isDictus=\(isDictus) activeIdentifiers=\(activeIdentifiers)"
            ))

            DispatchQueue.main.async {
                self.parent.onKeyboardChange(isDictus)
            }
        }
    }
}

/// UITextView subclass that shows a placeholder when empty.
///
/// WHY a subclass: UITextView has no built-in placeholder (unlike UITextField).
/// We overlay a UILabel that shows/hides based on whether the text view is empty.
private class PlaceholderTextView: UITextView {
    var placeholder: String = "" {
        didSet { placeholderLabel.text = placeholder; refreshPlaceholder() }
    }

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textColor = .placeholderText
        label.font = UIFont.preferredFont(forTextStyle: .body)
        return label
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupPlaceholder()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlaceholder()
    }

    private func setupPlaceholder() {
        addSubview(placeholderLabel)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    func refreshPlaceholder() {
        placeholderLabel.isHidden = !text.isEmpty
    }
}
