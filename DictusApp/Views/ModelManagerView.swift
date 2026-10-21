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
    @State private var searchText = ""
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
            .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Model or language")
    }

    @ViewBuilder
    private var modelList: some View {
        List {
            Section {
                voiceModelPicker
            } footer: {
                if !coordinator.canChangeSpeechRuntime {
                    Text("Finish this dictation before changing voice settings.")
                } else {
                    Text("Automatic picks the best installed model for your languages and this iPhone.")
                }
            }
            installedSection
            availableSection
        }
    }

    /// One choice for the app and the keyboard. Automatic keeps their separate
    /// defaults (the keyboard favours a lighter model while it runs in the background).
    private var voiceModelPicker: some View {
        let selected = modelManager.selectionMode == .automatic ? "automatic" : modelManager.activeModel ?? "unavailable"
        let choices = ModelInfo.installedRows(from: ModelInfo.allIncludingDeprecated).filter {
            isInstalled($0) && $0.isRuntimeAvailable(onOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                                                      capabilities: deviceCapabilities)
        }.sorted { $0.sizeBytes < $1.sizeBytes }
        return Picker("Voice Model", selection: Binding(
            get: { selected },
            set: { choice in
                if choice == "automatic" {
                    modelManager.useRecommendedSettings()
                } else {
                    modelManager.selectModel(choice)
                    modelManager.chooseKeyboardModel(choice)
                }
            }
        )) {
            let automatic = modelManager.selectionMode == .automatic ? modelManager.activeModel : nil
            Text(automatic.flatMap(ModelInfo.forIdentifier).map { "Automatic (\($0.displayName))" } ?? "Automatic")
                .tag("automatic")
            if selected != "automatic" && !choices.contains(where: { $0.identifier == selected }) {
                Text(ModelInfo.forIdentifier(selected)?.displayName ?? String(localized: "No compatible model"))
                    .tag(selected).disabled(true)
            }
            ForEach(choices) { model in
                Text(model.displayName).tag(model.identifier)
            }
        }
        .pickerStyle(.menu)
        .disabled(!coordinator.canChangeSpeechRuntime)
        .accessibilityIdentifier("models.voiceModel")
    }

    @ViewBuilder
    private var installedSection: some View {
        if !installedModels.isEmpty {
            Section("Installed") {
                ForEach(installedModels) { model in
                    modelRow(model)
                }
            }
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
            Text("Available")
        } footer: {
            Text("Voice models run on this iPhone. Recommended means compatible with it and your languages.")
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
