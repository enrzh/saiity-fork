// DictusApp/Views/RecordingView.swift
// Stable-layout recording screen: waveform + mic button always in place, text appears below.
import SwiftUI
import UIKit
import DictusCore

/// Determines the context in which RecordingView is shown.
///
/// WHY a mode enum instead of separate views:
/// The recording experience should feel identical whether the user reaches it
/// from onboarding or from HomeView's "New dictation" button.
/// The only difference is what happens when the user finishes:
/// - onboarding: calls onComplete to advance onboarding
/// - standalone: user taps mic again for new recording, or X to dismiss
enum RecordingMode {
    case onboarding
    case standalone
}

/// Stable-layout recording screen with always-visible waveform and fixed mic button.
///
/// WHY stable layout instead of state-driven visibility:
/// Elements appearing/disappearing causes jarring layout shifts. The waveform and mic
/// button stay in place across all states — only their visual appearance changes:
/// - Idle: flat waveform, blue mic
/// - Recording: animated waveform, red stop button
/// - Transcribing: sinusoidal waveform, disabled shimmer mic
/// - Result: flat waveform, blue mic (ready for new recording), text below
///
/// Transcription text appears BELOW the fixed elements, so nothing moves.
struct RecordingView: View {
    let mode: RecordingMode
    var onComplete: (() -> Void)?

    @EnvironmentObject var coordinator: DictationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var transcriptionResult: String?
    @State private var showResult = false
    @State private var showError = false
    @State private var errorMessage: String?
    /// Brief "Copié !" feedback when user taps the transcription result.
    @State private var showCopiedFeedback = false
    /// Two-step dismissal: animate out first, then reset coordinator status.
    @State private var isDismissing = false

    /// The stage this screen draws, which trails `coordinator.status` by up to
    /// `TranscribingStageHold.minimumDisplayDuration` (#309).
    ///
    /// WHY this screen and not only the keyboard overlay: the two share one visual
    /// vocabulary, and someone dictating inside DictusApp waits on this screen. Fixing
    /// the flash on one surface and not the other would make them disagree about what
    /// the phone is doing within the same second.
    @State private var displayedStatus: DictationStatus = .idle

    /// The rule. Pure and tested in DictusCore; the timer below is this surface's.
    @State private var hold = TranscribingStageHold()

    /// Fires when a held stage becomes drawable. At most one is ever in flight.
    @State private var holdTask: Task<Void, Never>?

    init(mode: RecordingMode, onComplete: (() -> Void)? = nil) {
        self.mode = mode
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("sAiity", systemImage: "waveform").font(.headline)
                Spacer()
                if mode == .standalone {
                    Button(action: dismissRecording) {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityLabel("Close dictation")
                }
            }
            .padding(.horizontal, 24).padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(showResult ? "Transcript" : "Listening")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if showResult, let result = transcriptionResult {
                                ShareLink(item: result) { Image(systemName: "square.and.arrow.up") }
                                    .accessibilityLabel("Share transcript")
                            }
                        }
                        if showResult, let result = transcriptionResult {
                            Text(result).font(.title3).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                UIPasteboard.general.string = result
                                showCopiedFeedback = true
                                HapticFeedback.recordingStopped()
                                UIAccessibility.post(notification: .announcement, argument: "Copied")
                            } label: {
                                Label(showCopiedFeedback ? "Copied" : "Copy transcript",
                                      systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                            }
                            .labelStyle(.titleAndIcon)
                            .buttonStyle(.bordered)
                            if mode == .onboarding {
                                Button("Continue", action: completeOnboarding)
                                    .buttonStyle(.borderedProminent)
                            }
                        } else if showError, let error = errorMessage {
                            Label("Something interrupted dictation", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text(userFacingError(error)).foregroundStyle(.secondary)
                            Button("Try again", action: retryRecording).buttonStyle(.borderedProminent)
                        } else {
                            Text(displayedStatus == .recording ? "Listening…" : "Your words will appear here.")
                                .font(.title3).foregroundStyle(.secondary)
                            Text("Finish recording when you’re ready.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 16) {
                HStack {
                    Label(statusTitle, systemImage: displayedStatus == .recording ? "mic.fill" : "mic.slash")
                    Spacer()
                    if displayedStatus == .recording { Text(formattedTime).monospacedDigit() }
                }
                .font(.subheadline).foregroundStyle(.secondary)
                if displayedStatus == .recording {
                    ProgressView(value: Double(coordinator.bufferEnergy.max() ?? 0), total: 1)
                        .tint(.accentColor).accessibilityLabel("Microphone input level")
                }
                micOrStopButton
            }
            .padding(24).frame(maxWidth: 680)
            .background(.bar)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .opacity(isDismissing ? 0 : 1)
        .animation(AccessibilityMotionPolicy.animation(reduceMotion: reduceMotion), value: showResult)
        .animation(AccessibilityMotionPolicy.animation(reduceMotion: reduceMotion), value: showCopiedFeedback)
        .onChange(of: coordinator.status) { newStatus in
            // `handleStatusChange` is deliberately still driven by the real status: it
            // does not draw a stage, it reveals the result text and the error, and a
            // terminal status preempts the hold anyway (#309).
            handleStatusChange(newStatus)
            advanceDisplayedStatus(to: newStatus)
        }
        // A screen that appears mid-dictation adopts the stage in flight at once,
        // rather than starting from `.idle` and pretending to enter it.
        .onAppear {
            // A failure this screen was never mounted for gets read here (#320). A cold
            // start that dies puts `.failed` in place while `SwipeBackOverlayView` owns
            // the window; MainTabView inserts this view only once the overlay is gone, by
            // which time the status has stopped changing and `onChange` will never fire.
            // Only `.failed` is adopted on appear: `.ready` would replay the result card
            // and, in onboarding, its auto-advance.
            if coordinator.status == .failed {
                handleStatusChange(.failed)
            }
            advanceDisplayedStatus(to: coordinator.status)
        }
        .onDisappear {
            holdTask?.cancel()
            holdTask = nil
            // Reset, not merely cancel: `.onAppear` re-adopts the stage in flight, and
            // a decision left pending here would be re-affirmed as "already decided"
            // with no timer left to draw it. A fresh hold draws whatever it is handed.
            //
            // The drawn stage is reset with it, and the two must move together. A fresh
            // hold believes `.idle` is on screen; if the coordinator has also returned
            // to `.idle` by the time the screen comes back, `apply` answers `.unchanged`
            // and nothing reassigns `displayedStatus` -- leaving the travelling peak and
            // "Traitement..." drawn over an idle screen. Resetting only one of the two
            // is what makes them disagree.
            hold = TranscribingStageHold()
            displayedStatus = .idle
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .navigationBarHidden(true)
    }

    private var isCancellationStage: Bool {
        coordinator.status == .requested
            || coordinator.status == .transcribing
            || coordinator.status == .processing
    }

    private var cancellationTitle: String {
        switch coordinator.status {
        case .transcribing: return "Cancel transcription"
        case .processing: return "Cancel cleanup"
        default: return "Cancel dictation"
        }
    }

    private var micOrStopButton: some View {
        Button {
            switch coordinator.status {
            case .recording:
                stopRecording()
            case .requested, .transcribing, .processing:
                cancelRecording()
            default:
                startRecording()
            }
        } label: {
            HStack(spacing: 12) {
                if isCancellationStage {
                    Image(systemName: "xmark")
                } else {
                    Image(systemName: displayedStatus == .recording ? "stop.fill" : "mic.fill")
                }
                Text(isCancellationStage ? cancellationTitle :
                     displayedStatus == .recording ? "Finish recording" : "Start dictation")
                Spacer()
                if !isCancellationStage { Image(systemName: "arrow.right") }
            }
            .font(.headline).padding(.vertical, 12).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .tint(displayedStatus == .recording ? .red : .accentColor)
        .accessibilityIdentifier(isCancellationStage ? "dictation.cancel" : "dictation.start")
    }

    // MARK: - Actions

    private func startRecording() {
        // Reset previous result state
        transcriptionResult = nil
        showResult = false
        showError = false
        errorMessage = nil
        showCopiedFeedback = false

        HapticFeedback.recordingStarted()
        coordinator.startDictation()
    }

    private func retryRecording() {
        coordinator.resetStatus()
        startRecording()
    }

    private func completeOnboarding() {
        coordinator.resetStatus()
        onComplete?()
    }

    private func dismissRecording() {
        HapticFeedback.recordingStopped()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { isDismissing = true }
        let generation = coordinator.dictationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard coordinator.dictationGeneration == generation else { return }
            coordinator.resetStatus()
        }
    }

    private func stopRecording() {
        HapticFeedback.recordingStopped()
        coordinator.stopDictation()
    }

    private func cancelRecording() {
        HapticFeedback.recordingStopped()
        coordinator.cancelDictation()
    }

    private func userFacingError(_ message: String) -> String {
        message
            .replacingOccurrences(of: "Dictus", with: "sAiity")
            .replacingOccurrences(of: "dictus", with: "sAiity")
    }

    // MARK: - Stage display (#309)

    /// Move `displayedStatus` toward `status`, honouring the transcription floor.
    ///
    /// The decision is `TranscribingStageHold`'s, in DictusCore, where it is tested.
    /// What lives here is only this screen's timer — a `Task` rather than a `Timer`,
    /// because it has to be cancelled from the view and cancellation is what keeps a
    /// terminal status from ever waiting behind a stage that no longer matters.
    private func advanceDisplayedStatus(to status: DictationStatus) {
        switch hold.apply(status, now: Date()) {
        case .unchanged:
            break
        case .draw(let drawn):
            holdTask?.cancel()
            holdTask = nil
            displayedStatus = drawn
        case .hold(_, let interval):
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                if case .draw(let drawn) = hold.release(now: Date()) {
                    displayedStatus = drawn
                }
            }
        }
    }

    // MARK: - Status Handling

    private func handleStatusChange(_ newStatus: DictationStatus) {
        UIAccessibility.post(notification: .announcement, argument: statusAnnouncement(for: newStatus))
        switch newStatus {
        case .ready:
            if let result = coordinator.lastResult, !result.isEmpty {
                transcriptionResult = result
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
                    showResult = true
                }
            }
        case .failed:
            showError = true
            // The reason the app itself recorded, not the transcription property (#320).
            // `lastResult` only ever holds transcribed text and `startDictation` nils it
            // on every entry path, so reading it here was reading nil one hundred percent
            // of the time and printing the fallback -- which named the model download,
            // whatever had actually failed.
            //
            // The fallback now names nothing. A failure with no recorded reason is a
            // failure we cannot explain, and the honest sentence for that is the one that
            // explains nothing. Every cause we *can* name already writes its own message
            // at its own call site.
            errorMessage = DictationErrorChannel.current ?? String(localized: "The dictation failed.")
        default:
            break
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let totalSeconds = Int(coordinator.bufferSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var statusTitle: String {
        if showCopiedFeedback { return "Copied" }
        if showResult { return "Dictation complete" }
        switch displayedStatus {
        case .idle, .ready: return "Ready to record"
        case .requested: return "Starting dictation"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .processing: return "Processing"
        case .failed: return "Dictation failed"
        }
    }

    private func statusAnnouncement(for status: DictationStatus) -> String {
        switch status {
        case .idle: return "Ready to record"
        case .requested: return "Starting dictation"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .processing: return "Processing"
        case .ready: return "Dictation complete"
        case .failed: return "Dictation failed. Try again or close."
        }
    }
}

#Preview("Recording - Idle") {
    RecordingView(mode: .standalone)
        .environmentObject(DictationCoordinator.shared)
}
