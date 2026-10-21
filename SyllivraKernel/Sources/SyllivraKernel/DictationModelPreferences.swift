import Foundation

/// Requested choices are independent of installed/resident model state.
public enum DictationModelPreferences {
    public static func canChangeRuntime(status: DictationStatus, finalizing: Bool) -> Bool {
        !DictationSessionLivenessPolicy.isActive(status) && !finalizing
    }
    public static func canPrepareModel(_ identifier: String, sessionModel: String,
                                       status: DictationStatus, finalizing: Bool) -> Bool {
        canChangeRuntime(status: status, finalizing: finalizing) || identifier == sessionModel
    }
    public static func migrate(in defaults: UserDefaults) {
        guard defaults.object(forKey: SharedKeys.appDictationModelReady) == nil else { return }
        let legacy = defaults.string(forKey: SharedKeys.activeModel)
        if let legacy, ModelInfo.forIdentifier(legacy) != nil {
            defaults.set(legacy, forKey: SharedKeys.appDictationModel)
            if defaults.string(forKey: SharedKeys.dictationWhisperModel) == nil {
                defaults.set(legacy, forKey: SharedKeys.dictationWhisperModel)
            }
            if defaults.string(forKey: SharedKeys.keyboardDictationModel) == nil {
                defaults.set(legacy, forKey: SharedKeys.keyboardDictationModel)
            }
        }
        defaults.set(defaults.bool(forKey: SharedKeys.modelReady), forKey: SharedKeys.appDictationModelReady)
    }

    public static func requestedAppModel(in defaults: UserDefaults) -> String {
        defaults.string(forKey: SharedKeys.dictationWhisperModel) ?? ModelInfo.defaultIdentifier
    }

    public static func resolveAppModel(in defaults: UserDefaults,
                                      installed: Set<String>, osMajor: Int, capabilities: DeviceCapabilities) -> String? {
        if ModelSelectionMode.active(from: defaults) == .automatic {
            return ModelSelectionProfile.active(from: defaults).resolvedIdentifier(installed: installed,
                osMajor: osMajor, capabilities: capabilities,
                requiredLanguages: SpokenLanguagePreferences.load(from: defaults))
        }
        let requested = requestedAppModel(in: defaults)
        guard installed.contains(requested), let model = ModelInfo.forIdentifier(requested),
              model.isRuntimeAvailable(onOSMajor: osMajor, capabilities: capabilities) else { return nil }
        return requested
    }

    public static func resolveKeyboardModel(in defaults: UserDefaults, installed: Set<String>,
                                           osMajor: Int, capabilities: DeviceCapabilities) -> String? {
        if let requested = defaults.string(forKey: SharedKeys.keyboardDictationModel) {
            guard installed.contains(requested), let model = ModelInfo.forIdentifier(requested),
                  model.isRuntimeAvailable(onOSMajor: osMajor, capabilities: capabilities) else { return nil }
            return requested
        }
        return ModelSelectionProfile.balanced.resolvedIdentifier(installed: installed,
            osMajor: osMajor, capabilities: capabilities,
            requiredLanguages: SpokenLanguagePreferences.load(from: defaults))
    }

    public static func requestedModel(for request: DictationLanguageRequest, in defaults: UserDefaults) -> String {
        if request.clientIdentifier?.hasPrefix("app-") == true {
            return defaults.string(forKey: SharedKeys.appDictationModel)
                ?? requestedAppModel(in: defaults)
        }
        return defaults.string(forKey: SharedKeys.activeModel)
            ?? defaults.string(forKey: SharedKeys.keyboardDictationModel) ?? ModelInfo.defaultIdentifier
    }
}
