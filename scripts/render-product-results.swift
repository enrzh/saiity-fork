// Run after a Debug simulator build: swift scripts/render-product-results.swift <udid> <derived-data>
import Foundation

guard CommandLine.arguments.count == 3 else { fatalError("Pass simulator ID and derived-data path") }
let udid = CommandLine.arguments[1], derived = CommandLine.arguments[2]
let products = derived + "/Build/Products/Debug-iphonesimulator"
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
                    result: "Please ask José Müller about the invoice tomorrow. 我晚上确认。",
                    original: "uh please ask José Müller about the invoice tomorrow 我晚上确认。",
                    onRestore: { _ in }, onFeedback: { _ in })
                    .padding(20).frame(width: width)
                    .background(Color(uiColor: .systemBackground))
                    .environment(\.dynamicTypeSize, sizeCategory)
                let host = UIHostingController(rootView: content)
                let size = host.sizeThatFits(in: CGSize(width: width, height: 4000))
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                host.view.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                let renderer = UIGraphicsImageRenderer(size: size)
                let rendered = renderer.image { context in host.view.layer.render(in: context.cgContext) }
                guard let data = rendered.pngData() else { fatalError("No result render") }
                try data.write(to: URL(fileURLWithPath: "/tmp/saiity-product-result-\(Int(width))-\(name).png"))
                window.isHidden = true
            }
        }
        print("PASS: shared result at two widths, normal text and accessibility sizes 3/5")
    }
}
"""#.replacingOccurrences(of: "// PRODUCTION_RESULT_COMPONENT", with: component)
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
