// DictusApp/Views/SettingsView.swift
// Settings pages pushed from the home list.
import AVFoundation
import SwiftUI
import UIKit
import SyllivraKernel

struct DictationSettingsView: View {
    @ObservedObject var modelManager: ModelManager
    @AppStorage(SharedKeys.polishEnabled, store: AppGroup.defaults) private var polishEnabled = true
    @AppStorage(SharedKeys.transcriptionOutputMode, store: AppGroup.defaults) private var transcriptionOutputModeRaw = TranscriptionOutputMode.defaultMode.storedValue
    @AppStorage(SharedKeys.writingStyle, store: AppGroup.defaults) private var writingStyleRaw = WritingStyle.defaultStyle.rawValue
    @AppStorage(SharedKeys.recordingReplayEnabled, store: AppGroup.defaults) private var replayEnabled = false
    @AppStorage(SharedKeys.historyEnabled, store: AppGroup.defaults) private var historyEnabled = true

    var body: some View {
        Form {
            Section {
                SpokenLanguagesPicker(modelManager: modelManager)
                Picker("Output", selection: $transcriptionOutputModeRaw) {
                    ForEach(TranscriptionOutputMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.storedValue)
                    }
                }
            } footer: {
                Text(activeOutputMode.explanation)
            }
            Section {
                if cleanupAvailable {
                    Toggle("Clean Up Text", isOn: $polishEnabled)
                        .accessibilityHint("Fixes punctuation and grammar after speech recognition.")
                }
                if polishEnabled && cleanupAvailable {
                    Picker("Writing Style", selection: $writingStyleRaw) {
                        ForEach(WritingStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style.rawValue)
                        }
                    }
                }
            } footer: {
                if PolishAvailability.state != .available {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(PolishAvailability.guidance(for: PolishAvailability.state))
                        if PolishAvailability.canOpenSystemSettings(for: PolishAvailability.state) {
                            Button("Open iPhone Settings", action: openSystemSettings).font(.footnote.bold())
                        }
                    }
                } else {
                    Text("Choose the processing model in Models.")
                }
            }
            Section {
                DictationPresencePicker()
                Toggle("Keep Last Recording", isOn: $replayEnabled)
                    .accessibilityIdentifier("dictation.replayPreference")
                    .onChange(of: replayEnabled) { _, enabled in if !enabled { RecordingReplay.shared.clear() } }
            } footer: {
                Text("Keeps up to the last 60 seconds in memory for five minutes so you can replay it. Audio is never saved or shared.")
            }
            Section {
                Toggle("Save History", isOn: $historyEnabled)
                    .onChange(of: historyEnabled) { _, enabled in
                        if !enabled { RecentDictations.disable(in: AppGroup.defaults) }
                    }
            } footer: {
                Text("Saved text stays on this iPhone. Turning this off keeps existing entries and stops adding new ones.")
            }
        }
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activeOutputMode: TranscriptionOutputMode {
        TranscriptionOutputMode(storedValue: transcriptionOutputModeRaw)
    }

    private var cleanupAvailable: Bool {
        if modelManager.cleanupBackend != .appleIntelligence { return true }
        return PolishAvailability.isAppleFMAvailable
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct KeyboardSettingsView: View {
    @AppStorage(SharedKeys.hapticIntensity, store: AppGroup.defaults) private var hapticIntensityRaw = HapticIntensity.default.rawValue
    @AppStorage(SharedKeys.keyContainersEnabled, store: AppGroup.defaults) private var keyContainersEnabled = true
    @AppStorage(SharedKeys.autocorrectEnabled, store: AppGroup.defaults) private var autocorrectEnabled = true
    @AppStorage(SharedKeys.adaptiveHitPredictionEnabled, store: AppGroup.defaults) private var adaptiveHitPredictionEnabled = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Layout") { TypingLanguagesPanel() }
                DefaultKeyboardModePicker()
                Toggle("Autocorrection", isOn: $autocorrectEnabled)
                    .accessibilityHint("Corrects the last word when you press Space.")
                    .onChange(of: autocorrectEnabled) { _, _ in KeyboardInteractionPreferences.notifyChanged() }
            } footer: {
                Text("Autocorrection supports English, German, French and Spanish, and uses your selected keyboard language for mixed sentences. Names, codes and web addresses stay unchanged.")
            }
            Section {
                KeyboardMaterialPicker()
                Toggle("Key Containers", isOn: $keyContainersEnabled)
                    .accessibilityHint("Shows opaque plates behind letters and symbols.")
                    .onChange(of: keyContainersEnabled) { _, _ in KeyboardInteractionPreferences.notifyChanged() }
                KeyPopupPicker()
                Picker("Haptics", selection: hapticPresetBinding) {
                    ForEach(HapticIntensity.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .accessibilityIdentifier("keyboard-haptics-setting")
            }
            Section {
                NavigationLink("Vocabulary") { VocabularyView() }
                    .accessibilityIdentifier("settings.words")
                NavigationLink("Text Replacements") { TextSnippetsView() }
                NavigationLink("Tap and Hold Options") { KeyboardHoldOptionsView() }
                    .accessibilityIdentifier("settings.keyboard.variants")
            }
            Section {
                KeyboardHoldSpeedPicker()
                Toggle("Adaptive Touch", isOn: $adaptiveHitPredictionEnabled)
                    .accessibilityHint("Nudges the gap between adjacent keys toward the more likely next letter.")
                    .onChange(of: adaptiveHitPredictionEnabled) { _, _ in KeyboardInteractionPreferences.notifyChanged() }
            } footer: {
                Text("Hold 123 or ABC to open the dictation board. On the board, hold 123 to return to letters.")
            }
        }
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let intensity = HapticIntensity.load(from: AppGroup.defaults)
            hapticIntensityRaw = intensity.rawValue
            intensity.persist()
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
}

struct HelpView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var microphonePermission = AVAudioSession.sharedInstance().recordPermission
    @State private var diagnosticResult = AppGroupDiagnostic.run()

    var body: some View {
        List {
            Section {
                NavigationLink("Keyboard Setup") { KeyboardSetupPage() }
                Button(action: openSystemSettings) {
                    LabeledContent("Microphone") {
                        Text(permissionLabel).foregroundStyle(microphonePermission == .denied ? Color(.systemRed) : .secondary)
                    }
                }
                .foregroundStyle(.primary)
                .accessibilityHint("Opens iPhone Settings")
            }
            Section("Troubleshooting") {
                NavigationLink("Report Last Dictation") { LastDictationIssueReportView() }
                NavigationLink("Diagnostics") { DiagnosticDetailView(result: diagnosticResult) }
                NavigationLink("Debug Logs") { DebugLogView() }
                NavigationLink("Cleanup Diagnostics") { PolishDebugView() }
            }
            Section("This iPhone") {
                let device = DeviceCapabilities.current()
                LabeledContent("Memory", value: "\(device.physicalMemoryGB) GB")
                LabeledContent("Temperature", value: thermalLabel(device.thermalState))
            }
            if let supportURL = URL(string: "https://github.com/enrzh/saiity-fork/issues") {
                Section { Link("Get Support", destination: supportURL) }
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        microphonePermission = AVAudioSession.sharedInstance().recordPermission
        diagnosticResult = AppGroupDiagnostic.run()
    }

    private var permissionLabel: String {
        switch microphonePermission {
        case .granted: return String(localized: "Allowed")
        case .denied: return String(localized: "Off")
        case .undetermined: return String(localized: "Not Set")
        @unknown default: return String(localized: "Unknown")
        }
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

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: appVersionText)
                NavigationLink("Licenses") { LicensesView() }
                if let privacyURL = URL(string: "https://aiity.de/privacy") {
                    Link("Privacy Policy", destination: privacyURL)
                }
            } footer: {
                Text("Speech is recognized on this iPhone. Downloading models uses the network. Server cleanup, if you choose it, sends text to that server.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

struct VocabularyView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var newWord = ""
    @State private var words: [String] = []
    @State private var hints: [String] = []
    @State private var vocabularyError: String?
    @State private var showingResetConfirmation = false

    var body: some View {
        List {
            Section {
                let entryLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 10))
                entryLayout {
                    TextField("Add a word or name", text: $newWord)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } footer: {
                Text("Words you add stay protected from autocorrection. Choose Use in dictation to approve a learned word as a hint.")
            }

            Section {
                if words.isEmpty {
                    Text("No custom words yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(words, id: \.self) { word in
                        let wordLayout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                            : AnyLayout(HStackLayout(spacing: 12))
                        wordLayout {
                            Text(hints.first { $0.caseInsensitiveCompare(word) == .orderedSame } ?? word)
                                .fixedSize(horizontal: false, vertical: true)
                            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                            Menu {
                            Button(isHint(word) ? "Remove dictation hint" : "Use in dictation") {
                                if isHint(word) { DictationVocabulary.remove(word, in: AppGroup.defaults) }
                                else if !DictationVocabulary.approve(word, in: AppGroup.defaults) {
                                    vocabularyError = "Keep up to 32 dictation hints, each under 65 characters and six words."
                                }
                                reload()
                                KeyboardInteractionPreferences.notifyVocabularyChanged()
                            }
                            } label: {
                                Label(LocalizedStringKey(isHint(word) ? "Hint on" : "Use in dictation"),
                                      systemImage: isHint(word) ? "mic.fill" : "mic")
                                    .font(.subheadline).frame(minHeight: 44)
                            }
                            .accessibilityLabel("Dictation hint for \(word)")
                            .accessibilityValue(isHint(word) ? "On" : "Off")
                            .accessibilityIdentifier("vocabulary.hint")
                        }
                    }
                    .onDelete(perform: deleteWords)
                }
            } header: {
                Text("Learned Words")
            } footer: {
                Text("Hints help Whisper recognize a word and help cleanup spell it. Keep up to 32, each under 65 characters and six words. Server cleanup receives only hints already in its transcript.")
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
                Button("Add Replacement", action: addSnippet)
                    .disabled(shortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Type the shortcut and press Space. The expansion is inserted locally before the space.")
            }

            Section("Your Replacements") {
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
        .navigationTitle("Text Replacements")
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
