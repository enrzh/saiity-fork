// Run after a Debug simulator build: swift scripts/render-product-results.swift <udid> <derived-data>
import Foundation

guard CommandLine.arguments.count == 3 else { fatalError("Pass simulator ID and derived-data path") }
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
let program = #"""
import SwiftUI
import UIKit
import DictusCore

// PRODUCTION_RESULT_COMPONENT

@main @MainActor struct RenderProductResults {
    static func main() throws {
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
            }
        }
        print("PASS: multilingual fallback result at two widths, normal text and accessibility sizes 3/5")
    }
}
"""#.replacingOccurrences(of: "// PRODUCTION_RESULT_COMPONENT", with: component)
    .replacingOccurrences(of: "RESULT_DIRECTORY", with: String(reflecting: resultDirectory.path))
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saiity-product-render-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let source = directory.appendingPathComponent("main.swift"), binary = directory.appendingPathComponent("render")
try program.write(to: source, atomically: true, encoding: .utf8)
func run(_ args: [String], capture: Bool = false) throws -> String {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = args
    if capture { process.standardOutput = pipe }
    try process.run()
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Failed: \(args.first ?? "command")") }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
let sdk = try run(["--sdk", "iphonesimulator", "--show-sdk-path"], capture: true)
_ = try run(["swiftc", "-parse-as-library", "-sdk", sdk, "-target", "arm64-apple-ios17.0-simulator",
             "-I", products, source.path, products + "/DictusApp.app/PlugIns/DictusKeyboard.appex/DictusKeyboard.debug.dylib",
             "-Xlinker", "-rpath", "-Xlinker", products + "/DictusApp.app/PlugIns/DictusKeyboard.appex", "-o", binary.path])
_ = try run(["simctl", "spawn", udid, binary.path])
