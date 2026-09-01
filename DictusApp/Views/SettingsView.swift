import AVFoundation
import SwiftUI
import UIKit
import DictusCore

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedKeys.liveActivityEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var liveActivityEnabled = true
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var polishEnabled = true
    @State private var microphonePermission = AVAudioSession.sharedInstance().recordPermission
    @StateObject private var modelManager = ModelManager()
    @State private var diagnosticResult = AppGroupDiagnostic.run()

    var body: some View {
        List {
            Section("Dictation") {
                if PolishAvailability.isToggleVisible {
                    Toggle("Automatic dictation cleanup", isOn: $polishEnabled)
                        .accessibilityHint("Cleans up dictation after speech recognition. Turn off to pass through the raw transcription.")
                    Text(polishEnabled ? "Cleanup runs after dictation." : "Cleanup is off; dictation passes through as transcribed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                polishStateFooter
            }
            Section("Keyboard") {
                NavigationLink { ModelManagerView(modelManager: modelManager) } label: {
                    Label("Models", systemImage: "square.stack.3d.up.fill")
                }
            }
            Section("Translation & Cleanup") {
                Toggle("Live Activity", isOn: $liveActivityEnabled)
                    .onChange(of: liveActivityEnabled) { _, enabled in
                        if LiveActivityStateMachine.shouldStartStandbyActivity(
                            isEnabled: enabled,
                            isBackground: scenePhase == .background
                        ) {
                            LiveActivityManager.shared.startStandbyActivity()
                        } else if !enabled {
                            LiveActivityManager.shared.stopStandbyActivity()
                        }
                    }
            }
            Section("Feedback") {
                Button(action: openSystemSettings) {
                    Label("Microphone", systemImage: "mic.fill")
                    Spacer()
                    Text(permissionLabel).foregroundStyle(.secondary)
                }
            }
            Section("Privacy") {
                if let privacyURL = URL(string: "https://aiity.de/privacy") {
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                }
            }
            Section("Support") {
                NavigationLink { DebugLogView() } label: {
                    Label("Debug Logs", systemImage: "wrench.and.screwdriver.fill")
                }
                NavigationLink { DiagnosticDetailView(result: diagnosticResult) } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                NavigationLink { LicensesView() } label: {
                    Label("Licenses", systemImage: "doc.text.fill")
                }
                Link(destination: URL(string: "https://github.com/enrzh")!) {
                    Label("Get Support", systemImage: "questionmark.circle.fill")
                }
            }
        }
        .contentMargins(.bottom, 88, for: .scrollContent)
        .navigationTitle("Settings")
        .onAppear {
            microphonePermission = AVAudioSession.sharedInstance().recordPermission
            diagnosticResult = AppGroupDiagnostic.run()
        }
    }

    @ViewBuilder private var polishStateFooter: some View {
        let state = PolishAvailability.state
        if state != .available {
            VStack(alignment: .leading, spacing: 6) {
                Text(polishStateMessage(for: state)).font(.caption).foregroundStyle(.secondary)
                if PolishAvailability.canOpenSystemSettings(for: state) {
                    Button("Open iPhone Settings", action: openSystemSettings).font(.caption.bold())
                }
            }
        }
    }

    private var permissionLabel: String {
        switch microphonePermission {
        case .granted: return "Allowed"
        case .denied: return "Denied"
        case .undetermined: return "Not Set"
        @unknown default: return "Unknown"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func polishStateMessage(for state: PolishAvailabilityState) -> String {
        switch state {
        case .available: return ""
        case .appleIntelligenceNotEnabled: return "Apple Intelligence is required for polish. Enable it in iPhone Settings."
        case .modelNotReady: return "The Apple Intelligence model is downloading. Try again in a few minutes."
        case .deviceNotEligible: return "Apple Intelligence is not supported on this device."
        case .osTooOld: return "Polish requires iOS 26 or later."
        case .sdkMissing: return "Polish is not available in this build."
        case .other(let reason): return "Apple Intelligence is unavailable (\(reason))."
        }
    }
}
