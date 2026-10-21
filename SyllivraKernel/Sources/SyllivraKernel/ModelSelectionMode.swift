import Foundation

/// Controls whether sAiity keeps the user's explicit model or selects the best
/// installed compatible model for the current device state.
public enum ModelSelectionMode: String, CaseIterable, Codable, Sendable {
    case automatic
    case manual

    public static let defaultMode: Self = .automatic

    public static func active(from defaults: UserDefaults) -> Self {
        guard let raw = defaults.string(forKey: SharedKeys.modelSelectionMode),
              let mode = Self(rawValue: raw) else {
            return defaultMode
        }
        return mode
    }

    public static var active: Self {
        active(from: AppGroup.defaults)
    }

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .manual: return "Manual"
        }
    }

    public var explanation: String {
        switch self {
        case .automatic:
            return "Chooses an installed model for your spoken languages using this iPhone's memory, temperature, and catalog estimates."
        case .manual:
            return "Keeps the model you select until you change it."
        }
    }

    public func persist(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: SharedKeys.modelSelectionMode)
    }
}

/// Automatic selection chooses only installed compatible models; downloading
/// remains an explicit action on the Models page.
public enum ModelSelectionProfile: String, CaseIterable, Sendable {
    case balanced, recommended, precise

    public static func active(from defaults: UserDefaults) -> Self {
        Self(rawValue: defaults.string(forKey: SharedKeys.modelSelectionProfile) ?? "") ?? .balanced
    }

    public var explanation: String {
        switch self {
        case .balanced: return "Default · balances model size, speed and accuracy."
        case .recommended: return "Recommended · chooses models suited to this iPhone."
        case .precise: return "Harder workload · prioritizes accuracy with more memory and processing time."
        }
    }

    public func preferredIdentifier(for capabilities: DeviceCapabilities) -> String {
        if capabilities.isA12OrA13iPhone { return "openai_whisper-base" }
        let preferred: String
        switch self {
        case .balanced: preferred = "openai_whisper-small"
        case .recommended: preferred = ModelInfo.recommendedIdentifier(for: capabilities)
        case .precise: preferred = "openai_whisper-large-v3_947MB"
        }
        return ModelInfo.forIdentifier(preferred)?.isSupported(on: capabilities) == true
            ? preferred : ModelInfo.recommendedIdentifier(for: capabilities)
    }

    public func resolvedIdentifier(installed: Set<String>, osMajor: Int, capabilities: DeviceCapabilities,
                                   requiredLanguages: [String]? = nil) -> String? {
        let compatible = ModelInfo.allIncludingDeprecated.filter { model in
            installed.contains(model.identifier) && model.isRuntimeAvailable(onOSMajor: osMajor, capabilities: capabilities)
                && (requiredLanguages.map { SpokenLanguagePreferences.accepts(model, languages: $0) } ?? true)
        }
        let multilingual = compatible.filter { $0.runtimeCapability.supportsAutomaticLanguageDetection }
        let eligible = multilingual.isEmpty ? compatible : multilingual
        let languageCodes = SpokenLanguagePreferences.normalized(requiredLanguages ?? [])
        let betterForLanguages = eligible.filter { model in
            !model.languageSupport.highlights.contains { entry in
                entry.note == .impreciseUpgradeRecommended && languageCodes.contains(entry.code)
            }
        }
        let candidates = betterForLanguages.isEmpty ? eligible : betterForLanguages
        guard !candidates.isEmpty else { return nil }
        if capabilities.prefersFastRuntimeModel {
            return candidates.max { $0.speedScore < $1.speedScore }?.identifier
        }
        let preferred = preferredIdentifier(for: capabilities)
        if candidates.contains(where: { $0.identifier == preferred }) { return preferred }
        if self == .precise { return candidates.max { $0.accuracyScore < $1.accuracyScore }?.identifier }
        let sizeBudget = ModelInfo.forIdentifier(preferred)?.sizeBytes ?? 0
        let withinBudget = candidates.filter { $0.sizeBytes <= sizeBudget }
        return withinBudget.max { $0.accuracyScore < $1.accuracyScore }?.identifier
            ?? candidates.min { $0.sizeBytes < $1.sizeBytes }?.identifier
    }
}
