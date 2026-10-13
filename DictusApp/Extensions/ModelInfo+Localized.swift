// DictusApp/Extensions/ModelInfo+Localized.swift
// Localized display strings for ModelInfo, resolved via String Catalog.
import SyllivraKernel
import SwiftUI

extension ModelInfo {
    /// The first-run model chosen by the app. Kept here so every app surface
    /// agrees even when the shared catalog's historical default changes.
    static let sAiityDefaultIdentifier = "openai_whisper-tiny"

    /// Localized description for display in model cards.
    /// Source strings are in English; French provided via String Catalog.
    var localizedDescription: String {
        if isExperimental {
            return String(localized: "Preview export. Test accuracy and speed on your own recordings.")
        }
        switch identifier {
        case "openai_whisper-tiny", "openai_whisper-base":
            return String(localized: "A compact starting point for everyday dictation.")
        case "openai_whisper-tiny.en", "openai_whisper-base.en", "openai_whisper-small.en":
            return String(localized: "Specialized for English dictation.")
        case "openai_whisper-small_216MB":
            return String(localized: "Compressed multilingual model with a smaller download.")
        case "openai_whisper-small":
            return String(localized: "A middle-ground multilingual voice model.")
        case "openai_whisper-medium":
            return String(localized: "More capacity for difficult speech; needs more memory.")
        case "parakeet-tdt-0.6b-v2":
            return String(localized: "NVIDIA speech recognition for English.")
        case "parakeet-tdt-0.6b-v3":
            return String(localized: "NVIDIA speech recognition for 25 European languages.")
        case QwenASRModel.small.rawValue, QwenASRModel.large.rawValue:
            return String(localized: "Qwen streaming recognition in the foreground app. Requires compatible iOS 18+ hardware; phone accuracy and speed remain unverified.")
        case "distil-whisper_distil-large-v3_594MB", "distil-whisper_distil-large-v3_turbo_600MB":
            return String(localized: "Distilled Whisper model specialized for English.")
        default:
            return String(localized: "Large multilingual Whisper export. Speed varies with your device.")
        }
    }
}

// MARK: - Incompatibility wording (issue #369)

extension ModelInfo.IncompatibilityReason {
    /// One short line telling the user which constraint they are looking at.
    ///
    /// WHY it names the hardware and not the app:
    /// the row is greyed because of the phone, and the sentence has to carry that
    /// or the user reads the disabled card as Dictus being broken or thin. It must
    /// not sound like an error or like something they did.
    var localizedText: String {
        switch self {
        case .hardwareGeneration:
            return String(localized: "Not supported on this iPhone")
        case .insufficientMemory(let requiredGB):
            // Says what the requirement is rather than restating the refusal.
            return String(localized: "Requires \(requiredGB) GB of memory or more")
        }
    }
}

// MARK: - Language support strings (issue #240)

extension ModelLanguageSupport.Coverage {
    /// One-line coverage summary shown at the top of the language detail view.
    var localizedSummary: String {
        switch self {
        case .whisperMultilingual:
            return String(localized: "About 99 languages (multilingual)")
        case .whisperEnglishOnly:
            return String(localized: "English only")
        case .parakeetEuropean:
            return String(localized: "25 European languages")
        case .qwenMultilingual:
            return String(localized: "Multilingual streaming; complete language coverage remains unverified")
        }
    }
}

extension ModelLanguageSupport.QualityNote {
    /// Localized wording for a curated per-tier quality note.
    var localizedText: String {
        switch self {
        case .impreciseUpgradeRecommended:
            return String(localized: "Smaller models may be less accurate. Verify on your own speech.")
        case .goodOnThisModel:
            return String(localized: "More model capacity; accuracy on this phone remains unverified.")
        }
    }
}

extension ModelLanguageSupport {
    /// User-facing display name for an ISO 639-1 code, localized by the
    /// system (French UI shows "chinois", English UI shows "Chinese").
    ///
    /// WHY Locale instead of hardcoded names:
    /// `Locale.localizedString(forLanguageCode:)` covers every code we curate
    /// in both app languages without maintaining a translation table.
    /// Falls back to the raw code for any code the OS cannot name.
    static func localizedLanguageName(for code: String) -> String {
        guard let name = Locale.current.localizedString(forLanguageCode: code) else {
            return code
        }
        // Locale returns lowercase names in some languages (e.g. "français");
        // capitalize the first letter for list display.
        return name.prefix(1).localizedCapitalized + name.dropFirst()
    }
}
