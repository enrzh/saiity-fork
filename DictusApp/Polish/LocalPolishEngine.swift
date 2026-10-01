import Foundation
import Combine
import UIKit
import DictusCore
import MLX
import MLXLLM
import MLXLMCommon

/// Weights run only in the app. The keyboard never loads an LLM or its Metal buffers.
actor LocalPolishEngine: PolishEngineProtocol {
    nonisolated let model: LocalCleanupModel
    nonisolated var identifier: String { "local:\(model.rawValue)" }
    private var container: ModelContainer?
    private var loading: Task<ModelContainer, Error>?

    init(model: LocalCleanupModel) { self.model = model }

    static func downloadConfiguration(for model: LocalCleanupModel) -> ModelRepoDownloader.Configuration {
        .init(repoPath: model.repository, directoryPatterns: [], includesRootMetadata: true,
              requiredPaths: ["config.json", "tokenizer.json", "tokenizer_config.json"], includesRootWeights: true)
    }

    private var configuration: ModelConfiguration {
        switch model {
        case .gemma3_1b: return LLMRegistry.gemma3_1B_qat_4bit
        case .qwen2_5_0_5b: return ModelConfiguration(id: model.repository)
        case .qwen2_5_1_5b: return LLMRegistry.qwen2_5_1_5b
        }
    }

    func prepare(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if container != nil { return }
        if let loading { container = try await loading.value; return }
        #if targetEnvironment(simulator)
        throw NSError(domain: "LocalCleanup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local cleanup models require a physical iPhone."])
        #else
        try await requireForeground()
        // MLX's desktop-sized buffer pool can retain the previous model's
        // allocations during a switch. Keep the iPhone cache bounded.
        Memory.cacheLimit = 16 * 1024 * 1024
        Memory.clearCache()
        let task = Task {
            let directory = configuration.modelDirectory(hub: defaultHubApi)
            let download = ModelRepoDownloader(configuration: Self.downloadConfiguration(for: model))
            try await download.download(to: directory, modelName: model.displayName) { progress($0.fraction) }
            try Task.checkCancellation()
            try await requireForeground()
            let loaded = try await LLMModelFactory.shared.loadContainer(configuration: ModelConfiguration(
                directory: directory, extraEOSTokens: configuration.extraEOSTokens))
            try Task.checkCancellation()
            return loaded
        }
        loading = task
        let observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { _ in task.cancel() }
        defer { loading = nil; NotificationCenter.default.removeObserver(observer) }
        container = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        #endif
    }

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode) async throws -> String {
        try await polish(raw: raw, targetLanguage: targetLanguage, mode: mode, style: .balanced)
    }

    func polish(raw: String, targetLanguage: SupportedLanguage, mode: PolishMode, style: WritingStyle) async throws -> String {
        try Task.checkCancellation()
        try await requireForeground()
        try await prepare()
        guard let container else { throw CancellationError() }
        defer { Memory.clearCache() }
        let prompt = DictationCleanupPrompt.instructions(style: style)
            + "\n\n<DICTATION_TRANSCRIPT>\n" + raw + "\n</DICTATION_TRANSCRIPT>"
        let evaluation = Task {
            try await requireForeground()
            return try await container.perform { context in
                let chat: [Chat.Message] = self.model == .gemma3_1b ? [.user(prompt)]
                    : [.system(DictationCleanupPrompt.instructions(style: style)), .user(raw)]
                let input = try await context.processor.prepare(input: UserInput(chat: chat))
                let stream = try generate(input: input,
                    parameters: GenerateParameters(maxTokens: min(2048, max(128, raw.count)), temperature: 0), context: context)
                var output = ""
                for try await item in stream {
                    try Task.checkCancellation()
                    if case .chunk(let text) = item { output += text }
                }
                try Task.checkCancellation()
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let observer = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main) { _ in evaluation.cancel() }
        defer { NotificationCenter.default.removeObserver(observer) }
        return try await withTaskCancellationHandler { try await evaluation.value } onCancel: { evaluation.cancel() }
    }

    nonisolated func contextFit(input: String, targetLanguage: SupportedLanguage, mode: PolishMode) -> PolishContextFit {
        PolishContextBudget.appleFoundationModels.fit(instructions: DictationCleanupPrompt.instructions(), input: input)
    }

    private func requireForeground() async throws {
        guard await MainActor.run(body: { UIApplication.shared.applicationState == .active }) else {
            throw NSError(domain: "LocalCleanup", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Keep sAiity open for local processing. Apple Foundation Models supports keyboard dictation in the background."])
        }
    }
}

#if DEBUG
enum CleanupModelProbe {
    /// Opt-in device check using public fixture text only. No user preferences
    /// or transcripts are read or changed, and no microphone is started.
    @MainActor static func startIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--cleanup-model-probe") else { return }
        precondition(ModelRepoDownloader.shouldInclude(filePath: "model.safetensors", patterns: [],
            includesRootMetadata: true, includesRootWeights: true))
        for path in ["../model.safetensors", "/model.safetensors", "weights/../../model.safetensors"] {
            precondition(!ModelRepoDownloader.shouldInclude(filePath: path, patterns: [],
                includesRootMetadata: true, includesRootWeights: true))
        }
        let arguments = ProcessInfo.processInfo.arguments
        let requested = arguments.firstIndex(of: "--cleanup-probe-model").flatMap { index in
            arguments.indices.contains(index + 1) ? LocalCleanupModel(rawValue: arguments[index + 1]) : nil
        }
        Task {
            if UIApplication.shared.applicationState != .active {
                for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) { break }
            }
            do {
                for model in requested.map({ [$0] }) ?? [.gemma3_1b] {
                    let engine = LocalPolishEngine(model: model)
                    let start = Date()
                    try await engine.prepare { value in
                        print("CLEANUP_PROBE model=\(model.rawValue) download=\(Int(value * 100))")
                    }
                    print("CLEANUP_PROBE model=\(model.rawValue) preparedSeconds=\(Date().timeIntervalSince(start)) memoryMB=\(Memory.activeMemory / 1_000_000)")
                    for raw in ["uh i i will send the invoice tomorrow", "Ich schicke dir the invoice tomorrow und 我晚上再确认。"] {
                        let began = Date()
                        let result = await PolishPipeline.transform(preprocessed: raw, engine: engine, target: .english, mode: .auto)
                        print("CLEANUP_PROBE model=\(model.rawValue) outcome=\(result.outcome.rawValue) seconds=\(Date().timeIntervalSince(began)) output=\(result.engineOutput ?? "nil")")
                    }
                }
                print("CLEANUP_PROBE finished")
            } catch { print("CLEANUP_PROBE failed=\(error.localizedDescription)") }
        }
    }
}
#endif

@MainActor final class CleanupModelManager: ObservableObject {
    static let shared = CleanupModelManager()
    @Published var preparing: LocalCleanupModel?
    @Published var progress: Double = 0
    @Published var error: String?
    @Published private(set) var failedModel: LocalCleanupModel?
    @Published private(set) var installedBytes: [LocalCleanupModel: Int64] = [:]
    private var engine: LocalPolishEngine?
    private var activeModel: LocalCleanupModel?
    private var preparationTask: Task<Void, Never>?

    private func directory(for model: LocalCleanupModel) -> URL {
        ModelConfiguration(id: model.repository).modelDirectory(hub: defaultHubApi)
    }

    func refreshArtifacts() {
        var sizes: [LocalCleanupModel: Int64] = [:]
        for model in LocalCleanupModel.allCases {
            let folder = directory(for: model)
            sizes[model] = ModelRepoDownloader.completedDownloadSize(in: folder, configuration: LocalPolishEngine.downloadConfiguration(for: model))
        }
        installedBytes = sizes
    }

    func delete(_ model: LocalCleanupModel, manager: ModelManager) throws {
        guard preparing == nil, manager.cleanupBackend != .local(model) else { return }
        try FileManager.default.removeItem(at: directory(for: model))
        if activeModel == model { engine = nil; activeModel = nil }
        refreshArtifacts()
    }

    func engine(for model: LocalCleanupModel) -> LocalPolishEngine {
        if let engine, activeModel == model { return engine }
        let next = LocalPolishEngine(model: model)
        engine = next
        activeModel = model
        return next
    }

    func select(_ model: LocalCleanupModel, manager: ModelManager) {
        guard preparing == nil else { return }
        preparing = model
        progress = 0
        error = nil
        failedModel = nil
        let engine = engine(for: model)
        preparationTask = Task {
            defer { preparing = nil; preparationTask = nil; refreshArtifacts() }
            do {
                try await engine.prepare { value in
                    Task { @MainActor in self.progress = value }
                }
                try Task.checkCancellation()
                manager.selectCleanupBackend(.local(model))
            } catch {
                if !Task.isCancelled { self.failedModel = model; self.error = error.localizedDescription }
            }
        }
    }

    func cancel() {
        preparationTask?.cancel()
        if let engine { Task { await engine.cancelPreparation() } }
    }
}

extension LocalPolishEngine {
    func cancelPreparation() { loading?.cancel() }
}
