import AVFoundation
import SwiftUI
import UIKit
import DictusCore

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedKeys.liveActivityEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var liveActivityEnabled = true
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var polishEnabled = true
    @AppStorage(SharedKeys.hapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var hapticsEnabled = true
    @AppStorage(SharedKeys.keyPopupsEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var keyPopupsEnabled = true
    @AppStorage(SharedKeys.suggestionsEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var suggestionsEnabled = true
    @State private var keyboardLayout = KeyboardLayoutPreference.layout(for: .active)
    @State private var microphonePermission = AVAudioSession.sharedInstance().recordPermission
    @StateObject private var modelManager = ModelManager()
    @State private var diagnosticResult = AppGroupDiagnostic.run()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsIntro

                settingsPanel("Dictation", systemImage: "waveform") {
                    VStack(alignment: .leading, spacing: 14) {
                        if PolishAvailability.isToggleVisible {
                            Toggle("Automatic dictation cleanup", isOn: $polishEnabled)
                                .accessibilityHint("Cleans up dictation after speech recognition. Turn off to pass through the raw transcription.")
                            Text(polishEnabled ? "Cleanup runs after dictation." : "Cleanup is off; dictation passes through as transcribed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        polishStateFooter
                    }
                }

                settingsPanel("Keyboard", systemImage: "keyboard") {
                    VStack(spacing: 0) {
                        Picker("Keyboard layout", selection: $keyboardLayout) {
                            ForEach(LayoutType.allCases, id: \.self) { layout in
                                Text(layout.displayName).tag(layout)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: keyboardLayout) { _, layout in
                            KeyboardLayoutPreference.setLayout(layout, for: .active)
                        }
                        Divider().padding(.vertical, 6)
                        Toggle("Key popups", isOn: $keyPopupsEnabled)
                        Divider().padding(.vertical, 6)
                        Toggle("Keyboard suggestions", isOn: $suggestionsEnabled)
                            .accessibilityHint("Shows word suggestions above the keyboard-mode keys.")
                        Divider().padding(.vertical, 6)
                        NavigationLink { ModelManagerView(modelManager: modelManager) } label: {
                            Label("Models", systemImage: "square.stack.3d.up.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                settingsPanel("Activity", systemImage: "bolt.fill") {
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

                settingsPanel("Feedback", systemImage: "hand.tap.fill") {
                    VStack(spacing: 0) {
                        Toggle("Haptic feedback", isOn: $hapticsEnabled)
                        Divider().padding(.vertical, 6)
                        Button(action: openSystemSettings) {
                            HStack {
                                Label("Microphone", systemImage: "mic.fill")
                                Spacer()
                                Text(permissionLabel).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                settingsPanel("Support", systemImage: "questionmark.circle.fill") {
                    VStack(spacing: 0) {
                        NavigationLink { DebugLogView() } label: {
                            Label("Debug Logs", systemImage: "wrench.and.screwdriver.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider().padding(.vertical, 6)
                        NavigationLink { DiagnosticDetailView(result: diagnosticResult) } label: {
                            Label("Diagnostics", systemImage: "stethoscope")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider().padding(.vertical, 6)
                        NavigationLink { LicensesView() } label: {
                            Label("Licenses", systemImage: "doc.text.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let supportURL = URL(string: "https://github.com/enrzh") {
                            Divider().padding(.vertical, 6)
                            Link(destination: supportURL) {
                                Label("Get Support", systemImage: "arrow.up.right")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if let privacyURL = URL(string: "https://aiity.de/privacy") {
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Settings")
        .onAppear {
            microphonePermission = AVAudioSession.sharedInstance().recordPermission
            diagnosticResult = AppGroupDiagnostic.run()
        }
    }

    private var settingsIntro: some View {
        HStack(spacing: 12) {
            DictusLogo(height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your setup")
                    .font(.headline)
                Text("Tune sAiity to your workflow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private func settingsPanel<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
