// Compile the production transcription owner with synthetic speech/language/log doubles.
import Foundation

guard let scratch = ProcessInfo.processInfo.environment["CODEX_TASK_TMP"],
      let artifacts = ProcessInfo.processInfo.environment["CODEX_TASK_ARTIFACTS"] else {
    fatalError("Run through codex-task")
}
let production = try String(contentsOfFile: "DictusApp/Audio/TranscriptionService.swift", encoding: .utf8)
    .replacingOccurrences(of: "import SyllivraKernel", with: "")
let doubles = #"""
import Foundation
protocol SpeechModelProtocol: AnyObject {
    var isReady: Bool { get }
    func releaseLoadedModel()
    func releaseLoadedModelAndWait() async
    func cancelCurrentInference()
    func transcribeDetailed(audioSamples: [Float], language: String?) async throws -> SpeechTranscriptionOutput
}
struct SpeechTranscriptionOutput { var text: String; var firstRegionReadyAfterSeconds: Double? = nil }
struct LanguageMode { var telemetryDescription = "auto" }
enum Language { case en; var rawValue: String { "en" } }
enum Engine { case whisper; var rawValue: String { "whisper" } }
struct TranscriptionLanguagePolicy {
    var sttLanguageCode: String? = "en"
    var modelIdentifier = "synthetic"
    var spokenLanguages = ["en"]
    var mode = LanguageMode()
    var keyboardLanguage = Language.en
    var engine = Engine.whisper
    var sttLanguageIsEffective = true
}
enum ModelInfo { static func forIdentifier(_ identifier: String) -> Int? { 1 } }
enum SpokenLanguagePreferences {
    @TaskLocal static var recognitionLanguages: [String] = []
    static func accepts(_ model: Int, languages: [String]) -> Bool { !languages.contains("unsupported") }
    static func displayName(_ code: String) -> String { code }
}
enum LogEvent {
    case transcriptionStarted(modelName: String)
    case transcriptionCompleted(durationMs: Int, wordCount: Int)
    case transcriptionFailed(error: String)
    case transcriptionPerformance(modelName: String, audioDurationMs: Int, transcriptionDurationMs: Int, peakMemoryMB: Int)
    case diagnosticProbe(component: String, instanceID: String, action: String, details: String)
}
enum PersistentLog { static func log(_ event: LogEvent) {} }
enum PolishFailureReason { case other(Error); var slug: String { "failure" } }
enum DictationRuntimeMetrics { static func elapsedMilliseconds(since: UInt64) -> Int { 1 } }
struct DeviceCapabilities { var availableMemoryMB = 100; static func current() -> Self { Self() } }
enum ModelWarmLatencyStore { static func record(_ value: Int, for model: String, in defaults: UserDefaults) {} }
enum AppGroup { static let defaults = UserDefaults(suiteName: "saiity-synthetic-owner")! }
class QwenSpeechEngine: SpeechModelProtocol {
    var isReady = true
    var capturedLanguages: [String] = []
    var language: String?
    var calls = 0
    var released = false
    var cancelled = false
    var duringInference: (() -> Void)?
    func releaseLoadedModel() { released = true }
    func releaseLoadedModelAndWait() async { released = true }
    func cancelCurrentInference() { cancelled = true }
    func transcribeDetailed(audioSamples: [Float], language: String?) async throws -> SpeechTranscriptionOutput {
        calls += 1
        capturedLanguages = SpokenLanguagePreferences.recognitionLanguages
        self.language = language
        duringInference?()
        return SpeechTranscriptionOutput(text: "Synthetic result.")
    }
}
"""#
let checks = #"""
@main enum Checks {
    static func main() async {
        var failed: [String] = []
        let policy = TranscriptionLanguagePolicy()
        let audio: [Float] = [0, 0.2, -0.1]
        let service = TranscriptionService(), engine = QwenSpeechEngine()
        service.prepare(engine: engine)
        do {
            let result = try await service.transcribeDetailed(audioSamples: audio, languagePolicy: policy)
            if result.text != "Synthetic result." || engine.capturedLanguages != ["en"] || engine.language != "en" {
                failed.append("language snapshot or result changed")
            }
        } catch { failed.append("valid inference rejected") }
        for (label, samples, ready) in [("empty", [Float](), true), ("nonfinite", [Float.nan], true), ("unready", audio, false)] {
            let owner = TranscriptionService(), runtime = QwenSpeechEngine()
            runtime.isReady = ready
            owner.prepare(engine: runtime)
            do {
                _ = try await owner.transcribeDetailed(audioSamples: samples, languagePolicy: policy)
                failed.append("admitted \(label) audio/runtime")
            } catch {}
            if runtime.calls != 0 { failed.append("\(label) reached the runtime") }
        }
        var unsupported = policy
        unsupported.spokenLanguages = ["unsupported"]
        let calls = engine.calls
        do {
            _ = try await service.transcribeDetailed(audioSamples: audio, languagePolicy: unsupported)
            failed.append("unsupported language admitted")
        } catch {}
        if engine.calls != calls { failed.append("unsupported language reached runtime") }
        for action in ["cancel", "replace", "release"] {
            let owner = TranscriptionService(), runtime = QwenSpeechEngine()
            owner.prepare(engine: runtime)
            runtime.duringInference = {
                switch action {
                case "cancel": owner.cancelCurrentInference()
                case "replace": owner.prepare(engine: QwenSpeechEngine())
                default: owner.releaseLoadedModel()
                }
            }
            do {
                _ = try await owner.transcribeDetailed(audioSamples: audio, languagePolicy: policy)
                failed.append("late \(action) result escaped")
            } catch is CancellationError {} catch { failed.append("wrong \(action) error") }
        }
        let cancelledOwner = TranscriptionService(), cancelledRuntime = QwenSpeechEngine()
        cancelledOwner.prepare(engine: cancelledRuntime)
        let cancelledTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cancelledOwner.transcribeDetailed(audioSamples: audio, languagePolicy: policy)
        }
        do { _ = try await cancelledTask.value; failed.append("cancelled task admitted") }
        catch is CancellationError {} catch { failed.append("wrong pre-cancellation error") }
        if cancelledRuntime.calls != 0 { failed.append("cancelled task reached runtime") }
        await service.releaseLoadedModelAndWait()
        if service.hasLoadedModel || !engine.released { failed.append("awaited release retained model") }
        guard failed.isEmpty else { fatalError(failed.joined(separator: "\n")) }
        print("PASS: production transcription owner preserves language snapshots and rejects invalid admission, cancellation and stale runtime results")
    }
}
"""#
let source = URL(fileURLWithPath: scratch).appendingPathComponent("transcription-owner.swift")
let executable = URL(fileURLWithPath: artifacts).appendingPathComponent("transcription-owner")
try (doubles + "\n" + production + "\n" + checks).write(to: source, atomically: true, encoding: .utf8)
func run(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: arguments[0])
    process.arguments = Array(arguments.dropFirst())
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Transcription owner probe failed") }
}
try run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", "-module-cache-path", scratch + "/owner-module-cache", source.path, "-o", executable.path])
try run([executable.path])
