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

    private var isKeyboardModel: Bool {
        modelManager.keyboardModel == model.identifier
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
            actionContent
        }
        .padding(.vertical, 8)
        .labelStyle(.titleAndIcon)
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
                             active: isActive || isKeyboardModel,
                             activeLabel: isActive ? (isKeyboardModel ? "App & keyboard" : "In app") : "Keyboard",
                             recommended: modelManager.isRecommended(model.identifier))

            Text(model.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(model.engine == .qwenASR ? Color.primary : .secondary)
                .lineLimit(typeSize.isAccessibilitySize || model.engine == .qwenASR ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Label(model.languageSupport.coverage.localizedSummary, systemImage: "globe")
                .font(.caption).foregroundStyle(model.engine == .qwenASR ? Color.primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            case .notDownloaded, .ready:
                EmptyView()
            case .downloading:
                Label("Downloading", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.tint)
            case .prewarming:
                Label("Preparing", systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.tint)
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
            modelMenu
        }
        .buttonStyle(.borderless)
        .font(.subheadline.weight(.semibold))
    }

    private var modelMenu: some View {
        Menu {
            Button { showsLanguageInfo = true } label: {
                Label("Model details", systemImage: "info.circle")
            }
            if state == .ready || isFailed { deleteButton }
        } label: {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(.secondary).buttonStyle(.borderless)
        .accessibilityLabel("Actions for \(model.displayName)")
        .accessibilityIdentifier("model.actions.\(model.identifier)")
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
                .accessibilityLabel("Download \(model.displayName)")
                .accessibilityHint("Downloads this model")
            case .downloading:
                Button {
                    modelManager.cancelCatalogDownload(model.identifier)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Cancel download of \(model.displayName)")
            case .prewarming:
                EmptyView()
            case .ready:
                if !isActive {
                    Button {
                        modelManager.selectModel(model.identifier)
                    } label: {
                        Label("Use in app", systemImage: "checkmark.circle")
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Use \(model.displayName) in app")
                    .accessibilityHint("Uses this model for transcription")
                }
            case .error(let message):
                Button {
                    startDownload()
                } label: {
                    Label(DictationProblem(message, downloading: true).action == .repairDownload ? "Repair download" : "Retry",
                          systemImage: "arrow.clockwise")
                        .frame(minHeight: 44)
                }
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
        }
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
    var activeLabel = "Selected"
    var recommended = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let titleLayout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        VStack(alignment: .leading, spacing: 6) {
            titleLayout {
                Text(name).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !size.isEmpty {
                    Text(size).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                }
            }
            if active {
                Label(activeLabel, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium)).foregroundStyle(.tint)
                    .fixedSize(horizontal: false, vertical: true)
            } else if recommended {
                Text("Recommended").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
        cleanup.installedBytes[model].map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModelCardHeading(name: model.displayName, size: size, active: active)
            Text(model.explanation).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !active || downloading {
                Label(downloading ? "Preparing" : cleanup.installedBytes[model] != nil ? "Installed" : "Not installed",
                      systemImage: downloading ? "arrow.down.circle" : cleanup.installedBytes[model] != nil ? "checkmark.circle" : "arrow.down.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if downloading {
                ProgressView(value: cleanup.progress)
                    .accessibilityValue("\(Int(cleanup.progress * 100)) percent")
            }
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
                    }
                } else if !active {
                    Button {
                        cleanup.select(model, manager: manager)
                    } label: {
                        Label(cleanup.installedBytes[model] != nil ? "Use for processing" : "Download & use",
                              systemImage: cleanup.installedBytes[model] != nil ? "checkmark.circle" : "arrow.down.circle")
                            .frame(minHeight: 44)
                    }
                    .disabled(cleanup.preparing != nil)
                    .accessibilityLabel(cleanup.installedBytes[model] != nil ? "Use \(model.displayName) for processing" : "Download and use \(model.displayName) for processing")
                    .accessibilityHint("Downloads this model if needed, then selects it for processing")
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                processingMenu
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 8)
        .labelStyle(.titleAndIcon)
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
                .listStyle(.insetGrouped)
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

    private var processingMenu: some View {
        Menu {
            Button { showInfo = true } label: { Label("Model details", systemImage: "info.circle") }
            if cleanup.installedBytes[model] != nil {
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(active || cleanup.preparing != nil)
                    .accessibilityHint(active ? "Choose another processing model before deleting this one." : "Removes this model from the device.")
            }
        } label: {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(.secondary).buttonStyle(.borderless)
        .accessibilityLabel("Actions for \(model.displayName)")
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
    .listStyle(.plain)
}
