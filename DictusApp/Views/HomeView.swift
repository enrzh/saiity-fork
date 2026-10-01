// DictusApp/Views/HomeView.swift
// Home dashboard showing real model readiness, dictation, and recent output.
import SwiftUI
import AVFoundation
import DictusCore

struct HomeView: View {
    @ObservedObject var modelManager: ModelManager
    @EnvironmentObject var coordinator: DictationCoordinator
    @EnvironmentObject var proStatus: ProStatusManager
    @AppStorage(SharedKeys.modelReady, store: AppGroup.defaults) private var modelReady = false

    @State private var showCopiedFeedback = false
    @State private var microphonePermission = MicrophonePermissionState.undetermined
    @AppStorage(SharedKeys.serviceEnabled, store: AppGroup.defaults) private var serviceEnabled = true
    @AppStorage(SharedKeys.modelLoadState, store: AppGroup.defaults) private var modelLoadStateRaw = ModelLoadState.idle.rawValue
    @AppStorage(SharedKeys.modelLoadFailure, store: AppGroup.defaults) private var modelLoadFailure = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section("Model selection") {
                ModelSelectionProfilePicker(modelManager: modelManager)
                Text(modelManager.selectionMode == .manual ? "Using your selected model. Choose a preset for automatic selection." : modelManager.selectionProfile.explanation)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                readinessPanel
                Toggle("Keyboard dictation", isOn: $serviceEnabled)
                    .onChange(of: serviceEnabled) { _, enabled in
                        updateServiceEnabled(enabled)
                    }
                    .accessibilityIdentifier("home.keyboardDictationToggle")
                readinessAction
            } header: {
                Text("Dictation")
            } footer: {
                Text("Enabling keyboard dictation makes it available from your keyboard. Recording starts only when you speak using the dictation control.")
            }

            Section {
                modelRow
            } header: {
                Text("Voice model")
            } footer: {
                Text("Used for new dictations. Recognition and speed depend on your device and spoken languages.")
            }

            if !recentDictationItems.isEmpty {
                Section("Recent dictations") {
                    recentActivity(items: recentDictationItems)
                    NavigationLink {
                        DictationHistoryView()
                    } label: {
                        Label("See all history", systemImage: "clock.arrow.circlepath")
                    }
                }
                .accessibilityIdentifier("home.recentActivity")
            }

            if PremiumFlags.paywallVisible {
                Section {
                    ProBannerView()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Speak")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            refreshMicrophonePermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DictusOnboardingCompleted"))) { _ in
            refreshMicrophonePermission()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshMicrophonePermission()
            }
        }
    }

    private var readinessPanel: some View {
        let readiness = currentReadiness
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: readiness.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(readinessColor(readiness))
                .frame(width: 30, height: 30)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(readiness.title)
                        .font(.headline)
                    Text(readinessSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var modelRow: some View {
        NavigationLink {
            ModelManagerView(modelManager: modelManager)
        } label: {
            LabeledContent {
                Text(ModelInfo.forIdentifier(modelManager.activeModel ?? "")?.displayName ?? "Choose a model")
                    .foregroundStyle(.secondary)
            } label: {
                Label("Active model", systemImage: "square.stack.3d.up")
            }
        }
        .accessibilityHint("Opens the models page")
    }

    private var recentDictationItems: [RecentDictation] {
        Array(RecentDictations.load(from: AppGroup.defaults).prefix(3))
    }

    @ViewBuilder
    private var readinessAction: some View {
        let readiness = currentReadiness
        if readiness.action == .openSettings {
            Button { openSystemSettings() } label: {
                actionRow("Open Settings", systemImage: "arrow.up.right")
            }
            .buttonStyle(.plain)
        } else if readiness.action == .requestMicrophone {
            Button { requestMicrophoneAccess() } label: {
                actionRow("Allow microphone", systemImage: "mic.badge.plus")
            }
            .buttonStyle(.plain)
        } else if !modelLoadFailure.isEmpty && readiness.action == .retry {
            Button { retryModelLoad() } label: {
                actionRow("Retry model load", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        } else if readiness.action == .retry {
            Button { coordinator.startDictation() } label: {
                actionRow("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        } else if readiness.action == .start {
            newDictationButton
        } else if modelLoadStateRaw == ModelLoadState.loading.rawValue {
            HStack(spacing: 12) {
                ProgressView()
                Text("Preparing your model")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
    }

    private func actionRow(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func readinessColor(_ readiness: DictationReadiness) -> Color {
        switch readiness.action {
        case .start: return .dictusSuccess
        case .retry, .openSettings: return .dictusRecording
        case .requestMicrophone: return .dictusAccent
        case .none: return .secondary
        }
    }

    private var newDictationButton: some View {
        Button {
            coordinator.startDictation()
        } label: {
            HStack(spacing: 12) {
                Label("Start dictation", systemImage: "waveform")
                    .foregroundStyle(.tint)
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.newDictation")
    }

    @ViewBuilder
    private func recentActivity(items: [RecentDictation]) -> some View {
        ForEach(items) { item in
            HStack(alignment: .top, spacing: 12) {
                NavigationLink {
                    DictationHistoryEditView(item: item) { edited in
                        RecentDictations.update(edited, in: AppGroup.defaults)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.text)
                            .font(.body)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Date(timeIntervalSince1970: item.createdAt), style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("Opens the full dictation")
                HStack(spacing: 4) {
                    Button { copy(item.text) } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy dictation")
                    ShareLink(item: item.text) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Share dictation")
                }
            }
            .frame(minHeight: 44)
        }
        if showCopiedFeedback {
            Label("Copied", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }
    }

    private func copy(_ result: String) {
        UIPasteboard.general.string = result
        HapticFeedback.recordingStopped()
        showCopiedFeedback = true
        UIAccessibility.post(notification: .announcement, argument: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopiedFeedback = false }
    }

    private var currentReadiness: DictationReadiness {
        DictationReadiness(serviceEnabled: serviceEnabled, microphonePermission: microphonePermission,
                           modelReady: modelReady, modelLoadState: ModelLoadState(rawValue: modelLoadStateRaw) ?? .idle,
                           status: coordinator.status, modelLoadFailure: modelLoadFailure)
    }

    private var readinessSubtitle: String {
        if currentReadiness.action == .retry, let error = DictationErrorChannel.current {
            return userFacingError(error)
        }
        return currentReadiness.subtitle
    }

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { refreshMicrophonePermission() }
        }
    }

    private func retryModelLoad() {
        modelLoadFailure = ""
        coordinator.preloadActiveModel()
    }

    private func refreshMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .authorized
        case .denied:
            microphonePermission = .denied
        case .notDetermined:
            microphonePermission = .undetermined
        case .restricted:
            microphonePermission = .restricted
        @unknown default:
            microphonePermission = .restricted
        }
    }

    private func updateServiceEnabled(_ enabled: Bool) {
        if enabled {
            coordinator.enableKeyboardSession()
            return
        }

        coordinator.disableKeyboardSession()
        if DictationSessionLivenessPolicy.isActive(coordinator.status) {
            coordinator.cancelDictation()
        }
        LiveActivityManager.shared.updateServiceEnabled(false)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func userFacingError(_ message: String) -> String {
        message
            .replacingOccurrences(of: "Dictus", with: "sAiity")
            .replacingOccurrences(of: "dictus", with: "sAiity")
    }
}

#Preview {
    NavigationStack {
        HomeView(modelManager: ModelManager())
            .environmentObject(DictationCoordinator.shared)
            .environmentObject(ProStatusManager())
    }
}

/// Shared typographic hierarchy for the app, independent of the keyboard's glass surfaces.
struct SaiityPageHeader: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow).font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.tint)
            Text(title).font(.largeTitle.weight(.bold)).tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }
}

struct DictationHistoryView: View {
    @State private var items: [RecentDictation] = []
    @State private var searchText = ""
    @State private var showClearConfirmation = false
    @AppStorage(SharedKeys.historyEnabled, store: AppGroup.defaults) private var historyEnabled = true

    private var filteredItems: [RecentDictation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No dictations yet" : "No matching dictations",
                    systemImage: searchText.isEmpty ? "waveform" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Completed dictations will appear here." : "Try another search.")
                )
            } else {
                ForEach(filteredItems) { item in
                    historyRow(item)
                }
                .onDelete(perform: deleteItems)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dictation history")
        .searchable(text: $searchText, prompt: "Search dictations")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Save dictation history", isOn: $historyEnabled)
                    .onChange(of: historyEnabled) { _, enabled in
                        if !enabled {
                            RecentDictations.disable(in: AppGroup.defaults)
                        }
                    }
                Text("Saved text stays on this iPhone. Turning saving off keeps existing entries, stops adding new ones, and removes the transcript from the diagnostic snapshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) {
                        showClearConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear dictation history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                RecentDictations.clear(in: AppGroup.defaults)
                reload()
            }
        } message: {
            Text("This removes saved dictation text from this device.")
        }
        .onAppear(perform: reload)
    }

    private func historyRow(_ item: RecentDictation) -> some View {
        NavigationLink {
            DictationHistoryEditView(item: item) { edited in
                RecentDictations.update(edited, in: AppGroup.defaults)
                reload()
            }
        } label: {
            Text(item.text)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHint("Opens the full dictation")
        }
        .padding(.vertical, 4)
    }

    private func reload() {
        items = RecentDictations.load(from: AppGroup.defaults)
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets where filteredItems.indices.contains(index) {
            RecentDictations.remove(filteredItems[index].id, from: AppGroup.defaults)
        }
        reload()
    }
}

private struct DictationHistoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let item: RecentDictation
    let onSave: (RecentDictation) -> Void

    init(item: RecentDictation, onSave: @escaping (RecentDictation) -> Void) {
        self.item = item
        self.onSave = onSave
        _text = State(initialValue: item.text)
    }

    var body: some View {
        Form {
            Section("Dictation") {
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .accessibilityLabel("Dictation text")
            }
        }
        .navigationTitle("Edit dictation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(RecentDictation(id: item.id, text: text, createdAt: item.createdAt))
                    dismiss()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Copy dictation")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: text) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Share dictation")
            }
        }
    }
}
