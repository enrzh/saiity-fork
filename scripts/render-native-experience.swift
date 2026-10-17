// Run from the repo: swift scripts/render-native-experience.swift <QA simulator> <derived-data> <output-directory> [--compile-only]
// Hosts the production SwiftUI bodies with inert data dependencies. Never captures audio or loads models.
import Foundation

guard CommandLine.arguments.count >= 4 else { fatalError("Pass simulator ID, derived-data path and output directory") }
let simulator = CommandLine.arguments[1], derived = CommandLine.arguments[2], output = CommandLine.arguments[3]
let advisorOnly = CommandLine.arguments.contains("--advisor")
let optionsOnly = CommandLine.arguments.contains("--voice-options")
let modelsOnly = CommandLine.arguments.contains("--model-cards")
let privacyOnly = CommandLine.arguments.contains("--privacy-only")
let landscapeOnly = CommandLine.arguments.contains("--landscape")
let vocabularyOnly = CommandLine.arguments.contains("--vocabulary")
let products = derived + "/Build/Products/Debug-iphonesimulator"
let extensionPath = products + "/DictusApp.app/PlugIns/DictusKeyboard.appex"
func read(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }
func section(_ source: String, from start: String, to end: String) -> String {
    guard let lower = source.range(of: start), let upper = source.range(of: end, range: lower.upperBound..<source.endIndex) else { fatalError("Missing source section: \(start)") }
    return String(source[lower.lowerBound..<upper.lowerBound])
}
let homeSource = try read("DictusApp/Views/HomeView.swift")
var home = section(homeSource, from: "struct HomeView: View", to: "#Preview")
let readiness = section(home, from: "    private var currentReadiness:", to: "    private var readinessSubtitle:")
home = home.replacingOccurrences(of: readiness, with: "    private var currentReadiness: DictationReadiness { fixtureReadiness }\n")
home = home.replacingOccurrences(of: "RecentDictations.load(from: AppGroup.defaults)", with: "fixtureHistory")
home = home.replacingOccurrences(of: "store: AppGroup.defaults", with: "store: fixtureDefaults")
home = home.replacingOccurrences(of: "SpokenLanguagePreferences.load(from: AppGroup.defaults)", with: "SpokenLanguagePreferences.load(from: fixtureDefaults)")
let result = section(homeSource, from: "struct DictationTranscriptResult: View", to: "private struct DictationHistoryEditView:")
let header = section(homeSource, from: "struct SaiityPageHeader: View", to: "struct DictationHistoryView:")
let history = section(homeSource, from: "struct DictationHistoryView: View", to: "/// Shared comparison/copy/recovery")
    .replacingOccurrences(of: "AppGroup.defaults", with: "fixtureDefaults")
guard let historyEditorStart = homeSource.range(of: "private struct DictationHistoryEditView:") else { fatalError("Missing history editor") }
let historyEditor = String(homeSource[historyEditorStart.lowerBound...])
    .replacingOccurrences(of: "AppGroup.defaults", with: "fixtureDefaults")
var recording = section(try read("DictusApp/Views/RecordingView.swift"), from: "enum RecordingMode", to: "#Preview")
recording = recording.replacingOccurrences(of: "@State private var transcriptionResult: String?", with: "@State private var transcriptionResult: String? = fixturePhase == .ready ? fixtureText : nil")
recording = recording.replacingOccurrences(of: "@State private var showResult = false", with: "@State private var showResult = fixturePhase == .ready")
let welcome = section(try read("DictusApp/Onboarding/WelcomePage.swift"), from: "struct WelcomePage: View", to: "\n}") + "\n}"
let activitySource = try read("DictusWidgets/DictusLiveActivity.swift")
guard let activityStart = activitySource.range(of: "/// One state vocabulary") else { fatalError("Missing activity presentation") }
let activity = String(activitySource[activityStart.lowerBound...])
let advisor = section(try read("DictusApp/Views/KeyboardModePicker.swift"), from: "struct DictationSettingsAdvisor: View", to: "struct DictationModelQuickPicker: View")
    .replacingOccurrences(of: "@State private var showsAdvice = false", with: "@State private var showsAdvice = fixtureAdvisorExpanded")
let voiceOptions = section(homeSource, from: "struct VoiceOptionsView: View", to: "/// Shared typographic hierarchy")
    .replacingOccurrences(of: "DisclosureGroup(\"Choose a keyboard model\") {", with: "DisclosureGroup(\"Choose a keyboard model\", isExpanded: .constant(fixtureOptionsExpanded)) {")
let voicePickers = section(try read("DictusApp/Views/KeyboardModePicker.swift"), from: "struct DictationModelQuickPicker: View", to: "struct CleanupModelPicker: View")
    .replacingOccurrences(of: "DisclosureGroup(\"Choose a voice model\") {", with: "DisclosureGroup(\"Choose a voice model\", isExpanded: .constant(fixtureOptionsExpanded)) {")
let modelState = section(try read("DictusApp/Models/ModelManager.swift"), from: "enum ModelState", to: "/// Byte counters")
let modelLocalization = try read("DictusApp/Extensions/ModelInfo+Localized.swift")
let modelCardSource = try read("DictusApp/Views/ModelCardView.swift")
let modelCards = String(modelCardSource[modelCardSource.range(of: "struct ModelCardView: View")!.lowerBound...])
let modelsPage = section(try read("DictusApp/Views/ModelManagerView.swift"), from: "struct ModelManagerView: View", to: "#Preview")
    .replacingOccurrences(of: "AppGroup.defaults", with: "fixtureDefaults")
    .replacingOccurrences(of: "@State private var searchText = \"\"", with: "@State private var searchText = fixtureModelSearch")
    .replacingOccurrences(of: "@State private var showsProcessingModels = false", with: "@State private var showsProcessingModels = fixtureProcessingModels")
var polishAvailability = try read("DictusApp/Polish/PolishAvailability.swift")
let availabilityState = section(polishAvailability, from: "    public static var state:", to: "    /// True only")
polishAvailability = polishAvailability.replacingOccurrences(of: availabilityState,
    with: "    public static var state: PolishAvailabilityState { .deviceNotEligible }\n\n")
let settingsSource = try read("DictusApp/Views/SettingsView.swift")
let settingsBody = section(settingsSource, from: "    var body: some View {", to: "        .onAppear {")
// Render only the production root and labels; settings lifecycle and destinations stay inert.
let settingsRoot = """
struct FixtureSettings: View {
    @Environment(\\.dynamicTypeSize) private var textSize
    @AppStorage(SharedKeys.historyEnabled, store: fixtureDefaults) private var historyEnabled = true
    let modelManager: ModelManager
\(settingsBody)
    }
    private var dictationSettings: some View { EmptyView() }
    private var keyboardSettings: some View { EmptyView() }
    private var wordsSettings: some View { EmptyView() }
    private var helpSettings: some View { EmptyView() }
    private var aboutSettings: some View { EmptyView() }
    private var activeOutputMode: TranscriptionOutputMode { .multilingual }
    private var appVersionText: String { "1.0.0 (243)" }
}
"""
var vocabulary = section(settingsSource, from: "struct VocabularyView: View", to: "struct TextSnippetsView: View")
let vocabularyReload = section(vocabulary, from: "    private func reload()", to: "    private func addWord()")
vocabulary = vocabulary.replacingOccurrences(of: vocabularyReload, with: "    private func reload() { words = [\"Zoë\", \"東京\"]; hints = [\"Zoë\"] }\n")
    .replacingOccurrences(of: "AppGroup.defaults", with: "fixtureDefaults")

let program = #"""
import SwiftUI
import UIKit
import AVFoundation
import SyllivraKernel

let fixtureText = "I’ll send the updated proposal tomorrow morning. 我們下午再確認一次。"
let fixtureOriginal = "um I’ll send the updated proposal tomorrow morning 我們下午再確認一次"
let fixtureSuite = "saiity-design-fixture-" + UUID().uuidString
let fixtureDefaults: UserDefaults = {
    guard let defaults = UserDefaults(suiteName: fixtureSuite) else { fatalError("No fixture defaults") }
    return defaults
}()
var fixturePhase = DictationStatus.idle
var fixtureAdvisorExpanded = false
var fixtureOptionsExpanded = false
var fixtureModelSearch = ""
var fixtureProcessingModels = false
var fixtureReadiness = DictationReadiness(serviceEnabled: true, microphonePermission: .authorized,
    modelReady: true, modelLoadState: .ready, status: .idle)
let fixtureSavedHistory = [
    RecentDictation(text: fixtureText, createdAt: Date().timeIntervalSince1970 - 480, originalText: fixtureOriginal),
    RecentDictation(text: "Please move our meeting to Friday afternoon.", createdAt: Date().timeIntervalSince1970 - 3600),
    RecentDictation(text: "Bitte schick mir die Notizen morgen.", createdAt: Date().timeIntervalSince1970 - 86400)
]
var fixtureHistory = fixtureSavedHistory

final class ProStatusManager: ObservableObject {}
final class ModelManager: ObservableObject {
    @Published var recognizer = DictationRecognizer.whisper
    @Published var selectionMode = ModelSelectionMode.manual
    @Published var selectionProfile = ModelSelectionProfile.balanced
    var downloadedModels: [String] = []
    var activeModel: String? = "openai_whisper-small"
    var keyboardModel: String? = "openai_whisper-small"
    var initialVoiceModel: String? = "openai_whisper-small"
    var isModelReady: Bool { downloadedModels.contains(activeModel ?? "") }
    var downloadProgress: [String: Float] = [:]
    var modelStates: [String: ModelState] = [:]
    var modelLoadState = ModelLoadState.idle
    var downloadByteInfo: [String: ModelDownloadBytes] = [:]
    var cleanupBackend = PolishCleanupBackend.appleIntelligence
    var customModels: [CustomModel] = []
    var preferredModelIdentifier = "openai_whisper-small"
    func isRecommended(_ id: String) -> Bool { id == "openai_whisper-small" }
    func selectModel(_ id: String) { activeModel = id }
    func useRecommendedSettings() { selectionMode = .automatic; selectionProfile = .recommended }
    func chooseDictationModel(_ model: String) { activeModel = model }
    func chooseKeyboardModel(_ model: String) { keyboardModel = model }
    func selectRecognizer(_ choice: DictationRecognizer) { recognizer = choice }
    func setSpokenLanguages(_ codes: [String]) {}
    func startCatalogDownload(_ model: String, onError: @escaping (String) -> Void) {}
    func cancelCatalogDownload(_ model: String) {}
    func loadState() {}
    func selectCleanupBackend(_ backend: PolishCleanupBackend) { cleanupBackend = backend }
    func deleteCustomModel(_ model: CustomModel) {}
    func deleteModel(_ identifier: String) throws {}
    func cleanupFailedModel(_ identifier: String) {}
}
struct ModelDownloadBytes { let downloadedMB: Int; let totalMB: Int }
final class CleanupModelManager: ObservableObject {
    static let shared = CleanupModelManager()
    var preparing: LocalCleanupModel?
    var failedModel: LocalCleanupModel?
    var installedBytes: [LocalCleanupModel: Int64] = [:]
    var progress: Double = 0.42
    var error: String?
    func cancel() {}
    func select(_ model: LocalCleanupModel, manager: ModelManager) {}
    func refreshArtifacts() {}
    func delete(_ model: LocalCleanupModel, manager: ModelManager) throws {}
}
struct ModelLanguageDetailView: View {
    let model: ModelInfo
    var body: some View { Text(model.languageSupport.coverage.localizedSummary) }
}
struct Device {
    static let current = Device()
    var realDevice: Self { self }
    var description: String { "This iPhone" }
}
final class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()
    @Published var status = DictationStatus.idle
    var realtimeTranscript = fixtureText
    var lastOriginalResult: String? = fixtureOriginal
    var lastResult: String? = fixtureText
    var lastTranslationFallbackReason: String?
    var keyboardSessionEnabled = false
    var isPreparingKeyboardSession = false
    var dictationGeneration = 1
    var bufferSeconds: Double = 8
    var bufferEnergy: [Float] = [0.1, 0.3, 0.4]
    var canChangeSpeechRuntime = true
    func startDictation() {}
    func stopDictation() {}
    func cancelDictation() {}
    func resetStatus() {}
    func preloadActiveModel() {}
    func setKeyboardDictationEnabled(_ enabled: Bool) {}
}
struct DictationErrorChannel { static var current: String? = "The voice model was unavailable. Your original words are still available." }
struct ProBannerView: View { var body: some View { EmptyView() } }
struct RecordingModelRecoveryView: View { var body: some View { EmptyView() } }
final class RecordingReplay: ObservableObject {
    static let shared = RecordingReplay()
    var available = false, playing = false, trimmed = false
    var message: String?
    func toggle() {}
    func stop() {}
    func refreshAvailability() {}
}
struct StopStandbyIntent: AppIntent {
    static var title: LocalizedStringResource = "Prototype power"
    var toggleDetection: Bool
    init() { toggleDetection = false }
    init(toggleDetection: Bool) { self.toggleDetection = toggleDetection }
    func perform() async throws -> some IntentResult { .result() }
}

// PRODUCTION_VIEWS

@main @MainActor struct RenderNativeExperience {
    static func main() throws {
        if PRIVACY_ONLY {
            let legacy = Data(#"{"phase":"ready","transcriptionPreview":"Fixture private words","detectionMuted":true,"serviceEnabled":false}"#.utf8)
            let state = try JSONDecoder().decode(DictusLiveActivityAttributes.ContentState.self, from: legacy)
            precondition(state.phase == .ready && state.detectionMuted && !state.serviceEnabled,
                         "Legacy activity status and power must survive")
            let encoded = try JSONEncoder().encode(state)
            let payload = String(decoding: encoded, as: UTF8.self)
            precondition(!payload.contains("transcriptionPreview") && !payload.contains("Fixture private words"),
                         "Live Activity payload exposes transcript content")
            print("PASS: legacy activity status/power survive without transcript payload")
            return
        }
        fixtureDefaults.set(false, forKey: SharedKeys.serviceEnabled)
        fixtureDefaults.set(["de", "zh", "en"], forKey: SharedKeys.spokenLanguages)
        for item in fixtureSavedHistory.reversed() {
            RecentDictations.append(item.text, in: fixtureDefaults,
                                    at: Date(timeIntervalSince1970: item.createdAt), originalText: item.originalText)
        }
        defer { fixtureDefaults.removePersistentDomain(forName: fixtureSuite) }
        try FileManager.default.createDirectory(atPath: "OUTPUT", withIntermediateDirectories: true)
        let coordinator = DictationCoordinator.shared
        let manager = ModelManager()
        for dark in [false, true] {
            for large in [false, true] {
                let width: CGFloat = LANDSCAPE_ONLY ? 874 : large ? 320 : 402
                let category: DynamicTypeSize = large ? .accessibility5 : .large
                let names = VOCABULARY_ONLY ? ["vocabulary"]
                    : MODELS_ONLY ? ["models-page", "models-processing", "models-empty", "models-filter-empty", "models-processing-empty", "model-downloading", "model-qwen", "model-error", "model-installed", "model-active", "model-keyboard", "model-preparing", "cleanup-installed", "cleanup-downloading", "cleanup-error"]
                    : OPTIONS_ONLY ? ["voice-options", "voice-details", "voice-streaming", "voice-downloading"]
                    : ADVISOR_ONLY ? ["advisor", "advisor-details", "advisor-streaming", "advisor-installed"]
                    : ["speak", "speak-empty", "settings", "history", "history-detail", "listening", "transcribing", "processing", "result", "failed", "welcome", "activity-recording", "activity-off", "activity-processing", "activity-ready", "activity-failed"]
                for name in names {
                    fixtureHistory = name == "speak-empty" ? [] : fixtureSavedHistory
                    fixturePhase = name == "result" ? .ready : name == "failed" ? .failed
                        : name == "transcribing" ? .transcribing : name == "processing" ? .processing : .recording
                    coordinator.status = fixturePhase
                    let content: AnyView
                    switch name {
                    case "history":
                        content = AnyView(NavigationStack { DictationHistoryView() })
                    case "history-detail":
                        content = AnyView(NavigationStack { DictationHistoryEditView(item: fixtureSavedHistory[0]) { _ in } })
                    case "vocabulary":
                        content = AnyView(NavigationStack { VocabularyView() })
                    case let pageName where pageName.hasPrefix("models-"):
                        fixtureModelSearch = pageName.hasSuffix("-empty") && pageName != "models-empty" ? "no matching model" : ""
                        fixtureProcessingModels = pageName.hasPrefix("models-processing")
                        manager.activeModel = pageName == "models-empty" ? nil : "openai_whisper-tiny"
                        manager.keyboardModel = pageName == "models-empty" ? nil : "openai_whisper-small"
                        manager.downloadedModels = pageName == "models-empty" ? [] : ["openai_whisper-tiny", "openai_whisper-small"]
                        manager.modelStates = Dictionary(uniqueKeysWithValues: manager.downloadedModels.map { ($0, ModelState.ready) })
                        manager.modelLoadState = .ready
                        CleanupModelManager.shared.installedBytes = [:]
                        CleanupModelManager.shared.preparing = nil
                        content = AnyView(NavigationStack { ModelManagerView(modelManager: manager) })
                    case let cleanupName where cleanupName.hasPrefix("cleanup-"):
                        guard let model = LocalCleanupModel.allCases.first else { fatalError("No cleanup model") }
                        CleanupModelManager.shared.installedBytes = cleanupName == "cleanup-installed" ? [model: 600_000_000] : [:]
                        CleanupModelManager.shared.preparing = cleanupName == "cleanup-downloading" ? model : nil
                        CleanupModelManager.shared.error = cleanupName == "cleanup-error" ? "Download interrupted. Retry when connected." : nil
                        CleanupModelManager.shared.failedModel = cleanupName == "cleanup-error" ? model : nil
                        content = large ? AnyView(CleanupModelCardView(model: model, manager: manager).padding(32))
                            : AnyView(NavigationStack { List { CleanupModelCardView(model: model, manager: manager) }.navigationTitle("Models") })
                    case let modelName where modelName.hasPrefix("model-"):
                        let identifier = modelName == "model-qwen" ? QwenASRModel.small.rawValue : "openai_whisper-small"
                        guard let model = ModelInfo.forIdentifier(identifier) else { fatalError("Missing model fixture") }
                        manager.activeModel = modelName == "model-active" ? identifier : "openai_whisper-tiny"
                        manager.keyboardModel = modelName == "model-keyboard" || modelName == "model-active" ? identifier : "openai_whisper-tiny"
                        manager.downloadedModels = ["openai_whisper-tiny", "openai_whisper-small"]
                        manager.modelStates = [identifier: modelName == "model-downloading" ? .downloading
                            : modelName == "model-error" ? .error("Download interrupted")
                            : modelName == "model-preparing" ? .prewarming
                            : ["model-installed", "model-active", "model-keyboard"].contains(modelName) ? .ready : .notDownloaded]
                        manager.downloadProgress = [identifier: 0.42]
                        manager.downloadByteInfo = [identifier: ModelDownloadBytes(downloadedMB: 203, totalMB: 483)]
                        content = large ? AnyView(ModelCardView(model: model, modelManager: manager, onDownloadError: { _ in }).padding(32))
                            : AnyView(NavigationStack {
                            List { ModelCardView(model: model, modelManager: manager, onDownloadError: { _ in }) }
                                .navigationTitle("Models")
                        })
                    case let optionsName where optionsName.hasPrefix("voice-"):
                        fixtureOptionsExpanded = optionsName == "voice-details"
                        fixtureAdvisorExpanded = false
                        manager.recognizer = optionsName == "voice-streaming" ? .streaming : .whisper
                        manager.activeModel = optionsName == "voice-streaming" ? QwenASRModel.small.rawValue : "openai_whisper-small"
                        manager.downloadedModels = optionsName == "voice-downloading" ? [] : ["openai_whisper-small"]
                        manager.downloadProgress = optionsName == "voice-downloading" ? ["openai_whisper-small": 0.42] : [:]
                        coordinator.status = .idle
                        content = AnyView(NavigationStack { VoiceOptionsView(modelManager: manager) })
                    case let advisorName where advisorName.hasPrefix("advisor"):
                        fixtureAdvisorExpanded = advisorName != "advisor"
                        manager.recognizer = advisorName == "advisor-streaming" ? .streaming : .whisper
                        manager.downloadedModels = advisorName == "advisor-installed" ? ["openai_whisper-small"] : []
                        coordinator.status = .idle
                        content = AnyView(NavigationStack {
                            List { DictationSettingsAdvisor(modelManager: manager) }
                                .navigationTitle("Dictation").navigationBarTitleDisplayMode(.inline)
                        })
                    case "speak", "speak-empty":
                        coordinator.status = .idle
                        content = LANDSCAPE_ONLY ? AnyView(HomeView(modelManager: manager)) : AnyView(TabView {
                            NavigationStack { HomeView(modelManager: manager) }.tabItem { Label("Speak", systemImage: "waveform") }
                            NavigationStack { FixtureSettings(modelManager: manager) }.tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        })
                    case "settings":
                        content = AnyView(NavigationStack { FixtureSettings(modelManager: manager) })
                    case "welcome": content = AnyView(ScrollView { WelcomePage(onNext: {}, onKeyboardSetup: {}).padding(24) })
                    case let activityName where activityName.hasPrefix("activity-"):
                        let phase: DictusLiveActivityAttributes.Phase = activityName == "activity-processing" ? .processing
                            : activityName == "activity-ready" ? .ready : activityName == "activity-failed" ? .failed
                            : activityName == "activity-off" ? .standby : .recording
                        let state = DictusLiveActivityAttributes.ContentState(phase: phase,
                            recordingStartDate: phase == .recording ? Date().addingTimeInterval(-8) : nil,
                            waveformLevels: [0.1, 0.3, 0.4],
                            serviceEnabled: activityName != "activity-off")
                        content = AnyView(DictationActivityCard(state: state))
                    default: content = AnyView(RecordingView(mode: .standalone))
                    }
                    let hosted = content.environmentObject(coordinator).environmentObject(ProStatusManager())
                        .environment(\.dynamicTypeSize, category).preferredColorScheme(dark ? .dark : .light)
                        .tint(Color.saiityAction)
                    let host = UIHostingController(rootView: hosted)
                    if name.hasPrefix("activity-") { host.safeAreaRegions = [] }
                    if MODELS_ONLY && large && !name.hasPrefix("models-") { host.safeAreaRegions = [] }
                    let height: CGFloat
                    if name.hasPrefix("activity-") {
                        let measured = host.sizeThatFits(in: CGSize(width: width, height: 4000))
                        precondition(measured.height <= 160, "Activity exceeds system height: \(name) \(measured)")
                        height = max(84, measured.height)
                    } else if MODELS_ONLY && large && !name.hasPrefix("models-") {
                        let measured = host.sizeThatFits(in: CGSize(width: width, height: 4000))
                        precondition(measured.height.isFinite && measured.height > 0 && measured.height < 4000,
                                     "Model content cannot be laid out at largest text size")
                        height = measured.height
                    } else { height = LANDSCAPE_ONLY ? 402 : 874 }
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
                    window.overrideUserInterfaceStyle = dark ? .dark : .light
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    host.view.frame = window.bounds
                    host.view.layoutIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                    let rendered = UIGraphicsImageRenderer(size: window.bounds.size).image { context in
                        host.view.layer.render(in: context.cgContext)
                    }
                    let path = "OUTPUT/\(name)-\(dark ? "dark" : "light")-\(large ? "large" : "normal").png"
                    guard let pixels = rendered.pngData() else { fatalError("Missing fixture pixels") }
                    try pixels.write(to: URL(fileURLWithPath: path))
                    print("Rendered \(path)")
                    window.isHidden = true
                }
            }
        }
    }
}
"""#.replacingOccurrences(of: "// PRODUCTION_VIEWS", with: modelState + "\n" + modelLocalization + "\n" + home + "\n" + result + "\n" + header + "\n" + history + "\n" + historyEditor + "\n" + recording + "\n" + welcome + "\n" + activity + "\n" + advisor + "\n" + voiceOptions + "\n" + voicePickers + "\n" + modelCards + "\n" + modelsPage + "\n" + polishAvailability + "\n" + settingsRoot + "\n" + vocabulary)
    .replacingOccurrences(of: "OUTPUT", with: output)
    .replacingOccurrences(of: "ADVISOR_ONLY", with: String(advisorOnly))
    .replacingOccurrences(of: "OPTIONS_ONLY", with: String(optionsOnly))
    .replacingOccurrences(of: "MODELS_ONLY", with: String(modelsOnly))
    .replacingOccurrences(of: "PRIVACY_ONLY", with: String(privacyOnly))
    .replacingOccurrences(of: "LANDSCAPE_ONLY", with: String(landscapeOnly))
    .replacingOccurrences(of: "VOCABULARY_ONLY", with: String(vocabularyOnly))
    .replacingOccurrences(of: "import AVFoundation", with: "import AVFoundation\nimport AppIntents")
let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_TASK_TMP"] ?? FileManager.default.temporaryDirectory.path)
    .appendingPathComponent("saiity-native-design-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let source = directory.appendingPathComponent("main.swift"), binary = directory.appendingPathComponent("render")
try program.write(to: source, atomically: true, encoding: .utf8)
func run(_ arguments: [String], capture: Bool = false) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    if capture { process.standardOutput = pipe }
    try process.run()
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Native fixture command failed") }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
let sdk = try run(["--sdk", "iphonesimulator", "--show-sdk-path"], capture: true)
_ = try run(["--sdk", "iphonesimulator", "swiftc", "-parse-as-library", "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator",
             "-module-cache-path", directory.appendingPathComponent("module-cache").path,
             "-I", products, source.path, extensionPath + "/DictusKeyboard.debug.dylib",
             "-Xlinker", "-rpath", "-Xlinker", extensionPath, "-o", binary.path])
if CommandLine.arguments.contains("--compile-only") {
    print("COMPILED: native app fixture; rendering was not run")
} else {
    _ = try run(["simctl", "spawn", simulator, binary.path])
}
