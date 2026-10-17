// DictusApp/Views/ModelManagerView.swift
// Native model management UI backed by the real model catalog and manager state.
import SwiftUI
import SyllivraKernel

/// Displays Tiny, Base, Medium, Large v3, and Turbo Whisper downloads plus any already-installed models.
struct ModelManagerView: View {
    @ObservedObject var modelManager: ModelManager

    @State private var modelToDelete: ModelInfo?
    @State private var showDeleteAlert = false
    @State private var partialModelToDelete: ModelInfo?
    @State private var showPartialDeleteAlert = false
    @State private var downloadError: String?
    @State private var showErrorAlert = false
    @State private var failedDownloadModelID: String?
    @State private var customModelToDelete: CustomModel?
    @State private var searchText = ""
    @State private var showsProcessingModels = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var coordinator: DictationCoordinator

    private let deviceCapabilities = DeviceCapabilities.current()

    private var catalogModels: [ModelInfo] {
        var models = ModelInfo.available(on: deviceCapabilities).filter {
            $0.runtimeCapability.minimumOSMajorVersion <= ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        }
        let preferred = modelManager.preferredModelIdentifier
        if !models.contains(where: { $0.identifier == preferred }),
           let model = ModelInfo.forIdentifier(preferred),
           model.isRuntimeAvailable(onOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                                    capabilities: deviceCapabilities) {
            models.append(model)
        }
        return models
    }

    private var installedModels: [ModelInfo] {
        ModelInfo.installedRows(from: ModelInfo.allIncludingDeprecated)
            .filter(isInstalled).filter(matchesFilter)
            .sorted { lhs, rhs in
                let leftActive = modelManager.activeModel == lhs.identifier
                let rightActive = modelManager.activeModel == rhs.identifier
                if leftActive != rightActive { return leftActive }
                let leftRecommended = modelManager.isRecommended(lhs.identifier)
                let rightRecommended = modelManager.isRecommended(rhs.identifier)
                if leftRecommended != rightRecommended { return leftRecommended }
                return lhs.sizeBytes < rhs.sizeBytes
            }
    }

    private var availableModels: [ModelInfo] {
        return catalogModels
            .filter { !isInstalled($0) }.filter(matchesFilter)
            .sorted { lhs, rhs in
                let leftRecommended = modelManager.isRecommended(lhs.identifier)
                let rightRecommended = modelManager.isRecommended(rhs.identifier)
                if leftRecommended != rightRecommended { return leftRecommended }
                if lhs.isExperimental != rhs.isExperimental { return !lhs.isExperimental }
                return lhs.sizeBytes < rhs.sizeBytes
            }
    }

    private func matchesFilter(_ model: ModelInfo) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let coverage = model.languageSupport
        let codes = coverage.highlights.map(\.code) + coverage.additionalCodes + coverage.tierGroups.flatMap(\.codes)
        let searchable = ([model.displayName, model.engine.displayName, model.description] +
                          codes.map { ModelLanguageSupport.localizedLanguageName(for: $0) }).joined(separator: " ")
        return searchable.localizedCaseInsensitiveContains(query)
    }

    private func isInstalled(_ model: ModelInfo) -> Bool {
        if modelManager.downloadedModels.contains(model.identifier) { return true }
        return modelManager.modelStates[model.identifier] == .ready
    }

    var body: some View {
        modelManagerContent
    }

    private var modelManagerContent: some View {
        // Xcode 26.3 can time out when it carries the concrete nested List type
        // through every sheet, alert, and cover modifier below.
        AnyView(configuredModelList)
        .alert("Delete custom model?", isPresented: Binding(get: { customModelToDelete != nil }, set: { if !$0 { customModelToDelete = nil } })) {
            Button("Cancel", role: .cancel) { customModelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = customModelToDelete { modelManager.deleteCustomModel(model) }
                customModelToDelete = nil
            }
        } message: {
            Text("This removes the saved model configuration from Syllivra.")
        }
        .onAppear {
            modelManager.loadState()
        }
        .alert("Delete model?", isPresented: $showDeleteAlert, presenting: modelToDelete) { model in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                do {
                    try modelManager.deleteModel(model.identifier)
                } catch {
                    failedDownloadModelID = nil
                    presentError(error.localizedDescription)
                }
            }
        } message: { model in
            Text("Delete \(model.displayName)? The model will be removed from your device.")
        }
        .alert("Delete partial download?", isPresented: $showPartialDeleteAlert, presenting: partialModelToDelete) { model in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelManager.cleanupFailedModel(model.identifier)
            }
        } message: { model in
            Text("Delete the partially downloaded files for \(model.displayName)? The next download will start from the beginning.")
        }
        .alert("Model action failed", isPresented: $showErrorAlert) {
            if let failedDownloadModelID {
                Button("Retry") {
                    modelManager.startCatalogDownload(failedDownloadModelID, onError: presentError)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            if let downloadError {
                Text(downloadError)
            }
        }
    }

    /// Keep the large List result separate from its presentation modifiers.
    /// Xcode 26.3 otherwise spends too long type-checking the nested sections
    /// together with the alerts and full-screen cover below.
    private var configuredModelList: some View {
        modelList
            .listStyle(.insetGrouped)
            .textCase(nil)
            .contentMargins(.bottom, 88, for: .scrollContent)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: showsProcessingModels ? "Processing model" : "Voice model or language")
    }

    private var modelTypePicker: some View {
        Picker("Model type", selection: $showsProcessingModels) {
            Text("Voice").tag(false)
            Text("Processing").tag(true)
        }
    }

    @ViewBuilder
    private var modelList: some View {
        List {
            Section {
                if typeSize.isAccessibilitySize {
                    modelTypePicker.pickerStyle(.menu)
                } else {
                    modelTypePicker.pickerStyle(.segmented)
                }
            }
            if showsProcessingModels {
                dictationCleanupSection
            } else {
                Section {
                    currentModelRow("In app", keyboard: false)
                    currentModelRow("Keyboard", keyboard: true)
                    NavigationLink {
                        VoiceOptionsView(modelManager: modelManager)
                    } label: {
                        Text("Voice options")
                    }
                } header: {
                    Text("In use")
                } footer: {
                    Text("Choose from installed models. App and keyboard choices are independent.")
                    if !coordinator.canChangeSpeechRuntime {
                        Text("Finish this dictation before changing voice settings.")
                    }
                }
                installedSection
                availableSection
            }
        }
    }

    @ViewBuilder
    private func currentModelRow(_ title: LocalizedStringKey, keyboard: Bool) -> some View {
        let identifier = keyboard
            ? AppGroup.defaults.string(forKey: SharedKeys.keyboardDictationModel) ?? "automatic"
            : modelManager.activeModel ?? "unavailable"
        let choices = ModelInfo.installedRows(from: ModelInfo.allIncludingDeprecated).filter {
            isInstalled($0) && (!keyboard || $0.engine != .qwenASR)
                && $0.isRuntimeAvailable(onOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                                         capabilities: deviceCapabilities)
        }.sorted { $0.sizeBytes < $1.sizeBytes }
        Picker(title, selection: Binding(
            get: { identifier },
            set: { selected in
                if keyboard { modelManager.chooseKeyboardModel(selected) }
                else { modelManager.selectModel(selected) }
            }
        )) {
            if keyboard {
                Text(modelManager.keyboardModel.flatMap(ModelInfo.forIdentifier).map {
                    "Automatic (\($0.displayName))"
                } ?? "Automatic").tag("automatic")
            }
            if identifier != "automatic" && !choices.contains(where: { $0.identifier == identifier }) {
                Text(ModelInfo.forIdentifier(identifier)?.displayName ?? String(localized: "No compatible model"))
                    .tag(identifier).disabled(true)
            }
            ForEach(choices) { model in
                Text(model.displayName).tag(model.identifier)
            }
        }
        .pickerStyle(.menu)
        .disabled(!coordinator.canChangeSpeechRuntime || (!keyboard && choices.isEmpty))
        .accessibilityIdentifier(keyboard ? "models.keyboardModel" : "models.appModel")
    }

    @ViewBuilder
    private var installedSection: some View {
        Section {
            if installedModels.isEmpty {
                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No models installed. Download a voice model below." : "No matching installed models")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(installedModels) { model in
                    modelRow(model)
                }
            }
        } header: {
            Text("Installed")
        }
    }

    @ViewBuilder
    private var availableSection: some View {
        Section {
            if availableModels.isEmpty {
                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "All available models are installed" : "No matching downloads")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(availableModels) { model in
                    modelRow(
                        model,
                        incompatibilityReason: model.incompatibilityReason(on: deviceCapabilities)
                    )
                }
            }
        } header: {
            Text("Downloads")
        } footer: {
            Text("Voice models run on this iPhone. Recommendations reflect compatibility, not measured accuracy or speed on your device.")
        }
    }

    private func modelRow(
        _ model: ModelInfo,
        incompatibilityReason: ModelInfo.IncompatibilityReason? = nil
    ) -> some View {
        ModelCardView(
            model: model,
            modelManager: modelManager,
            onDownloadError: { error in
                failedDownloadModelID = model.identifier
                presentError(error)
            },
            incompatibilityReason: incompatibilityReason,
            onDeleteRequest: {
                requestDelete(model)
            },
            onDeletePartialRequest: {
                partialModelToDelete = model
                showPartialDeleteAlert = true
            }
        )
    }

    private func requestDelete(_ model: ModelInfo) {
        modelToDelete = model
        showDeleteAlert = true
    }

    @ViewBuilder
    private var dictationCleanupSection: some View {
        let localModels = LocalCleanupModel.allCases.filter { matchesProcessingFilter($0.displayName + " " + $0.explanation) }
        let cleanupModels = modelManager.customModels.filter { $0.role == .cleanup && matchesProcessingFilter($0.name) }
        let showsApple = matchesProcessingFilter("Apple Intelligence")
        Section {
            if showsApple { appleIntelligenceCleanupRow }
            ForEach(localModels, id: \.self) { model in
                CleanupModelCardView(model: model, manager: modelManager)
            }
            ForEach(cleanupModels) { model in
                customCleanupRow(model)
            }
            if !showsApple && localModels.isEmpty && cleanupModels.isEmpty {
                Text("No matching processing models").foregroundStyle(.secondary)
            }
        } header: {
            Text("Text processing")
        } footer: {
            Text("One processing model handles punctuation, cleanup and grammar. Apple supports background processing; downloaded local models need Syllivra to stay open.")
        }
    }

    private func matchesProcessingFilter(_ text: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }

    private var isAppleIntelligenceCleanupActive: Bool {
        modelManager.cleanupBackend == .appleIntelligence
    }

    private var appleIntelligenceCleanupRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ModelCardHeading(name: "Apple Intelligence", size: "", active: isAppleIntelligenceCleanupActive)
            Text("Included on supported iPhones. Works in the background.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if PolishAvailability.state != .available {
                Text(PolishAvailability.guidance(for: PolishAvailability.state))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !isAppleIntelligenceCleanupActive {
                Button {
                    modelManager.selectCleanupBackend(.appleIntelligence)
                } label: {
                    Label("Use for processing", systemImage: "checkmark.circle").frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .accessibilityHint("Uses Apple Intelligence for dictation cleanup")
            }
        }
        .padding(.vertical, 8)
        .labelStyle(.titleAndIcon)
    }

    private func customCleanupRow(_ model: CustomModel) -> some View {
        let isActive = modelManager.cleanupBackend == .ollama(model.id)
        let actionLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 4) {
            ModelCardHeading(name: model.name, size: model.source.displayName, active: isActive)
            Text(customModelStatus(model)).font(.footnote).foregroundStyle(.secondary)
            Text("Dictated text is sent to \(URL(string: model.repositoryURL)?.host ?? "your configured server"). Choose a server you trust.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actionLayout {
                if model.validationError == nil && !isActive {
                    Button {
                        modelManager.selectCleanupBackend(.ollama(model.id))
                    } label: {
                        Label("Use for processing", systemImage: "checkmark.circle").frame(minHeight: 44)
                    }
                    .accessibilityHint("Uses this Ollama model for dictation cleanup")
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Menu {
                    Button("Delete configuration", role: .destructive) { customModelToDelete = model }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Actions for \(model.name)")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
        .labelStyle(.titleAndIcon)
    }

    private func customModelStatus(_ model: CustomModel) -> String {
        if let error = model.validationError { return "Invalid: \(error)" }
        if model.role == .asr && model.source == .huggingFace && model.remoteValidationState == .needsVerification {
            return "Needs remote verification before use · \(model.source.displayName)"
        }
        if let error = model.runtimeSupportError {
            if model.role == .asr && model.source == .huggingFace && model.remoteValidationState == .verified {
                return "Verified, but runtime unavailable: \(error)"
            }
            return error
        }
        if model.role == .cleanup && model.source == .ollama && model.validationError == nil {
            return "Available for dictation cleanup · \(model.source.displayName)"
        }
        return "Configuration only · \(model.source.displayName)"
    }

    private func presentError(_ error: String) {
        downloadError = DictationProblem(error, downloading: true).message
        showErrorAlert = true
    }

}

#Preview {
    NavigationStack {
        ModelManagerView(modelManager: ModelManager())
    }
}
