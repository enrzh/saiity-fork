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
    @AppStorage(SharedKeys.modelLoadState, store: AppGroup.defaults) private var modelLoadStateRaw = ModelLoadState.idle.rawValue
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                dashboardHeader
                readinessPanel

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
            if enabled {
                NotificationCenter.default.post(
                    name: Notification.Name("DictusServiceToggleRequested"),
                    object: nil
                )
            } else {
                NotificationCenter.default.post(
                    name: Notification.Name("DictusStopStandbyRequested"),
                    object: nil
                )
            }
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

    private var dashboardHeader: some View {
        let readiness = currentReadiness
        return HStack(alignment: .center, spacing: 14) {
            DictusLogo(height: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text("sAiity")
                    .font(.title2.weight(.bold))
                Text(greetingTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(readinessColor(readiness))
                        .frame(width: 7, height: 7)
                    Text(readiness.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readinessPanel: some View {
        let readiness = currentReadiness
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: readiness.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(readinessColor(readiness))
                    .frame(width: 42, height: 42)
                    .background(readinessColor(readiness).opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ready when you are")
                        .font(.headline)
                    Text(readinessSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            readinessAction
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var readinessAction: some View {
        let readiness = currentReadiness
        if readiness.action == .openSettings {
            Button { openSystemSettings() } label: {
                Label("Open Settings", systemImage: "arrow.up.right")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
        } else if readiness.action == .requestMicrophone {
            Button { requestMicrophoneAccess() } label: {
                Label("Allow microphone", systemImage: "mic.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
        } else if readiness.action == .retry {
            Button { coordinator.startDictation() } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        } else if readiness.action == .start {
            newDictationButton
        }
    }

    private func readinessColor(_ readiness: DictationReadiness) -> Color {
        switch readiness.action {
        case .start: return .dictusSuccess
        case .retry, .openSettings: return .dictusRecording
        case .requestMicrophone: return .dictusAccent
        case .none: return .secondary
        }
    }

    private var newDictationButton: some View {
        Button {
            coordinator.startDictation()
        } label: {
            Label("Start dictation", systemImage: "waveform")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .controlSize(.large)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityIdentifier("home.newDictation")
    }

    private func recentActivity(result: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recent dictation", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Button { copy(result) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            Text(result)
                .font(.body)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
            if showCopiedFeedback {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
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

    private var currentReadiness: DictationReadiness {
        DictationReadiness(serviceEnabled: serviceEnabled, microphonePermission: microphonePermission,
                           modelReady: modelReady, modelLoadState: ModelLoadState(rawValue: modelLoadStateRaw) ?? .idle,
                           status: coordinator.status)
    }

    private var readinessSubtitle: String {
        if currentReadiness.action == .retry, let error = DictationErrorChannel.current {
            return userFacingError(error)
        }
        return currentReadiness.subtitle
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
