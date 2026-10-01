import AVFoundation
import SwiftUI
import UIKit
import DictusCore

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var polishEnabled = true
    @AppStorage(SharedKeys.transcriptionOutputMode, store: UserDefaults(suiteName: AppGroup.identifier)) private var transcriptionOutputModeRaw = TranscriptionOutputMode.defaultMode.storedValue
    @AppStorage(SharedKeys.writingStyle, store: UserDefaults(suiteName: AppGroup.identifier)) private var writingStyleRaw = WritingStyle.defaultStyle.rawValue
    @AppStorage(SharedKeys.hapticIntensity, store: UserDefaults(suiteName: AppGroup.identifier)) private var hapticIntensityRaw = HapticIntensity.default.rawValue
    @AppStorage(SharedKeys.keyContainersEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var keyContainersEnabled = true
    @AppStorage(SharedKeys.autocorrectEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var autocorrectEnabled = true
    @AppStorage(SharedKeys.adaptiveHitPredictionEnabled, store: UserDefaults(suiteName: AppGroup.identifier)) private var adaptiveHitPredictionEnabled = true
    @State private var microphonePermission = AVAudioSession.sharedInstance().recordPermission
    @ObservedObject var modelManager: ModelManager
    @State private var diagnosticResult = AppGroupDiagnostic.run()

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ModelManagerView(modelManager: modelManager)
                } label: {
                    Label("Models", systemImage: "square.stack.3d.up")
                }
                DictationModelQuickPicker(modelManager: modelManager)
                CleanupModelPicker(manager: modelManager)
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
                    .accessibilityHint("Corrects the last word when you press Space.")
                    .onChange(of: autocorrectEnabled) { _, _ in
                        KeyboardInteractionPreferences.notifyChanged()
                    }
                Picker("Keyboard haptics", selection: hapticPresetBinding) {
                    ForEach(HapticIntensity.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .accessibilityIdentifier("keyboard-haptics-setting")
                .accessibilityHint("Choose Off, the default key vibration, or the stronger Snappy vibration.")
                Toggle("Key containers", isOn: $keyContainersEnabled)
                    .accessibilityHint("Draws plates behind character rows. The bottom bar, including Period, always keeps its plates.")
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
                NavigationLink("Tap and hold options") { KeyboardHoldOptionsView() }
                KeyboardMaterialPicker()
            } header: {
                Text("Keyboard")
            } footer: {
                Text("The keyboard starts in the iPhone language. After a few words, typing follows the language of the sentence until another language takes over. Autocorrection and adaptive touch targets support English, German, French and Spanish. Other scripts, names, codes and web addresses are left unchanged.")
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
                NavigationLink("Keyboard setup") {
                    KeyboardSetupPage(onNext: {})
                }
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
                KeyboardInteractionPreferences.notifyVocabularyChanged()
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
        KeyboardInteractionPreferences.notifyVocabularyChanged()
    }

    private func deleteWords(at offsets: IndexSet) {
        for index in offsets where words.indices.contains(index) {
            UserDictionary.shared.forget(words[index])
        }
        reload()
        KeyboardInteractionPreferences.notifyVocabularyChanged()
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
