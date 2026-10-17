// DictusApp/Views/HomeView.swift
// Home dashboard showing real model readiness, dictation, and recent output.
import SwiftUI
import AVFoundation
import SyllivraKernel

struct HomeView: View {
    @ObservedObject var modelManager: ModelManager
    @EnvironmentObject var coordinator: DictationCoordinator
    @EnvironmentObject var proStatus: ProStatusManager
    @AppStorage(SharedKeys.appDictationModelReady, store: AppGroup.defaults) private var modelReady = false

    @State private var showCopiedFeedback = false
    @ObservedObject private var replay = RecordingReplay.shared
    @State private var microphonePermission = MicrophonePermissionState.undetermined
    @State private var recentDictationItems: [RecentDictation] = []
    @AppStorage(SharedKeys.recentDictations, store: AppGroup.defaults) private var recentDictationData = Data()
    @AppStorage(SharedKeys.historyEnabled, store: AppGroup.defaults) private var historyEnabled = true
    @AppStorage(SharedKeys.serviceEnabled, store: AppGroup.defaults) private var serviceEnabled = true
    @AppStorage(SharedKeys.modelLoadState, store: AppGroup.defaults) private var modelLoadStateRaw = ModelLoadState.idle.rawValue
    @AppStorage(SharedKeys.modelLoadFailure, store: AppGroup.defaults) private var modelLoadFailure = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        List {
            Section {
                readinessPanel
                readinessAction
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Section {
                NavigationLink { VoiceOptionsView(modelManager: modelManager) } label: {
                    LabeledContent("Spoken languages", value: SpokenLanguagePreferences.summary(SpokenLanguagePreferences.load(from: AppGroup.defaults)))
                }
                .accessibilityIdentifier("home.voiceOptions")
                .accessibilityHint("Choose spoken languages and voice models.")
                keyboardPowerRow
            } footer: {
                if serviceEnabled && (coordinator.isPreparingKeyboardSession || !coordinator.keyboardSessionEnabled) {
                    Text(LocalizedStringKey(coordinator.isPreparingKeyboardSession ? "Preparing the keyboard microphone…"
                         : "Microphone needs preparation. Turn keyboard dictation off and on when you’re ready."))
                }
            }
            if replay.available && coordinator.canChangeSpeechRuntime {
                Section {
                    Button(replay.playing ? "Stop replay" : replay.trimmed ? "Replay last 60 seconds" : "Replay last recording") { replay.toggle() }
                    if let message = replay.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section("Recent dictations") {
                if !historyEnabled {
                    Text("History is off. New dictations aren’t saved.").foregroundStyle(.secondary)
                } else if recentDictationItems.isEmpty {
                    Text("Your finished text will appear here.").foregroundStyle(.secondary)
                }
                recentActivity(items: recentDictationItems)
                NavigationLink("History", destination: DictationHistoryView())
            }
            .accessibilityIdentifier("home.recentActivity")

            if PremiumFlags.paywallVisible {
                Section { ProBannerView() }
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .navigationTitle("Speak")
        .navigationBarTitleDisplayMode(.large)
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

    private var readinessPanel: some View {
        let readiness = currentReadiness
        return Label {
            VStack(alignment: .leading, spacing: 6) {
                Text(readiness.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if readiness.action != .start {
                    Text(readinessSubtitle).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if readiness.action == .start && modelManager.recognizer == .streaming {
                    Text("Keep Syllivra open while streaming.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: readiness.symbol)
        }
    }

    private var keyboardPowerRow: some View {
        Toggle("Keyboard dictation", isOn: Binding(
            get: { serviceEnabled },
            set: { enabled in coordinator.setKeyboardDictationEnabled(enabled) }
        ))
        .accessibilityHint("Turning on prepares the microphone for your keyboard. Hold its microphone to record a dictation.")
        .accessibilityIdentifier("home.keyboardDictationToggle")
    }

    private func reloadRecentDictations() {
        recentDictationItems = Array(RecentDictations.load(from: AppGroup.defaults).prefix(3))
    }

    @ViewBuilder
    private var readinessAction: some View {
        let readiness = currentReadiness
        if readiness.action == .openSettings {
            Button { openSystemSettings() } label: {
                actionRow("Open Settings", systemImage: "arrow.up.right")
            }
        } else if readiness.action == .requestMicrophone {
            Button { requestMicrophoneAccess() } label: {
                actionRow("Allow microphone", systemImage: "mic.badge.plus")
            }
        } else if readiness.action == .models || readiness.action == .repairDownload {
            NavigationLink { ModelManagerView(modelManager: modelManager) } label: {
                actionRow("Models & downloads", systemImage: "arrow.down.circle")
            }
        } else if !modelLoadFailure.isEmpty && readiness.action == .retry {
            Button { retryModelLoad() } label: {
                actionRow("Retry model load", systemImage: "arrow.clockwise")
            }
        } else if readiness.action == .retry {
            Button { coordinator.startDictation() } label: {
                actionRow("Try again", systemImage: "arrow.clockwise")
            }
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
        } else if !modelReady && !DictationSessionLivenessPolicy.isActive(coordinator.status) {
            NavigationLink {
                ModelManagerView(modelManager: modelManager)
            } label: {
                Label("Choose a voice model", systemImage: "arrow.down.circle")
            }
        }
    }

    private func actionRow(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }

    private var newDictationButton: some View {
        Button {
            coordinator.startDictation()
        } label: {
            Label("Start dictation", systemImage: "mic.fill")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityIdentifier("home.newDictation")
    }

    @ViewBuilder
    private func recentActivity(items: [RecentDictation]) -> some View {
        ForEach(items) { item in
            let rowLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            rowLayout {
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
                        Text(Date(timeIntervalSince1970: item.createdAt).formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .accessibilityHint("Opens the full dictation")
                Button { copy(item.text) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .padding(.vertical, 4)
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
        DictationReadiness(serviceEnabled: true,
                           microphonePermission: microphonePermission,
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

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func userFacingError(_ message: String) -> String {
        DictationProblem(message).message
    }

}

#Preview {
    NavigationStack {
        HomeView(modelManager: ModelManager())
            .environmentObject(DictationCoordinator.shared)
            .environmentObject(ProStatusManager())
    }
}

/// Contextual access to the existing preferences and download manager.
struct VoiceOptionsView: View {
    @ObservedObject var modelManager: ModelManager

    var body: some View {
        List {
            Section {
                SpokenLanguagesPicker(modelManager: modelManager)
            }
            DictationSettingsAdvisor(modelManager: modelManager)
            Section("In Syllivra") {
                DictationModelQuickPicker(scope: .app, modelManager: modelManager)
                Label(modelManager.isModelReady ? "Ready in Syllivra" : "Choose or install a voice model", systemImage: modelManager.isModelReady ? "checkmark.circle" : "arrow.down.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("From your keyboard") {
                DisclosureGroup("Choose a keyboard model") {
                    DictationModelQuickPicker(scope: .keyboard, modelManager: modelManager)
                }
                Label(modelManager.keyboardModel == nil ? "Keyboard model needed" : "Keyboard model installed", systemImage: modelManager.keyboardModel == nil ? "arrow.down.circle" : "checkmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink {
                    ModelManagerView(modelManager: modelManager)
                } label: {
                    Label("Models & downloads", systemImage: "square.stack.3d.up")
                }
            } footer: {
                Text("Voice model changes apply to your next dictation.")
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .navigationTitle("Voice options")
        .navigationBarTitleDisplayMode(.inline)
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
    @AppStorage(SharedKeys.historyEnabled, store: AppGroup.defaults) private var historyEnabled = true

    private var filteredItems: [RecentDictation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            Section {
                Toggle("Save dictation history", isOn: $historyEnabled)
                    .onChange(of: historyEnabled) { _, enabled in
                        if !enabled {
                            RecentDictations.disable(in: AppGroup.defaults)
                        }
                    }
            } footer: {
                Text("Saved text stays on this iPhone. Turning saving off keeps existing entries, stops adding new ones, and removes the transcript from the diagnostic snapshot.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if filteredItems.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No dictations yet" : "No matching dictations",
                    systemImage: searchText.isEmpty ? "waveform" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Completed dictations will appear here." : "Try another search.")
                )
            } else {
                Section("Saved dictations") {
                    ForEach(filteredItems) { item in
                        historyRow(item)
                    }
                    .onDelete(perform: deleteItems)
                }
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .navigationTitle("History")
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
                Text(Date(timeIntervalSince1970: item.createdAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
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
                    .navigationTitle("Edit transcript")
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
