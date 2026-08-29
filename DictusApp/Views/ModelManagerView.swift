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

    /// Only prewarming and RAM loading use the blocking preparation cover.
    /// Downloads stay in the list so their real cancel action remains reachable.
    @State private var preparingModelID: String?

    private let deviceCapabilities = DeviceCapabilities.current()

    private var installedModels: [ModelInfo] {
        ModelInfo.redesignCatalog.filter { isInstalled($0) }
    }

    private var availableModels: [ModelInfo] {
        let catalogIDs = Set(ModelInfo.redesignCatalog.map(\.identifier))
        return ModelInfo.available(on: deviceCapabilities)
            .filter { catalogIDs.contains($0.identifier) && !isInstalled($0) }
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
        return ModelInfo.redesignCatalog.first { model in
            modelManager.modelStates[model.identifier] == .prewarming
        }?.identifier
    }

    private func canDelete(_ model: ModelInfo) -> Bool {
        modelManager.modelStates[model.identifier] == .ready
            && modelManager.activeModel != model.identifier
            && modelManager.downloadedModels.count > 1
    }

    var body: some View {
        List {
            Section("Installed") {
                if installedModels.isEmpty {
                    Text("No models installed")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(installedModels) { model in
                        modelRow(model)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canDelete(model) {
                                    Button(role: .destructive) {
                                        requestDelete(model)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }

            Section("Available") {
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
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Models")
        .background(Color.dictusBackground.ignoresSafeArea())
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
            if preparingModelID == nil, let liveActivePrepModel {
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
        .listRowBackground(Color.dictusSurface)
        .listRowSeparator(.visible)
    }

    private func requestDelete(_ model: ModelInfo) {
        modelToDelete = model
        showDeleteAlert = true
    }

    private func presentError(_ error: String) {
        downloadError = error
        showErrorAlert = true
    }
}

#Preview {
    NavigationStack {
        ModelManagerView(modelManager: ModelManager())
    }
}
