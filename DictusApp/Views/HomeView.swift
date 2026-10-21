// DictusApp/Views/HomeView.swift
// The app's single root list: readiness, keyboard dictation, recent text and settings.
import SwiftUI
import AVFoundation
import SyllivraKernel

struct HomeView: View {
    @ObservedObject var modelManager: ModelManager
    @EnvironmentObject var coordinator: DictationCoordinator
    @AppStorage(SharedKeys.appDictationModelReady, store: AppGroup.defaults) private var modelReady = false

    @ObservedObject private var replay = RecordingReplay.shared
    @State private var microphonePermission = MicrophonePermissionState.undetermined
    @State private var recentDictationItems: [RecentDictation] = []
    @AppStorage(SharedKeys.recentDictations, store: AppGroup.defaults) private var recentDictationData = Data()
    @AppStorage(SharedKeys.historyEnabled, store: AppGroup.defaults) private var historyEnabled = true
    @AppStorage(SharedKeys.serviceEnabled, store: AppGroup.defaults) private var serviceEnabled = true
    @AppStorage(SharedKeys.modelLoadState, store: AppGroup.defaults) private var modelLoadStateRaw = ModelLoadState.idle.rawValue
    @AppStorage(SharedKeys.modelLoadFailure, store: AppGroup.defaults) private var modelLoadFailure = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            if currentReadiness.action != .start {
                Section { readinessRows }
            }
            Section {
                Toggle("Keyboard Dictation", isOn: Binding(
                    get: { serviceEnabled },
                    set: { enabled in coordinator.setKeyboardDictationEnabled(enabled) }
                ))
                .accessibilityIdentifier("home.keyboardDictationToggle")
            } footer: {
                Text(LocalizedStringKey(keyboardFooter))
            }
            if replay.available && coordinator.canChangeSpeechRuntime {
                Section {
                    Button(replay.playing ? "Stop Replay" : replay.trimmed ? "Replay Last 60 Seconds" : "Replay Last Recording") { replay.toggle() }
                } footer: {
                    if let message = replay.message { Text(message) }
                }
            }
            if historyEnabled && !recentDictationItems.isEmpty {
                Section("Recent") {
                    ForEach(recentDictationItems) { recentRow($0) }
                    NavigationLink("All Dictations") { DictationHistoryView() }
                }
                .accessibilityIdentifier("home.recentActivity")
            }
            Section {
                NavigationLink("Dictation") { DictationSettingsView(modelManager: modelManager) }
                    .accessibilityIdentifier("settings.dictation")
                NavigationLink("Keyboard") { KeyboardSettingsView() }
                    .accessibilityIdentifier("settings.keyboard")
                NavigationLink { ModelManagerView(modelManager: modelManager) } label: {
                    LabeledContent("Models", value: activeModelName)
                }
                .accessibilityLabel("Models")
                .accessibilityValue(activeModelName)
                .accessibilityIdentifier("settings.models")
            }
            Section {
                NavigationLink("Help") { HelpView() }
                    .accessibilityIdentifier("settings.help")
                NavigationLink("About") { AboutView() }
                    .accessibilityIdentifier("settings.about")
            }
        }
        .navigationTitle("Syllivra")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button { coordinator.startDictation() } label: {
                    Label("New Dictation", systemImage: "mic")
                }
                .disabled(currentReadiness.action != .start)
                .accessibilityIdentifier("home.newDictation")
            }
        }
        .onDisappear { replay.stop() }
        .onAppear {
            replay.refreshAvailability()
            refreshMicrophonePermission()
            reloadRecentDictations()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DictusOnboardingCompleted"))) { _ in
            refreshMicrophonePermission()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshMicrophonePermission()
                reloadRecentDictations()
            }
        }
        .onChange(of: recentDictationData) { _, _ in reloadRecentDictations() }
    }

    /// One problem, one sentence and one way forward.
    @ViewBuilder
    private var readinessRows: some View {
        let readiness = currentReadiness
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(readiness.title).font(.headline)
                if modelLoadStateRaw == ModelLoadState.loading.rawValue && readiness.action == .none {
                    ProgressView()
                }
            }
            Text(readinessSubtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
        switch readiness.action {
        case .openSettings:
            Button("Open Settings", action: openSystemSettings)
        case .requestMicrophone:
            Button("Allow Microphone", action: requestMicrophoneAccess)
        case .models, .repairDownload:
            NavigationLink("Models") { ModelManagerView(modelManager: modelManager) }
        case .retry:
            Button("Try Again") {
                if modelLoadFailure.isEmpty { coordinator.startDictation() } else { retryModelLoad() }
            }
        case .none where !modelReady && modelLoadStateRaw != ModelLoadState.loading.rawValue:
            NavigationLink("Choose a Voice Model") { ModelManagerView(modelManager: modelManager) }
        case .none, .start:
            EmptyView()
        }
    }

    private var keyboardFooter: String {
        if !serviceEnabled { return "Turn on to dictate from the Syllivra keyboard in any app." }
        if coordinator.isPreparingKeyboardSession { return "Preparing the keyboard microphone…" }
        if !coordinator.keyboardSessionEnabled {
            return "Microphone needs preparation. Turn keyboard dictation off and on when you’re ready."
        }
        return "Hold the microphone on the Syllivra keyboard to dictate."
    }

    private var activeModelName: String {
        modelManager.activeModel.flatMap(ModelInfo.forIdentifier)?.displayName ?? ""
    }

    private func recentRow(_ item: RecentDictation) -> some View {
        NavigationLink {
            DictationHistoryEditView(item: item) { edited in
                RecentDictations.update(edited, in: AppGroup.defaults)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text).lineLimit(2)
                Text(Self.shortDate(item.createdAt)).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityHint("Opens the full dictation")
        .swipeActions(edge: .leading) {
            Button("Copy", systemImage: "doc.on.doc") { copy(item) }.tint(.accentColor)
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { copy(item) }
            ShareLink(item: item.text)
        }
    }

    /// Time for today, "Yesterday", then a short date.
    static func shortDate(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func reloadRecentDictations() {
        recentDictationItems = Array(RecentDictations.load(from: AppGroup.defaults).prefix(3))
    }

    private func copy(_ item: RecentDictation) {
        UIPasteboard.general.string = item.text
        HapticFeedback.recordingStopped()
        UIAccessibility.post(notification: .announcement, argument: "Copied")
    }

    private var currentReadiness: DictationReadiness {
        DictationReadiness(serviceEnabled: true,
                           microphonePermission: microphonePermission,
                           modelReady: modelReady, modelLoadState: ModelLoadState(rawValue: modelLoadStateRaw) ?? .idle,
                           status: coordinator.status, modelLoadFailure: modelLoadFailure)
    }

    private var readinessSubtitle: String {
        if currentReadiness.action == .retry, let error = DictationErrorChannel.current {
            return DictationProblem(error).message
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

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        HomeView(modelManager: ModelManager())
            .environmentObject(DictationCoordinator.shared)
    }
}

/// Shared typographic hierarchy for the app, independent of the keyboard's glass surfaces.
struct SaiityPageHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title.weight(.bold))
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
                Section {
                    ForEach(filteredItems) { item in
                        historyRow(item)
                    }
                    .onDelete(perform: deleteItems)
                }
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .navigationTitle("Dictations")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search dictations")
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
            VStack(alignment: .leading, spacing: 6) {
                Text(item.text).font(.body).lineSpacing(3)
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                Text(HomeView.shortDate(item.createdAt))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityHint("Opens the full dictation")
        }
        .padding(.vertical, 8)
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

/// Shared comparison/copy/recovery controls for a live result and saved history.
struct DictationTranscriptResult: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let result: String
    let original: String?
    var onRestore: ((String) -> Void)?
    var onFeedback: ((RecentDictation.Feedback) -> Void)?
    var translationFallback = false
    @State private var showOriginal = false
    @State private var copied = false
    @State private var restoreBackup: String?
    @State private var rated = false
    @State private var isEditing = false
    @State private var editingText = ""

    private var differs: Bool {
        guard let original else { return false }
        return original.trimmingCharacters(in: .whitespacesAndNewlines) != result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var displayed: String { showOriginal ? original ?? result : result }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if translationFallback {
                Label("Translation could not be verified. Original kept.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(displayed).font(.title2).lineSpacing(4).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { resultActions }
                VStack(alignment: .leading, spacing: 8) { resultActions }
            }
            .font(.subheadline)
            if showOriginal {
                Text("Original is speech recognition before cleanup or translation.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let onRestore, let original, (differs && showOriginal) || restoreBackup != nil {
                Button(restoreBackup == nil ? (typeSize.isAccessibilitySize ? "Original" : "Use original")
                       : (typeSize.isAccessibilitySize ? "Result" : "Restore previous result")) {
                    let replacement = restoreBackup ?? original
                    restoreBackup = restoreBackup == nil ? result : nil
                    showOriginal = false
                    onRestore(replacement)
                }.buttonStyle(.bordered).accessibilityIdentifier("dictation.restoreOriginal")
                    .accessibilityLabel(restoreBackup == nil ? "Use original transcript" : "Restore previous result")
            }
            if rated {
                Text("Feedback saved on this device.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                TextEditor(text: $editingText)
                    .font(.body).padding(16)
                    .accessibilityLabel("Dictation text")
                    .navigationTitle("Edit Transcript")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isEditing = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { onRestore?(editingText); showOriginal = false; isEditing = false }
                        }
                    }
            }
        }
        .onChange(of: showOriginal) { _, _ in copied = false }
        .onChange(of: result) { _, _ in copied = false; showOriginal = false }
    }

    @ViewBuilder private var resultActions: some View {
        copyButton
        if onRestore != nil {
            Button { editingText = displayed; isEditing = true } label: {
                Label("Edit", systemImage: "pencil").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain).foregroundStyle(.primary).accessibilityIdentifier("dictation.editResult")
        }
        Menu {
            if differs {
                Button { showOriginal.toggle() } label: {
                    Label(showOriginal ? "Show result" : "Show original", systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("dictation.resultVariant")
                .accessibilityLabel("Transcript version")
                .accessibilityValue(showOriginal ? "Original" : "Result")
            }
            shareButton
            if onFeedback != nil && !rated {
                Section("Could you use the delivered result without editing?") {
                    feedbackButton(.accepted, "Usable unchanged", "hand.thumbsup")
                    feedbackButton(.needsEditing, "Needs editing", "pencil")
                }
            }
        } label: {
            Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
        }.foregroundStyle(.primary).accessibilityLabel("More transcript actions")
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = displayed
            copied = true
            UIAccessibility.post(notification: .announcement, argument: "Copied")
        } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").frame(minHeight: 44) }
            .buttonStyle(.bordered)
            .tint(.primary)
            .accessibilityLabel(copied ? "Copied transcript" : "Copy transcript")
    }
    private var shareButton: some View {
        ShareLink(item: displayed) { Label("Share", systemImage: "square.and.arrow.up") }
    }
    private func feedbackButton(_ feedback: RecentDictation.Feedback, _ label: String, _ icon: String) -> some View {
        let title = typeSize.isAccessibilitySize ? (feedback == .accepted ? "Usable" : "Edit") : label
        return Button { onFeedback?(feedback); rated = true } label: { Label(title, systemImage: icon) }
            .accessibilityLabel(label)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(Date(timeIntervalSince1970: item.createdAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote).foregroundStyle(.secondary)
                DictationTranscriptResult(result: text, original: item.originalText,
                    onRestore: { text = $0 }, onFeedback: {
                        RecentDictations.recordFeedback(text == item.text ? $0 : .needsEditing,
                            for: item.id, in: AppGroup.defaults)
                    })
            }
            .frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemBackground))
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(RecentDictation(id: item.id, text: text, createdAt: item.createdAt,
                        originalText: item.originalText, feedback: text == item.text ? item.feedback : .needsEditing))
                    dismiss()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
