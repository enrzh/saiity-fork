// DictusApp/Views/KeyboardModePicker.swift
// Native pickers for keyboard defaults and interaction preferences.
import SwiftUI
import DictusCore

/// Native picker for the model policy. The resolver changes only among models
/// already installed on the device; it never starts a download by itself.
struct ModelSelectionModePicker: View {
    @ObservedObject var modelManager: ModelManager
    @State private var selection = ModelSelectionMode.active

    var body: some View {
        Picker("Model selection", selection: selectionBinding) {
            ForEach(ModelSelectionMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .onAppear { selection = modelManager.selectionMode }
        .accessibilityHint(modelManager.selectionMode.explanation)
    }

    private var selectionBinding: Binding<ModelSelectionMode> {
        Binding(
            get: { selection },
            set: {
                selection = $0
                modelManager.setSelectionMode($0)
            }
        )
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
    @AppStorage(SharedKeys.liquidGlassEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var liquidGlassEnabled = true

    var body: some View {
        Picker("Keyboard material", selection: $liquidGlassEnabled) {
            Text("Liquid Glass").tag(true)
            Text("Solid").tag(false)
        }
        .accessibilityHint("Choose solid keys or liquid glass keys.")
        .onChange(of: liquidGlassEnabled) { _, _ in
            KeyboardInteractionPreferences.notifyChanged()
        }
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
        .accessibilityHint("Choose off, popup above the key, or popout from the key.")
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
