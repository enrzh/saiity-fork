// DictusApp/Views/ModelManagerView.swift
// Native model management UI backed by the real model catalog and manager state.
import SwiftUI
import DictusCore

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
            .contentMargins(.bottom, 88, for: .scrollContent)
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Model, engine or language")
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private var modelList: some View {
        List {
            Section {
                NavigationLink {
                    VoiceOptionsView(modelManager: modelManager)
                } label: {
                    Label("Voice options", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("Choose app and keyboard models in Voice options. Manage downloads here.")
            }
            installedSection
            availableSection
            dictationCleanupSection
        }
    }

    @ViewBuilder
    private var installedSection: some View {
        Section {
            if installedModels.isEmpty {
                Text("No models installed")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(installedModels) { model in
                    modelRow(model)
                }
            }
        } header: {
            modelSectionHeader("Installed", systemImage: "tray.full.fill")
        } footer: {
            modelEngineFooter(for: installedModels)
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var availableSection: some View {
        Section {
            if availableModels.isEmpty {
                Text(searchText.isEmpty ? "All available models are installed" : "No matching downloads")
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
            modelSectionHeader("Downloads", systemImage: "arrow.down.circle")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                modelEngineFooter(for: availableModels)
                Text("Recommendations reflect compatibility and editorial guidance, not measured accuracy on your iPhone.")
            }
        }
        .listSectionSeparator(.hidden)
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
        .listRowSeparator(.hidden)
    }

    private func requestDelete(_ model: ModelInfo) {
        modelToDelete = model
        showDeleteAlert = true
    }

    @ViewBuilder
    private var dictationCleanupSection: some View {
        let cleanupModels = modelManager.customModels.filter { $0.role == .cleanup }
        Section {
            CleanupModelPicker(manager: modelManager)
            appleIntelligenceCleanupRow
            ForEach(LocalCleanupModel.allCases, id: \.self) { model in
                CleanupModelCardView(model: model, manager: modelManager)
            }
            ForEach(cleanupModels) { model in
                customCleanupRow(model)
            }
        } header: {
            modelSectionHeader("Dictation cleanup", systemImage: "sparkles")
        } footer: {
            Text("Speech recognition and text processing use separate models. Apple supports background processing; downloaded local processing models require Syllivra to stay open.")
                .font(.caption)
        }
        .listSectionSeparator(.hidden)
    }

    private var isAppleIntelligenceCleanupActive: Bool {
        modelManager.cleanupBackend == .appleIntelligence
    }

    private var appleIntelligenceCleanupRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Apple Intelligence")
                    if isAppleIntelligenceCleanupActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                Text("On-device Foundation Models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(PolishAvailability.guidance(for: PolishAvailability.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isAppleIntelligenceCleanupActive {
                Button {
                    modelManager.selectCleanupBackend(.appleIntelligence)
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.saiityOnAction)
                .controlSize(.small)
                .accessibilityHint("Uses Apple Intelligence for dictation cleanup")
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    private func customCleanupRow(_ model: CustomModel) -> some View {
        let isActive = modelManager.cleanupBackend == .ollama(model.id)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.name)
                    if isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                Text("\(model.source.displayName) · \(model.role.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(customModelStatus(model)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if model.validationError == nil && !isActive {
                    Button {
                        modelManager.selectCleanupBackend(.ollama(model.id))
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityHint("Uses this Ollama model for dictation cleanup")
                }
                Button(role: .destructive) { customModelToDelete = model } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(model.name)")
            }
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
    }

    private func modelSectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
        .padding(.bottom, 4)
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

    @ViewBuilder
    private func modelEngineFooter(for models: [ModelInfo]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if models.contains(where: { $0.engine == .whisperKit }) {
                Text("WhisperKit runs speech recognition locally on Apple silicon.")
            }
            if models.contains(where: { $0.engine == .parakeet }) {
                Text("NVIDIA on-device ASR is Parakeet v2/v3. Nemotron speech checkpoints are not in the current FluidAudio runtime, so they are not one-tap downloads.")
            }
        }
        .font(.caption)
    }
}

#Preview {
    NavigationStack {
        ModelManagerView(modelManager: ModelManager())
    }
}
