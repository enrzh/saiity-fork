// Preserve the exact upstream license texts from the resolved dependency graph.
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/generate-license-notices.swift <resolved-checkouts>")
}
let checkouts = URL(fileURLWithPath: CommandLine.arguments[1])
struct Notice: Codable {
    let name: String
    let source: String
    let text: String
    var note: String? = nil
}
let packages: [(String, String, String)] = [
    ("DeviceKit", "DeviceKit", "LICENSE"), ("FluidAudio", "FluidAudio", "LICENSE"),
    ("WhisperKit", "WhisperKit", "LICENSE"), ("MLX Swift", "mlx-swift", "LICENSE"),
    ("MLX Swift LM", "mlx-swift-lm", "LICENSE"), ("MLX", "mlx-swift", "Source/Cmlx/mlx/LICENSE"),
    ("MLX C", "mlx-swift", "Source/Cmlx/mlx-c/LICENSE"),
    ("Metal-cpp", "mlx-swift", "Source/Cmlx/metal-cpp/LICENSE.txt"),
    ("fmt", "mlx-swift", "Source/Cmlx/fmt/LICENSE"),
    ("nlohmann/json", "mlx-swift", "Source/Cmlx/json/LICENSE.MIT"),
    ("Swift Transformers", "swift-transformers", "LICENSE"),
    ("Swift Jinja", "swift-jinja", "LICENSE"), ("Swift Crypto", "swift-crypto", "LICENSE.txt"),
    ("Swift ASN.1", "swift-asn1", "LICENSE.txt"), ("Swift Collections", "swift-collections", "LICENSE.txt"),
    ("Swift Numerics", "swift-numerics", "LICENSE.txt"), ("yyjson", "yyjson", "LICENSE")]
var notices = try packages.map { name, package, file in
    let checkout = checkouts.appendingPathComponent(package)
    var text = try String(contentsOf: checkout.appendingPathComponent(file), encoding: .utf8)
    let attribution = checkout.appendingPathComponent("NOTICE.txt")
    if FileManager.default.fileExists(atPath: attribution.path) {
        text += "\n\n" + (try String(contentsOf: attribution, encoding: .utf8))
    }
    return Notice(name: name, source: "https://github.com/" + [
        "DeviceKit": "devicekit/DeviceKit", "FluidAudio": "FluidInference/FluidAudio", "WhisperKit": "argmaxinc/WhisperKit",
        "speech-swift": "soniqo/speech-swift",
        "mlx-swift": "ml-explore/mlx-swift", "mlx-swift-lm": "ml-explore/mlx-swift-lm",
        "swift-transformers": "huggingface/swift-transformers", "swift-jinja": "huggingface/swift-jinja", "yyjson": "ibireme/yyjson"
    ][package, default: "apple/" + package],
    text: text)
}
notices.append(Notice(name: "Qwen3 Speech Swift", source: "https://github.com/soniqo/speech-swift",
    text: try String(contentsOf: root.appendingPathComponent("Vendor/QwenASRRuntime/LICENSE"), encoding: .utf8)))
notices.append(Notice(name: "Dictus", source: "https://github.com/getdictus/dictus-ios",
                     text: try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8),
                     note: "Attribution for inherited app, keyboard and shared source code. The current shared package is SyllivraKernel; DictusCore is no longer linked."))
notices.append(Notice(name: "giellakbd-ios", source: "https://github.com/divvun/giellakbd-ios",
    text: try String(contentsOf: root.appendingPathComponent("DictusKeyboard/Vendored/LICENSE-MIT"), encoding: .utf8)))
notices.append(Notice(name: "AOSP keyboard and dictionaries", source: "https://android.googlesource.com/platform/packages/inputmethods/LatinIME/",
    text: "Copyright The Android Open Source Project\n\n" + (try String(contentsOf: checkouts.appendingPathComponent("FluidAudio/LICENSE"), encoding: .utf8))))
notices.append(Notice(name: "fastcluster", source: "https://github.com/fastcluster/fastcluster",
    text: try String(contentsOf: checkouts.appendingPathComponent("FluidAudio/ThirdPartyLicenses/fastcluster-LICENSE.md"), encoding: .utf8)))
notices.append(Notice(name: "VBx", source: "https://github.com/BUTSpeechFIT/VBx",
    text: try String(contentsOf: checkouts.appendingPathComponent("FluidAudio/ThirdPartyLicenses/vbx-LICENSE.md"), encoding: .utf8)))
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(notices)
let destination = root.appendingPathComponent("DictusApp/Resources/OpenSourceNotices.json")
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: destination, options: .atomic)
print("Wrote \(notices.count) notices with full upstream license texts")
