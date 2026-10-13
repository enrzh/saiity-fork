import SwiftUI
import SyllivraKernel

/// Keyboard handoff reflects the actual session, with no timer or simulated waveform.
struct SwipeBackOverlayView: View {
    @EnvironmentObject private var coordinator: DictationCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                DictusLogo(height: 32, foregroundOnly: true)
                SaiityPageHeader(title: "Dictation from your keyboard",
                                 subtitle: "Finish speaking here, then return to the app you were typing in.")
                VStack(alignment: .leading, spacing: 20) {
                    Label(statusTitle, systemImage: coordinator.status == .recording ? "mic.fill" : "waveform")
                        .font(.title2.weight(.semibold))
                    if coordinator.status == .failed {
                        Text(DictationErrorChannel.current ?? String(localized: "The dictation failed."))
                            .foregroundStyle(.secondary)
                        Button("Try again") { coordinator.resetStatus(); coordinator.startDictation() }
                            .buttonStyle(SaiityPrimaryActionStyle())
                    } else if coordinator.status == .recording {
                        Text("The microphone is listening. Stop when you have finished.").foregroundStyle(.secondary)
                        Button { coordinator.stopDictation() } label: {
                            Label("Finish recording", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(SaiityPrimaryActionStyle())
                    } else if coordinator.status == .ready, let result = coordinator.lastResult {
                        Text(result).textSelection(.enabled)
                    } else if coordinator.status == .idle {
                        Button("Start dictation") { coordinator.startDictation() }.buttonStyle(SaiityPrimaryActionStyle())
                    } else {
                        ProgressView("Working on your device")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 18) {
                    Label("1. Speak and finish recording", systemImage: "mic")
                    Label("2. Wait for your transcript", systemImage: "text.alignleft")
                    Label("3. Return to your previous app", systemImage: "arrow.uturn.backward")
                    Text("Use the back-to-app link at the top of the screen, or swipe along the bottom edge. The Syllivra keyboard inserts the completed text.")
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
        case .requested: return "Starting dictation"
        case .recording: return "Listening"
        case .transcribing: return "Preparing your text"
        case .processing: return "Applying your writing options"
        case .ready: return "Ready to use"
        case .failed: return "Dictation interrupted"
        }
    }
}
