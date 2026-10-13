// DictusApp/Views/ModelCardView.swift
// Native model-management row with real lifecycle state and actions.
import SwiftUI
import SyllivraKernel

/// Renders one catalog model as a native List row.
///
/// The row reads all metadata and lifecycle state from ModelInfo and ModelManager.
/// Download and cancellation lifecycles belong to ModelManager so they survive
/// SwiftUI view reconstruction.
struct ModelCardView: View {
    let model: ModelInfo
    @ObservedObject var modelManager: ModelManager
    let onDownloadError: (String) -> Void

    /// A non-nil reason keeps an unavailable model visible but prevents actions.
    var incompatibilityReason: ModelInfo.IncompatibilityReason?

    /// The parent owns confirmation alerts so every destructive menu action shares one path.
    var onDeleteRequest: (() -> Void)?
    var onDeletePartialRequest: (() -> Void)?

    @State private var showsLanguageInfo = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var state: ModelState {
        modelManager.modelStates[model.identifier] ?? .notDownloaded
    }

    private var isActive: Bool {
        modelManager.activeModel == model.identifier
    }

    private var isLoading: Bool {
        isActive && modelManager.modelLoadState == .loading
    }

    private var canDeleteModel: Bool {
        !isActive && modelManager.downloadedModels.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            modelSummary
                .frame(maxWidth: .infinity, alignment: .leading)
            actionContent
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityHint(incompatibilityReason.map { Text($0.localizedText) } ?? Text(""))
        .sheet(isPresented: $showsLanguageInfo) {
            ModelLanguageDetailView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var modelSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            ModelCardHeading(name: model.displayName, size: model.sizeLabel,
                             active: isActive, recommended: modelManager.isRecommended(model.identifier))

            Text(model.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(model.engine == .qwenASR ? Color.primary : .secondary)
                .lineLimit(typeSize.isAccessibilitySize || model.engine == .qwenASR ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Text(model.languageSupport.coverage.localizedSummary)
                .font(.caption).foregroundStyle(model.engine == .qwenASR ? Color.primary : .secondary)
            if model.isExperimental {
                Label("Preview · validate on your iPhone", systemImage: "flask")
                    .font(.caption).foregroundStyle(.primary)
            }

            statusContent

            downloadProgressContent
        }
    }

    private var downloadProgressContent: some View {
        Group {
            if case .downloading = state {
                VStack(alignment: .leading, spacing: 3) {
                    if let progress = modelManager.downloadProgress[model.identifier] {
                        ProgressView(value: Double(progress), total: 1)
                            .tint(.accentColor)
                            .accessibilityValue(Text(downloadProgressLabel(progress)))
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    let metadataLayout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 6))
                    metadataLayout {
                        if let progress = modelManager.downloadProgress[model.identifier] {
                            Text(downloadProgressLabel(progress))
                        }
                        if let bytes = modelManager.downloadByteInfo[model.identifier] {
                            Text("\(bytes.downloadedMB) MB of \(bytes.totalMB) MB")
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minHeight: 32, alignment: .leading)
            }
        }
    }

    private func downloadProgressLabel(_ progress: Float) -> String {
        "\(Int(progress * 100)) percent"
    }

    @ViewBuilder
    private var statusContent: some View {
        if let incompatibilityReason {
            Label("Unavailable · \(incompatibilityReason.localizedText)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.primary)
        } else if isLoading {
            Label("Loading", systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.tint)
        } else {
            switch state {
            case .notDownloaded:
                Label("Not installed", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .downloading:
                Label("Downloading", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.tint)
            case .prewarming:
                Label("Preparing", systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.tint)
            case .ready:
                if isActive {
                    EmptyView()
                } else {
                    Label("Installed", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .error(let message):
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text(DictationProblem(message, downloading: true).message)
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        let actionLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        actionLayout {
            primaryAction
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Button {
                showsLanguageInfo = true
            } label: {
                Label("Info", systemImage: "info.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Supported languages")

            if state == .ready || isFailed {
                deleteButton
            }
        }
        if state == .ready && !canDeleteModel {
            Text(isActive ? "Choose another model before deleting this one." : "Keep at least one voice model installed.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if incompatibilityReason != nil {
            EmptyView()
        } else if isLoading || state == .prewarming {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(Text(isLoading ? "Loading" : "Preparing"))
        } else {
            switch state {
            case .notDownloaded:
                Button {
                    startDownload()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .frame(minHeight: 44)
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.saiityOnAction)
                .controlSize(.small)
                .accessibilityHint("Downloads this model")
            case .downloading:
                Button {
                    modelManager.cancelCatalogDownload(model.identifier)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .frame(minHeight: 44)
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .prewarming:
                EmptyView()
            case .ready:
                if !isActive {
                    Button {
                        modelManager.selectModel(model.identifier)
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                            .frame(minHeight: 44)
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color.saiityOnAction)
                    .controlSize(.small)
                    .accessibilityHint("Uses this model for transcription")
                }
            case .error(let message):
                Button {
                    startDownload()
                } label: {
                    Label(DictationProblem(message, downloading: true).action == .repairDownload ? "Repair download" : "Retry", systemImage: "arrow.clockwise.circle")
                        .frame(minHeight: 44)
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .foregroundStyle(Color.saiityOnAction)
                .help(DictationProblem(message, downloading: true).message)
            }
        }
    }

    private var isFailed: Bool {
        if case .error = state { return true }
        return false
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            if isFailed {
                onDeletePartialRequest?()
            } else {
                onDeleteRequest?()
            }
        } label: {
            Label("Delete", systemImage: "trash")
                .frame(minHeight: 44)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!isFailed && !canDeleteModel)
        .accessibilityHint(isFailed ? "Removes partial download files." : canDeleteModel ? "Removes this model from the device." : "At least one installed model must remain active.")
    }

    private func startDownload() {
        modelManager.startCatalogDownload(model.identifier, onError: onDownloadError)
    }

}

struct ModelCardHeading: View {
    let name: String
    let size: String
    var active = false
    var recommended = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let headingLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        headingLayout {
            Text(name).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            if active {
                Text("Active").font(.caption.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if recommended {
                Text("Recommended").font(.caption.weight(.semibold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(size).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CleanupModelCardView: View {
    let model: LocalCleanupModel
    @ObservedObject var manager: ModelManager
    @ObservedObject private var cleanup = CleanupModelManager.shared
    @State private var showInfo = false
    @State private var confirmDelete = false
    @State private var deleteError: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var active: Bool { manager.cleanupBackend == .local(model) }
    private var downloading: Bool { cleanup.preparing == model }
    private var size: String {
        cleanup.installedBytes[model].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "4-bit"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModelCardHeading(name: model.displayName, size: size, active: active)
            Text(model.explanation).font(.subheadline).foregroundStyle(.primary)
            Label(downloading ? "Preparing" : cleanup.installedBytes[model] != nil ? "Downloaded" : "Not installed",
                  systemImage: downloading ? "arrow.down.circle" : "sparkles")
                .font(.caption).foregroundStyle(.secondary)
            if downloading { ProgressView(value: cleanup.progress) }
            if let error = cleanup.error, cleanup.failedModel == model {
                Text(error).font(.footnote).foregroundStyle(.primary)
            }
            let actionLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            actionLayout {
                if downloading {
                    Button { cleanup.cancel() } label: {
                        Label("Cancel", systemImage: "xmark.circle").frame(minHeight: 44)
                    }.buttonStyle(.bordered)
                } else if !active {
                    Button {
                        cleanup.select(model, manager: manager)
                    } label: {
                        Label(cleanup.installedBytes[model] != nil ? "Select" : "Download", systemImage: "arrow.down.circle")
                            .frame(minHeight: 44)
                    }.buttonStyle(.borderedProminent).foregroundStyle(Color.saiityOnAction)
                        .disabled(cleanup.preparing != nil)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button { showInfo = true } label: {
                    Label("Info", systemImage: "info.circle").frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.bordered)
                if cleanup.installedBytes[model] != nil && !active {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                    }
                        .accessibilityLabel("Delete \(model.displayName)").disabled(cleanup.preparing != nil)
                }
            }.controlSize(.small)
        }
        .padding(.vertical, 6)
        .onAppear { cleanup.refreshArtifacts() }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                List {
                    Section("Processing model") {
                        LabeledContent("Model", value: model.displayName)
                        LabeledContent("Engine", value: "MLX · on device")
                        LabeledContent("Parameters", value: model.parameterCount)
                        LabeledContent("Quantization", value: "4-bit")
                        LabeledContent("Storage", value: cleanup.installedBytes[model].map {
                            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                        } ?? "Not downloaded")
                    }
                    Section("Use") {
                        Text("Punctuation, cleanup and grammar run in one pass. Keep Syllivra open while processing; Apple Foundation Models remains the background option.")
                        Text("Speed depends on text length and your iPhone. Mixed-language rewrites are checked and fall back to conservative cleanup when meaning changes.")
                        Text(model.explanation)
                    }
                    if let source = URL(string: "https://huggingface.co/" + model.repository) {
                        Section { Link("Model card, languages and license", destination: source) }
                    }
                }
                .navigationTitle(model.displayName)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showInfo = false } } }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .alert("Delete processing model?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                do { try cleanup.delete(model, manager: manager) } catch { deleteError = error.localizedDescription }
            }
        } message: { Text("Delete the downloaded files for \(model.displayName)?") }
        .alert("Could not delete model", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
    }
}

#Preview {
    List {
        ModelCardView(
            model: ModelInfo.redesignCatalog[0],
            modelManager: ModelManager(),
            onDownloadError: { _ in }
        )
    }
    .listStyle(.insetGrouped)
}
