// DictusApp/Views/ModelCardView.swift
// Native model-management row with real lifecycle state and actions.
import SwiftUI
import DictusCore

/// Renders one catalog model as a native List row.
///
/// The row reads all metadata and lifecycle state from ModelInfo and ModelManager.
/// Download tasks are kept here because the existing manager API exposes the
/// async download operation, while cancellation is performed by cancelling that
/// operation's Task.
struct ModelCardView: View {
    let model: ModelInfo
    @ObservedObject var modelManager: ModelManager
    let onDownloadError: (String) -> Void

    /// A non-nil reason keeps an unavailable model visible but prevents actions.
    var incompatibilityReason: ModelInfo.IncompatibilityReason?

    /// The parent owns confirmation alerts so swipe and menu deletion share one path.
    var onDeleteRequest: (() -> Void)?
    var onDeletePartialRequest: (() -> Void)?

    @State private var showsLanguageInfo = false
    @State private var isCancelling = false
    @State private var downloadTask: Task<Void, Never>?

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
        HStack(alignment: .top, spacing: 12) {
            modelSummary
            Spacer(minLength: 8)
            actionContent
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(incompatibilityReason == nil ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityHint(incompatibilityReason.map { Text($0.localizedText) } ?? Text(""))
        .sheet(isPresented: $showsLanguageInfo) {
            ModelLanguageDetailView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var modelSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(model.displayName)
                    .font(.headline)
                    .lineLimit(2)

                if modelManager.isRecommended(model.identifier) {
                    Text("Recommended")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.dictusAccent)
                }
            }

            Text("\(model.engine.displayName) · \(model.sizeLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            statusContent

            if case .downloading = state,
               let progress = modelManager.downloadProgress[model.identifier] {
                ProgressView(value: Double(progress), total: 1)
                    .tint(Color.dictusAccent)
                    .accessibilityValue(Text("\(Int(progress * 100)) percent"))

                if let bytes = modelManager.downloadByteInfo[model.identifier] {
                    Text("\(bytes.downloadedMB) MB of \(bytes.totalMB) MB")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusContent: some View {
        if let incompatibilityReason {
            Label("Unavailable · \(incompatibilityReason.localizedText)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isCancelling {
            Label("Cancelling", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isLoading {
            Label("Loading", systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(Color.dictusAccent)
        } else {
            switch state {
            case .notDownloaded:
                Label("Not installed", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .downloading:
                Label("Downloading", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(Color.dictusAccent)
            case .prewarming:
                Label("Preparing", systemImage: "gearshape")
                    .font(.caption)
                    .foregroundStyle(Color.dictusAccent)
            case .ready:
                Label(isActive ? "Active" : "Installed", systemImage: isActive ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(isActive ? Color.dictusSuccess : .secondary)
            case .error:
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        if incompatibilityReason != nil {
            EmptyView()
        } else if isCancelling {
            ProgressView()
                .accessibilityLabel("Cancelling")
        } else if isLoading || state == .prewarming {
            ProgressView()
                .accessibilityLabel(Text(isLoading ? "Loading" : "Preparing"))
        } else {
            switch state {
            case .notDownloaded:
                Button {
                    startDownload()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Downloads this model")
            case .downloading:
                if downloadTask != nil {
                    Button("Cancel", role: .cancel) {
                        cancelDownload()
                    }
                    .buttonStyle(.borderless)
                }
            case .prewarming:
                EmptyView()
            case .ready:
                if !isActive {
                    Button {
                        modelManager.selectModel(model.identifier)
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Uses this model for transcription")
                }
            case .error(let message):
                Button {
                    startDownload()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
                .help(message)
            }
        }

        Button {
            showsLanguageInfo = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Supported languages")

        if state == .ready || isFailed {
            deletionMenu
        }
    }

    private var isFailed: Bool {
        if case .error = state { return true }
        return false
    }

    private var deletionMenu: some View {
        Menu {
            if isFailed {
                Button(role: .destructive) {
                    onDeletePartialRequest?()
                } label: {
                    Label("Delete partial download", systemImage: "trash")
                }
            } else if canDeleteModel {
                Button(role: .destructive) {
                    onDeleteRequest?()
                } label: {
                    Label("Delete model", systemImage: "trash")
                }
            } else if modelManager.downloadedModels.count <= 1 {
                Button("At least one model must stay installed") { }
                    .disabled(true)
            } else {
                Button("Select another model to delete this one") { }
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Model options")
    }

    private func startDownload() {
        guard downloadTask == nil else { return }
        isCancelling = false
        downloadTask = Task { @MainActor in
            do {
                try await modelManager.downloadModel(model.identifier)
            } catch is CancellationError {
                modelManager.cleanupFailedModel(model.identifier)
            } catch {
                onDownloadError(error.localizedDescription)
            }
            downloadTask = nil
            isCancelling = false
        }
    }

    private func cancelDownload() {
        guard let downloadTask else { return }
        isCancelling = true
        downloadTask.cancel()
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
    .background(Color.dictusBackground)
}
