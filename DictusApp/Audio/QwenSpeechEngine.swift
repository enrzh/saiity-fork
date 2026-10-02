import Foundation
import UIKit
import MLX
import Qwen3ASR
import SpeechVAD
import DictusCore

/// Same Qwen3-ASR MLX checkpoints and pause-final behavior as the macOS app.
/// GPU weights stay in the app, never in the keyboard extension.
@available(iOS 18.0, *)
final class QwenSpeechEngine: SpeechModelProtocol {
    let engineName = "Qwen3-ASR"
    private let worker = QwenInference()
    private let stateLock = NSLock()
    private var ready = false
    private var cancellation = InferenceCancellation()
    private var foregroundObserver: NSObjectProtocol?
    var isReady: Bool { stateLock.withLock { ready } }
    init() {
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.cancelCurrentInference() }
    }
    deinit { if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) } }
    func cancelCurrentInference() { stateLock.withLock { cancellation.cancel() } }
    private func newWork() -> InferenceCancellation {
        stateLock.withLock { cancellation.cancel(); cancellation = InferenceCancellation(); return cancellation }
    }
    private var currentWork: InferenceCancellation { stateLock.withLock { cancellation } }

    static func configuration(for model: QwenASRModel) -> ModelRepoDownloader.Configuration {
        .init(repoPath: model.repository, directoryPatterns: [], includesRootMetadata: true,
              requiredPaths: ["config.json", "vocab.json", "merges.txt", "tokenizer_config.json"],
              includesRootWeights: true)
    }
    static var vadConfiguration: ModelRepoDownloader.Configuration {
        .init(repoPath: SileroVADModel.defaultModelId, directoryPatterns: [], includesRootMetadata: true,
              requiredPaths: ["config.json"], includesRootWeights: true)
    }
    static func isInstalled(_ model: QwenASRModel) -> Bool {
        guard let directory = model.directory else { return false }
        return ModelRepoDownloader.completedDownloadSize(in: directory, configuration: configuration(for: model)) != nil
            && ModelRepoDownloader.completedDownloadSize(in: directory.appendingPathComponent("vad"),
                                                         configuration: vadConfiguration) != nil
    }

    func prepare(modelIdentifier: String) async throws {
        guard let choice = QwenASRModel(rawValue: modelIdentifier), Self.isInstalled(choice),
              let directory = choice.directory else {
            throw SpeechModelError.modelNotInstalled(identifier: modelIdentifier)
        }
        let control = newWork()
        try await withTaskCancellationHandler {
            try await worker.prepare(choice: choice, directory: directory, control: control)
            try control.check()
        } onCancel: { control.cancel() }
        stateLock.withLock { ready = true }
    }
    func releaseLoadedModel() {
        stateLock.withLock { ready = false; cancellation.cancel() }
        Task { await worker.release() }
    }
    func releaseLoadedModelAndWait() async {
        stateLock.withLock { ready = false; cancellation.cancel() }
        await worker.release()
    }
    func transcribe(audioSamples: [Float], language: String?) async throws -> String {
        try await transcribeDetailed(audioSamples: audioSamples, language: language).text
    }
    func transcribeDetailed(audioSamples: [Float], language: String?) async throws -> SpeechTranscriptionOutput {
        try Task.checkCancellation()
        let control = newWork()
        let output = try await withTaskCancellationHandler {
            try await worker.finish(samples: audioSamples, language: language, session: nil, control: control)
        } onCancel: { control.cancel() }
        try Task.checkCancellation()
        return output
    }
    func beginRealtime(session: UInt64) async throws {
        let control = newWork()
        try await worker.begin(session: session, control: control)
    }
    func appendRealtime(_ samples: [Float], session: UInt64, language: String?) async throws -> String? {
        try Task.checkCancellation()
        let control = currentWork
        return try await withTaskCancellationHandler {
            try await worker.append(samples, session: session, language: language, control: control)
        } onCancel: { control.cancel() }
    }
    func finishRealtime(samples: [Float], session: UInt64, language: String?) async throws -> SpeechTranscriptionOutput {
        try Task.checkCancellation()
        let control = currentWork
        let output = try await withTaskCancellationHandler {
            try await worker.finish(samples: samples, language: language, session: session, control: control)
        } onCancel: { control.cancel() }
        try Task.checkCancellation()
        return output
    }
}

@available(iOS 18.0, *)
private actor QwenInference {
    private var model: Qwen3ASRModel?
    private var vadModel: SileroVADModel?
    private var vad: StreamingVADProcessor?
    private var buffer = StreamingSpeechBuffer()
    private var regions: [SpeechRegionTranscript] = []
    private var sampleCount = 0
    private var session: UInt64?
    private var transcript = ""

    func prepare(choice: QwenASRModel, directory: URL, control: InferenceCancellation) async throws {
        #if targetEnvironment(simulator)
        throw NSError(domain: "QwenASR", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Qwen dictation requires a physical iPhone."])
        #else
        try await requireForeground()
        Memory.cacheLimit = 16 * 1024 * 1024
        Memory.clearCache()
        let loaded = try await Qwen3ASRModel.fromPretrained(modelId: choice.repository,
            cacheDir: directory, offlineMode: true)
        try control.check()
        try await requireForeground()
        let detector = try await SileroVADModel.fromPretrained(cacheDir: directory.appendingPathComponent("vad"),
                                                        offlineMode: true)
        try control.check()
        try await requireForeground()
        model = loaded; vadModel = detector
        // A checkpoint loader may apply a desktop cache budget; keep the phone bound.
        Memory.cacheLimit = 16 * 1024 * 1024
        #endif
    }
    func release() {
        model?.unload()
        model = nil; vadModel = nil; vad = nil
        buffer = StreamingSpeechBuffer(); regions = []; sampleCount = 0; session = nil; transcript = ""
        Memory.clearCache()
    }
    func begin(session: UInt64, control: InferenceCancellation) async throws {
        try await requireForeground()
        try control.check()
        guard model != nil, let vadModel else { throw SpeechModelError.modelNotInstalled(identifier: "Qwen3-ASR") }
        self.session = session
        buffer = StreamingSpeechBuffer(); regions = []; sampleCount = 0; transcript = ""
        vad = StreamingVADProcessor(model: vadModel)
    }
    func append(_ samples: [Float], session: UInt64, language: String?, control: InferenceCancellation) async throws -> String? {
        try await requireForeground()
        guard self.session == session else { throw CancellationError() }
        let previousCount = regions.count
        try decode(samples, language: language, flush: false, control: control)
        return regions.count == previousCount ? nil : transcript
    }
    func finish(samples: [Float], language: String?, session: UInt64?, control: InferenceCancellation) async throws -> SpeechTranscriptionOutput {
        try await requireForeground()
        if let session {
            guard self.session == session, sampleCount <= samples.count else { throw CancellationError() }
        } else {
            try await begin(session: 0, control: control)
        }
        for start in stride(from: sampleCount, to: samples.count, by: 8_000) {
            try decode(Array(samples[start..<min(start + 8_000, samples.count)]), language: language,
                       flush: false, control: control)
        }
        try decode([], language: language, flush: true, control: control)
        self.session = nil
        Memory.clearCache()
        return SpeechTranscriptionOutput(text: transcript, regions: regions)
    }
    private func decode(_ samples: [Float], language: String?, flush: Bool, control: InferenceCancellation) throws {
        try control.check()
        guard let model, let vad else { throw CancellationError() }
        sampleCount += samples.count
        var events = vad.process(samples: samples)
        if flush { events += vad.flush() }
        let boundaries = events.map { event -> StreamingSpeechBuffer.Event in
            switch event {
            case .speechStarted(let time): return .started(Int((Double(time) * 16_000).rounded()))
            case .speechEnded(let segment): return .ended(Int((Double(segment.endTime) * 16_000).rounded()))
            }
        }
        for slice in buffer.append(samples, events: boundaries, flush: flush) {
            try control.check()
            let started = DispatchTime.now().uptimeNanoseconds
            var options = Qwen3DecodingOptions(maxTokens: 448, language: language,
                                               context: DictationVocabulary.recognitionPrompt)
            options.shouldCancel = { control.isCancelled || Task.isCancelled }
            let text = try model.transcribeCancellable(audio: slice.samples, sampleRate: 16_000, options: options)
            try control.check()
            guard !text.hasPrefix("[Audio encoded:") else {
                throw NSError(domain: "QwenASR", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "The Qwen model could not decode speech. Repair its download in Models."])
            }
            regions.append(SpeechRegionTranscript(region: slice.region, text: text, detectedLanguage: nil,
                decodeDurationSeconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000))
            transcript = SpeechTranscriptMerger.merge([transcript, text])
        }
    }
    private func requireForeground() async throws {
        try Task.checkCancellation()
        guard await MainActor.run(body: { UIApplication.shared.applicationState == .active }) else {
            throw NSError(domain: "QwenASR", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Keep sAiity open for Qwen dictation. Choose Whisper Auto to dictate from another app."])
        }
    }
}
