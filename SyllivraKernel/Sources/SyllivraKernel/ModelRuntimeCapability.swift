import Foundation

/// Runtime facts that affect whether a catalog model can actually be loaded.
/// Language coverage remains owned by `ModelLanguageSupport`; this type only
/// describes platform capability and a conservative local fallback.
public struct ModelRuntimeCapability: Equatable, Sendable {
    public let minimumOSMajorVersion: Int
    public let supportsAutomaticLanguageDetection: Bool
    public let fallbackIdentifier: String?

    public init(
        minimumOSMajorVersion: Int,
        supportsAutomaticLanguageDetection: Bool,
        fallbackIdentifier: String?
    ) {
        self.minimumOSMajorVersion = minimumOSMajorVersion
        self.supportsAutomaticLanguageDetection = supportsAutomaticLanguageDetection
        self.fallbackIdentifier = fallbackIdentifier
    }
}

public enum ModelRuntimeFallbackReason: String, Equatable, Sendable {
    case unknownModel
    case unavailableOnOS
    case incompatibleDevice
    case notInstalled
    case unsupportedLanguages
}

/// The result of resolving a requested catalog row to a locally runnable row.
public struct ModelRuntimeResolution: Equatable, Sendable {
    public let requestedIdentifier: String?
    public let resolvedIdentifier: String?
    public let fallbackReason: ModelRuntimeFallbackReason?

    public init(
        requestedIdentifier: String?,
        resolvedIdentifier: String?,
        fallbackReason: ModelRuntimeFallbackReason?
    ) {
        self.requestedIdentifier = requestedIdentifier
        self.resolvedIdentifier = resolvedIdentifier
        self.fallbackReason = fallbackReason
    }

    public var usedFallback: Bool {
        requestedIdentifier != nil
            && resolvedIdentifier != nil
            && requestedIdentifier != resolvedIdentifier
    }
}

extension ModelInfo {
    /// Picks the best installed model for the current device without requiring
    /// a previously selected identifier to be valid.
    public static func automaticRuntimeResolution(
        installedIdentifiers: Set<String>,
        osMajor: Int,
        capabilities: DeviceCapabilities
    ) -> ModelRuntimeResolution {
        runtimeResolution(
            for: recommendedIdentifier(for: capabilities),
            installedIdentifiers: installedIdentifiers,
            osMajor: osMajor,
            capabilities: capabilities
        )
    }

    /// Runtime capability metadata for the selected engine/model family.
    /// No language claim is made here beyond the existing catalog support data.
    public var runtimeCapability: ModelRuntimeCapability {
        switch engine {
        case .whisperKit:
            return ModelRuntimeCapability(
                minimumOSMajorVersion: 17,
                supportsAutomaticLanguageDetection: languageSupport.coverage != .whisperEnglishOnly,
                fallbackIdentifier: nil
            )
        case .parakeet:
            return ModelRuntimeCapability(
                minimumOSMajorVersion: 17,
                supportsAutomaticLanguageDetection: languageSupport.coverage == .parakeetEuropean,
                fallbackIdentifier: "openai_whisper-small"
            )
        case .qwenASR:
            return ModelRuntimeCapability(minimumOSMajorVersion: 18,
                supportsAutomaticLanguageDetection: true, fallbackIdentifier: nil)
        }
    }

    public func isRuntimeAvailable(onOSMajor osMajor: Int, capabilities: DeviceCapabilities) -> Bool {
        osMajor >= runtimeCapability.minimumOSMajorVersion && isSupported(on: capabilities)
    }

    /// Resolve only to an installed, device-compatible model. A missing fallback
    /// remains unresolved so the caller can show the existing model-download error.
    public static func runtimeResolution(
        for requestedIdentifier: String?,
        installedIdentifiers: Set<String>,
        osMajor: Int,
        capabilities: DeviceCapabilities,
        fallbackLanguages: [String]? = nil
    ) -> ModelRuntimeResolution {
        guard let requestedIdentifier else {
            return ModelRuntimeResolution(
                requestedIdentifier: nil,
                resolvedIdentifier: nil,
                fallbackReason: .unknownModel
            )
        }

        let requestedModel = forIdentifier(requestedIdentifier)
        let requestedReason: ModelRuntimeFallbackReason
        if let requestedModel {
            if osMajor < requestedModel.runtimeCapability.minimumOSMajorVersion {
                requestedReason = .unavailableOnOS
            } else if !requestedModel.isSupported(on: capabilities) {
                requestedReason = .incompatibleDevice
            } else if !installedIdentifiers.contains(requestedIdentifier) {
                requestedReason = .notInstalled
            } else if let languages = fallbackLanguages, !languages.isEmpty,
                      !SpokenLanguagePreferences.accepts(requestedModel, languages: languages) {
                requestedReason = .unsupportedLanguages
            } else {
                return ModelRuntimeResolution(
                    requestedIdentifier: requestedIdentifier,
                    resolvedIdentifier: requestedIdentifier,
                    fallbackReason: nil
                )
            }
        } else {
            requestedReason = .unknownModel
        }

        var candidates: [String] = []
        if let fallback = requestedModel?.runtimeCapability.fallbackIdentifier {
            candidates.append(fallback)
        }

        let fastFirst = capabilities.prefersFastRuntimeModel
        let defaultOrder = fastFirst
            ? ["openai_whisper-base", "openai_whisper-tiny", "openai_whisper-small"]
            : [recommendedIdentifier(for: capabilities), "openai_whisper-small", "openai_whisper-base", "openai_whisper-tiny"]
        candidates.append(contentsOf: defaultOrder)

        // Measured warm latency is a tie-breaker only for compatible fallback
        // artifacts. Accuracy and multilingual coverage still outrank a noisy
        // one-off timing sample.
        let warmLatencies = ModelWarmLatencyStore.load(from: AppGroup.defaults)
        let ranked = candidates.enumerated().sorted { left, right in
            let leftLatency = warmLatencies[candidates[left.offset]] ?? Double.greatestFiniteMagnitude
            let rightLatency = warmLatencies[candidates[right.offset]] ?? Double.greatestFiniteMagnitude
            if leftLatency != rightLatency { return leftLatency < rightLatency }
            return left.offset < right.offset
        }.map(\.element)
        candidates = ranked

        if requestedModel?.engine == .qwenASR && requestedReason != .unsupportedLanguages {
            return ModelRuntimeResolution(requestedIdentifier: requestedIdentifier,
                resolvedIdentifier: nil, fallbackReason: requestedReason)
        }
        for candidate in candidates where candidate != requestedIdentifier {
            guard let model = forIdentifier(candidate),
                  installedIdentifiers.contains(candidate),
                  fallbackLanguages.map({ SpokenLanguagePreferences.accepts(model, languages: $0) }) ?? true,
                  model.isRuntimeAvailable(onOSMajor: osMajor, capabilities: capabilities) else {
                continue
            }
            return ModelRuntimeResolution(
                requestedIdentifier: requestedIdentifier,
                resolvedIdentifier: candidate,
                fallbackReason: requestedReason
            )
        }

        return ModelRuntimeResolution(
            requestedIdentifier: requestedIdentifier,
            resolvedIdentifier: nil,
            fallbackReason: requestedReason
        )
    }
}

/// Persists only aggregate model timing, never audio or transcript content.
public enum ModelWarmLatencyStore {
    public static func load(from defaults: UserDefaults) -> [String: Double] {
        guard let data = defaults.data(forKey: SharedKeys.modelWarmLatency),
              let values = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return values.filter { $0.value.isFinite && $0.value > 0 }
    }

    public static func record(_ durationMilliseconds: Int,
                              for identifier: String,
                              in defaults: UserDefaults) {
        guard durationMilliseconds > 0, !identifier.isEmpty else { return }
        var values = load(from: defaults)
        let sample = Double(durationMilliseconds)
        if let previous = values[identifier] {
            values[identifier] = (previous * 0.8) + (sample * 0.2)
        } else {
            values[identifier] = sample
        }
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: SharedKeys.modelWarmLatency)
        }
    }
}
