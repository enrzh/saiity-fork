// DictusCore/Sources/DictusCore/ModelInfo.swift
import Foundation

public struct KeyboardSetupStatus: Equatable, Sendable {
    public let keyboardInstalled: Bool
    public let fullAccessHandshake: Bool
    public let handshakeDate: Date?

    /// The app and keyboard extension share this bundle-id prefix. It is used to
    /// classify an input mode identifier, not to claim that the mode is currently
    /// selected; `UITextInputMode.activeInputModes` only describes enabled modes.
    public static let dictusKeyboardIdentifierPrefix = "de.aiity.saiity.ios"

    public init(keyboardInstalled: Bool, fullAccessHandshake: Bool, handshakeDate: Date? = nil) {
        self.keyboardInstalled = keyboardInstalled
        self.fullAccessHandshake = fullAccessHandshake
        self.handshakeDate = handshakeDate
    }

    public static func isDictusKeyboardIdentifier(_ identifier: String?) -> Bool {
        guard let identifier, !identifier.isEmpty else { return false }
        if identifier.hasPrefix(dictusKeyboardIdentifierPrefix) { return true }
        let lowered = identifier.lowercased()
        return lowered.contains("saiity") && lowered.contains("keyboard")
    }

    public static func isCurrentFullAccessHandshake(
        verified: Bool,
        probe: String?,
        acknowledgedProbe: String?
    ) -> Bool {
        verified && probe != nil && probe == acknowledgedProbe
    }

    /// A handshake can only be written by the sAiity keyboard extension itself.
    /// Preserve the extension-owned handshake across transiently incomplete
    /// `activeInputModes` reads. A later false handshake is the removal signal.
    public var keyboardDetected: Bool { keyboardInstalled || fullAccessHandshake }
    public var fullAccessVerified: Bool { keyboardDetected && fullAccessHandshake }
    public var canContinue: Bool { fullAccessVerified }
}

/// Visibility state of a model in the download catalog.
///
/// Visibility distinguishes models that are currently selectable from models kept
/// only for backward compatibility.
public enum CatalogVisibility {
    case available
    case deprecated
    /// Artifact metadata only; excluded from app selection and runtime lookup.
    case evaluationOnly
}

/// Metadata for a supported WhisperKit model variant.
/// Used by the model manager UI and dictation pipeline.
///
/// Each model has a WhisperKit identifier (matching the argmaxinc/whisperkit-coreml
/// repository naming), a human-readable display name, numeric gauge scores for
/// accuracy and speed (0.0-1.0), and a short English description.
public struct ModelInfo: Identifiable {
    /// Identifiable conformance uses `identifier` as the unique ID.
    /// WHY Identifiable: SwiftUI's ForEach requires elements to be Identifiable
    /// so it can efficiently diff and animate list changes.
    public var id: String { identifier }

    public let identifier: String
    public let displayName: String
    public let sizeLabel: String
    public let sizeBytes: Int64

    /// Speech-to-text engine this model uses (WhisperKit or Parakeet).
    public let engine: SpeechEngine

    /// Editorial accuracy gauge (0...1), not measured WER or a cross-engine benchmark.
    public let accuracyScore: Double

    /// Relative speed gauge (0...1); only explicitly cited measurements are device evidence.
    public let speedScore: Double

    /// Short English description for the model selection UI.
    public let description: String

    /// Whether this model is shown in the download catalog or only kept for backward compatibility.
    public let visibility: CatalogVisibility

    // MARK: - Deprecated label properties (backward compat)

    /// Use accuracyScore instead. Kept temporarily for existing UI references.
    @available(*, deprecated, message: "Use accuracyScore gauge instead")
    public var accuracyLabel: String {
        switch accuracyScore {
        case 0.8...: return "Best"
        case 0.5...: return "Better"
        default: return "Good"
        }
    }

    /// Use speedScore instead. Kept temporarily for existing UI references.
    @available(*, deprecated, message: "Use speedScore gauge instead")
    public var speedLabel: String {
        switch speedScore {
        case 0.8...: return "Fast"
        case 0.5...: return "Balanced"
        default: return "Slow"
        }
    }

    // MARK: - Catalog

    /// The model used for a new installation before the user makes a choice.
    /// Existing device-specific recommendations remain available to the model
    /// catalog, but onboarding starts with the smallest Whisper model so the
    /// first download is predictable and lightweight.
    public static let defaultIdentifier = "openai_whisper-tiny"

    /// Resolves the initial selection without overwriting an existing choice.
    /// Empty values represent a new installation; non-empty values are kept so
    /// legacy and deprecated model selections continue to resolve normally.
    public static func initialModelIdentifier(existingSelection: String?) -> String {
        guard let selection = existingSelection,
              !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultIdentifier
        }
        return selection
    }

    /// Models available for new downloads: Tiny, Base, Medium, Large v3, and
    /// Large v3 Turbo. The full `redesignCatalog` stays resolvable so already
    /// downloaded Parakeet/preview rows still appear under Installed.
    public static let downloadableIdentifiers: Set<String> = [
        "openai_whisper-tiny",
        "openai_whisper-base",
        "openai_whisper-medium",
        "openai_whisper-large-v3_947MB",
        "openai_whisper-large-v3_turbo_954MB"
    ]

    public static let all: [ModelInfo] = {
        redesignCatalog.filter { model in
            model.visibility == .available && downloadableIdentifiers.contains(model.identifier)
        }
    }()

    /// The complete set of model identifiers currently loadable by the app.
    public static let redesignCatalog: [ModelInfo] = [
        ModelInfo(
            identifier: "openai_whisper-tiny",
            displayName: "Tiny",
            sizeLabel: "~77 MB",
            sizeBytes: 76_635_397,
            engine: .whisperKit,
            accuracyScore: 0.3,
            speedScore: 1.0,
            description: "Fast but inaccurate",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-tiny.en",
            displayName: "Tiny (English)",
            sizeLabel: "~153 MB",
            sizeBytes: 152_992_804,
            engine: .whisperKit,
            accuracyScore: 0.35,
            speedScore: 1.0,
            description: "English-only and fast",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-base",
            displayName: "Base",
            sizeLabel: "~147 MB",
            sizeBytes: 146_719_453,
            engine: .whisperKit,
            accuracyScore: 0.4,
            speedScore: 0.9,
            description: "Fast but inaccurate",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-base.en",
            displayName: "Base (English)",
            sizeLabel: "~147 MB",
            sizeBytes: 146_719_453,
            engine: .whisperKit,
            accuracyScore: 0.45,
            speedScore: 0.9,
            description: "English-only and balanced",
            visibility: .available
        ),
        // Speed scores recalibrated 2026-05-09 from measured RTF on iPhone 15 Pro Max
        // (issue #168 audit / PR #170): small ~17×, medium ~4×, turbo ~2.7×.
        // The pre-recalibration scores ranked turbo above medium for speed, which
        // contradicted measurement and misled users at model selection.
        ModelInfo(
            identifier: "openai_whisper-small",
            displayName: "Small",
            sizeLabel: "~487 MB",
            sizeBytes: 486_487_465,
            engine: .whisperKit,
            accuracyScore: 0.6,
            speedScore: 0.95,
            description: "Accurate and balanced",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-small.en",
            displayName: "Small (English)",
            sizeLabel: "~487 MB",
            sizeBytes: 486_487_465,
            engine: .whisperKit,
            accuracyScore: 0.62,
            speedScore: 0.95,
            description: "English-only and accurate",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-small_216MB",
            displayName: "Small (Quantized)",
            sizeLabel: "~216 MB",
            sizeBytes: 216_000_000,
            engine: .whisperKit,
            accuracyScore: 0.55,
            speedScore: 0.95,
            description: "Compact and fast",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-medium",
            displayName: "Medium",
            sizeLabel: "~1.53 GB",
            sizeBytes: 1_529_654_233,
            engine: .whisperKit,
            accuracyScore: 0.8,
            speedScore: 0.55,
            description: "Best accuracy",
            visibility: .available
        ),
        ModelInfo(
            identifier: "parakeet-tdt-0.6b-v2",
            displayName: "NVIDIA Parakeet v2",
            sizeLabel: "~800 MB",
            sizeBytes: 800_000_000,
            engine: .parakeet,
            accuracyScore: 0.82,
            speedScore: 0.86,
            description: "Fast and accurate, English only (NVIDIA)",
            visibility: .available
        ),
        ModelInfo(
            identifier: "parakeet-tdt-0.6b-v3",
            displayName: "NVIDIA Parakeet v3",
            sizeLabel: "~800 MB",
            sizeBytes: 800_000_000,
            engine: .parakeet,
            accuracyScore: 0.85,
            speedScore: 0.85,
            description: "Fast and accurate (NVIDIA)",
            visibility: .available
        ),
        // Phase 37 (issue #104): Whisper Turbo re-introduced using Argmax's
        // iPhone-supported quantized variant `openai_whisper-large-v3_turbo_954MB`.
        //
        // The previous non-quantized `openai_whisper-large-v3_turbo` identifier was
        // the root cause of the historical failures (2026-03 removals + 2026-04-22
        // retest on iPhone 15 Pro Max): that build is M-series-only and triggers
        // `ANE model load has failed ... Must re-compile the E5 bundle` on iPhone
        // ANE regardless of chip generation, because the non-quantized TextDecoder
        // exceeds the mobile ANE's memory budget.
        //
        // Source of truth: https://huggingface.co/argmaxinc/whisperkit-coreml/blob/main/config.json
        // iPhone 14/15/16/17 families (identifiers iPhone15,iPhone16,iPhone17,iPhone18)
        // list this `_954MB` variant as supported.
        ModelInfo(
            identifier: "openai_whisper-large-v3_turbo_954MB",
            displayName: "Turbo",
            sizeLabel: "~954 MB",
            sizeBytes: 954_000_000,
            engine: .whisperKit,
            accuracyScore: 0.9,
            speedScore: 0.2,
            description: "Most accurate but slowest",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-large-v2_949MB",
            displayName: "Large v2",
            sizeLabel: "~949 MB",
            sizeBytes: 949_000_000,
            engine: .whisperKit,
            accuracyScore: 0.87,
            speedScore: 0.15,
            description: "High accuracy, older generation",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-large-v2_turbo_955MB",
            displayName: "Large v2 Turbo",
            sizeLabel: "~955 MB",
            sizeBytes: 955_000_000,
            engine: .whisperKit,
            accuracyScore: 0.88,
            speedScore: 0.25,
            description: "High accuracy and faster",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-large-v3_947MB",
            displayName: "Large v3",
            sizeLabel: "~947 MB",
            sizeBytes: 947_000_000,
            engine: .whisperKit,
            accuracyScore: 0.93,
            speedScore: 0.12,
            description: "Highest accuracy",
            visibility: .available
        ),
        ModelInfo(
            identifier: "distil-whisper_distil-large-v3_594MB",
            displayName: "Distil-Whisper Large v3",
            sizeLabel: "~594 MB",
            sizeBytes: 594_000_000,
            engine: .whisperKit,
            accuracyScore: 0.86,
            speedScore: 0.50,
            description: "High accuracy, compact",
            visibility: .available
        ),
        ModelInfo(
            identifier: "distil-whisper_distil-large-v3_turbo_600MB",
            displayName: "Distil-Whisper Large v3 Turbo",
            sizeLabel: "~600 MB",
            sizeBytes: 600_000_000,
            engine: .whisperKit,
            accuracyScore: 0.87,
            speedScore: 0.55,
            description: "High accuracy, compact and fast",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-large-v3-v20240930_626MB",
            displayName: "Large v3 (2024)",
            sizeLabel: "~626 MB",
            sizeBytes: 626_000_000,
            engine: .whisperKit,
            accuracyScore: 0.92,
            speedScore: 0.20,
            description: "High accuracy, optimized",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-large-v3-v20240930_turbo_632MB",
            displayName: "Large v3 Turbo (2024)",
            sizeLabel: "~632 MB",
            sizeBytes: 632_000_000,
            engine: .whisperKit,
            accuracyScore: 0.91,
            speedScore: 0.30,
            description: "High accuracy, optimized and faster",
            visibility: .available
        ),
        // Verified against the Argmax repository tree, 2026-09-12.
        // Preview exports use the existing sequential WhisperKit pipeline.
        ModelInfo(
            identifier: "openai_whisper-small.en_217MB",
            displayName: "Small English · Compact",
            sizeLabel: "~218 MB", sizeBytes: 217_878_408,
            engine: .whisperKit, accuracyScore: 0.6, speedScore: 0.9,
            description: "Quantized English-only model. Preview export; evaluate on your device.",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-medium.en",
            displayName: "Medium English",
            sizeLabel: "~1.53 GB", sizeBytes: 1_529_674_079,
            engine: .whisperKit, accuracyScore: 0.8, speedScore: 0.5,
            description: "English-only medium model. Larger download; preview on iPhone.",
            visibility: .available
        ),
        ModelInfo(
            identifier: "openai_whisper-large-v3-v20240930_547MB",
            displayName: "Large v3 Turbo · Compact",
            sizeLabel: "~550 MB", sizeBytes: 549_554_198,
            engine: .whisperKit, accuracyScore: 0.8, speedScore: 0.5,
            description: "More compressed multilingual Turbo export. Preview; accuracy may differ.",
            visibility: .available
        )
    ]

    /// Preview exports have the expected WhisperKit bundle layout, but are not
    /// explicitly listed in Argmax's iPhone support matrix (checked 2026-09-12).
    /// Neither this flag nor a passing local RAM gate proves device compatibility.
    public var isExperimental: Bool {
        switch identifier {
        case "openai_whisper-small.en_217MB",
             "openai_whisper-medium.en",
             "openai_whisper-large-v3-v20240930_547MB":
            return true
        default:
            return false
        }
    }

    /// All known models, using one authoritative metadata row per identifier.
    /// Older downloads remain resolvable because their identifiers stay in the
    /// current catalog; duplicate legacy rows could otherwise shadow current data.
    public static let allIncludingDeprecated: [ModelInfo] = redesignCatalog.filter {
        $0.visibility != .evaluationOnly
    }

    /// Research access only. Never feed these rows into model selection.
    public static let evaluationCandidates: [ModelInfo] = redesignCatalog.filter {
        $0.visibility == .evaluationOnly
    }

    /// Removes duplicate identifiers while preferring the last metadata entry.
    /// Reversing again preserves the original catalog order for the retained rows.
    public static func installedRows(from models: [ModelInfo]) -> [ModelInfo] {
        var seen = Set<String>()
        return models.reversed()
            .filter { $0.visibility != .evaluationOnly }
            .filter { seen.insert($0.identifier).inserted }
            .reversed()
    }

    /// Set of all supported model identifiers for quick lookup.
    /// Uses allIncludingDeprecated so downloaded Tiny/Base models still resolve.
    public static let supportedIdentifiers: Set<String> = Set(allIncludingDeprecated.map(\.identifier))

    /// Look up a model by its WhisperKit identifier.
    /// Searches allIncludingDeprecated so deprecated models are still resolvable.
    /// Returns nil if the identifier is not in the supported list.
    public static func forIdentifier(_ id: String) -> ModelInfo? {
        allIncludingDeprecated.first { $0.identifier == id }
    }

    // MARK: - Device-compatible Recommendation

    /// Returns the recommended model identifier based on hardware compatibility
    /// first, then device RAM.
    ///
    /// WHY compatibility before RAM:
    /// Argmax only supports Tiny/Base on A12/A13 iPhones, while A14 devices with the
    /// same 4 GB RAM tier support Small — so RAM alone cannot separate them, and
    /// recommending Small on an iPhone 11 traps onboarding in Core ML optimization
    /// and can jetsam the app (issue #362). `DeviceCapabilities.isA12OrA13iPhone`
    /// owns that test; `isSupported(on:)` reads the same predicate. After the
    /// hardware exception, Parakeet v3 (~800 MB) remains the pick for >= 6 GB.
    ///
    /// WHY in ModelInfo (not ModelManager):
    /// This is catalog-level logic — which model fits this device. It doesn't
    /// depend on download state or any @Published properties. Accessible from
    /// both ModelManager and onboarding without passing an ObservableObject.
    ///
    /// WHY a function taking `DeviceCapabilities` instead of a cached static let:
    /// Phase 37 introduces per-device gating that needs deterministic inputs for
    /// unit testing. The caller-less overload still exists for convenience — it
    /// reads the current device, same behaviour as before.
    /// Turbo is intentionally never recommended by default during Phase 37.
    public static func recommendedIdentifier(for capabilities: DeviceCapabilities) -> String {
        if capabilities.isA12OrA13iPhone {
            // Base, not Tiny: it is the most accurate variant Argmax lists for this
            // tier, and `a12a13SupportedIdentifiers` keeps the two consistent.
            return "openai_whisper-base"
        }
        return capabilities.physicalMemoryGB >= 6
            ? "openai_whisper-medium"
            : "openai_whisper-base"
    }

    public static func recommendedIdentifier() -> String {
        recommendedIdentifier(for: DeviceCapabilities.current())
    }

    /// Whether the given model identifier matches the device-recommended model.
    public static func isRecommended(_ identifier: String) -> Bool {
        identifier == recommendedIdentifier()
    }

    // MARK: - Per-device gating (Phase 37, issue #104)

    /// Whether this model is safe to expose on a device with the given capabilities.
    ///
    /// For the quantized Whisper Turbo (`_954MB`): requires ≥ 6 GB RAM. This matches
    /// Argmax's published compatibility matrix: all iPhone 14/15/16/17 families
    /// (iPhone15,X through iPhone18,X in Apple identifier nomenclature) list this
    /// variant as supported, and those devices ship with 6 GB+ RAM.
    /// For every other model: returns true — existing catalog entries have already
    /// been validated on the minimum supported device class.
    ///
    /// Called from the Settings UI to decide whether the Turbo row appears in the
    /// "Available" section. Backend paths (ModelManager download/delete, already-
    /// downloaded list) intentionally do NOT filter by this, so a user who obtained
    /// Turbo under a more permissive build can still manage it.
    /// The only Whisper variants Argmax lists as supported on A12/A13 iPhones.
    ///
    /// WHY the `.en` variants are listed even though Dictus does not ship them:
    /// this set is a transcription of Argmax's published matrix, so it stays
    /// comparable against the source when that matrix is revisited. They simply
    /// never match a catalog entry today.
    ///
    /// Source of truth: https://huggingface.co/argmaxinc/whisperkit-coreml/raw/main/config.json
    static let a12a13SupportedIdentifiers: Set<String> = [
        "openai_whisper-tiny",
        "openai_whisper-tiny.en",
        "openai_whisper-base",
        "openai_whisper-base.en"
    ]

    /// Why a model cannot run on a given device, or `nil` when it can.
    ///
    /// WHY the reason is modelled here and not phrased here:
    /// the UI has to tell the user which constraint they are looking at (issue #369),
    /// and that sentence must be localized. DictusCore owns the policy; the app layer
    /// maps each case to its French/English wording in `ModelInfo+Localized.swift`.
    public enum IncompatibilityReason: Equatable, Sendable {
        /// The chip predates the variant. Argmax's support matrix, not memory.
        case hardwareGeneration
        /// The device has less RAM than the variant needs.
        case insufficientMemory(requiredGB: Int)
    }

    /// The reason this model cannot run on the given device, or `nil` if it can.
    ///
    /// WHY `isSupported(on:)` delegates here rather than duplicating the rules:
    /// issue #369 renders the reason next to a disabled row, so a divergence between
    /// "is it gated" and "why is it gated" would be visible as a greyed card with no
    /// explanation, or an explanation on a tappable card. One function, no drift.
    public func incompatibilityReason(on capabilities: DeviceCapabilities) -> IncompatibilityReason? {
        // WHY this branch comes first: on A12/A13 the limit is the Core ML support
        // matrix, not memory. Falling through to the RAM rule would leave Small,
        // Small (Quantized) and Medium selectable in Settings on an iPhone 11, and
        // downloading any of them reproduces the issue #362 optimization hang.
        // Parakeet is excluded here too — it is absent from Argmax's matrix and
        // needs ~800 MB of headroom these 3-4 GB devices do not have.
        if capabilities.isA12OrA13iPhone {
            return Self.a12a13SupportedIdentifiers.contains(identifier) ? nil : .hardwareGeneration
        }
        switch identifier {
        case "openai_whisper-medium.en", "openai_whisper-large-v3-v20240930_547MB",
             "openai_whisper-large-v3_turbo_954MB",
             "openai_whisper-large-v2_949MB",
             "openai_whisper-large-v2_turbo_955MB",
             "openai_whisper-large-v3_947MB",
             "distil-whisper_distil-large-v3_594MB",
             "distil-whisper_distil-large-v3_turbo_600MB",
             "openai_whisper-large-v3-v20240930_626MB",
             "openai_whisper-large-v3-v20240930_turbo_632MB":
            return capabilities.physicalMemoryGB >= 6 ? nil : .insufficientMemory(requiredGB: 6)
        default:
            return nil
        }
    }

    public func isSupported(on capabilities: DeviceCapabilities) -> Bool {
        incompatibilityReason(on: capabilities) == nil
    }

    /// The rows the Settings "Available" section should render for this device:
    /// the visible catalog, plus the device's recommended model even when that model
    /// is deprecated.
    ///
    /// WHY incompatible models are NOT filtered out (issue #369, reversing #104):
    /// hiding them told the user nothing, and the absence read as a property of
    /// Dictus rather than of their phone. On an A12/A13 iPhone the gating from
    /// issue #362 would collapse this list to a single entry. They stay in the list
    /// and the card renders them disabled with a reason; `incompatibilityReason(on:)`
    /// is what the view asks. Deprecation still filters — deprecated means superseded,
    /// not unrunnable, so those rows would have nothing to explain.
    ///
    /// WHY the recommendation is force-included (issue #362):
    /// On A12/A13 iPhones the recommendation is Base, which is `.deprecated` and so
    /// absent from `all`. Without this exception the app has a reachable dead end:
    /// onboarding installs Base, the user downloads a second model, deleting Base
    /// then becomes permitted, and Base cannot be reinstalled from anywhere. Base
    /// stays deprecated globally on purpose — on A14+ Small is strictly better — so
    /// the exception is scoped to the model this device is actually told to use.
    ///
    /// WHY the exception is guarded on `.deprecated` rather than matching the
    /// identifier alone: a recommended model may still be dropped from `all`
    /// when it is `.deprecated`. A bare identifier match is enough now that
    /// downloadable rows are a fixed Whisper set, but keeping the deprecation
    /// guard avoids resurrecting a hidden compatibility row that is not the
    /// recommendation.
    ///
    /// Starts from `all` so compatibility entries never duplicate current UI rows.
    public static func available(on capabilities: DeviceCapabilities) -> [ModelInfo] {
        let recommended = recommendedIdentifier(for: capabilities)
        if all.contains(where: { $0.identifier == recommended }) { return all }
        return all + allIncludingDeprecated.filter {
            $0.visibility == .deprecated && $0.identifier == recommended
        }
    }
}
