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
    @StateObject private var modelManager = ModelManager()
    @ObservedObject private var setup = KeyboardSetupModel.shared
    @AppStorage(SharedKeys.polishEnabled, store: AppGroup.defaults) private var polishEnabled = true
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var preparingModelID: String?
    private var recommendedModel: String {
        ModelInfo.initialModelIdentifier(existingSelection: modelManager.activeModel)
    }
    private var modelReady: Bool { modelManager.downloadedModels.contains(recommendedModel) && modelManager.modelStates[recommendedModel] == .ready }
    // Full Access is verified by the keyboard extension, which can only report
    // after the user actually switches to it. The next stage provides that path.
    private var canContinue: Bool { setup.keyboardInstalled && modelReady }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SaiityPageHeader(title: "Set up your keyboard",
                             subtitle: "Follow the guide, verify access with the real keyboard, then prepare your voice model.")
            KeyboardSetupCard()
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
            Button("Continue to keyboard verification", action: onNext).buttonStyle(SaiityPrimaryActionStyle())
                .disabled(!canContinue).accessibilityHint(canContinue ? "Next, switch to the sAiity keyboard and complete Full Access verification" : "Add the keyboard and install the voice model before switching to the sAiity keyboard and completing Full Access verification")
        }
        .onAppear {
            setup.refresh()
            refreshModel()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            setup.refresh()
            refreshModel()
        }
        .fullScreenCover(item: Binding<PreparingItem?>(get: { preparingModelID.map(PreparingItem.init) }, set: { preparingModelID = $0?.id })) { item in
            ModelLoadingOverlay(modelManager: modelManager, modelIdentifier: item.id, context: .onboarding, isPresented: Binding(get: { preparingModelID != nil }, set: { if !$0 { preparingModelID = nil } }))
        }
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
    private struct PreparingItem: Identifiable { let id: String }
}
