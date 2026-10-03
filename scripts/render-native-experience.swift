// Run from the repo: swift scripts/render-native-experience.swift <QA simulator> <derived-data> <output-directory>
// Hosts the production SwiftUI bodies with inert data dependencies. Never captures audio or loads models.
import Foundation

guard CommandLine.arguments.count == 4 else { fatalError("Pass simulator ID, derived-data path and output directory") }
let simulator = CommandLine.arguments[1], derived = CommandLine.arguments[2], output = CommandLine.arguments[3]
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
let result = section(homeSource, from: "struct DictationTranscriptResult: View", to: "private struct DictationHistoryEditView:")
let header = section(homeSource, from: "struct SaiityPageHeader: View", to: "struct DictationHistoryView:")
var recording = section(try read("DictusApp/Views/RecordingView.swift"), from: "enum RecordingMode", to: "#Preview")
recording = recording.replacingOccurrences(of: "@State private var transcriptionResult: String?", with: "@State private var transcriptionResult: String? = fixturePhase == .ready ? fixtureText : nil")
recording = recording.replacingOccurrences(of: "@State private var showResult = false", with: "@State private var showResult = fixturePhase == .ready")
let welcome = section(try read("DictusApp/Onboarding/WelcomePage.swift"), from: "struct WelcomePage: View", to: "\n}") + "\n}"
let activitySource = try read("DictusWidgets/DictusLiveActivity.swift")
guard let activityStart = activitySource.range(of: "/// One state vocabulary") else { fatalError("Missing activity presentation") }
let activity = String(activitySource[activityStart.lowerBound...])

let program = #"""
import SwiftUI
import UIKit
import AVFoundation
import DictusCore

let fixtureText = "I’ll send the updated proposal tomorrow morning. 我們下午再確認一次。"
let fixtureOriginal = "um I’ll send the updated proposal tomorrow morning 我們下午再確認一次"
let fixtureSuite = "saiity-design-fixture-" + UUID().uuidString
let fixtureDefaults: UserDefaults = {
    guard let defaults = UserDefaults(suiteName: fixtureSuite) else { fatalError("No fixture defaults") }
    return defaults
}()
var fixturePhase = DictationStatus.idle
var fixtureReadiness = DictationReadiness(serviceEnabled: true, microphonePermission: .authorized,
    modelReady: true, modelLoadState: .ready, status: .idle)
let fixtureHistory = [RecentDictation(text: fixtureText, createdAt: Date().timeIntervalSince1970 - 480, originalText: fixtureOriginal)]

final class ProStatusManager: ObservableObject {}
final class ModelManager: ObservableObject {
    var recognizer = DictationRecognizer.whisper
    var selectionMode = ModelSelectionMode.manual
    var selectionProfile = ModelSelectionProfile.balanced
}
final class DictationCoordinator: ObservableObject {
    static let shared = DictationCoordinator()
    @Published var status = DictationStatus.idle
    var realtimeTranscript = fixtureText
    var lastOriginalResult: String? = fixtureOriginal
    var lastResult: String? = fixtureText
    var dictationGeneration = 1
    var bufferSeconds: Double = 8
    var bufferEnergy: [Float] = [0.1, 0.3, 0.4]
    func startDictation() {}
    func stopDictation() {}
    func cancelDictation() {}
    func resetStatus() {}
    func preloadActiveModel() {}
    func setKeyboardDictationEnabled(_ enabled: Bool) {}
}
struct DictationErrorChannel { static var current: String? = "The voice model was unavailable. Your original words are still available." }
struct ProBannerView: View { var body: some View { EmptyView() } }
struct VoiceOptionsView: View { let modelManager: ModelManager; var body: some View { EmptyView() } }
struct ModelManagerView: View { let modelManager: ModelManager; var body: some View { EmptyView() } }
struct DictationHistoryView: View { var body: some View { EmptyView() } }
struct DictationHistoryEditView: View { let item: RecentDictation; let onSave: (RecentDictation) -> Void; var body: some View { EmptyView() } }
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
        fixtureDefaults.set(false, forKey: SharedKeys.serviceEnabled)
        defer { fixtureDefaults.removePersistentDomain(forName: fixtureSuite) }
        try FileManager.default.createDirectory(atPath: "OUTPUT", withIntermediateDirectories: true)
        let coordinator = DictationCoordinator.shared
        let manager = ModelManager()
        for dark in [false, true] {
            for large in [false, true] {
                let width: CGFloat = large ? 320 : 402
                let category: DynamicTypeSize = large ? .accessibility3 : .large
                for name in ["speak", "listening", "result", "failed", "welcome", "activity-recording", "activity-off", "activity-processing", "activity-ready", "activity-failed"] {
                    fixturePhase = name == "result" ? .ready : name == "failed" ? .failed : .recording
                    coordinator.status = fixturePhase
                    let content: AnyView
                    switch name {
                    case "speak":
                        coordinator.status = .idle
                        content = AnyView(TabView {
                            NavigationStack { HomeView(modelManager: manager) }.tabItem { Label("Speak", systemImage: "waveform") }
                            Text("Settings").tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                        })
                    case "welcome": content = AnyView(ScrollView { WelcomePage(onNext: {}).padding(24) })
                    case let activityName where activityName.hasPrefix("activity-"):
                        let phase: DictusLiveActivityAttributes.Phase = activityName == "activity-processing" ? .processing
                            : activityName == "activity-ready" ? .ready : activityName == "activity-failed" ? .failed
                            : activityName == "activity-off" ? .standby : .recording
                        let state = DictusLiveActivityAttributes.ContentState(phase: phase,
                            recordingStartDate: phase == .recording ? Date().addingTimeInterval(-8) : nil,
                            waveformLevels: [0.1, 0.3, 0.4], transcriptionPreview: phase == .ready ? fixtureText : nil,
                            serviceEnabled: activityName != "activity-off")
                        content = AnyView(DictationActivityCard(state: state))
                    default: content = AnyView(RecordingView(mode: .standalone))
                    }
                    let hosted = content.environmentObject(coordinator).environmentObject(ProStatusManager())
                        .environment(\.dynamicTypeSize, category).environment(\.colorScheme, dark ? .dark : .light)
                        .tint(Color.saiityAction)
                    let host = UIHostingController(rootView: hosted)
                    if name.hasPrefix("activity-") { host.safeAreaRegions = [] }
                    let height: CGFloat
                    if name.hasPrefix("activity-") {
                        let measured = host.sizeThatFits(in: CGSize(width: width, height: 4000))
                        precondition(measured.height <= 160, "Activity exceeds system height: \(name) \(measured)")
                        height = max(84, measured.height)
                    } else { height = 874 }
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
"""#.replacingOccurrences(of: "// PRODUCTION_VIEWS", with: home + "\n" + result + "\n" + header + "\n" + recording + "\n" + welcome + "\n" + activity)
    .replacingOccurrences(of: "OUTPUT", with: output)
    .replacingOccurrences(of: "import AVFoundation", with: "import AVFoundation\nimport AppIntents")
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saiity-native-design-" + UUID().uuidString)
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
_ = try run(["swiftc", "-parse-as-library", "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator",
             "-I", products, source.path, extensionPath + "/DictusKeyboard.debug.dylib",
             "-Xlinker", "-rpath", "-Xlinker", extensionPath, "-o", binary.path])
_ = try run(["simctl", "spawn", simulator, binary.path])
