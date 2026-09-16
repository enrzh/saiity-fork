import SwiftUI
import UIKit
import DictusCore

enum OnboardingStage: Int, CaseIterable {
    case welcome
    case permissions
    case availability
    case tryIt
}

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SharedKeys.onboardingCurrentPage, store: AppGroup.defaults) private var storedStage = 0
    @State private var stage: OnboardingStage = .welcome
    @State private var didLoadStage = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    stageContent.frame(maxWidth: 560).frame(maxWidth: .infinity)
                        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
                }.scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Set up sAiity")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) { stageProgress.padding(.horizontal, 24).padding(.vertical, 12).background(.bar) }
            .interactiveDismissDisabled()
            .onAppear {
                guard !didLoadStage else { return }
                stage = OnboardingStage(rawValue: min(max(storedStage, 0), 3)) ?? .welcome
                didLoadStage = true
            }
            .onChange(of: stage) { _, newStage in
                storedStage = newStage.rawValue
                UIAccessibility.post(notification: .announcement, argument: "Step \(newStage.rawValue + 1) of 4")
            }
        }
    }

    @ViewBuilder private var stageContent: some View {
        switch stage {
        case .welcome: WelcomePage(onNext: { advance(to: .permissions) })
        case .permissions: MicPermissionPage(onNext: { advance(to: .availability) })
        case .availability: AvailabilityPage(onNext: { advance(to: .tryIt) })
        case .tryIt:
            GlobeKeyTutorialPage(
                onComplete: finishOnboarding,
                onReturnToSetup: { advance(to: .availability) }
            )
            .environmentObject(DictationCoordinator.shared)
        }
    }

    private var stageProgress: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(stage.rawValue + 1), total: 4).tint(.accentColor)
            Text("Step \(stage.rawValue + 1) of 4").font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("Onboarding progress")
                .accessibilityValue(Text("Step \(stage.rawValue + 1) of 4"))
        }
    }

    private func advance(to next: OnboardingStage) {
        withAnimation(AccessibilityMotionPolicy.animation(reduceMotion: reduceMotion)) { stage = next }
    }

    private func finishOnboarding() { storedStage = 0; isComplete = true }
}

struct AvailabilityPage: View {
    let onNext: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var coordinator: DictationCoordinator
    @StateObject private var modelManager = ModelManager()
    @AppStorage(SharedKeys.onboardingFullAccessVerified, store: AppGroup.defaults) private var fullAccessVerified = false
    @AppStorage(SharedKeys.onboardingFullAccessHandshakeDate, store: AppGroup.defaults) private var fullAccessHandshakeDate = 0.0
    @AppStorage(SharedKeys.polishEnabled, store: AppGroup.defaults) private var polishEnabled = true
    @State private var keyboardInstalled = false
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var preparingModelID: String?
    private var recommendedModel: String {
        ModelInfo.initialModelIdentifier(existingSelection: modelManager.activeModel)
    }
    private var modelReady: Bool { modelManager.downloadedModels.contains(recommendedModel) && modelManager.modelStates[recommendedModel] == .ready }
    private var keyboardStatus: KeyboardSetupStatus {
        let handshake = KeyboardSetupStatus.isCurrentFullAccessHandshake(
            verified: AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified),
            probe: AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessProbe),
            acknowledgedProbe: AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessAcknowledgedProbe)
        )
        return KeyboardSetupStatus(
            keyboardInstalled: keyboardInstalled,
            fullAccessHandshake: handshake,
            handshakeDate: fullAccessHandshakeDate > 0 ? Date(timeIntervalSince1970: fullAccessHandshakeDate) : nil
        )
    }
    // Full Access is verified by the keyboard extension, which can only report
    // after the user actually switches to it. The next stage provides that path.
    private var canContinue: Bool { keyboardStatus.keyboardDetected && modelReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SaiityPageHeader(eyebrow: "CONNECT YOUR KEYBOARD", title: "Three small steps.\nA lot less typing.",
                             subtitle: "Connect the keyboard, grant Full Access and install your first voice model.")
            checklistRow("Add sAiity keyboard", detail: keyboardInstalled ? "Installed" : "Open Keyboard Settings to add it", done: keyboardInstalled, action: openSettings)
            checklistRow("Allow Full Access", detail: fullAccessDetail, done: keyboardStatus.fullAccessVerified, action: openSettings)
            VStack(alignment: .leading, spacing: 10) {
                checklistRow("Install voice model", detail: modelStatus, done: modelReady, action: startDownload)
                if isDownloading, let progress = modelManager.downloadProgress[recommendedModel] {
                    ProgressView(value: Double(progress)).tint(.accentColor).accessibilityLabel("Downloading voice model").accessibilityValue("\(Int(progress * 100)) percent")
                    if let bytes = modelManager.downloadByteInfo[recommendedModel] { Text("\(bytes.downloadedMB) MB of \(bytes.totalMB) MB").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red); Button("Try again", action: startDownload).buttonStyle(.bordered) }
            }
            Toggle("Automatic dictation cleanup", isOn: $polishEnabled)
                .accessibilityHint("Cleans up dictation after speech recognition. Turn off to pass through the raw transcription.")
            Text(polishEnabled ? "Cleanup runs after dictation. Turn it off to pass through the raw transcription." : "Cleanup is off, so dictation passes through as transcribed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Continue to keyboard verification", action: onNext).frame(maxWidth: .infinity).buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!canContinue).accessibilityHint(canContinue ? "Next, switch to the sAiity keyboard and complete Full Access verification" : "Add the keyboard and install the voice model before switching to the sAiity keyboard and completing Full Access verification")
            if !keyboardStatus.fullAccessVerified {
                Button("Open Keyboard Settings", action: openSettings)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Opens iOS Keyboard Settings. Full Access is verified only by the keyboard extension.")
            }
        }
        .onAppear {
            ensureFullAccessProbe()
            refreshKeyboard()
            refreshModel()
            if modelReady {
                coordinator.enableKeyboardSession()
            }
            DarwinNotificationCenter.addObserver(for: DarwinNotificationName.keyboardFullAccessChanged) {
                DispatchQueue.main.async {
                    refreshKeyboard()
                }
            }
        }
        .onDisappear {
            DarwinNotificationCenter.removeObserver(for: DarwinNotificationName.keyboardFullAccessChanged)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshKeyboard(); refreshModel() } }
        .fullScreenCover(item: Binding<PreparingItem?>(get: { preparingModelID.map(PreparingItem.init) }, set: { preparingModelID = $0?.id })) { item in
            ModelLoadingOverlay(modelManager: modelManager, modelIdentifier: item.id, context: .onboarding, isPresented: Binding(get: { preparingModelID != nil }, set: { if !$0 { preparingModelID = nil } }))
        }
    }

    private var fullAccessDetail: String {
        if keyboardStatus.fullAccessVerified {
            return "Verified by the sAiity keyboard"
        }
        if keyboardStatus.keyboardInstalled {
            return "Not verified yet. Enable Full Access, then use the sAiity keyboard once."
        }
        return "Add sAiity keyboard first. Full Access is verified when it appears."
    }

    private var modelStatus: String { if modelReady { return "Ready" }; if modelManager.modelStates[recommendedModel] == .prewarming { return "Preparing" }; if isDownloading { return "Downloading" }; return "Required for offline dictation" }
    private func checklistRow(_ title: String, detail: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(done ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if !done { Image(systemName: "arrow.up.right").foregroundStyle(.tertiary) }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(done ? "Complete" : detail)
    }
    private func refreshKeyboard() {
        AppGroup.defaults.synchronize()
        let modes = UITextInputMode.activeInputModes
        let inputModeInstalled = modes.contains {
            KeyboardSetupStatus.isDictusKeyboardIdentifier($0.value(forKey: "identifier") as? String)
        }
        let storedVerified = AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified)
        let handshake = KeyboardSetupStatus.isCurrentFullAccessHandshake(
            verified: storedVerified,
            probe: AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessProbe),
            acknowledgedProbe: AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessAcknowledgedProbe)
        )
        let handshakeDate = AppGroup.defaults.object(forKey: SharedKeys.onboardingFullAccessHandshakeDate) as? Double
        let status = KeyboardSetupStatus(
            keyboardInstalled: inputModeInstalled,
            fullAccessHandshake: handshake,
            handshakeDate: handshakeDate.map(Date.init(timeIntervalSince1970:))
        )
        let installed = status.keyboardDetected
        keyboardInstalled = installed
        if handshake {
            fullAccessVerified = true
        }
        let announcement: String
        if status.fullAccessVerified {
            announcement = "sAiity keyboard and Full Access verified"
        } else if status.keyboardInstalled {
            announcement = "sAiity keyboard detected; Full Access is not verified yet"
        } else {
            announcement = "sAiity keyboard not detected"
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
    private func refreshModel() { if modelManager.downloadedModels.contains(recommendedModel) { modelManager.modelStates[recommendedModel] = .ready } }
    private func startDownload() {
        guard !isDownloading else { return }
        isDownloading = true
        errorMessage = nil
        preparingModelID = recommendedModel
        Task {
            do {
                try await modelManager.downloadModel(recommendedModel)
                isDownloading = false
                coordinator.enableKeyboardSession()
            } catch {
                isDownloading = false
                preparingModelID = nil
                let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                errorMessage = detail.isEmpty
                    ? "Could not install the voice model. Try again."
                    : detail
            }
        }
    }
    private func openSettings() {
        ensureFullAccessProbe()
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    private func ensureFullAccessProbe() {
        guard AppGroup.defaults.string(forKey: SharedKeys.onboardingFullAccessProbe) == nil else { return }
        AppGroup.defaults.set(UUID().uuidString, forKey: SharedKeys.onboardingFullAccessProbe)
    }
    private struct PreparingItem: Identifiable { let id: String }
}
