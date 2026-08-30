// DictusApp/Views/HomeView.swift
// Home dashboard showing real model readiness, dictation, and recent output.
import SwiftUI
import AVFoundation
import DictusCore

struct HomeView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @EnvironmentObject var proStatus: ProStatusManager
    @ObservedObject var modelManager: ModelManager
    var onModelsRequested: (() -> Void)?

    @State private var showCopiedFeedback = false
    @State private var microphonePermission = MicrophonePermissionState.undetermined
    @Environment(\.scenePhase) private var scenePhase

    init(modelManager: ModelManager, onModelsRequested: (() -> Void)? = nil) {
        self.modelManager = modelManager
        self.onModelsRequested = onModelsRequested
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                greeting
                modelStatusSurface

                if modelManager.isModelReady {
                    newDictationButton
                } else if let onModelsRequested {
                    Button(action: onModelsRequested) {
                        Label("Open Models", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if let result = coordinator.lastResult, !result.isEmpty {
                    recentActivity(result: result)
                }

                if PremiumFlags.paywallVisible {
                    ProBannerView()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("sAiity")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            modelManager.loadState()
            refreshMicrophonePermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DictusOnboardingCompleted"))) { _ in
            modelManager.loadState()
            refreshMicrophonePermission()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshMicrophonePermission()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("sAiity")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                if proStatus.isProActive {
                    Text("Pro")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dictusAccent)
                }
            }
            Spacer()
            DictusLogo(height: 34)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingTitle)
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text(readinessSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if microphonePermission.isRecoverable {
                Button {
                    openSystemSettings()
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelStatusSurface: some View {
        Group {
            if let modelIdentifier = modelManager.activeModel,
               modelManager.isModelReady {
                let info = ModelInfo.forIdentifier(modelIdentifier)
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active model")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(info?.displayName ?? modelIdentifier)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                        if let size = info?.sizeLabel {
                            Text(size)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.dictusSuccess)
                        .accessibilityLabel("Ready")
                }
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No model selected")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        Text("Download a model to start dictating.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .dictusGlass(in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var newDictationButton: some View {
        Button {
            coordinator.startDictation()
        } label: {
            Label("New dictation", systemImage: "waveform")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .controlSize(.large)
        .accessibilityIdentifier("home.newDictation")
    }

    private func recentActivity(result: String) -> some View {
        Button {
            UIPasteboard.general.string = result
            HapticFeedback.recordingStopped()
            showCopiedFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopiedFeedback = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent activity")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(showCopiedFeedback ? "Copied" : "Tap to copy")
                        .font(.caption)
                        .foregroundStyle(showCopiedFeedback ? Color.dictusSuccess : .secondary)
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(result)
                    .font(.body)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .dictusGlass(in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.recentActivity")
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

        if !modelManager.isModelReady {
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
        HomeView(modelManager: ModelManager())
            .environmentObject(DictationCoordinator.shared)
            .environmentObject(ProStatusManager())
    }
}
