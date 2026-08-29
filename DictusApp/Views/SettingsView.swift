import AVFoundation
import SwiftUI
import UIKit
import DictusCore

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedKeys.liveActivityEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var liveActivityEnabled = true
    @AppStorage(SharedKeys.transcriptionLanguage, store: UserDefaults(suiteName: AppGroup.identifier)) private var transcriptionLanguage = TranscriptionLanguageMode.autoDetect.storedValue
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var polishEnabled = false
    @State private var microphonePermission = AVAudioSession.sharedInstance().recordPermission

    var body: some View {
        List {
            Section("Transcription") {
                Picker("Language", selection: $transcriptionLanguage) {
                    ForEach(TranscriptionLanguageMode.settingsOptions, id: \.storedValue) { mode in
                        Text(mode.settingsDisplayName).tag(mode.storedValue)
                    }
                }
                if PolishAvailability.isToggleVisible { Toggle("Polish transcription", isOn: $polishEnabled) }
                polishStateFooter
            }
            Section("Features") {
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
            Section("Permissions") {
                Button(action: openSystemSettings) {
                    Label("Microphone", systemImage: "mic.fill")
                    Spacer()
                    Text(permissionLabel).foregroundStyle(.secondary)
                }
            }
            Section("Privacy") {
                Link(destination: URL(string: "https://saiity.de/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
            }
            Section("Legal & Help") {
                NavigationLink { LicensesView() } label: {
                    Label("Licenses", systemImage: "doc.text.fill")
                }
                Link(destination: URL(string: "mailto:support@saiity.de")!) {
                    Label("Contact Support", systemImage: "questionmark.circle.fill")
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { microphonePermission = AVAudioSession.sharedInstance().recordPermission }
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
