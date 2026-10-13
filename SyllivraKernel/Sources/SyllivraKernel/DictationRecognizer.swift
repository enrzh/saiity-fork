import Foundation

/// Matches the macOS recognition fork; live text is an independent preference.
public enum DictationRecognizer: String, CaseIterable, Sendable {
    case streaming, whisper

    public var displayName: String { self == .streaming ? "Streaming" : "Whisper Auto" }
    public var defaultModelIdentifier: String {
        self == .streaming ? QwenASRModel.small.rawValue : ModelInfo.defaultIdentifier
    }
    public var modelPreferenceKey: String {
        self == .streaming ? SharedKeys.dictationStreamingModel : SharedKeys.dictationWhisperModel
    }
    public func contains(_ model: ModelInfo) -> Bool {
        (model.engine == .whisperKit) == (self == .whisper)
    }
    public static func load(from defaults: UserDefaults) -> Self {
        if let raw = defaults.string(forKey: SharedKeys.dictationRecognizer), let choice = Self(rawValue: raw) {
            return choice
        }
        let model = (defaults.string(forKey: SharedKeys.appDictationModel)
            ?? defaults.string(forKey: SharedKeys.activeModel)).flatMap(ModelInfo.forIdentifier)
        return model?.engine == .parakeet || model?.engine == .qwenASR ? .streaming : .whisper
    }
}

/// Qwen ASR is speech recognition, independent of the Qwen text-cleanup models.
public enum QwenASRModel: String, CaseIterable, Sendable {
    case small = "qwen3-asr-0.6b-4bit"
    case large = "qwen3-asr-1.7b-4bit"

    public var repository: String {
        self == .small ? "aufklarer/Qwen3-ASR-0.6B-MLX-4bit" : "aufklarer/Qwen3-ASR-1.7B-MLX-4bit"
    }
    public var directory: URL? {
        AppGroup.containerURL?.appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(rawValue, isDirectory: true)
    }
    public var requiredMemoryGB: Int { self == .small ? 6 : 8 }
}
