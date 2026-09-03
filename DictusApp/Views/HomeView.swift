// DictusApp/Views/HomeView.swift
// Home dashboard showing real model readiness, dictation, and recent output.
import SwiftUI
import AVFoundation
import DictusCore

struct HomeView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @EnvironmentObject var proStatus: ProStatusManager
    @AppStorage(SharedKeys.modelReady, store: AppGroup.defaults) private var modelReady = false

    @State private var showCopiedFeedback = false
    @State private var microphonePermission = MicrophonePermissionState.undetermined
    @AppStorage(SharedKeys.serviceEnabled, store: AppGroup.defaults) private var serviceEnabled = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                greeting
                Section("Readiness") {
                    readinessSection
                }

                if let result = coordinator.lastResult, !result.isEmpty {
                    recentActivity(result: result)
                }

                if PremiumFlags.paywallVisible {
                    ProBannerView()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("sAiity")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $serviceEnabled) {
                    Label("Dictation service", systemImage: serviceEnabled ? "waveform" : "waveform.slash")
                }
                .labelsHidden()
                .tint(.accentColor)
                .accessibilityLabel("Dictation service")
                .accessibilityValue(serviceEnabled ? "On" : "Off")
            }
        }
        .onChange(of: serviceEnabled) { _, enabled in
            guard !enabled else { return }
            LiveActivityManager.shared.stopStandbyActivity()
            NotificationCenter.default.post(
                name: Notification.Name("DictusStopStandbyRequested"),
                object: nil
            )
        }
        .onAppear {
            refreshMicrophonePermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DictusOnboardingCompleted"))) { _ in
            refreshMicrophonePermission()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshMicrophonePermission()
            }
        }
    }

    private var greeting: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: serviceEnabled ? "waveform" : "waveform.slash")
                .font(.title2.weight(.medium))
                .foregroundStyle(serviceEnabled ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingTitle)
                    .font(.title2.weight(.semibold))
                Text(serviceEnabled ? "Ready for private, on-device dictation" : "Dictation service is turned off")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: readinessSymbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(readinessTitle)
                        .font(.body.weight(.semibold))
                    Text(readinessSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            if !serviceEnabled {
                Text("Turn on the service from the top right to use dictation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if microphonePermission.isRecoverable {
                Button { openSystemSettings() } label: {
                    Label("Open Settings", systemImage: "arrow.up.right")
                }
                .buttonStyle(.bordered)
            } else if !microphonePermission.isAuthorized {
                Button { requestMicrophoneAccess() } label: {
                    Label("Allow microphone", systemImage: "mic.badge.plus")
                }
                .buttonStyle(.bordered)
            }

            if microphonePermission.isAuthorized && modelReady {
                newDictationButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var newDictationButton: some View {
        Button {
            coordinator.startDictation()
        } label: {
            Label("Start dictation", systemImage: "waveform")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .controlSize(.large)
        .accessibilityIdentifier("home.newDictation")
    }

    private func recentActivity(result: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent dictation")
                .font(.headline)
            Text(result)
                .font(.body)
                .lineLimit(4)
            Button("Copy") { copy(result) }
                .buttonStyle(.bordered)
            Text(showCopiedFeedback ? "Copied" : "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(!showCopiedFeedback)
                .frame(minHeight: 20, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.recentActivity")
    }

    private func copy(_ result: String) {
        UIPasteboard.general.string = result
        HapticFeedback.recordingStopped()
        showCopiedFeedback = true
        UIAccessibility.post(notification: .announcement, argument: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopiedFeedback = false }
    }

    private var readinessSymbol: String {
        if !microphonePermission.isAuthorized { return "mic.slash" }
        if !modelReady { return "arrow.down.circle" }
        return "checkmark.circle"
    }

    private var readinessTitle: String {
        if microphonePermission.isRecoverable { return "Microphone access is off" }
        if !microphonePermission.isAuthorized { return "Microphone access needed" }
        if !modelReady { return "Choose a local model" }
        if coordinator.status == .failed { return "Dictation needs another try" }
        return "Ready to dictate"
    }

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { refreshMicrophonePermission() }
        }
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning"
        case 12..<18:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }

    private var readinessSubtitle: String {
        if let recoveryMessage = microphonePermission.recoveryMessage {
            return recoveryMessage
        }

        if !microphonePermission.isAuthorized {
            return "Microphone access has not been granted yet."
        }

        if !modelReady {
            return "Choose a local model to begin."
        }

        switch coordinator.status {
        case .idle, .ready:
            return "Offline dictation, ready when you are."
        case .failed:
            return userFacingError(DictationErrorChannel.current ?? coordinator.status.recordingLabel)
        default:
            return coordinator.status.recordingLabel
        }
    }

    private func refreshMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .authorized
        case .denied:
            microphonePermission = .denied
        case .notDetermined:
            microphonePermission = .undetermined
        case .restricted:
            microphonePermission = .restricted
        @unknown default:
            microphonePermission = .restricted
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func userFacingError(_ message: String) -> String {
        message
            .replacingOccurrences(of: "Dictus", with: "sAiity")
            .replacingOccurrences(of: "dictus", with: "sAiity")
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(DictationCoordinator.shared)
            .environmentObject(ProStatusManager())
    }
}
