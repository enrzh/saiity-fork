// DictusApp/Views/ModelCardView.swift
// Native model-management row with real lifecycle state and actions.
import SwiftUI
import DictusCore

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
    @State private var downloadTask: Task<Void, Never>?

    private let actionColumnWidth: CGFloat = 128

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
        HStack(alignment: .center, spacing: 12) {
            modelSummary
                .frame(maxWidth: .infinity, alignment: .leading)
            actionContent
                .frame(width: actionColumnWidth, alignment: .trailing)
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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.displayName)
                    .font(.headline)
                    .lineLimit(2)

                if modelManager.isRecommended(model.identifier) {
                    Text("Recommended")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }

            Text(model.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text("\(model.engine.displayName) · \(model.sizeLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Text("Accuracy \(scoreText(model.accuracyScore))")
                Text("Speed \(scoreText(model.speedScore))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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

                    HStack(spacing: 6) {
                        if let progress = modelManager.downloadProgress[model.identifier] {
                            Text(downloadProgressLabel(progress))
                        }
                        if let bytes = modelManager.downloadByteInfo[model.identifier] {
                            Text("· \(bytes.downloadedMB) MB of \(bytes.totalMB) MB")
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(height: 32, alignment: .leading)
            }
        }
    }

    private func scoreText(_ score: Double) -> String {
        "\(Int(score * 100))%"
    }

    private func downloadProgressLabel(_ progress: Float) -> String {
        "\(Int(progress * 100)) percent"
    }

    @ViewBuilder
    private var statusContent: some View {
        if let incompatibilityReason {
            Label("Unavailable · \(incompatibilityReason.localizedText)", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Label(isActive ? "Active" : "Installed", systemImage: isActive ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(isActive ? .green : .secondary)
            case .error:
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        VStack(alignment: .trailing, spacing: 2) {
            primaryAction
                .frame(minHeight: 44)
            HStack(spacing: 0) {
                Button {
                    showsLanguageInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Supported languages")

                if state == .ready || isFailed {
                    deletionMenu
                }
            }
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if incompatibilityReason != nil {
            Color.clear
                .frame(height: 44)
                .accessibilityHidden(true)
        } else if isLoading || state == .prewarming {
            ProgressView()
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(Text(isLoading ? "Loading" : "Preparing"))
        } else {
            switch state {
            case .notDownloaded:
                Button {
                    startDownload()
                } label: {
                    Text("Download")
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityHint("Downloads this model")
            case .downloading:
                Button("Cancel", role: .cancel) {
                    downloadTask?.cancel()
                }
                .fixedSize(horizontal: true, vertical: false)
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
            case .prewarming:
                Color.clear.frame(height: 44).accessibilityHidden(true)
            case .ready:
                if !isActive {
                    Button {
                        modelManager.selectModel(model.identifier)
                    } label: {
                        Text("Select")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("Uses this model for transcription")
                } else {
                    Color.clear.frame(height: 44).accessibilityHidden(true)
                }
            case .error(let message):
                Button {
                    startDownload()
                } label: {
                    Text("Retry")
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(.orange)
                .help(message)
            }
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
        downloadTask = Task { @MainActor in
            do {
                try await modelManager.downloadModel(model.identifier)
            } catch is CancellationError {
                // Manager cancellation resolves the request to .notDownloaded.
            } catch {
                onDownloadError(error.localizedDescription)
            }
        }
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
