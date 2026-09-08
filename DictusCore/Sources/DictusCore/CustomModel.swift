import Foundation

public enum CustomModelRole: String, Codable, CaseIterable, Sendable {
    case asr
    case cleanup

    public var displayName: String {
        switch self {
        case .asr: return "Speech recognition"
        case .cleanup: return "Dictation cleanup"
        }
    }
}

public enum CustomModelSource: String, Codable, CaseIterable, Sendable {
    case huggingFace
    case nvidia
    case ollama

    public var displayName: String {
        switch self {
        case .huggingFace: return "Hugging Face"
        case .nvidia: return "NVIDIA"
        case .ollama: return "Ollama"
        }
    }
}

public enum CustomModelRemoteValidationState: String, Codable, Sendable {
    case notRequired
    case verified
    case needsVerification
}

public struct CustomModel: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var repositoryURL: String
    public var role: CustomModelRole
    public var source: CustomModelSource
    public var modelName: String?
    public var remoteValidationState: CustomModelRemoteValidationState

    private enum CodingKeys: String, CodingKey {
        case id, name, repositoryURL, role, source, modelName, remoteValidationState
    }

    public init(id: UUID = UUID(), name: String, repositoryURL: String,
                role: CustomModelRole, source: CustomModelSource, modelName: String? = nil,
                remoteValidationState: CustomModelRemoteValidationState? = nil) {
        self.id = id
        self.name = name
        self.repositoryURL = repositoryURL
        self.role = role
        self.source = source
        self.modelName = modelName
        self.remoteValidationState = remoteValidationState ??
            (role == .asr && source == .huggingFace ? .needsVerification : .notRequired)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let role = try values.decode(CustomModelRole.self, forKey: .role)
        let source = try values.decode(CustomModelSource.self, forKey: .source)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            repositoryURL: try values.decode(String.self, forKey: .repositoryURL),
            role: role,
            source: source,
            modelName: try values.decodeIfPresent(String.self, forKey: .modelName),
            remoteValidationState: try values.decodeIfPresent(CustomModelRemoteValidationState.self, forKey: .remoteValidationState)
        )
    }

    /// Stable identity used to replace an existing registration rather than
    /// creating duplicate rows when the same source is added again.
    public var identityKey: String {
        let normalizedURL = repositoryURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        let normalizedModelName = modelName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return [role.rawValue, source.rawValue, normalizedURL, normalizedModelName].joined(separator: "|")
    }

    public var validationError: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter a model name."
        }
        guard let url = URL(string: repositoryURL),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return "Use a valid model URL."
        }
        guard url.user == nil, url.password == nil else {
            return "Model URLs must not contain credentials or a port."
        }
        let isOllamaLoopback = source == .ollama && role == .cleanup &&
            ["localhost", "127.0.0.1", "::1"].contains(host)
        guard url.port == nil || (isOllamaLoopback && url.port == 11434) else {
            return "Model URLs must not contain credentials or a non-default port."
        }
        switch (source, role) {
        case (.ollama, .asr): return "Ollama models can only be used for cleanup."
        case (.ollama, .cleanup):
            guard !(modelName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Enter the Ollama model name."
            }
            let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
            let isOllamaCloud = host == "ollama.com" || host == "www.ollama.com"
            guard (isLoopback && (scheme == "http" || scheme == "https")) ||
                  (isOllamaCloud && scheme == "https") else {
                return "Use a local Ollama address or https://ollama.com."
            }
        case (.huggingFace, _):
            guard scheme == "https", host == "huggingface.co" || host == "www.huggingface.co" else {
                return "Use a Hugging Face model URL."
            }
            guard isRepositoryPath(url.path, componentCount: 2) else {
                return "Use a Hugging Face repository URL."
            }
        case (.nvidia, .asr):
            guard scheme == "https", host == "developer.nvidia.com" else {
                return "Use an NVIDIA model URL."
            }
            guard isNVIDIAASRRepositoryPath(url.path) else {
                return "Use an NVIDIA model repository URL."
            }
        case (.nvidia, .cleanup): return "NVIDIA sources are only supported for speech recognition."
        }
        guard url.query == nil, url.fragment == nil else {
            return "Model URLs must not contain a query or fragment."
        }
        return nil
    }

    /// Runtime gate for custom ASR. WhisperKit can only consume the exact
    /// Core ML export layout used by its repository, not arbitrary HF/NVIDIA
    /// checkpoints. Keep unsupported registrations visible but configuration-only.
    public var runtimeSupportError: String? {
        guard role == .asr else { return nil }
        guard source == .huggingFace else {
            return "Custom ASR is configuration-only: this source is not a WhisperKit Core ML export."
        }
        guard let url = URL(string: repositoryURL),
              url.host?.lowercased() == "huggingface.co" || url.host?.lowercased() == "www.huggingface.co" else {
            return "Custom ASR is configuration-only: only Hugging Face WhisperKit Core ML exports are supported."
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard path == WhisperModelRepository.repositoryID.lowercased() else {
            return "Custom ASR is configuration-only: the repository must be argmaxinc/whisperkit-coreml."
        }
        guard let variant = modelName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !variant.isEmpty,
              ModelInfo.forIdentifier(variant) != nil else {
            return "Custom ASR is configuration-only: choose a known WhisperKit Core ML variant."
        }
        return nil
    }

    private func containsASRMarker(in path: String) -> Bool {
        let value = path.lowercased()
        return [
            "asr", "speech", "recogn", "transcrib", "whisper", "wav2vec",
            "parakeet", "nemotron", "moonshine", "sensevoice", "qwen3-asr",
            "omnilingual", "canary", "seamless", "zipformer", "vosk"
        ].contains { value.contains($0) }
    }

    private func isRepositoryPath(_ path: String, componentCount: Int) -> Bool {
        let components = path.split(separator: "/")
        guard components.count == componentCount, components.allSatisfy({ !$0.isEmpty }) else { return false }
        return components.first?.lowercased() != "models"
    }

    private func isNVIDIAASRRepositoryPath(_ path: String) -> Bool {
        let components = path.split(separator: "/").map { $0.lowercased() }
        guard components.count >= 2,
              ["nemo", "riva", "nvidia-riva", "nvidia-nemo"].contains(components[0]) else {
            return false
        }
        let knownModelFamilies = ["canary", "nemotron", "parakeet", "whisper", "wav2vec"]
        return knownModelFamilies.contains { components[1].hasPrefix($0) }
    }

    /// Checks the public Hugging Face model metadata for an ASR pipeline.
    /// Other sources use their provider-specific URL checks above.
    public func remoteValidationError() async -> String? {
        guard validationError == nil else { return validationError }
        guard role == .asr, source == .huggingFace else { return nil }
        guard let url = URL(string: repositoryURL) else {
            return "Use a Hugging Face model URL."
        }
        let repoPath = url.path.split(separator: "/").map(String.init).joined(separator: "/")
        guard !repoPath.isEmpty else { return "Use a Hugging Face model URL." }

        guard let metadataURL = URL(string: "https://huggingface.co/api/models/\(repoPath)") else {
            return "The model URL could not be checked."
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: metadataURL)
            guard let httpResponse = response as? HTTPURLResponse else {
                return "Could not verify the Hugging Face model right now. Try again later."
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return Self.remoteValidationMessage(forHTTPStatus: httpResponse.statusCode)
            }
            return Self.metadataIndicatesASR(data)
                ? nil
                : "Hugging Face reports that this is not a speech-recognition model."
        } catch {
            return "Could not verify the model metadata. Check your connection and try again."
        }
    }

    public static func remoteValidationMessage(forHTTPStatus statusCode: Int) -> String {
        if statusCode == 404 { return "Hugging Face repository was not found." }
        return "Could not verify the Hugging Face model right now. Try again later."
    }

    public static func metadataIndicatesASR(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let metadata = object as? [String: Any] else { return false }
        let pipelineTag = (metadata["pipeline_tag"] as? String)?.lowercased()
        if pipelineTag == "automatic-speech-recognition" { return true }
        let tags = (metadata["tags"] as? [String] ?? []).map { $0.lowercased() }
        return tags.contains {
            $0 == "automatic-speech-recognition" ||
            $0 == "audio-to-text" ||
            $0 == "speech-recognition"
        }
    }

    public static func load(from defaults: UserDefaults) -> [CustomModel] {
        guard let data = defaults.data(forKey: SharedKeys.customModels),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        let decoder = JSONDecoder()
        return array.compactMap { value in
            guard JSONSerialization.isValidJSONObject(value),
                  let item = try? JSONSerialization.data(withJSONObject: value),
                  let model = try? decoder.decode(CustomModel.self, from: item) else { return nil }
            return model
        }.deduplicatedByIdentity()
    }

    public static func save(_ models: [CustomModel], to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(models.deduplicatedByIdentity()), forKey: SharedKeys.customModels)
    }
}

private extension Array where Element == CustomModel {
    func deduplicatedByIdentity() -> [CustomModel] {
        var result: [CustomModel] = []
        for model in self {
            result.removeAll { $0.id == model.id || $0.identityKey == model.identityKey }
            result.append(model)
        }
        return result
    }
}
