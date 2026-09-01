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
                Color(.systemBackground).ignoresSafeArea()
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
    @StateObject private var modelManager = ModelManager()
    @AppStorage(SharedKeys.onboardingFullAccessVerified, store: AppGroup.defaults) private var fullAccessVerified = false
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
        KeyboardSetupStatus(
            keyboardInstalled: keyboardInstalled,
            fullAccessHandshake: fullAccessVerified
        )
    }
    // Full Access is verified by the keyboard extension, which can only report
    // after the user actually switches to it. The next stage provides that path.
    private var canContinue: Bool { keyboardInstalled && modelReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Make sAiity available", systemImage: "checklist").font(.title2.weight(.semibold))
            Text("Complete the essentials once. Voice processing stays on this iPhone.").font(.body).foregroundStyle(.secondary)
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
        .onAppear { refreshKeyboard(); refreshModel() }
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
        Button(action: action) { HStack(alignment: .top, spacing: 12) { Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? .green : .secondary); VStack(alignment: .leading, spacing: 3) { Text(title).font(.body.weight(.medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); if !done { Image(systemName: "chevron.right").foregroundStyle(.tertiary) } }.contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityValue(done ? "Complete" : detail)
    }
    private func refreshKeyboard() {
        let installed = UITextInputMode.activeInputModes.contains {
            ($0.value(forKey: "identifier") as? String)?.contains("de.aiity.saiity.ios") == true
        }
        let handshake = AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified)
        keyboardInstalled = installed
        fullAccessVerified = handshake

        let status = KeyboardSetupStatus(keyboardInstalled: installed, fullAccessHandshake: handshake)
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
    private func startDownload() { guard !isDownloading else { return }; isDownloading = true; errorMessage = nil; preparingModelID = recommendedModel; Task { do { try await modelManager.downloadModel(recommendedModel); isDownloading = false } catch { isDownloading = false; preparingModelID = nil; errorMessage = "Could not install the voice model. Try again." } } }
    private func openSettings() { guard let url = URL(string: UIApplication.openSettingsURLString) else { return }; UIApplication.shared.open(url) }
    private struct PreparingItem: Identifiable { let id: String }
}
