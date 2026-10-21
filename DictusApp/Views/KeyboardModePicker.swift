// DictusApp/Views/KeyboardModePicker.swift
// Native pickers for keyboard defaults and interaction preferences.
import SwiftUI
import SyllivraKernel

struct SpokenLanguagesPicker: View {
    @ObservedObject var modelManager: ModelManager
    @State private var languages = SpokenLanguagePreferences.load(from: AppGroup.defaults)
    @State private var query = ""

    var body: some View {
        NavigationLink {
            List {
                Section {
                    Button { update([]) } label: {
                        LabeledContent("Any Language") {
                            if languages.isEmpty { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Syllivra detects the language as you speak. Choose every language you speak to limit recognition and model recommendations to them.")
                }
                Section {
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
            .navigationTitle("Spoken Languages")
        } label: {
            LabeledContent("Spoken Languages", value: SpokenLanguagePreferences.summary(languages))
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

/// Selects the product surface that opens first. The old ABC/123 preference is
/// intentionally left readable for migration, but is no longer exposed here.
struct DefaultKeyboardModePicker: View {
    @AppStorage(SharedKeys.defaultKeyboardMode, store: UserDefaults(suiteName: AppGroup.identifier))
    private var selectedMode = DefaultKeyboardMode.dictationBoard.rawValue

    var body: some View {
        LabeledContent("Default Keyboard") {
            Picker("Default Keyboard", selection: $selectedMode) {
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
        .accessibilityHint("Choose whether Syllivra opens on the dictation board or typing keyboard.")
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

/// Native picker for the optional Live Activity presence.
struct DictationPresencePicker: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = DictationPresenceMode.active

    var body: some View {
        Toggle("Live Activity", isOn: Binding(
            get: { selection.showsLiveActivity },
            set: { apply($0 ? .liveActivity : .off) }
        ))
        .onAppear { selection = DictationPresenceMode.active }
        .accessibilityHint("Shows dictation status on the Lock Screen and in the Dynamic Island.")
    }

    private func apply(_ mode: DictationPresenceMode) {
        selection = mode
        mode.persist()
        LiveActivityManager.shared.applyPresenceMode(mode, isBackground: scenePhase == .background)
    }
}
