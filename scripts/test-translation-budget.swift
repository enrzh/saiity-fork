// Compile actual coordinator methods against a stalled SDK fixture, without loading translation models.
// swift scripts/test-translation-budget.swift <coordinator-source> <Core-products>
import Foundation

guard CommandLine.arguments.count == 3 else { fatalError("Pass coordinator source and Core product directory") }
let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
let products = CommandLine.arguments[2]
func method(_ marker: String) -> String {
    guard let start = source.range(of: marker),
          let end = source.range(of: "\n    }\n", range: start.upperBound..<source.endIndex) else {
        fatalError("Production method not found: \(marker)")
    }
    return String(source[start.lowerBound..<end.upperBound]).replacingOccurrences(of: "private func", with: "func")
}
func acceptsDeadline(_ body: String) -> String {
    // The baseline accepted no deadline. Add only the unused parameter so both bodies run identical checks.
    body.contains("deadline: PolishDeadline") ? body : body.replacingOccurrences(
        of: "generation: Int\n", with: "generation: Int,\n        deadline: PolishDeadline\n")
}
let program = #"""
import Foundation
import Translation
import SyllivraKernel

@MainActor final class TranslationSession {
    typealias Request = Translation.TranslationSession.Request
    typealias Response = Translation.TranslationSession.Response
    static var latest: TranslationSession?
    static var stalled = true
    var cancellations = 0
    private var pending: CheckedContinuation<[Response], Error>?
    init(installedSource: Locale.Language, target: Locale.Language?) { Self.latest = self }
    func translations(from batch: [Request]) async throws -> [Response] {
        if !Self.stalled { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            // Release an old implementation that never cancels the SDK; this is not a simulated success.
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                let completion = pending; pending = nil
                completion?.resume(throwing: URLError(.timedOut))
            }
        }
    }
    func cancel() {
        cancellations += 1
        let completion = pending; pending = nil
        completion?.resume(throwing: CancellationError())
    }
}
struct Sessions {
    let current = 1
    func mayReport(from: Int, request: DictationLanguageRequest, currentRequest: DictationLanguageRequest) -> Bool {
        request == currentRequest && from == current
    }
}
@MainActor final class Coordinator {
    let sessions = Sessions()
    let currentLanguageRequest = DictationLanguageRequest(mode: .autoDetect, translationTarget: .english,
        sessionID: "fixture", generation: 1, clientIdentifier: "fixture")
    var hostCalls = 0
    private var pending: (UUID, String, CheckedContinuation<TranslationOutcome, Never>)?
    var clauseDeadlines: [ContinuousClock.Instant] = []
    func translateWithHost(_ transcript: String, source: String?, target: TranslationLanguage,
        request: DictationLanguageRequest, generation: Int, id: UUID) async -> TranslationOutcome {
        hostCalls += 1
        return await withCheckedContinuation { pending = (id, transcript, $0) }
    }
    func cancelPendingTranslation(id: UUID) {
        guard let entry = pending, entry.0 == id else { return }
        pending = nil
        entry.2.resume(returning: .fallback(entry.1, reason: .unavailable))
    }
    func translationOutcome(_ transcript: String, target: TranslationLanguage, sourceHint: String?,
        request: DictationLanguageRequest, generation: Int, deadline: PolishDeadline = PolishDeadline()) async -> TranslationOutcome {
        clauseDeadlines.append(deadline.instant)
        return .original(transcript)
    }
    // PRODUCTION_PROCESS
    // PRODUCTION_HOST
    // PRODUCTION_INSTALLED
}
@main @MainActor struct CheckTranslationBudget {
    static func main() async {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: " + message) }
        }
        let coordinator = Coordinator()
        let request = coordinator.currentLanguageRequest
        let raw = "Do not send 42 EUR to Léa.\n\nBitte schicken Sie die Rechnung morgen an die Firma."
        _ = await coordinator.processAuthoritativeFinalTranscript(raw, request: request)
        check(coordinator.clauseDeadlines.count > 1, "Mixed-language fixture must use multiple clauses")
        check(coordinator.clauseDeadlines.dropFirst().allSatisfy { $0 == coordinator.clauseDeadlines.first },
              "Translation clauses must retain one deadline")

        let clock = ContinuousClock(), started = clock.now
        let host = await coordinator.translateWithHostLimited(raw, source: "en", target: .english, request: request,
            generation: 1, deadline: PolishDeadline(timeout: .milliseconds(30)))
        check(started.duration(to: clock.now) < .seconds(1), "Host work must use the remaining budget")
        check(host.resolvedText == raw && host.fallbackReason == .unavailable, "Timed-out host preserves the full original")
        let hostCalls = coordinator.hostCalls
        _ = await coordinator.translateWithHostLimited(raw, source: "en", target: .english, request: request,
            generation: 1, deadline: PolishDeadline(timeout: .zero))
        check(coordinator.hostCalls == hostCalls, "Expired host work must not start")
        let cancelledHost = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await coordinator.translateWithHostLimited(raw, source: "en", target: .english, request: request,
                generation: 1, deadline: PolishDeadline(timeout: .zero))
        }
        check(await cancelledHost.value.fallbackReason == .cancelled, "Host cancellation must take priority over expiry")

        let installedStarted = clock.now
        let installed = await coordinator.translateWithInstalledSource(raw, source: "en", target: .english, request: request,
            generation: 1, deadline: PolishDeadline(timeout: .milliseconds(30)))
        check(installedStarted.duration(to: clock.now) < .milliseconds(100), "Installed SDK must receive timeout cancellation")
        check(installed.resolvedText == raw && installed.fallbackReason == .unavailable, "Installed timeout preserves the full original")
        let previousSession = TranslationSession.latest
        let alreadyCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await coordinator.translateWithInstalledSource(raw, source: "en", target: .english, request: request,
                generation: 1, deadline: PolishDeadline(timeout: .seconds(1)))
        }
        check(await alreadyCancelled.value.fallbackReason == .cancelled, "Installed pre-cancellation retains its identity")
        check(TranslationSession.latest === previousSession, "Already-cancelled work must not create an SDK session")

        let task = Task { await coordinator.translateWithInstalledSource(raw, source: "en", target: .english, request: request,
            generation: 1, deadline: PolishDeadline(timeout: .seconds(1))) }
        try? await Task.sleep(for: .milliseconds(5))
        task.cancel()
        let cancelled = await task.value
        check(cancelled.resolvedText == raw && cancelled.fallbackReason == .cancelled, "Parent cancellation retains its identity")
        TranslationSession.stalled = false
        _ = await coordinator.translateWithInstalledSource(raw, source: "en", target: .english, request: request,
            generation: 1, deadline: PolishDeadline(timeout: .milliseconds(30)))
        let completedSession = TranslationSession.latest
        // A call completed before its deadline must retire its timer.
        try? await Task.sleep(for: .milliseconds(80))
        check(completedSession?.cancellations == 0, "Finished SDK work must retire its timer")
        if failures > 0 { exit(1) }
        print("PASS: production clause deadline, host/installed cancellation, full original fallback and retired timers")
        print("Fixture SDK only; Apple pair availability, model behavior and physical latency remain unverified")
    }
}
"""#.replacingOccurrences(of: "// PRODUCTION_PROCESS", with: method("    func processAuthoritativeFinalTranscript("))
    .replacingOccurrences(of: "// PRODUCTION_HOST", with: acceptsDeadline(method("    private func translateWithHostLimited(")))
    .replacingOccurrences(of: "// PRODUCTION_INSTALLED", with: acceptsDeadline(method("    private func translateWithInstalledSource(")))
let directory = FileManager.default.temporaryDirectory.appendingPathComponent("syllivra-translation-budget-" + UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let code = directory.appendingPathComponent("main.swift"), binary = directory.appendingPathComponent("check")
try program.write(to: code, atomically: true, encoding: .utf8)
func run(_ args: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = args
    process.environment = ProcessInfo.processInfo.environment.filter { $0.key != "SDKROOT" }
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
}
try run(["--sdk", "macosx", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
         "-I", products, "-L", products, "-lSyllivraKernel", code.path, "-o", binary.path])
try run([binary.path])
