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
        case .qwen3ASR:
            return ModelRuntimeCapability(
                minimumOSMajorVersion: 18,
                supportsAutomaticLanguageDetection: true,
                fallbackIdentifier: "openai_whisper-small"
            )
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
        capabilities: DeviceCapabilities
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
        candidates.append(contentsOf: [
            "openai_whisper-small",
            "openai_whisper-base",
            "openai_whisper-tiny",
            recommendedIdentifier(for: capabilities)
        ])

        for candidate in candidates where candidate != requestedIdentifier {
            guard let model = forIdentifier(candidate),
                  installedIdentifiers.contains(candidate),
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
