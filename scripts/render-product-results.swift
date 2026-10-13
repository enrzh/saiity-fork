// Run after a Debug simulator build: swift scripts/render-product-results.swift <udid> <derived-data>
// Add --compile-only when the QA simulator cannot be booted within the device limit.
import Foundation

guard CommandLine.arguments.count == 3 || (CommandLine.arguments.count == 4 && CommandLine.arguments[3] == "--compile-only") else {
    fatalError("Pass simulator ID and derived-data path, optionally --compile-only")
}
let udid = CommandLine.arguments[1], derived = CommandLine.arguments[2]
let products = derived + "/Build/Products/Debug-iphonesimulator"
let resultDirectory = URL(fileURLWithPath: derived).appendingPathComponent("multilingual-result-renders")
try FileManager.default.createDirectory(at: resultDirectory, withIntermediateDirectories: true)
let componentFile = try String(contentsOfFile: "DictusApp/Views/HomeView.swift", encoding: .utf8)
guard let start = componentFile.range(of: "struct DictationTranscriptResult: View {"),
      let end = componentFile.range(of: "private struct DictationHistoryEditView:", range: start.upperBound..<componentFile.endIndex) else {
    fatalError("Shared production result component not found")
}
let component = String(componentFile[start.lowerBound..<end.lowerBound])
func homeLines(start marker: String, end endMarker: String) -> String {
    guard let start = componentFile.range(of: marker),
          let end = componentFile.range(of: endMarker, range: start.upperBound..<componentFile.endIndex) else {
        fatalError("Production Home fragment not found: \(marker)")
    }
    return String(componentFile[start.lowerBound..<end.lowerBound])
}
let recentsStorage = homeLines(start: "@AppStorage(SharedKeys.recentDictations", end: "\n")
    .replacingOccurrences(of: "AppGroup.defaults", with: "qaHistoryDefaults")
let recentsChange = homeLines(start: ".onChange(of: recentDictationData)", end: "\n")
let recentsReload = homeLines(start: "    private func reloadRecentDictations()", end: "    @ViewBuilder")
    .replacingOccurrences(of: "AppGroup.defaults", with: "qaHistoryDefaults")
let recentRow = homeLines(start: "            HStack(alignment: .top, spacing: 12) {", end: "            .frame(minHeight: 44)")
    .replacingOccurrences(of: "AppGroup.defaults", with: "qaHistoryDefaults")
let program = #"""
import SwiftUI
import UIKit
import SyllivraKernel

// PRODUCTION_RESULT_COMPONENT

let qaHistorySuite = "syllivra-history-render-" + UUID().uuidString
let qaHistoryDefaults = UserDefaults(suiteName: qaHistorySuite)!
final class HistoryObservation { var reloads = 0; var words: [String] = [] }
final class FabricatedDictationStage: ObservableObject { @Published var status = 0 }
struct HistoryRefreshProbe: View {
    @State private var recentDictationItems: [RecentDictation] = []
    // PRODUCTION_RECENTS_STORAGE
    @ObservedObject var coordinator: FabricatedDictationStage
    let observed: HistoryObservation
    var body: some View {
        VStack { Text("\(coordinator.status)"); Text(recentDictationItems.first?.text ?? "empty") }
            .onAppear { reloadRecentDictations() }
            // PRODUCTION_RECENTS_CHANGE
    }
    // PRODUCTION_RECENTS_RELOAD
}
struct RecentRowProbe: View {
    let item = RecentDictation(text: "明日の予定を確認します。 Café — API_242\nשלום — يرجى تأكيد الفاتورة.")
    func reloadRecentDictations() { }
    func copy(_ text: String) { }
    var body: some View {
        // PRODUCTION_RECENT_ROW
    }
}
private struct DictationHistoryEditView: View {
    let item: RecentDictation
    let onSave: (RecentDictation) -> Void
    var body: some View { Text(item.text) }
}

@main @MainActor struct RenderProductResults {
    static func main() throws {
        defer { qaHistoryDefaults.removePersistentDomain(forName: qaHistorySuite) }
        let stages = FabricatedDictationStage(), observation = HistoryObservation()
        let historyWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        historyWindow.rootViewController = UIHostingController(rootView: HistoryRefreshProbe(coordinator: stages, observed: observation))
        historyWindow.makeKeyAndVisible()
        func settleHistory() { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        settleHistory()
        precondition(observation.reloads > 0 && observation.words.isEmpty)
        let initialReloads = observation.reloads
        for stage in 1...6 { stages.status = stage; settleHistory() }
        precondition(observation.reloads == initialReloads, "Dictation stages still decoded unchanged history")
        RecentDictations.append("Fabricated first result", in: qaHistoryDefaults)
        settleHistory()
        precondition(observation.words == ["Fabricated first result"], "Saved result did not refresh Home")
        let original = RecentDictations.load(from: qaHistoryDefaults)[0]
        RecentDictations.update(RecentDictation(id: original.id, text: "Fabricated edited result", createdAt: original.createdAt), in: qaHistoryDefaults)
        settleHistory()
        precondition(observation.words == ["Fabricated edited result"], "Saved edit did not refresh Home")
        RecentDictations.clear(in: qaHistoryDefaults)
        settleHistory()
        precondition(observation.words.isEmpty, "Cleared history remained visible")
        historyWindow.isHidden = true
        print("PASS: production Home storage reloads for append/edit/clear, not six dictation stage changes")
        for width in [320.0, 402.0] {
            for (name, sizeCategory) in [("normal", DynamicTypeSize.large), ("large", .accessibility3), ("largest", .accessibility5)] {
                let content = DictationTranscriptResult(
                    result: "明日の予定を確認します。 Cafe\u{301} — API_240\nשלום — يرجى تأكيد الفاتورة.",
                    original: "明日の予定を確認します。 Cafe\u{301} — API_240\nשלום — يرجى تأكيد الفاتورة.",
                    onRestore: { _ in }, onFeedback: { _ in }, translationFallback: true)
                    .padding(20).frame(width: width)
                    .background(Color(uiColor: .systemBackground))
                    .environment(\.dynamicTypeSize, sizeCategory)
                let host = UIHostingController(rootView: content)
                let size = host.sizeThatFits(in: CGSize(width: width, height: 4000))
                precondition(size.height.isFinite && size.height > 0 && size.height < 4000)
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                host.view.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                let renderer = UIGraphicsImageRenderer(size: size)
                let rendered = renderer.image { context in host.view.layer.render(in: context.cgContext) }
                guard let data = rendered.pngData() else { fatalError("No result render") }
                let directory = URL(fileURLWithPath: RESULT_DIRECTORY)
                try data.write(to: directory.appendingPathComponent("result-\(Int(width))-\(name).png"))
                window.isHidden = true

                let row = RecentRowProbe().padding(24).frame(width: width)
                    .background(Color(uiColor: .systemBackground))
                    .environment(\.dynamicTypeSize, sizeCategory)
                let rowHost = UIHostingController(rootView: row)
                let rowSize = rowHost.sizeThatFits(in: CGSize(width: width, height: 4000))
                precondition(rowSize.height.isFinite && rowSize.height >= 44 && rowSize.height < 4000)
                let rowWindow = UIWindow(frame: CGRect(origin: .zero, size: rowSize))
                rowWindow.rootViewController = rowHost
                rowWindow.makeKeyAndVisible()
                rowHost.view.frame = rowWindow.bounds
                rowHost.view.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                let rowImage = UIGraphicsImageRenderer(size: rowSize).image { rowHost.view.layer.render(in: $0.cgContext) }
                try rowImage.pngData()!.write(to: directory.appendingPathComponent("recent-row-\(Int(width))-\(name).png"))
                rowWindow.isHidden = true
            }
        }
        print("PASS: multilingual fallback result at two widths, normal text and accessibility sizes 3/5")
    }
}
"""#.replacingOccurrences(of: "// PRODUCTION_RESULT_COMPONENT", with: component)
    .replacingOccurrences(of: "// PRODUCTION_RECENTS_STORAGE", with: recentsStorage)
    .replacingOccurrences(of: "// PRODUCTION_RECENTS_CHANGE", with: recentsChange)
    .replacingOccurrences(of: "// PRODUCTION_RECENT_ROW", with: recentRow)
    .replacingOccurrences(of: "// PRODUCTION_RECENTS_RELOAD", with: recentsReload.replacingOccurrences(
        of: "recentDictationItems = Array(RecentDictations.load(from: qaHistoryDefaults).prefix(3))",
        with: "recentDictationItems = Array(RecentDictations.load(from: qaHistoryDefaults).prefix(3)); observed.reloads += 1; observed.words = recentDictationItems.map(\\.text)"))
    .replacingOccurrences(of: "RESULT_DIRECTORY", with: String(reflecting: resultDirectory.path))
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saiity-product-render-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let source = directory.appendingPathComponent("main.swift"), binary = directory.appendingPathComponent("render")
try program.write(to: source, atomically: true, encoding: .utf8)
func run(_ args: [String], capture: Bool = false) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = args
    process.environment = ProcessInfo.processInfo.environment.filter { $0.key != "SDKROOT" }
    if capture { process.standardOutput = pipe }
    try process.run()
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Failed: \(args.first ?? "command")") }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
let sdk = try run(["--sdk", "iphonesimulator", "--show-sdk-path"], capture: true)
_ = try run(["--sdk", "iphonesimulator", "swiftc", "-parse-as-library", "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator",
             "-I", products, source.path, products + "/DictusApp.app/PlugIns/DictusKeyboard.appex/DictusKeyboard.debug.dylib",
             "-Xlinker", "-rpath", "-Xlinker", products + "/DictusApp.app/PlugIns/DictusKeyboard.appex", "-o", binary.path])
if CommandLine.arguments.contains("--compile-only") {
    print("COMPILED, NOT RUN: product/history rendering checks at \(binary.path)")
} else {
    _ = try run(["simctl", "spawn", udid, binary.path])
}
