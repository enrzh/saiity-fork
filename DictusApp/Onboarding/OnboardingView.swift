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
    @AppStorage(SharedKeys.polishEnabled, store: AppGroup.defaults) private var polishEnabled = false
    @State private var keyboardInstalled = false
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var preparingModelID: String?
    private var recommendedModel: String { ModelInfo.recommendedIdentifier() }
    private var modelReady: Bool { modelManager.downloadedModels.contains(recommendedModel) && modelManager.modelStates[recommendedModel] == .ready }
    private var canContinue: Bool { keyboardInstalled && modelReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Make sAiity available", systemImage: "checklist").font(.title2.weight(.semibold))
            Text("Complete the essentials once. Voice processing stays on this iPhone.").font(.body).foregroundStyle(.secondary)
            checklistRow("Add sAiity keyboard", detail: keyboardInstalled ? "Installed" : "Open Settings to add it", done: keyboardInstalled, action: openSettings)
            checklistRow("Allow Full Access", detail: fullAccessVerified ? "Verified by sAiity keyboard" : "Open Settings, enable it, then return to sAiity", done: fullAccessVerified, action: openSettings)
            VStack(alignment: .leading, spacing: 10) {
                checklistRow("Install voice model", detail: modelStatus, done: modelReady, action: startDownload)
                if isDownloading, let progress = modelManager.downloadProgress[recommendedModel] {
                    ProgressView(value: Double(progress)).tint(.accentColor).accessibilityLabel("Downloading voice model").accessibilityValue("\(Int(progress * 100)) percent")
                    if let bytes = modelManager.downloadByteInfo[recommendedModel] { Text("\(bytes.downloadedMB) MB of \(bytes.totalMB) MB").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red); Button("Try again", action: startDownload).buttonStyle(.bordered) }
            }
            Toggle("Optional cleanup", isOn: $polishEnabled).accessibilityHint("Applies local cleanup after dictation")
            Button("Try dictation", action: onNext).frame(maxWidth: .infinity).buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!canContinue).accessibilityHint(canContinue ? "Continue to the first dictation" : "Add the keyboard, allow Full Access, and install the voice model first")
            if !fullAccessVerified {
                Button("Check keyboard status", action: refreshKeyboard)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Reads the recent keyboard handshake; switch to sAiity keyboard to verify Full Access")
            }
        }
        .onAppear { refreshKeyboard(); refreshModel() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshKeyboard(); refreshModel() } }
        .fullScreenCover(item: Binding<PreparingItem?>(get: { preparingModelID.map(PreparingItem.init) }, set: { preparingModelID = $0?.id })) { item in
            ModelLoadingOverlay(modelManager: modelManager, modelIdentifier: item.id, context: .onboarding, isPresented: Binding(get: { preparingModelID != nil }, set: { if !$0 { preparingModelID = nil } }))
        }
    }

    private var modelStatus: String { if modelReady { return "Ready" }; if modelManager.modelStates[recommendedModel] == .prewarming { return "Preparing" }; if isDownloading { return "Downloading" }; return "Required for offline dictation" }
    private func checklistRow(_ title: String, detail: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(alignment: .top, spacing: 12) { Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? .green : .secondary); VStack(alignment: .leading, spacing: 3) { Text(title).font(.body.weight(.medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); if !done { Image(systemName: "chevron.right").foregroundStyle(.tertiary) } }.contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityValue(done ? "Complete" : detail)
    }
    private func refreshKeyboard() {
        keyboardInstalled = UITextInputMode.activeInputModes.contains { ($0.value(forKey: "identifier") as? String)?.contains("de.aiity.saiity.ios") == true }
        fullAccessVerified = AppGroup.defaults.bool(forKey: SharedKeys.onboardingFullAccessVerified)
        UIAccessibility.post(notification: .announcement, argument: fullAccessVerified ? "sAiity keyboard and Full Access verified" : keyboardInstalled ? "sAiity keyboard detected; Full Access will be verified when the keyboard appears" : "Checking for sAiity keyboard")
    }
    private func refreshModel() { if modelManager.downloadedModels.contains(recommendedModel) { modelManager.modelStates[recommendedModel] = .ready } }
    private func startDownload() { guard !isDownloading else { return }; isDownloading = true; errorMessage = nil; preparingModelID = recommendedModel; Task { do { try await modelManager.downloadModel(recommendedModel); isDownloading = false } catch { isDownloading = false; preparingModelID = nil; errorMessage = "Could not install the voice model. Try again." } } }
    private func openSettings() { guard let url = URL(string: UIApplication.openSettingsURLString) else { return }; UIApplication.shared.open(url) }
    private struct PreparingItem: Identifiable { let id: String }
}
