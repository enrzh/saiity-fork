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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.displayName)
                    .font(.headline)
                    .lineLimit(2)

                if isActive {
                    Text("Active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                } else if modelManager.isRecommended(model.identifier) {
                    Text("Recommended")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Spacer(minLength: 0)
                Text(model.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(model.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(model.languageSupport.coverage.localizedSummary)
                .font(.caption).foregroundStyle(.secondary)
            if model.isExperimental {
                Label("Preview · validate on your iPhone", systemImage: "flask")
                    .font(.caption).foregroundStyle(.orange)
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
                if isActive {
                    EmptyView()
                } else {
                    Label("Installed", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .error:
                Label("Failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        HStack(spacing: 8) {
            primaryAction
            Spacer(minLength: 0)
            Button {
                showsLanguageInfo = true
            } label: {
                Label("Info", systemImage: "info.circle")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Supported languages")

            if state == .ready || isFailed {
                deleteButton
            }
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
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityHint("Downloads this model")
            case .downloading:
                Button {
                    modelManager.cancelCatalogDownload(model.identifier)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
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
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityHint("Uses this model for transcription")
                }
            case .error(let message):
                Button {
                    startDownload()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise.circle")
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .foregroundStyle(.orange)
                .help(message)
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
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!isFailed && !canDeleteModel)
        .accessibilityHint(canDeleteModel ? "Removes this model from the device." : "At least one installed model must remain active.")
    }

    private func startDownload() {
        modelManager.startCatalogDownload(model.identifier, onError: onDownloadError)
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
