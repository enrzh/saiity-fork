import SwiftUI
import UIKit
import SyllivraKernel

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
    @AppStorage(SharedKeys.onboardingUsage, store: AppGroup.defaults) private var usage = OnboardingUsage.keyboard.rawValue
    @State private var showAppTry = false
    @StateObject private var modelManager = ModelManager()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                ScrollView {
                    stageContent.fullWidthButtons().frame(maxWidth: 560).frame(maxWidth: .infinity)
                        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
                }.scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Set up Syllivra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage != .welcome {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { advance(to: OnboardingStage(rawValue: stage.rawValue - 1) ?? .welcome) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { stageProgress.padding(.horizontal, 24).padding(.vertical, 12).background(.bar) }
            .interactiveDismissDisabled()
            .fullScreenCover(isPresented: $showAppTry) {
                RecordingView(mode: .onboarding, onComplete: finishOnboarding)
                    .environmentObject(DictationCoordinator.shared)
            }
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
        case .welcome: WelcomePage(onNext: {
            usage = OnboardingUsage.appOnly.rawValue
            DictationCoordinator.shared.setKeyboardDictationEnabled(false)
            advance(to: .permissions)
        }, onKeyboardSetup: { usage = OnboardingUsage.keyboard.rawValue; advance(to: .permissions) })
        case .permissions: MicPermissionPage(onNext: { advance(to: .availability) })
        case .availability: AvailabilityPage(modelManager: modelManager, onNext: { advance(to: .tryIt) })
        case .tryIt:
            if usage == OnboardingUsage.appOnly.rawValue {
                VStack(alignment: .leading, spacing: 20) {
                    SaiityPageHeader(title: "Try a dictation", subtitle: "Speak here, then copy or share your words. You can add the keyboard later in Settings.")
                    Button("Try a dictation") { showAppTry = true }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    Button("Finish setup without dictating", action: finishOnboarding).buttonStyle(.bordered)
                }
            } else {
            GlobeKeyTutorialPage(
                onComplete: finishOnboarding,
                onReturnToSetup: { advance(to: .availability) }
            )
            .environmentObject(DictationCoordinator.shared)
            }
        }
    }

    private var stageProgress: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(stage.rawValue + 1), total: 4).tint(.accentColor)
            Text("Step \(stage.rawValue + 1) of 4").font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel("Onboarding progress")
                .accessibilityValue(Text("Step \(stage.rawValue + 1) of 4"))
            Button("Set up later") {
                DictationCoordinator.shared.setKeyboardDictationEnabled(false)
                finishOnboarding()
            }
            .frame(minHeight: 44)
            .accessibilityHint("Finish setup later in Settings. Dictation stays off.")
        }
    }

    private func advance(to next: OnboardingStage) {
        withAnimation(AccessibilityMotionPolicy.animation(reduceMotion: reduceMotion)) { stage = next }
    }

    private func finishOnboarding() { showAppTry = false; storedStage = 0; isComplete = true }
}

struct AvailabilityPage: View {
    @ObservedObject var modelManager: ModelManager
    let onNext: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var setup = KeyboardSetupModel.shared
    @AppStorage(SharedKeys.polishEnabled, store: AppGroup.defaults) private var polishEnabled = true
    @State private var errorMessage: String?
    private var isDownloading: Bool {
        recommendedModel.map { modelManager.downloadProgress[$0] != nil || modelManager.modelStates[$0] == .prewarming } ?? false
    }
    private var recommendedModel: String? {
        if !usesKeyboard { return modelManager.initialVoiceModel }
        if let requested = AppGroup.defaults.string(forKey: SharedKeys.keyboardDictationModel) { return requested }
        return ModelSelectionProfile.balanced.resolvedIdentifier(installed: Set(ModelInfo.downloadableIdentifiers),
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            capabilities: DeviceCapabilities.current(),
            requiredLanguages: SpokenLanguagePreferences.load(from: AppGroup.defaults))
    }
    private var modelReady: Bool {
        recommendedModel.map { modelManager.downloadedModels.contains($0) && modelManager.modelStates[$0] == .ready } ?? false
    }
    private var installedAlternative: String? {
        let installed = usesKeyboard ? modelManager.keyboardModel : modelManager.activeModel
        return installed != recommendedModel ? installed : nil
    }
    // Full Access is verified by the keyboard extension, which can only report
    // after the user actually switches to it. The next stage provides that path.
    private var usesKeyboard: Bool { OnboardingUsage.active(from: AppGroup.defaults).usesKeyboard }
    private var canContinue: Bool { OnboardingUsage.active(from: AppGroup.defaults).canContinue(keyboardInstalled: setup.keyboardInstalled, modelReady: modelReady) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SaiityPageHeader(title: usesKeyboard ? "Set up your keyboard" : "Prepare your voice",
                             subtitle: usesKeyboard ? "Add the keyboard and prepare a model for the languages you speak." : "Choose your spoken languages and install a local voice model.")
            SpokenLanguagesPicker(modelManager: modelManager)
                .disabled(isDownloading)
            if usesKeyboard { KeyboardSetupCard() }
            VStack(alignment: .leading, spacing: 10) {
                if let recommendedModel {
                checklistRow(modelReady ? "Voice model ready" : "Install voice model", detail: ModelInfo.forIdentifier(recommendedModel).map { "\($0.displayName) · \($0.sizeBytes / 1_000_000) MB · \(modelStatus)" } ?? modelStatus, done: modelReady, action: startDownload)
                    .disabled(isDownloading || modelReady)
                if isDownloading {
                    if let progress = modelManager.downloadProgress[recommendedModel] {
                        ProgressView(value: Double(progress)).tint(.accentColor).accessibilityLabel("Downloading voice model").accessibilityValue("\(Int(progress * 100)) percent")
                    } else { ProgressView("Preparing voice model") }
                    if let bytes = modelManager.downloadByteInfo[recommendedModel] { Text("\(bytes.downloadedMB) MB of \(bytes.totalMB) MB").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Button("Cancel download") { modelManager.cancelCatalogDownload(recommendedModel) }
                }
                } else {
                    Text("No compatible model covers these languages on this iPhone. Change your spoken languages to see a recommendation.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let errorMessage {
                    let problem = DictationProblem(errorMessage, downloading: true)
                    Text(problem.message).font(.caption).foregroundStyle(.red)
                    Button(problem.action == .repairDownload ? "Repair download" : "Try again", action: startDownload).buttonStyle(.bordered)
                }
                if let installedAlternative, let model = ModelInfo.forIdentifier(installedAlternative) {
                    Text("\(model.displayName) is already installed. You can use it now or download the recommended model for your languages.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Continue with \(model.displayName)", action: onNext)
                        .buttonStyle(.bordered).disabled(usesKeyboard && !setup.keyboardInstalled)
                }
            }
            Toggle("Automatic dictation cleanup", isOn: $polishEnabled)
                .accessibilityHint("Cleans up dictation after speech recognition. Turn off to pass through the raw transcription.")
            Text(polishEnabled ? "Cleanup runs after dictation. Turn it off to pass through the raw transcription." : "Cleanup is off, so dictation passes through as transcribed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(usesKeyboard ? "Continue to keyboard verification" : "Try speaking here", action: onNext)
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!canContinue).accessibilityHint(usesKeyboard
                    ? "Add the keyboard and install a voice model, then switch to it to verify Full Access."
                    : "Install a local voice model to try dictation here. Keyboard installation is optional.")
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
    }

    private var modelStatus: String { if modelReady { return "Ready" }; if let recommendedModel, modelManager.modelStates[recommendedModel] == .prewarming { return "Preparing" }; if isDownloading { return "Downloading" }; return "Required for offline dictation" }
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
            .padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(done ? "Complete" : detail)
    }
    private func refreshModel() { modelManager.loadState() }
    private func startDownload() {
        guard !isDownloading, let recommendedModel else { return }
        errorMessage = nil
        modelManager.startCatalogDownload(recommendedModel) { detail in
            errorMessage = detail.isEmpty ? "Could not install the voice model. Try again." : detail
        }
    }
}

extension View {
    /// Buttons fill the column, as on Apple's own setup screens (iOS 26 and later).
    @ViewBuilder func fullWidthButtons() -> some View {
        if #available(iOS 26.0, *) { buttonSizing(.flexible) } else { self }
    }
}
