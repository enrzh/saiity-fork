// Native macOS check of the production downloader. No network, model download or microphone.
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("saiity-download-check-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let coreBuild = root.appendingPathComponent("SyllivraKernel/.build/out/Products/Debug")
let production = try String(contentsOf: root.appendingPathComponent("DictusApp/Models/ModelRepoDownloader.swift"), encoding: .utf8)
    .replacingOccurrences(of: "import FluidAudio", with: "")
let stubs = #"""
enum AsrModelVersion { case v2, v3 }
enum Repo {
    case parakeetV2, parakeet
    var remotePath: String { "fixture/unused" }
}
enum ModelNames {
    enum ASR { static let requiredModels: Set<String> = ["fixture.mlmodelc"]; static let vocabularyFile = "vocab.json" }
}
final class TrackedTask: URLSessionDownloadTask, @unchecked Sendable {
    var resumes = 0, cancels = 0
    override init() { super.init() }
    override func resume() { resumes += 1 }
    override func cancel() { cancels += 1 }
}
@main struct DownloadCheck {
    static func main() async throws {
        try ModelRepoDownloader.checkDownloadReceipt()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for beforeRegistration in [true, false] {
            let task = TrackedTask()
            let delegate = FileDownloadDelegate(destination: URL(fileURLWithPath: "/unused"),
                filePath: "fixture", stallTimeoutSeconds: 1, onBytes: { _ in })
            if beforeRegistration { delegate.cancel() }
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    delegate.start(task: task, continuation: continuation)
                    precondition(task.resumes == (beforeRegistration ? 0 : 1), "Canceled task resumed after registration")
                    if !beforeRegistration { delegate.cancel() }
                    delegate.urlSession(session, task: task, didCompleteWithError: URLError(.cancelled))
                }
                fatalError("Canceled download completed successfully")
            } catch {
                precondition(error is CancellationError, "Network cancellation was reported as failure: \(error)")
            }
            precondition(task.cancels == 1)
        }
        let task = TrackedTask()
        let delegate = FileDownloadDelegate(destination: URL(fileURLWithPath: "/unused"),
            filePath: "fixture", stallTimeoutSeconds: 1, onBytes: { _ in })
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.start(task: task, continuation: continuation)
            delegate.urlSession(session, task: task, didCompleteWithError: nil)
        }
        delegate.cancel()
        precondition(task.resumes == 1)
        print("PASS: offline receipts and production download cancellation before/during/after registration")
    }
}
"""#
let source = directory.appendingPathComponent("check.swift"), binary = directory.appendingPathComponent("check")
try (production + "\n" + stubs).write(to: source, atomically: true, encoding: .utf8)
func run(_ executable: URL, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = executable; process.arguments = arguments
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Failed: \(executable.lastPathComponent), status \(process.terminationStatus)") }
}
try run(URL(fileURLWithPath: "/usr/bin/xcrun"), ["swiftc", "-parse-as-library", "-DDEBUG", "-I", coreBuild.path,
    "-L", coreBuild.path, "-lSyllivraKernel", source.path, "-o", binary.path])
try run(binary, [])
