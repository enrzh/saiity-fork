import SwiftUI
import DictusCore

/// Keyboard handoff reflects the actual session, with no timer or simulated waveform.
struct SwipeBackOverlayView: View {
    @EnvironmentObject private var coordinator: DictationCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DictusLogo(height: 52)
                SaiityPageHeader(eyebrow: "FROM YOUR KEYBOARD", title: "Your words are coming with you.",
                                 subtitle: "Finish speaking here, then return to the app you were typing in.")
                VStack(alignment: .leading, spacing: 20) {
                    Label(statusTitle, systemImage: coordinator.status == .recording ? "mic.fill" : "waveform")
                        .font(.title2.weight(.semibold))
                    if coordinator.status == .failed {
                        Text(DictationErrorChannel.current ?? String(localized: "The dictation failed."))
                            .foregroundStyle(.secondary)
                        Button("Try again") { coordinator.resetStatus(); coordinator.startDictation() }
                            .buttonStyle(.borderedProminent)
                    } else if coordinator.status == .recording {
                        Text("The microphone is listening. Stop when you have finished.").foregroundStyle(.secondary)
                        Button { coordinator.stopDictation() } label: {
                            Label("Finish recording", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    } else if coordinator.status == .ready, let result = coordinator.lastResult {
                        Text(result).textSelection(.enabled)
                    } else if coordinator.status == .idle {
                        Button("Start dictation") { coordinator.startDictation() }.buttonStyle(.borderedProminent)
                    } else {
                        ProgressView("Working on your device")
                    }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 28))
                VStack(alignment: .leading, spacing: 18) {
                    Label("1. Speak and finish recording", systemImage: "mic")
                    Label("2. Wait for your transcript", systemImage: "text.alignleft")
                    Label("3. Return to your previous app", systemImage: "arrow.uturn.backward")
                    Text("Use the back-to-app link at the top of the screen, or swipe along the bottom edge. The sAiity keyboard inserts the completed text.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var statusTitle: LocalizedStringKey {
        switch coordinator.status {
        case .idle: return "Ready to dictate"
        case .requested: return "Starting the microphone"
        case .recording: return "Listening to you"
        case .transcribing: return "Writing your words"
        case .processing: return "Tidying your transcript"
        case .ready: return "Ready to take back"
        case .failed: return "Let’s try that again"
        }
    }
}
