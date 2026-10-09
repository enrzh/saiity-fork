// DictusApp/Views/KeyboardModePicker.swift
// Native pickers for keyboard defaults and interaction preferences.
import SwiftUI
import DictusCore
import DeviceKit

/// Advice is shared by Voice options, Dictation settings and Models.
/// Recommendations are applied explicitly; downloads remain a separate action.
struct DictationSettingsAdvisor: View {
    @ObservedObject var modelManager: ModelManager
    @EnvironmentObject private var coordinator: DictationCoordinator
    @State private var showsAdvice = false
    private var phoneName: String {
        switch DeviceCapabilities.current().deviceModelIdentifier {
        case "iPhone19,2": return "iPhone 18 Pro"
        case "iPhone18,4": return "iPhone Air"
        default: return Device.current.realDevice.description
        }
    }

    private func recommendedModel(_ recognizer: DictationRecognizer, profile: ModelSelectionProfile,
                                  installed: Set<String>) -> ModelInfo? {
        profile.resolvedIdentifier(
            installed: installed,
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            capabilities: DeviceCapabilities.current(), recognizer: recognizer,
            requiredLanguages: SpokenLanguagePreferences.load(from: AppGroup.defaults))
            .flatMap(ModelInfo.forIdentifier)
    }
    private var usesRecommendation: Bool {
        modelManager.selectionMode == .automatic && modelManager.selectionProfile == .recommended
            && AppGroup.defaults.string(forKey: SharedKeys.keyboardDictationModel) == nil
    }
    var body: some View {
        Section {
            DisclosureGroup("View recommendation", isExpanded: $showsAdvice) {
                recommendation("In sAiity", recognizer: modelManager.recognizer, profile: .recommended)
                recommendation("From your keyboard", recognizer: .whisper, profile: .balanced)
            }
            Button(usesRecommendation ? "Recommended settings applied" : "Use recommended settings") {
                modelManager.useRecommendedSettings()
            }
            .accessibilityIdentifier("dictation.useRecommendedSettings")
            .disabled(usesRecommendation || !coordinator.canChangeSpeechRuntime)
        } header: {
            Text("Recommended settings")
        } footer: {
            Text("For \(phoneName) and your spoken languages. Apply changes voice model routing only; writing options and languages stay as you chose them. Uses installed models and adapts when your phone is warm or low on memory. Downloads are optional.")
        }
        .accessibilityIdentifier("dictation.settingsAdvisor")
    }
    private func recommendation(_ title: LocalizedStringKey, recognizer: DictationRecognizer,
                                profile: ModelSelectionProfile) -> some View {
        let model = recommendedModel(recognizer, profile: profile, installed: Set(ModelInfo.downloadableIdentifiers))
        let installed = recommendedModel(recognizer, profile: profile, installed: Set(modelManager.downloadedModels))
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(model?.displayName ?? "No compatible recommendation")
            if let model, !modelManager.downloadedModels.contains(model.identifier) {
                Text(installed.map { "Automatic will use \($0.displayName) until you download this model in Models." }
                     ?? "Download a compatible model in Models to get started.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model?.engine == .qwenASR {
                Text("Keep sAiity open for Streaming. The keyboard uses Whisper independently.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct DictationModelQuickPicker: View {
    enum Scope { case app, keyboard, both }
    var scope: Scope = .both
    @ObservedObject var modelManager: ModelManager
    @EnvironmentObject private var coordinator: DictationCoordinator
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage(SharedKeys.dictationRealtimeText, store: AppGroup.defaults) private var realtime = false
    private var selectedModel: String {
        if modelManager.selectionMode == .automatic {
            return modelManager.activeModel ?? modelManager.initialVoiceModel ?? "unavailable"
        }
        return modelManager.activeModel ?? AppGroup.defaults.string(forKey: modelManager.recognizer.modelPreferenceKey)
            ?? modelManager.recognizer.defaultModelIdentifier
    }
    private var models: [ModelInfo] { availableModels(for: modelManager.recognizer) }
    private func availableModels(for recognizer: DictationRecognizer) -> [ModelInfo] {
        ModelInfo.allIncludingDeprecated.filter {
            recognizer.contains($0)
                && $0.isRuntimeAvailable(onOSMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
                                        capabilities: DeviceCapabilities.current())
                && (ModelInfo.downloadableIdentifiers.contains($0.identifier)
                    || modelManager.downloadedModels.contains($0.identifier))
        }.sorted { $0.sizeBytes < $1.sizeBytes }
    }
    var body: some View {
        Group {
            if scope != .keyboard {
            if textSize.isAccessibilitySize {
                recognizerPicker.pickerStyle(.menu)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dictation engine").font(.subheadline)
                    recognizerPicker.pickerStyle(.segmented)
                }.padding(.vertical, 4)
            }
            DisclosureGroup("Choose a voice model") {
            Picker(modelManager.recognizer == .streaming ? "Streaming model" : "Whisper model",
                   selection: Binding(get: { selectedModel }, set: modelManager.chooseDictationModel)) {
                if selectedModel == "unavailable" { Text("No compatible recommendation").tag("unavailable") }
                ForEach(models) { model in
                    Text(textSize.isAccessibilitySize && model.engine == .qwenASR
                         ? model.displayName.replacingOccurrences(of: "Qwen3-ASR", with: "Qwen")
                         : model.displayName).tag(model.identifier)
                }
            }
            .accessibilityValue(ModelInfo.forIdentifier(selectedModel)?.displayName ?? "Choose a model")
            .accessibilityIdentifier("dictation.model")
            }
            if ModelInfo.forIdentifier(selectedModel)?.engine == .qwenASR {
                Toggle("Realtime text", isOn: $realtime).accessibilityIdentifier("dictation.realtime")
                Text("Words appear after pauses while you speak. Cleanup runs when you finish. Qwen runs while sAiity is open; your keyboard uses its own model.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if selectedModel == "unavailable" {
                Text("No compatible model covers your spoken languages on this iPhone. Change the languages, or select a model manually.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if !modelManager.downloadedModels.contains(selectedModel) {
                if let progress = modelManager.downloadProgress[selectedModel] {
                    ProgressView("Downloading model", value: Double(progress))
                    Button("Cancel download") { modelManager.cancelCatalogDownload(selectedModel) }
                } else {
                    Button("Download selected model") {
                        modelManager.startCatalogDownload(selectedModel, onError: { _ in })
                    }
                }
                if case .error(let message) = modelManager.modelStates[selectedModel] {
                    Text(DictationProblem(message, downloading: true).message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            let languages = SpokenLanguagePreferences.load(from: AppGroup.defaults)
            if !languages.isEmpty, let model = ModelInfo.forIdentifier(selectedModel), !SpokenLanguagePreferences.accepts(model, languages: languages) {
                Text("This model does not cover your selected spoken languages. Choose a compatible model or change your language preferences.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            }
            if scope != .app {
            Picker("Keyboard model", selection: Binding(
                get: { AppGroup.defaults.string(forKey: SharedKeys.keyboardDictationModel) ?? "automatic" },
                set: modelManager.chooseKeyboardModel)) {
                Text("Automatic").tag("automatic")
                ForEach(modelManager.downloadedModels.filter { ModelInfo.forIdentifier($0)?.engine != .qwenASR }, id: \.self) { id in
                    Text(ModelInfo.forIdentifier(id)?.displayName ?? id).tag(id)
                }
            }.accessibilityIdentifier("dictation.keyboardModel")
            Text(modelManager.keyboardModel.flatMap(ModelInfo.forIdentifier).map {
                "Keyboard dictation uses \($0.displayName), independently of your in-app choice."
            } ?? "Download a Whisper model to enable dictation from your keyboard.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!coordinator.canChangeSpeechRuntime)
    }
    private var recognizerPicker: some View {
        Picker("Dictation engine", selection: Binding(get: { modelManager.recognizer }, set: modelManager.selectRecognizer)) {
            ForEach(DictationRecognizer.allCases, id: \.self) { choice in
                Text(choice.displayName).tag(choice)
                    .disabled(choice == .streaming && availableModels(for: choice).isEmpty)
            }
        }.accessibilityIdentifier("dictation.recognizer")
    }
}

struct SpokenLanguagesPicker: View {
    @ObservedObject var modelManager: ModelManager
    @State private var languages = SpokenLanguagePreferences.load(from: AppGroup.defaults)
    @State private var query = ""

    var body: some View {
        NavigationLink {
            List {
                Section {
                    Button("Broad language support") { update([]) }
                    Text("Choose every language you speak, including mixed-language dictation. This guides model recommendations without forcing recognition into one language.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Spoken languages") {
                    ForEach(SpokenLanguagePreferences.availableCodes.filter {
                        query.isEmpty || ModelLanguageSupport.localizedLanguageName(for: $0).localizedCaseInsensitiveContains(query)
                    }, id: \.self) { code in
                        Toggle(ModelLanguageSupport.localizedLanguageName(for: code), isOn: Binding(
                            get: { languages.contains(code) }, set: { enabled in
                                update(enabled ? languages + [code] : languages.filter { $0 != code })
                            }))
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Language")
            .navigationTitle("Spoken languages")
        } label: {
            LabeledContent("Spoken languages", value: SpokenLanguagePreferences.summary(languages))
        }
        .disabled(!DictationCoordinator.shared.canChangeSpeechRuntime)
        .onAppear { languages = SpokenLanguagePreferences.load(from: AppGroup.defaults) }
        .accessibilityIdentifier("dictation.spokenLanguages")
    }

    private func update(_ codes: [String]) {
        modelManager.setSpokenLanguages(codes)
        languages = SpokenLanguagePreferences.load(from: AppGroup.defaults)
    }
}

struct CleanupModelPicker: View {
    @ObservedObject var manager: ModelManager
    @ObservedObject private var local = CleanupModelManager.shared
    var body: some View {
        Picker("Processing model", selection: Binding(
            get: { manager.cleanupBackend.storageValue },
            set: { value in
                guard let backend = PolishCleanupBackend.parse(value) else { return }
                if case .local(let model) = backend { local.select(model, manager: manager) }
                else { manager.selectCleanupBackend(backend) }
            })) {
            Text("Apple Foundation Models").tag(PolishCleanupBackend.appleIntelligence.storageValue)
            ForEach(LocalCleanupModel.allCases, id: \.self) { model in
                Text(model.displayName).tag(PolishCleanupBackend.local(model).storageValue)
            }
            ForEach(PolishCleanupBackend.validOllamaCleanupModels(from: manager.customModels)) { model in
                Text(model.name).tag(PolishCleanupBackend.ollama(model.id).storageValue)
            }
        }
        .disabled(local.preparing != nil)
        .accessibilityHint("One model handles punctuation, cleanup and grammar. Local models download once before selection.")
        if let model = local.preparing {
            ProgressView("Preparing \(model.displayName)", value: local.progress)
            Button("Cancel download") { local.cancel() }
        }
        if let error = local.error { Text(error).font(.footnote).foregroundStyle(.red) }
        if case .local(let model) = manager.cleanupBackend { Text(model.explanation).font(.footnote).foregroundStyle(.secondary) }
        if case .ollama(let id) = manager.cleanupBackend,
           let model = manager.customModels.first(where: { $0.id == id }) {
            Text("Cleanup sends your dictated text to \(URL(string: model.repositoryURL)?.host ?? "your configured server"). Speech recognition stays on this iPhone. Choose a server you trust.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KeyboardHoldSpeedPicker: View {
    @AppStorage(SharedKeys.keyboardHoldSpeed, store: AppGroup.defaults) private var speed = KeyboardHoldSpeed.default.rawValue
    var body: some View {
        Picker("Tap and hold speed", selection: $speed) {
            ForEach(KeyboardHoldSpeed.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
        }
        .onChange(of: speed) { _, _ in KeyboardInteractionPreferences.notifyChanged() }
    }
}

/// The catalog is shared with the keyboard. Every alternate can be disabled;
/// the ordinary tap remains available on each key.
struct KeyboardHoldOptionsView: View {
    @State private var page = 0
    @State private var selectedKey: String?
    @State private var revision = 0
    @State private var padStyle: HostFieldPolicy.NumberPadStyle = .digits
    @State private var emojiCategoryID = "people"
    @State private var showEmojiOverrides = false
    private var kind: KeyboardVariantKind {
        page == 0 ? .letter : page == 3 ? .emoji : page == 4 && padStyle == .phone ? .phone : .symbol
    }
    private var rows: [[String]] {
        switch page {
        case 0:
            var rows = KeyboardVariantLayout.rows(for: .active)
            if let last = rows.indices.last { rows[last] = ["⇧"] + rows[last] + ["⌫"] }
            return rows + [["123", "☺", "space", ".", "return"]]
        case 1, 2:
            return (page == 1 ? KeyboardSymbolsLayout.numbers : KeyboardSymbolsLayout.symbols).map { row in
                row.compactMap {
                    switch $0.kind {
                    case .insert(let value): return value
                    case .pageToggle: return page == 1 ? "#+=" : "123"
                    case .delete: return "⌫"
                    default: return nil
                    }
                }
            } + [["ABC", "☺", "space", "return"]]
        case 4: return [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"],
            [padStyle == .phone ? "*" : padStyle == .decimal ? Locale.current.decimalSeparator ?? "." : "ABC", "0", "⌫"]]
        default: return (EmojiStore.categories.first { $0.id == emojiCategoryID }?.emojis ?? [])
            .filter { KeyboardVariantPreferences.allOptions(for: $0, kind: .emoji).count > 1 }
            .reduce(into: [[String]]()) { rows, value in
                if rows.isEmpty || rows[rows.count - 1].count == 8 { rows.append([]) }
                rows[rows.count - 1].append(value)
            }
        }
    }
    var body: some View {
        let _ = revision
        List {
            Section {
                Picker("Page", selection: $page) {
                    Text("ABC").tag(0); Text("123").tag(1); Text("#+=").tag(2); Text("Emoji").tag(3); Text("Pad").tag(4)
                }.pickerStyle(.segmented)
            }
            if page == 3 {
                Section {
                    Picker("Default skin tone", selection: Binding(
                        get: { KeyboardVariantPreferences.defaultSkinTone },
                        set: { KeyboardVariantPreferences.setDefaultSkinTone($0); revision += 1 })) {
                        Text("👋 Original").tag("")
                        ForEach(Array(EmojiSkinToneVariants.modifiers.enumerated()), id: \.element) { index, tone in
                            Text("👋" + tone + " " + ["Light", "Medium light", "Medium", "Medium dark", "Dark"][index]).tag(tone)
                        }
                    }
                    ForEach(Array(EmojiSkinToneVariants.modifiers.enumerated()), id: \.element) { index, tone in
                        Toggle(isOn: Binding(
                            get: { KeyboardVariantPreferences.isToneEnabled(tone) },
                            set: { KeyboardVariantPreferences.setToneEnabled($0, tone: tone); revision += 1 })) {
                            HStack(spacing: 12) {
                                Text("\u{1F44B}" + tone).font(.title2)
                                Text(["Light", "Medium light", "Medium", "Medium dark", "Dark"][index])
                            }
                        }
                    }
                    Toggle("Customize individual emoji", isOn: $showEmojiOverrides)
                } header: { Text("Skin tones") }
                  footer: { Text("The default tone applies to ordinary emoji. Recents keep the tone you chose. Holding lets you choose another tone; joined combinations keep their individual options below.") }
            }
            Section {
                if page == 4 {
                    Picker("Field type", selection: $padStyle) {
                        Text("Numbers").tag(HostFieldPolicy.NumberPadStyle.digits)
                        Text("Decimal").tag(HostFieldPolicy.NumberPadStyle.decimal)
                        Text("Phone").tag(HostFieldPolicy.NumberPadStyle.phone)
                    }
                }
                if page == 3 && showEmojiOverrides {
                    Picker("Emoji category", selection: $emojiCategoryID) {
                        ForEach(EmojiStore.categories.filter { $0.emojis.contains { EmojiSkinToneVariants.options(for: $0).count > 1 } }) { Text($0.name).tag($0.id) }
                    }
                }
                ForEach(Array((page == 3 && !showEmojiOverrides ? [] : rows).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                            let hasOptions = KeyboardVariantPreferences.allOptions(for: key, kind: kind).count > 1
                            Button {
                                selectedKey = key
                            } label: {
                                Text(key).font(.system(size: page == 3 ? 23 : 18))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(selectedKey == key ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill),
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .bottom) { if hasOptions { Circle().fill(Color.accentColor).frame(width: 3, height: 3).padding(3) } }
                            }.buttonStyle(.plain).disabled(!hasOptions)
                        }
                    }
                }
            } footer: {
                if page != 3 || showEmojiOverrides {
                    Text("Keys with a dot have alternate characters or emoji tones. Select a key, then keep only the alternates you use. Ordinary taps always stay enabled.")
                }
            }
            if let selectedKey, page != 3 || showEmojiOverrides {
                Section("Options for \(selectedKey)") {
                    ForEach(KeyboardVariantPreferences.allOptions(for: selectedKey, kind: kind).dropFirst(), id: \.self) { option in
                        Toggle(option, isOn: Binding(
                            get: { KeyboardVariantPreferences.isEnabled(option, for: selectedKey, kind: kind) },
                            set: { KeyboardVariantPreferences.setEnabled($0, option: option, key: selectedKey, kind: kind); revision += 1 }))
                    }
                }
            }
        }
        .navigationTitle("Tap and hold options")
        .onAppear { KeyboardVariantPreferences.reload() }
        .onChange(of: page) { _, _ in selectedKey = nil }
        .onChange(of: emojiCategoryID) { _, _ in selectedKey = nil }
        .onChange(of: padStyle) { _, _ in selectedKey = nil }
    }
}

/// Selects the product surface that opens first. The old ABC/123 preference is
/// intentionally left readable for migration, but is no longer exposed here.
struct DefaultKeyboardModePicker: View {
    @AppStorage(SharedKeys.defaultKeyboardMode, store: UserDefaults(suiteName: AppGroup.identifier))
    private var selectedMode = DefaultKeyboardMode.dictationBoard.rawValue

    var body: some View {
        LabeledContent("Default keyboard") {
            Picker("Default keyboard", selection: $selectedMode) {
                ForEach(DefaultKeyboardMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .onAppear {
            if UserDefaults(suiteName: AppGroup.identifier)?.string(forKey: SharedKeys.defaultKeyboardMode) == nil {
                selectedMode = DefaultKeyboardMode.active.rawValue
            }
        }
        .accessibilityHint("Choose whether sAiity opens on the dictation board or typing keyboard.")
    }
}

/// Automatic language plus one layout type. Explicit per-language rows were
/// dropped so Settings and the keyboard menu stay on the same two choices.
struct TypingLanguagesPanel: View {
    @State private var layout = LayoutType.active

    var body: some View {
        Picker("Keyboard layout", selection: layoutBinding) {
            ForEach(LayoutType.allCases, id: \.self) { entry in
                Text(entry.displayName).tag(entry)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityHint("Choose AZERTY, QWERTY, QWERTZ, or QWERTZ Deutschland.")
        .onAppear { layout = LayoutType.active }
    }

    private var layoutBinding: Binding<LayoutType> {
        Binding(
            get: { layout },
            set: { newValue in
                KeyboardLayoutPreference.setGlobalLayout(newValue)
                layout = newValue
            }
        )
    }
}

/// Native picker for the keyboard surface material.
struct KeyboardMaterialPicker: View {
    @AppStorage(SharedKeys.keyboardTopBarEnabled, store: AppGroup.defaults)
    private var topBarEnabled = false
    @AppStorage(SharedKeys.liquidGlassEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var liquidGlassEnabled = true
    @AppStorage(SharedKeys.keyboardInsetEnabled, store: AppGroup.defaults)
    private var insetEnabled = true

    var body: some View {
        Toggle("Show top bar", isOn: $topBarEnabled)
            .accessibilityIdentifier("keyboard-top-bar-setting")
            .accessibilityHint("Shows More, dictation power and the dictation board shortcut above typing pages.")
            .onChange(of: topBarEnabled) { _, _ in KeyboardInteractionPreferences.notifyChanged() }
            Picker("Keyboard material", selection: $liquidGlassEnabled) {
                Text("Liquid Glass").tag(true)
                Text("Solid").tag(false)
            }
            .accessibilityHint("Choose Liquid Glass or Solid for the shared keyboard background.")
            .onChange(of: liquidGlassEnabled) { _, _ in
                KeyboardInteractionPreferences.notifyChanged()
            }
            Toggle("Keyboard inset", isOn: $insetEnabled)
                .accessibilityHint("Shows the shared background behind every keyboard page and its bottom bar, in either material.")
                .onChange(of: insetEnabled) { _, _ in KeyboardInteractionPreferences.notifyChanged() }
    }
}

/// Native picker for the optional Live Activity presence.
struct DictationPresencePicker: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = DictationPresenceMode.active

    var body: some View {
        Picker("Dictation presence", selection: selectionBinding) {
            ForEach(DictationPresenceMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .onAppear { selection = DictationPresenceMode.active }
        .accessibilityHint("Choose off or Live Activity.")
    }

    private var selectionBinding: Binding<DictationPresenceMode> {
        Binding(
            get: { selection },
            set: { apply($0) }
        )
    }

    private func apply(_ mode: DictationPresenceMode) {
        selection = mode
        mode.persist()
        LiveActivityManager.shared.applyPresenceMode(mode, isBackground: scenePhase == .background)
    }
}

/// Native picker for key-press preview behavior.
struct KeyPopupPicker: View {
    @State private var selection = KeyPopupMode.active

    var body: some View {
        Picker("Key popups", selection: selectionBinding) {
            ForEach(KeyPopupMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .onAppear { selection = KeyPopupMode.active }
        .accessibilityHint("Choose off, popup, popout, or a brief flash of the tapped key container.")
    }

    private var selectionBinding: Binding<KeyPopupMode> {
        Binding(
            get: { selection },
            set: {
                selection = $0
                $0.persist()
            }
        )
    }
}
