// DictusApp/Views/ModelManagerView.swift
// Native model management UI backed by the real model catalog and manager state.
import SwiftUI
import DictusCore

/// Displays the seven loadable models in native Installed and Available sections.
struct ModelManagerView: View {
    @ObservedObject var modelManager: ModelManager

    @State private var modelToDelete: ModelInfo?
    @State private var showDeleteAlert = false
    @State private var partialModelToDelete: ModelInfo?
    @State private var showPartialDeleteAlert = false
    @State private var downloadError: String?
    @State private var showErrorAlert = false
    @State private var showAddModel = false
    @State private var customModelToDelete: CustomModel?

    /// Only prewarming and RAM loading use the blocking preparation cover.
    /// Downloads stay in the list so their real cancel action remains reachable.
    @State private var preparingModelID: String?

    private let deviceCapabilities = DeviceCapabilities.current()

    private var installedModels: [ModelInfo] {
        ModelInfo.installedRows(from: ModelInfo.allIncludingDeprecated)
            .filter(isInstalled)
    }

    private var availableModels: [ModelInfo] {
        return ModelInfo.available(on: deviceCapabilities)
            .filter { !isInstalled($0) }
    }

    private func isInstalled(_ model: ModelInfo) -> Bool {
        if modelManager.downloadedModels.contains(model.identifier) { return true }
        return modelManager.modelStates[model.identifier] == .ready
    }

    /// The first model currently compiling or loading, in catalog order.
    private var liveActivePrepModel: String? {
        if modelManager.modelLoadState == .loading,
           let active = modelManager.activeModel {
            return active
        }
        return ModelInfo.allIncludingDeprecated.first { model in
            modelManager.modelStates[model.identifier] == .prewarming
        }?.identifier
    }

    var body: some View {
        modelManagerContent
    }

    private var modelManagerContent: some View {
        // Xcode 26.3 can time out when it carries the concrete nested List type
        // through every sheet, alert, and cover modifier below.
        AnyView(configuredModelList)
        .sheet(isPresented: $showAddModel) {
            NavigationStack { AddCustomModelView(modelManager: modelManager) }
        }
        .alert("Delete custom model?", isPresented: Binding(get: { customModelToDelete != nil }, set: { if !$0 { customModelToDelete = nil } })) {
            Button("Cancel", role: .cancel) { customModelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = customModelToDelete { modelManager.deleteCustomModel(model) }
                customModelToDelete = nil
            }
        } message: {
            Text("This removes the saved model configuration from sAiity.")
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
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let downloadError {
                Text(downloadError)
            }
        }
        .onChange(of: liveActivePrepModel) { _, newValue in
            if let newValue, preparingModelID == nil {
                preparingModelID = newValue
            }
        }
        .onAppear {
            if preparingModelID == nil {
                preparingModelID = liveActivePrepModel
            }
        }
        .fullScreenCover(item: Binding<PreparingModelItem?>(
            get: { preparingModelID.map(PreparingModelItem.init) },
            set: { preparingModelID = $0?.id }
        )) { item in
            ModelLoadingOverlay(
                modelManager: modelManager,
                modelIdentifier: item.id,
                context: .modelSelection,
                isPresented: Binding(
                    get: { preparingModelID != nil },
                    set: { if !$0 { preparingModelID = nil } }
                )
            )
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddModel = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add custom model")
                }
            }
    }

    @ViewBuilder
    private var modelList: some View {
        List {
            installedSection
            availableSection
            customModelsSection(.asr, title: "Custom speech recognition")
            customModelsSection(.cleanup, title: "Custom cleanup")
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
            Text("Installed")
        } footer: {
            modelEngineFooter(for: installedModels)
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var availableSection: some View {
        Section {
            if availableModels.isEmpty {
                Text("All available models are installed")
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
            Text("Available")
        } footer: {
            modelEngineFooter(for: availableModels)
        }
        .listSectionSeparator(.hidden)
    }

    private struct PreparingModelItem: Identifiable {
        let id: String
    }

    private func modelRow(
        _ model: ModelInfo,
        incompatibilityReason: ModelInfo.IncompatibilityReason? = nil
    ) -> some View {
        ModelCardView(
            model: model,
            modelManager: modelManager,
            onDownloadError: { error in
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
    private func customModelsSection(_ role: CustomModelRole, title: String) -> some View {
        let models = modelManager.customModels.filter { $0.role == role }
        if !models.isEmpty {
            Section(title) {
                ForEach(models) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.name)
                            Text("\(model.source.displayName) · \(model.role.displayName)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(customModelStatus(model)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { customModelToDelete = model } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
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
        downloadError = error
        showErrorAlert = true
    }

    @ViewBuilder
    private func modelEngineFooter(for models: [ModelInfo]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if models.contains(where: { $0.engine == .whisperKit }) {
                Text("WhisperKit runs speech recognition locally on Apple silicon.")
            }
            if models.contains(where: { $0.engine == .parakeet }) {
                Text("Parakeet is a fast on-device recognition engine from NVIDIA.")
            }
        }
        .font(.caption)
    }
}

private struct AddCustomModelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var modelManager: ModelManager
    @State private var name = ""
    @State private var url = ""
    @State private var role: CustomModelRole = .asr
    @State private var source: CustomModelSource = .huggingFace
    @State private var modelName = ""
    @State private var isVerifying = false
    @State private var verificationError: String?
    @State private var verifiedIdentityKey: String?

    private var model: CustomModel {
        let candidate = CustomModel(name: name, repositoryURL: url, role: role, source: source,
                                    modelName: modelName.isEmpty ? nil : modelName)
        return CustomModel(id: candidate.id, name: candidate.name, repositoryURL: candidate.repositoryURL,
                           role: candidate.role, source: candidate.source, modelName: candidate.modelName,
                           remoteValidationState: verifiedIdentityKey == candidate.identityKey ? .verified : candidate.remoteValidationState)
    }

    var body: some View {
        Form {
            Section("Model") {
                Picker("Use for", selection: $role) {
                    Text(CustomModelRole.asr.displayName).tag(CustomModelRole.asr)
                    Text(CustomModelRole.cleanup.displayName).tag(CustomModelRole.cleanup)
                }
                Picker("Source", selection: $source) {
                    Text(CustomModelSource.huggingFace.displayName).tag(CustomModelSource.huggingFace)
                    if role == .asr { Text(CustomModelSource.nvidia.displayName).tag(CustomModelSource.nvidia) }
                    if role == .cleanup { Text(CustomModelSource.ollama.displayName).tag(CustomModelSource.ollama) }
                }
                TextField("Display name", text: $name)
                TextField("Repository URL", text: $url)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                if source == .ollama {
                    TextField("Ollama model name", text: $modelName)
                        .textInputAutocapitalization(.never)
                }
                if let error = model.validationError { Text(error).font(.caption).foregroundStyle(.red) }
                if role == .asr && source == .huggingFace && model.validationError == nil {
                    Button(isVerifying ? "Checking model..." : "Check model") {
                        verifyModel()
                    }
                    .disabled(isVerifying)
                    if let verificationError {
                        Text(verificationError).font(.caption).foregroundStyle(.red)
                    } else if verifiedIdentityKey == model.identityKey {
                        Label("ASR model verified", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            Section { Text("Ollama cleanup models are used for dictation cleanup. Custom speech-recognition sources are saved for future runtime support and are not loaded yet.")
                .font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Add Model")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { modelManager.addCustomModel(model); dismiss() }
                    .disabled(model.validationError != nil ||
                              (role == .asr && source == .huggingFace && model.remoteValidationState != .verified))
            }
        }
        .onChange(of: role) { _, newRole in
            if newRole == .asr && source == .ollama { source = .huggingFace }
            if newRole == .cleanup && source == .nvidia { source = .ollama }
        }
        .onChange(of: model.identityKey) { _, _ in
            verifiedIdentityKey = nil
            verificationError = nil
        }
    }

    private func verifyModel() {
        let candidate = model
        isVerifying = true
        verificationError = nil
        Task {
            let error = await candidate.remoteValidationError()
            await MainActor.run {
                verificationError = error
                verifiedIdentityKey = error == nil ? candidate.identityKey : nil
                isVerifying = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        ModelManagerView(modelManager: ModelManager())
    }
}
