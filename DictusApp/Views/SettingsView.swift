import AVFoundation
import SwiftUI
import UIKit
import DictusCore

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var polishEnabled = true
    @AppStorage(SharedKeys.transcriptionOutputMode, store: UserDefaults(suiteName: AppGroup.identifier)) private var transcriptionOutputModeRaw = TranscriptionOutputMode.defaultMode.storedValue
    @AppStorage(SharedKeys.writingStyle, store: UserDefaults(suiteName: AppGroup.identifier)) private var writingStyleRaw = WritingStyle.defaultStyle.rawValue
    @AppStorage(SharedKeys.hapticIntensity, store: UserDefaults(suiteName: AppGroup.identifier)) private var hapticIntensityRaw = HapticIntensity.on.rawValue
    @AppStorage(SharedKeys.keyContainersEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var keyContainersEnabled = false
    @AppStorage(SharedKeys.autocorrectEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var autocorrectEnabled = true
    @State private var microphonePermission = AVAudioSession.sharedInstance().recordPermission
    @ObservedObject var modelManager: ModelManager
    @State private var diagnosticResult = AppGroupDiagnostic.run()

    var body: some View {
        List {
            Section {
                if PolishAvailability.isToggleVisible {
                    Toggle("Automatic cleanup", isOn: $polishEnabled)
                        .accessibilityHint("Cleans up dictation after speech recognition.")
                    NavigationLink {
                        CleanupSettingsView(modelManager: modelManager)
                    } label: {
                        Label("Cleanup options", systemImage: "sparkles")
                    }
                }
                Picker("Dictation output", selection: $transcriptionOutputModeRaw) {
                    ForEach(TranscriptionOutputMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.storedValue)
                    }
                }
                Picker("Writing style", selection: $writingStyleRaw) {
                    ForEach(WritingStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                DictationPresencePicker()
            } header: {
                Text("Dictation")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(activeOutputMode.explanation)
                    if PolishAvailability.state != .available {
                        polishStateFooter
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Keyboard layout") {
                    TypingLanguagesPanel()
                }
                DefaultKeyboardModePicker()
                Toggle("Autocorrection", isOn: $autocorrectEnabled)
                    .accessibilityHint("Automatically corrects common misspellings.")
                    .onChange(of: autocorrectEnabled) { _, _ in
                        KeyboardInteractionPreferences.notifyChanged()
                    }
                Toggle("Keyboard haptics", isOn: hapticsEnabledBinding)
                    .accessibilityHint("Provides a vibration when keys are pressed.")
                Toggle("Key containers", isOn: $keyContainersEnabled)
                    .accessibilityHint("Draws a plate behind letter and symbol keys. Command keys keep their plates.")
                    .onChange(of: keyContainersEnabled) { _, _ in
                        KeyboardInteractionPreferences.notifyChanged()
                    }
                KeyPopupPicker()
                KeyboardMaterialPicker()
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Language follows the iPhone.")
            }

            Section("Personalization") {
                NavigationLink {
                    VocabularyView()
                } label: {
                    Label("Vocabulary", systemImage: "character.book.closed")
                }
                NavigationLink {
                    TextSnippetsView()
                } label: {
                    Label("Text replacements", systemImage: "text.badge.plus")
                }
            }

            Section("Help") {
                NavigationLink {
                    DictationHistoryView()
                } label: {
                    Label("Dictation history", systemImage: "clock.arrow.circlepath")
                }

                Button(action: openSystemSettings) {
                    HStack {
                        Label("Microphone", systemImage: "mic.fill")
                        Spacer(minLength: 12)
                        Text(permissionLabel)
                            .foregroundStyle(permissionForeground)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens iPhone Settings")

                NavigationLink { troubleshootingView } label: {
                    Label("Troubleshooting", systemImage: "wrench.and.screwdriver")
                }

                if let supportURL = URL(string: "https://github.com/enrzh") {
                    Link(destination: supportURL) {
                        Label("Get support", systemImage: "questionmark.circle")
                    }
                }
            }

            Section("About") {
                NavigationLink { LicensesView() } label: {
                    Label("Licenses", systemImage: "doc.text")
                }

                if let privacyURL = URL(string: "https://aiity.de/privacy") {
                    Link(destination: privacyURL) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

                LabeledContent("Version", value: appVersionText)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            microphonePermission = AVAudioSession.sharedInstance().recordPermission
            diagnosticResult = AppGroupDiagnostic.run()
            let intensity = HapticIntensity.load(from: UserDefaults(suiteName: AppGroup.identifier))
            hapticIntensityRaw = intensity.rawValue
            intensity.persist()
            modelManager.loadState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                microphonePermission = AVAudioSession.sharedInstance().recordPermission
                diagnosticResult = AppGroupDiagnostic.run()
            }
        }
    }

    private var hapticsEnabledBinding: Binding<Bool> {
        Binding(
            get: { HapticIntensity.load(from: UserDefaults(suiteName: AppGroup.identifier)).isEnabled },
            set: { enabled in
                let value: HapticIntensity = enabled ? .on : .off
                hapticIntensityRaw = value.rawValue
                value.persist()
                HapticFeedback.refreshEnabledState()
            }
        )
    }

    private var activeOutputMode: TranscriptionOutputMode {
        TranscriptionOutputMode(storedValue: transcriptionOutputModeRaw)
    }

    private var appVersionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return String(localized: "Normal")
        case .fair: return String(localized: "Warm")
        case .serious: return String(localized: "Hot · slower processing")
        case .critical: return String(localized: "Cooling needed")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private var troubleshootingView: some View {
        List {
            Section("Setup") {
                Button("Open iPhone Settings", action: openSystemSettings)
                Text("Enable sAiity under General → Keyboard → Keyboards. Allow microphone access for dictation.")
                    .font(.caption)
            }
            Section("On this iPhone") {
                let device = DeviceCapabilities.current()
                LabeledContent("Device memory", value: "\(device.physicalMemoryGB) GB")
                LabeledContent("Thermal condition", value: thermalLabel(device.thermalState))
            }
            Section("Diagnostics") {
                NavigationLink("Report last dictation") { LastDictationIssueReportView() }
                NavigationLink("Debug Logs") { DebugLogView() }
                NavigationLink("Diagnostics") { DiagnosticDetailView(result: diagnosticResult) }
            }
        }
        .navigationTitle("Troubleshooting")
    }

    @ViewBuilder private var polishStateFooter: some View {
        let state = PolishAvailability.state
        if state != .available {
            VStack(alignment: .leading, spacing: 6) {
                Text(polishStateMessage(for: state)).font(.caption).foregroundStyle(.secondary)
                if PolishAvailability.canOpenSystemSettings(for: state) {
                    Button("Open iPhone Settings", action: openSystemSettings).font(.caption.bold())
                }
            }
        }
    }

    private var permissionLabel: String {
        switch microphonePermission {
        case .granted: return "Allowed"
        case .denied: return "Denied"
        case .undetermined: return "Not set"
        @unknown default: return "Unknown"
        }
    }

    private var permissionForeground: Color {
        switch microphonePermission {
        case .granted: return .secondary
        case .denied: return Color(.systemRed)
        case .undetermined: return Color(.systemOrange)
        @unknown default: return .secondary
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func polishStateMessage(for state: PolishAvailabilityState) -> String {
        switch state {
        case .available: return ""
        default: return PolishAvailability.guidance(for: state)
        }
    }
}

private struct CleanupSettingsView: View {
    @ObservedObject var modelManager: ModelManager
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var polishEnabled = true

    private var backend: Binding<PolishCleanupBackend> {
        Binding(get: { modelManager.cleanupBackend }, set: { modelManager.selectCleanupBackend($0) })
    }

    var body: some View {
        List {
            Section {
                Toggle("Automatic cleanup", isOn: $polishEnabled)
                Picker("Cleanup model", selection: backend) {
                    Text(PolishCleanupBackend.appleIntelligence.displayName)
                        .tag(PolishCleanupBackend.appleIntelligence)
                    ForEach(PolishCleanupBackend.validOllamaCleanupModels(from: modelManager.customModels)) { model in
                        Text(model.name).tag(PolishCleanupBackend.ollama(model.id))
                    }
                }
            } footer: {
                Text(PolishAvailability.guidance(for: PolishAvailability.state))
            }
        }
        .navigationTitle("Cleanup")
    }
}

struct VocabularyView: View {
    @State private var newWord = ""
    @State private var words: [String] = []
    @State private var showingResetConfirmation = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("Add a word or name", text: $newWord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } footer: {
                Text("These words are protected from local autocorrection and improve your personal dictionary.")
            }

            Section("Learned words") {
                if words.isEmpty {
                    Text("No custom words yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                    }
                    .onDelete(perform: deleteWords)
                }
            }

            if !words.isEmpty {
                Section {
                    Button("Reset learned words", role: .destructive) {
                        showingResetConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Vocabulary")
        .toolbar { EditButton() }
        .confirmationDialog(
            "Reset learned words?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                UserDictionary.shared.resetAll()
                reload()
            }
        } message: {
            Text("This removes every word sAiity learned from your typing.")
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        UserDictionary.shared.reload()
        words = UserDictionary.shared.allLearnedWords.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        _ = UserDictionary.shared.learn(word)
        newWord = ""
        reload()
    }

    private func deleteWords(at offsets: IndexSet) {
        for index in offsets where words.indices.contains(index) {
            UserDictionary.shared.forget(words[index])
        }
        reload()
    }
}

struct TextSnippetsView: View {
    @State private var shortcut = ""
    @State private var expansion = ""
    @State private var snippets: [TextSnippet] = []

    var body: some View {
        List {
            Section {
                TextField("Shortcut", text: $shortcut)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Expanded text", text: $expansion, axis: .vertical)
                    .lineLimit(2...5)
                Button("Add replacement", action: addSnippet)
                    .disabled(shortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Type the shortcut and press Space. The expansion is inserted locally before the space.")
            }

            Section("Your replacements") {
                if snippets.isEmpty {
                    Text("No text replacements yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snippets) { snippet in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snippet.shortcut)
                                .font(.body.weight(.semibold))
                            Text(snippet.expansion)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .onDelete(perform: deleteSnippets)
                }
            }
        }
        .navigationTitle("Text replacements")
        .toolbar { EditButton() }
        .onAppear(perform: reload)
    }

    private func reload() {
        snippets = SnippetStore.load(from: AppGroup.defaults)
    }

    private func addSnippet() {
        guard SnippetStore.upsert(
            shortcut: shortcut,
            expansion: expansion,
            in: AppGroup.defaults
        ) != nil else { return }
        shortcut = ""
        expansion = ""
        reload()
    }

    private func deleteSnippets(at offsets: IndexSet) {
        for index in offsets where snippets.indices.contains(index) {
            SnippetStore.remove(snippets[index].id, from: AppGroup.defaults)
        }
        reload()
    }
}
