import AVFoundation
import SwiftUI
import UIKit
import DictusCore

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var polishEnabled = true
    @AppStorage(SharedKeys.transcriptionOutputMode, store: UserDefaults(suiteName: AppGroup.identifier)) private var transcriptionOutputModeRaw = TranscriptionOutputMode.defaultMode.storedValue
    @AppStorage(SharedKeys.writingStyle, store: UserDefaults(suiteName: AppGroup.identifier)) private var writingStyleRaw = WritingStyle.defaultStyle.rawValue
    @AppStorage(SharedKeys.hapticIntensity, store: UserDefaults(suiteName: AppGroup.identifier)) private var hapticIntensityRaw = HapticIntensity.default.rawValue
    @AppStorage(SharedKeys.keyContainersEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var keyContainersEnabled = true
    @AppStorage(SharedKeys.recordingReplayEnabled, store: AppGroup.defaults) private var replayEnabled = false
    @AppStorage(SharedKeys.autocorrectEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var autocorrectEnabled = true
    @AppStorage(SharedKeys.adaptiveHitPredictionEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var adaptiveHitPredictionEnabled = true
    @State private var microphonePermission = AVAudioSession.sharedInstance().recordPermission
    @ObservedObject var modelManager: ModelManager
    @State private var diagnosticResult = AppGroupDiagnostic.run()

    var body: some View {
        List {
            Section("Preferences") {
                NavigationLink { dictationSettings } label: {
                    settingsLabel("Dictation", systemImage: "waveform")
                }
                .accessibilityIdentifier("settings.dictation")
                NavigationLink { keyboardSettings } label: {
                    settingsLabel("Keyboard", systemImage: "keyboard")
                }
                .accessibilityIdentifier("settings.keyboard")
                NavigationLink {
                    ModelManagerView(modelManager: modelManager)
                } label: {
                    settingsLabel("Models", systemImage: "square.stack.3d.up")
                }
                .accessibilityIdentifier("settings.models")
            }

            Section("Your words") {
                NavigationLink { wordsSettings } label: {
                    settingsLabel("Words & shortcuts", systemImage: "character.book.closed")
                }
                .accessibilityIdentifier("settings.words")
                NavigationLink {
                    DictationHistoryView()
                } label: {
                    settingsLabel("Dictation history", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("settings.history")
            }

            Section("Help") {
                NavigationLink { helpSettings } label: {
                    settingsLabel("Setup & help", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("settings.help")
                NavigationLink { aboutSettings } label: {
                    settingsLabel("About", systemImage: "info.circle")
                }
                .accessibilityIdentifier("settings.about")
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

    @ViewBuilder private func settingsLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        if textSize.isAccessibilitySize { Text(title) }
        else { Label(title, systemImage: systemImage) }
    }

    private func settingsPage<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        List { content() }
            .listStyle(.insetGrouped)
            .contentMargins(.bottom, 88, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }

    private var dictationSettings: some View {
        settingsPage("Dictation") {
            DictationSettingsAdvisor(modelManager: modelManager)
            Section("In sAiity") {
                DictationModelQuickPicker(scope: .app, modelManager: modelManager)
            }
            Section("From your keyboard") {
                DictationModelQuickPicker(scope: .keyboard, modelManager: modelManager)
            }
            Section {
                SpokenLanguagesPicker(modelManager: modelManager)
            }
            Section {
                if cleanupAvailable {
                    Toggle("Automatic cleanup", isOn: $polishEnabled)
                        .accessibilityHint("Cleans up dictation after speech recognition.")
                }
                Picker("Dictation output", selection: $transcriptionOutputModeRaw) {
                    ForEach(TranscriptionOutputMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.storedValue)
                    }
                }
                if polishEnabled && cleanupAvailable {
                    Picker("Writing style", selection: $writingStyleRaw) {
                        ForEach(WritingStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                }
            } header: {
                Text("Writing")
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
            Section("Advanced") {
                Toggle("Keep last recording briefly", isOn: $replayEnabled)
                    .accessibilityIdentifier("dictation.replayPreference")
                    .onChange(of: replayEnabled) { _, enabled in if !enabled { RecordingReplay.shared.clear() } }
                Text("Off by default. Keeps up to the last 60 seconds in memory for five minutes, until your next dictation, or until you leave the app. Audio is never saved or shared.")
                    .font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup("Models and Live Activity") {
                    CleanupModelPicker(manager: modelManager)
                    DictationPresencePicker()
                }
                .accessibilityIdentifier("settings.dictation.advanced")
            }
        }
    }

    private var keyboardSettings: some View {
        settingsPage("Keyboard") {
            Section {
                LabeledContent("Keyboard layout") {
                    TypingLanguagesPanel()
                }
                DefaultKeyboardModePicker()
                Toggle("Autocorrection", isOn: $autocorrectEnabled)
                    .accessibilityHint("Corrects the last word when you press Space.")
                    .onChange(of: autocorrectEnabled) { _, _ in
                        KeyboardInteractionPreferences.notifyChanged()
                    }
            } header: {
                Text("Typing")
            } footer: {
                Text("Typing follows the language of the sentence. Autocorrection and adaptive touch support English, German, French and Spanish. Other scripts, names, codes and web addresses stay unchanged.")
            }
            Section("Appearance & feedback") {
                KeyboardMaterialPicker()
                Picker("Keyboard haptics", selection: hapticPresetBinding) {
                    ForEach(HapticIntensity.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .accessibilityIdentifier("keyboard-haptics-setting")
                .accessibilityHint("Choose Off, the default key vibration, or the stronger Snappy vibration.")
            }
            Section("Press and hold") {
                NavigationLink("Emoji & key variants") { KeyboardHoldOptionsView() }
                    .accessibilityIdentifier("settings.keyboard.variants")
                Text("Hold the bottom-left 123 or ABC key to open dictation. On the dictation board, hold 123 to return to letters. A quick tap still switches letters and symbols.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Advanced") {
                DisclosureGroup("Advanced keyboard options") {
                    Toggle("Key containers", isOn: $keyContainersEnabled)
                        .accessibilityHint("Shows faint backgrounds behind letters and symbols.")
                        .onChange(of: keyContainersEnabled) { _, _ in
                            KeyboardInteractionPreferences.notifyChanged()
                        }
                    Toggle("Adaptive hit prediction", isOn: $adaptiveHitPredictionEnabled)
                        .accessibilityHint("Nudges the gap between adjacent keys toward the more likely next letter. Off uses neutral seams.")
                        .onChange(of: adaptiveHitPredictionEnabled) { _, _ in
                            KeyboardInteractionPreferences.notifyChanged()
                        }
                    KeyPopupPicker()
                    KeyboardHoldSpeedPicker()
                }
                .accessibilityIdentifier("settings.keyboard.advanced")
            }
        }
    }

    private var wordsSettings: some View {
        settingsPage("Words & shortcuts") {
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
        }
    }

    private var helpSettings: some View {
        settingsPage("Setup & help") {
            Section("Help") {
                NavigationLink("Keyboard setup") {
                    KeyboardSetupPage(onNext: {})
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
        }
    }

    private var aboutSettings: some View {
        settingsPage("About") {
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
    }

    private var hapticPresetBinding: Binding<HapticIntensity> {
        Binding(
            get: { HapticIntensity(rawValue: hapticIntensityRaw) ?? .default },
            set: { preset in
                hapticIntensityRaw = preset.rawValue
                preset.persist()
                HapticFeedback.refreshEnabledState()
                HapticFeedback.keyTapped()
                KeyboardInteractionPreferences.notifyChanged()
            }
        )
    }

    private var activeOutputMode: TranscriptionOutputMode {
        TranscriptionOutputMode(storedValue: transcriptionOutputModeRaw)
    }

    private var cleanupAvailable: Bool {
        if modelManager.cleanupBackend != .appleIntelligence { return true }
        return PolishAvailability.isAppleFMAvailable
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

struct VocabularyView: View {
    @State private var newWord = ""
    @State private var words: [String] = []
    @State private var hints: [String] = []
    @State private var vocabularyError: String?
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
                Text("Words you add are protected from autocorrection. Whisper recognition and cleanup use approved spellings; Parakeet uses them during cleanup. Automatically learned words become hints only when you choose Use in dictation. Server processing receives only hints already present in its transcript.")
            }

            Section("Learned words") {
                if words.isEmpty {
                    Text("No custom words yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(words, id: \.self) { word in
                        HStack {
                            Text(hints.first { $0.caseInsensitiveCompare(word) == .orderedSame } ?? word)
                            Spacer()
                            if isHint(word) {
                                Image(systemName: "mic.fill").foregroundStyle(.secondary)
                                    .accessibilityLabel("Dictation hint enabled")
                            }
                        }
                        .contextMenu {
                            Button(isHint(word) ? "Remove dictation hint" : "Use in dictation") {
                                if isHint(word) { DictationVocabulary.remove(word, in: AppGroup.defaults) }
                                else if !DictationVocabulary.approve(word, in: AppGroup.defaults) {
                                    vocabularyError = "Keep up to 32 dictation hints, each under 65 characters and six words."
                                }
                                reload()
                                KeyboardInteractionPreferences.notifyVocabularyChanged()
                            }
                        }
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
                DictationVocabulary.clear(in: AppGroup.defaults)
                reload()
                KeyboardInteractionPreferences.notifyVocabularyChanged()
            }
        } message: {
            Text("This removes your learned words and approved dictation hints.")
        }
        .alert("Vocabulary", isPresented: Binding(get: { vocabularyError != nil },
            set: { if !$0 { vocabularyError = nil } })) {
                Button("OK") { vocabularyError = nil }
            } message: { Text(vocabularyError ?? "") }
        .onAppear(perform: reload)
    }

    private func reload() {
        UserDictionary.shared.reload()
        hints = DictationVocabulary.stored(in: AppGroup.defaults)
        words = Set(Array(UserDictionary.shared.allLearnedWords.keys) + hints.map { $0.lowercased() }).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        guard DictationVocabulary.isValid(word) else {
            vocabularyError = "Use up to 64 characters and six words, including letters from any language. Line breaks are not allowed."
            return
        }
        _ = UserDictionary.shared.learn(word, allowSingleCharacter: true)
        if !DictationVocabulary.approve(word, in: AppGroup.defaults) {
            vocabularyError = "Word saved. The 32 dictation hints are full; remove a hint to use this word in dictation too."
        }
        newWord = ""
        reload()
        KeyboardInteractionPreferences.notifyVocabularyChanged()
    }

    private func deleteWords(at offsets: IndexSet) {
        for index in offsets where words.indices.contains(index) {
            UserDictionary.shared.forget(words[index])
            DictationVocabulary.remove(words[index], in: AppGroup.defaults)
        }
        reload()
        KeyboardInteractionPreferences.notifyVocabularyChanged()
    }

    private func isHint(_ word: String) -> Bool {
        hints.contains { $0.caseInsensitiveCompare(word) == .orderedSame }
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
