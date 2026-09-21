import Foundation

/// User-selected backend for post-STT dictation cleanup / grammar.
///
/// Apple Intelligence is the built-in on-device Foundation Models path.
/// Ollama is only used when the user picks a valid registered cleanup model.
public enum PolishCleanupBackend: Hashable, Sendable {
    case appleIntelligence
    case ollama(UUID)

    public static let appleIntelligenceStorageValue = "appleIntelligence"

    public var storageValue: String {
        switch self {
        case .appleIntelligence:
            return Self.appleIntelligenceStorageValue
        case .ollama(let id):
            return "ollama:\(id.uuidString)"
        }
    }

    public var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .ollama: return "Ollama"
        }
    }

    public static func parse(_ raw: String) -> PolishCleanupBackend? {
        if raw == appleIntelligenceStorageValue { return .appleIntelligence }
        guard raw.hasPrefix("ollama:") else { return nil }
        let rest = String(raw.dropFirst("ollama:".count))
        guard let id = UUID(uuidString: rest) else { return nil }
        return .ollama(id)
    }

    public static func validOllamaCleanupModels(from models: [CustomModel]) -> [CustomModel] {
        models.filter { $0.role == .cleanup && $0.source == .ollama && $0.validationError == nil }
    }

    /// Resolve the stored preference, migrating older installs that silently
    /// used a valid Ollama cleanup registration. The first load writes the key
    /// so later Ollama registrations cannot steal an Apple Intelligence default.
    public static func load(
        from defaults: UserDefaults?,
        customModels: [CustomModel]? = nil
    ) -> PolishCleanupBackend {
        let models = customModels ?? defaults.map { CustomModel.load(from: $0) } ?? []
        let validOllama = validOllamaCleanupModels(from: models)
        let resolvedPreference: PolishCleanupBackend

        if let raw = defaults?.string(forKey: SharedKeys.polishCleanupBackend) {
            if raw == "ollama" {
                resolvedPreference = validOllama.first.map { .ollama($0.id) } ?? .appleIntelligence
            } else if let parsed = parse(raw) {
                resolvedPreference = resolved(parsed, validOllama: validOllama)
            } else {
                resolvedPreference = .appleIntelligence
            }
        } else if let first = validOllama.first {
            resolvedPreference = .ollama(first.id)
        } else {
            resolvedPreference = .appleIntelligence
        }

        if defaults?.object(forKey: SharedKeys.polishCleanupBackend) == nil {
            resolvedPreference.persist(to: defaults)
        }
        return resolvedPreference
    }

    public func persist(to defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.identifier)) {
        defaults?.set(storageValue, forKey: SharedKeys.polishCleanupBackend)
    }

    /// When the selected Ollama model is deleted, keep a remaining Ollama
    /// cleanup model if one exists; otherwise return to Apple Intelligence.
    public static func handleDeletedModel(
        _ model: CustomModel,
        remaining: [CustomModel],
        defaults: UserDefaults?
    ) {
        guard let raw = defaults?.string(forKey: SharedKeys.polishCleanupBackend),
              case .ollama(let id) = parse(raw),
              id == model.id else { return }
        load(from: defaults, customModels: remaining).persist(to: defaults)
    }

    public static func resolved(
        _ stored: PolishCleanupBackend,
        validOllama: [CustomModel]
    ) -> PolishCleanupBackend {
        switch stored {
        case .appleIntelligence:
            return .appleIntelligence
        case .ollama(let id):
            if validOllama.contains(where: { $0.id == id }) {
                return .ollama(id)
            }
            if let first = validOllama.first {
                return .ollama(first.id)
            }
            return .appleIntelligence
        }
    }

    /// Runtime engine after availability gates. An explicit Apple Intelligence
    /// choice never silently falls through to Ollama.
    public static func resolvedEngine(
        preference: PolishCleanupBackend,
        appleFMAvailable: Bool,
        validOllamaIDs: Set<UUID>
    ) -> PolishCleanupEngineKind {
        switch preference {
        case .appleIntelligence:
            return appleFMAvailable ? .appleIntelligence : .passthrough
        case .ollama(let id):
            if validOllamaIDs.contains(id) {
                return .ollama(id)
            }
            return appleFMAvailable ? .appleIntelligence : .passthrough
        }
    }
}

public enum PolishCleanupEngineKind: Equatable, Sendable {
    case appleIntelligence
    case ollama(UUID)
    case passthrough
}
