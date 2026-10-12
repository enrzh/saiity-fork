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
private struct RecordingModelRecoveryView: View {
    @StateObject private var manager = ModelManager()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ModelManagerView(modelManager: manager)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var transcriptionResult: String?
    @State private var showResult = false
    @State private var showError = false
    @State private var errorMessage: String?
    /// Brief "Copié !" feedback when user taps the transcription result.
    @State private var showCopiedFeedback = false
    /// Two-step dismissal: animate out first, then reset coordinator status.
    @State private var isDismissing = false
    @ObservedObject private var replay = RecordingReplay.shared
    @State private var showRecoveryModels = false

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
                HStack(spacing: 8) {
                    DictusLogo(height: 22, foregroundOnly: true).accessibilityHidden(true)
                    Text("Syllivra").font(.headline)
                }
                Spacer()
                    Button(action: dismissRecording) {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .accessibilityLabel("Close dictation")
            }
            .padding(.horizontal, 24).padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if replay.available && !DictationSessionLivenessPolicy.isActive(coordinator.status) {
                        Button(replay.playing ? "Stop replay" : replay.trimmed ? "Replay last 60 seconds" : "Replay recording") { replay.toggle() }
                            .buttonStyle(.plain).frame(minHeight: 44).accessibilityIdentifier("dictation.replay")
                        if let message = replay.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(showResult ? "Transcript" : statusTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if displayedStatus == .recording {
                                Text(formattedTime).font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if showResult, let result = transcriptionResult {
                            DictationTranscriptResult(result: result, original: coordinator.lastOriginalResult,
                                onRestore: { transcriptionResult = $0 },
                                onFeedback: savedResultFeedback(for: result),
                                translationFallback: coordinator.lastTranslationFallbackReason != nil)
                        } else if showError, let error = errorMessage {
                            Label("Something interrupted dictation", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text(userFacingError(error)).foregroundStyle(.secondary)
                            if DictationProblem(error).action != .retry {
                                Button("Try dictation again", action: retryRecording).buttonStyle(.bordered)
                                    .disabled(!coordinator.canChangeSpeechRuntime)
                            }
                        } else {
                            Text(!coordinator.realtimeTranscript.isEmpty ? coordinator.realtimeTranscript :
                                 displayedStatus == .recording ? "Listening…" : "Your words will appear here.")
                                .font(.title2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !coordinator.realtimeTranscript.isEmpty {
                                Text("Live preview. Your final text appears when you finish.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                }
                .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 16) {
                if showResult {
                    Image(systemName: "checkmark").foregroundStyle(Color.saiityAction)
                        .frame(height: 28).accessibilityHidden(true)
                } else {
                    SaiityVoiceSignal(level: displayedStatus == .recording ? coordinator.bufferEnergy.max() ?? 0 : nil)
                        .frame(height: 28)
                }
                if mode == .onboarding && showResult {
                    Button("Continue", action: completeOnboarding)
                        .buttonStyle(SaiityPrimaryActionStyle())
                } else {
                    micOrStopButton
                }
            }
            .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $showRecoveryModels) {
            RecordingModelRecoveryView()
        }
        .opacity(isDismissing ? 0 : 1)
        .animation(AccessibilityMotionPolicy.animation(reduceMotion: reduceMotion), value: showResult)
        .animation(AccessibilityMotionPolicy.animation(reduceMotion: reduceMotion), value: showCopiedFeedback)
        .onChange(of: coordinator.status) { _, newStatus in
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
            // Reopening Speak restores its result; setup does not adopt an old dictation.
            if coordinator.status == .failed || (coordinator.status == .ready && mode == .standalone) {
                handleStatusChange(coordinator.status)
            }
            advanceDisplayedStatus(to: coordinator.status)
        }
        .onDisappear {
            replay.stop()
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
            if showError, let errorMessage {
                switch DictationProblem(errorMessage).action {
                case .openSettings:
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    return
                case .models, .repairDownload: showRecoveryModels = true; return
                case .retry: break
                }
            }
            switch coordinator.status {
            case .recording:
                stopRecording()
            case .requested, .transcribing, .processing:
                cancelRecording()
            default:
                startRecording()
            }
        } label: {
            SaiityVoiceActionLabel(
                LocalizedStringKey(showError ? recoveryTitle : isCancellationStage ? cancellationTitle :
                    coordinator.status == .recording ? "Finish dictation" : showResult ? "Dictate again" : "Start dictation"),
                systemImage: isCancellationStage ? "xmark" : coordinator.status == .recording ? "stop.fill" : nil)
        }
        .buttonStyle(SaiityPrimaryActionStyle())
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
            if mode == .onboarding { dismiss() }
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
        DictationProblem(message).message
    }

    private var recoveryTitle: String {
        let problem = DictationProblem(errorMessage ?? "")
        return problem.action == .repairDownload ? "Models & downloads" : problem.actionTitle
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

    private func savedResultFeedback(for result: String) -> ((RecentDictation.Feedback) -> Void)? {
        guard AppGroup.defaults.object(forKey: SharedKeys.historyEnabled) as? Bool ?? true else { return nil }
        guard let item = RecentDictations.load(from: AppGroup.defaults).first(where: {
            $0.text == String(result.trimmingCharacters(in: .whitespacesAndNewlines).prefix(RecentDictations.maxTextCharacters))
        }) else { return nil }
        return { RecentDictations.recordFeedback($0, for: item.id, in: AppGroup.defaults) }
    }

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
        if showResult { return "Ready to use" }
        switch displayedStatus {
        case .idle, .ready: return "Ready to record"
        case .requested: return "Starting dictation"
        case .recording, .transcribing, .processing: return displayedStatus.recordingLabel
        case .failed: return "Dictation failed"
        }
    }

    private func statusAnnouncement(for status: DictationStatus) -> String {
        switch status {
        case .idle: return "Ready to record"
        case .requested: return "Starting dictation"
        case .recording, .transcribing, .processing:
            return NSLocalizedString(status.recordingLabel, comment: "Dictation progress")
        case .ready: return "Dictation complete"
        case .failed: return "Dictation failed. Try again or close."
        }
    }
}

#Preview("Recording - Idle") {
    RecordingView(mode: .standalone)
        .environmentObject(DictationCoordinator.shared)
}
