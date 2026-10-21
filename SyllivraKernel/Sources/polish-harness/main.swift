// SyllivraKernel/Sources/polish-harness/main.swift
//
// Off-device polish eval harness. Runs the REAL pipeline (PolishPipeline +
// AppleFoundationModelsPolishEngine) on text fixtures, on a Mac with Apple
// Intelligence. The polish input is text (the `raw` field of a device export),
// so no audio is needed. NOT run by CI — Apple FM is non-deterministic and
// absent from CI runners.
//
// Usage:
//   swift run polish-harness show  <fixtures.json> [--runs N] [--instructions <prompt.txt>]
//   swift run polish-harness eval  <fixtures.json> [--instructions <prompt.txt>]
//   swift run polish-harness ab    <fixtures.json> --a <promptA.txt> --b <promptB.txt>
//
// `--instructions <file>` overrides the system prompt (A/B a candidate without
// recompiling). `ab` runs two prompt files side by side.


import Foundation
import SyllivraKernel
#if canImport(FoundationModels)
import FoundationModels
#endif

// Everything below is macOS-only. The guard is not about Apple Intelligence —
// that is checked at runtime further down — it is about the entry point. The
// `SyllivraKernel-Package` scheme builds every target in the package, so pointing it
// at an iOS destination compiles this harness too, and its `@available(macOS
// 26.0, *)` uses are errors there. An executable still needs a `main` on every
// platform it is built for, hence the `#else` stub rather than an empty file. (#301)
#if os(macOS)

// MARK: - Arg parsing

func optionValue(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first, ["show", "eval", "ab", "prompt", "spans", "quality", "quality-template"].contains(command), args.count >= 2 else {
    print("""
    polish-harness — off-device polish eval (macOS + Apple Intelligence)

      show   <fixtures.json> [--runs N] [--instructions <prompt.txt>] [--spans]
      eval   <fixtures.json> [--instructions <prompt.txt>] [--spans]
      ab     <fixtures.json> --a <promptA.txt> --b <promptB.txt>
      prompt <fixtures.json> [--id <fixtureID>] [--out <dir>]
      spans  <fixtures.json>
      quality <product-fixtures.json> <captured-run.json>
      quality-template <product-fixtures.json> --model <installed-model-id>

    --spans  multilingual coordinator path (floor + per-sentence engine)
    spans    print floor + sentence-span decisions; no model required

    """)
    exit(2)
}

if command == "quality" || command == "quality-template" {
    do {
        let fixtures = try JSONDecoder().decode([ASREvaluation.Fixture].self,
            from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        if command == "quality-template" {
            guard let id = optionValue("--model", in: args), let model = ModelInfo.forIdentifier(id) else {
                print("Provide a known model identifier with --model"); exit(2)
            }
            var run = ASREvaluation.emptyRun(model: model, fixtures: fixtures, device: "FILL_DEVICE",
                osVersion: "FILL_OS", modelRevision: "FILL_MODEL_REVISION", runtimeRevision: "FILL_RUNTIME_REVISION")
            let eligible = ASREvaluation.eligibleFixtures(fixtures, for: model)
            run.outcomes = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, .pending) })
            run.finalTranscripts = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, "") })
            run.stopToProxyMs = [:]; run.cold = [:]; run.acceptedWithoutEdits = [:]
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(run), as: UTF8.self))
        } else {
            guard args.count >= 3 else { print("Provide a captured-run JSON path"); exit(2) }
            let run = try JSONDecoder().decode(ASREvaluation.CapturedRun.self,
                from: Data(contentsOf: URL(fileURLWithPath: args[2])))
            guard let model = ModelInfo.forIdentifier(run.modelIdentifier) else { print("Unknown model"); exit(2) }
            let scores = try ASREvaluation.score(run, fixtures: fixtures, model: model)
            let summary = try ASREvaluation.productSummary(run, fixtures: fixtures, model: model)
            print("Device: \(run.device), OS: \(run.osVersion), model: \(run.modelIdentifier)")
            print("Cases: \(summary.cases); inserted: \(summary.inserted); failures: \(summary.failures); cancelled: \(summary.cancelled)")
            print("Unsupported cases excluded: \(fixtures.count - summary.cases)")
            print("Usable unchanged: \(summary.acceptedUnchanged) / \(summary.rated) explicitly rated results")
            print("Protected-fact failures: \(summary.protectedFactFailures); hallucinated silence: \(summary.hallucinatedSilence)")
            for metric in ["wer", "cer"] {
                let cases = scores.filter { $0.metric == metric }
                let units = cases.reduce(0) { $0 + $1.units }
                if units > 0 { print("\(metric.uppercased()): \(Double(cases.reduce(0) { $0 + $1.errors }) / Double(units))") }
            }
            for (label, values) in [("Cold", summary.coldLatencyMs), ("Warm", summary.warmLatencyMs)] where !values.isEmpty {
                let sorted = values.sorted()
                let median = sorted[max(0, Int(ceil(Double(sorted.count) * 0.5)) - 1)]
                let p95 = sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
                print("\(label) Stop-to-proxy n=\(values.count), p50=\(median)ms, p95=\(p95)ms")
                if values.count < 20 { print("Too few samples for a reliable p95 comparison.") }
            }
        }
        exit(0)
    } catch { print("Invalid capture: \(error)"); exit(1) }
}

let fixturesPath = args[1]
let runs = Int(optionValue("--runs", in: args) ?? "1") ?? 1
let instructionsFile = optionValue("--instructions", in: args)
let abA = optionValue("--a", in: args)
let abB = optionValue("--b", in: args)
// #268 D2, throwaway. `prompt` only.
let promptFixtureID = optionValue("--id", in: args)
let promptOutputDir = optionValue("--out", in: args)
let useSpans = args.contains("--spans")

// MARK: - Load fixtures

let fixtures: [Fixture]
do {
    fixtures = try FixtureLoader.load(fixturesPath)
} catch {
    print("error: cannot load fixtures at \(fixturesPath): \(error)")
    exit(1)
}

func loadInstructions(_ path: String?) -> (@Sendable (PolishMode, SupportedLanguage) -> String)? {
    guard let path else { return nil }
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("error: cannot read instructions file \(path)")
        exit(1)
    }
    return { _, _ in text }
}

// MARK: - Run

guard #available(macOS 26.0, *) else {
    print("error: this harness requires macOS 26 with Apple Intelligence.")
    exit(1)
}

#if canImport(FoundationModels)
// `prompt` never runs a model — it prints the bytes one would be sent — so it is
// usable on a machine with Apple Intelligence off, which is the point of it.
if command != "prompt", command != "spans" {
    switch SystemLanguageModel.default.availability {
    case .available:
        break
    default:
        print("error: Apple Foundation Models not available (\(SystemLanguageModel.default.availability)). Enable Apple Intelligence in System Settings.")
        exit(1)
    }
}
#else
print("error: FoundationModels not importable on this toolchain.")
exit(1)
#endif

@available(macOS 26.0, *)
func makeEngine(_ override: (@Sendable (PolishMode, SupportedLanguage) -> String)?) -> any PolishEngineProtocol {
    if let override { return AppleFoundationModelsPolishEngine(instructionsOverride: override) }
    return AppleFoundationModelsPolishEngine()
}

@available(macOS 26.0, *)
struct RunOutcome {
    let final: String
    let engineOutput: String?
    let outcome: PolishMetrics.Outcome
    let engineMs: Int
    /// Raw NLLanguage code of the input ("fr", "it", "zh-Hans", …).
    let detected: String?
    let mode: PolishMode?
    /// Set when the engine threw (#315) — the same slug the app exports, so a
    /// failure seen here reads against the field data without a translation.
    let failureReason: PolishFailureReason?

    init(final: String,
         engineOutput: String?,
         outcome: PolishMetrics.Outcome,
         engineMs: Int,
         detected: String?,
         mode: PolishMode?,
         failureReason: PolishFailureReason? = nil) {
        self.final = final
        self.engineOutput = engineOutput
        self.outcome = outcome
        self.engineMs = engineMs
        self.detected = detected
        self.mode = mode
        self.failureReason = failureReason
    }
}

@available(macOS 26.0, *)
func runOnce(_ fx: Fixture, engine: any PolishEngineProtocol) async -> RunOutcome {
    guard let target = fx.language else {
        return await runOnceAuto(fx, engine: engine)
    }
    let preprocessed = VerbalPunctuationPrepass.apply(fx.raw, language: target)
    // Mirror the coordinator's fallback: non-success returns the deterministic
    // floor (decoded pre-pass), never the literal raw. (#185)
    guard let detected = PolishPipeline.detectLanguage(in: preprocessed) else {
        let fallback = PolishPostpass.decodeFromEngine(preprocessed, language: target)
        return RunOutcome(final: fallback, engineOutput: nil, outcome: .skipped, engineMs: 0, detected: nil, mode: nil)
    }
    let mode = PolishMode.natural
    let r = await PolishPipeline.transform(preprocessed: preprocessed, engine: engine, target: target, mode: mode)
    let final = PolishPipeline.resolvedOutput(r, preprocessed: preprocessed, target: target, mode: mode)
    return RunOutcome(final: final, engineOutput: r.engineOutput, outcome: r.outcome, engineMs: r.engineMs, detected: detected.rawValue, mode: mode, failureReason: r.failureReason)
}

/// Auto-detect path (#239), mirroring `PolishCoordinator.polishAutoDetected`:
/// verbal-punctuation pre-pass keyed on the DETECTED language
/// (`autoPreprocess`), no language typography post-pass, engine runs the
/// language-agnostic auto prompt, non-success falls back to the deterministic
/// floor (the pre-pass output). `target` below is the placeholder the engine
/// API requires — the auto prompt and guardrails ignore it.
@available(macOS 26.0, *)
func runOnceAuto(_ fx: Fixture, engine: any PolishEngineProtocol) async -> RunOutcome {
    guard let detectedCode = PolishPipeline.detectLanguageCode(in: fx.raw) else {
        return RunOutcome(final: fx.raw, engineOutput: nil, outcome: .skipped, engineMs: 0, detected: nil, mode: nil)
    }
    let preprocessed = PolishPipeline.autoPreprocess(fx.raw, detectedCode: detectedCode)
    let r = await PolishPipeline.transform(preprocessed: preprocessed, engine: engine, target: .english, mode: .auto)
    let final = PolishPipeline.resolvedOutput(r, preprocessed: preprocessed, target: .english, mode: .auto)
    return RunOutcome(final: final, engineOutput: r.engineOutput, outcome: r.outcome, engineMs: r.engineMs, detected: detectedCode, mode: .auto, failureReason: r.failureReason)
}

/// Multilingual product path: language-neutral floor, then sequential
/// sentence-span polish. Mixed-script slices stay on the floor.
@available(macOS 26.0, *)
func runOnceSpans(_ fx: Fixture, engine: any PolishEngineProtocol) async -> RunOutcome {
    let r = await PolishSpanPipeline.polish(raw: fx.raw, engine: engine)
    let detected = r.detectedLanguages.isEmpty ? nil : r.detectedLanguages.joined(separator: ",")
    return RunOutcome(
        final: r.text,
        engineOutput: r.outcome == .success ? r.text : nil,
        outcome: r.outcome,
        engineMs: r.engineMs,
        detected: detected,
        mode: .auto,
        failureReason: r.failureReason
    )
}

@available(macOS 26.0, *)
func runFixture(_ fx: Fixture, engine: any PolishEngineProtocol) async -> RunOutcome {
    if useSpans {
        return await runOnceSpans(fx, engine: engine)
    }
    return await runOnce(fx, engine: engine)
}

func spanSummary(for raw: String) -> String {
    let floor = PolishPostpass.cleanupFloor(raw, language: nil)
    let spans = PolishSpanDetector.spans(in: floor)
    if spans.isEmpty {
        return "(none)"
    }
    return spans.map { span in
        let lang = span.languageCode ?? "-"
        let decision = span.polishable ? "polishable" : "passthrough"
        return "[\(lang) \(decision)] \(span.text)"
    }.joined(separator: " | ")
}

@available(macOS 26.0, *)
func runHarness() async {
    switch command {
    case "show":
        let engine = makeEngine(loadInstructions(instructionsFile))
        for fx in fixtures {
            print("\n━━ [\(fx.id)] lang=\(fx.lang) stt=\(fx.sttEngine ?? "PK")\(useSpans ? " spans" : "")")
            print("  raw:      \(fx.raw)")
            if useSpans {
                print("  floor:    \(PolishPostpass.cleanupFloor(fx.raw, language: nil))")
                print("  spans:    \(spanSummary(for: fx.raw))")
            }
            for run in 1...max(1, runs) {
                let o = await runFixture(fx, engine: engine)
                let tag = runs > 1 ? " #\(run)" : ""
                let why = o.failureReason.map { ", reason=\($0.slug)" } ?? ""
                let route = "\(o.outcome.rawValue), \(o.engineMs)ms, detected=\(o.detected ?? "-")→\(o.mode?.rawValue ?? "-")\(why)"
                print("  polished\(tag): \(o.final)")
                print("            (\(route))")
                // When the guardrail rejects, `final` is the raw fallback — surface
                // what the engine actually produced so repair/guardrail issues are visible.
                if o.outcome != .success, let engineOutput = o.engineOutput {
                    print("  engineOut\(tag): \(engineOutput)")
                }
            }
        }

    case "eval":
        let engine = makeEngine(loadInstructions(instructionsFile))
        var passed = 0, total = 0
        for fx in fixtures {
            let o = await runFixture(fx, engine: engine)
            let checks = fx.expect ?? []
            let failures = checks.compactMap { $0.failure(polished: o.final, raw: fx.raw) }
            total += 1
            if failures.isEmpty {
                passed += 1
                print("✓ [\(fx.id)]  (\(o.outcome.rawValue), \(o.engineMs)ms)")
            } else {
                print("✗ [\(fx.id)]  (\(o.outcome.rawValue), \(o.engineMs)ms)")
                for f in failures { print("    – \(f)") }
                print("    → \(o.final)")
            }
        }
        print("\nSummary: \(passed)/\(total) fixtures passed all checks (LLM is non-deterministic — re-run to gauge variance)")

    case "ab":
        guard let abA, let abB else { print("error: ab requires --a <file> --b <file>"); exit(2) }
        let engineA = makeEngine(loadInstructions(abA))
        let engineB = makeEngine(loadInstructions(abB))
        for fx in fixtures {
            print("\n━━ [\(fx.id)] lang=\(fx.lang)")
            print("  raw: \(fx.raw)")
            let a = await runOnce(fx, engine: engineA)
            let b = await runOnce(fx, engine: engineB)
            print("  A (\(a.engineMs)ms): \(a.final)")
            print("  B (\(b.engineMs)ms): \(b.final)")
        }

    // #268 D2, throwaway. Prints the exact two strings the polish engine sends —
    // the resolved system instructions and the user turn — for a fixture, so the
    // ANE measurement runs on the shipping prompt rather than on a paraphrase of
    // it. The user turn carries the PRE-PASSED text, because that is what the
    // engine receives: `runOnce` applies `VerbalPunctuationPrepass` first, and the
    // mode is resolved the same way rather than assumed to be `.natural` — a
    // Parakeet fixture whose detected language differs from its target resolves to
    // `.repair`, and printing the Natural instructions for it would be printing a
    // prompt the engine would never send.
    case "spans":
        for fx in fixtures {
            let floor = PolishPostpass.cleanupFloor(fx.raw, language: nil)
            print("\n━━ [\(fx.id)] lang=\(fx.lang) stt=\(fx.sttEngine ?? "PK")")
            print("  raw:   \(fx.raw)")
            print("  floor: \(floor)")
            print("  spans: \(spanSummary(for: fx.raw))")
        }

    case "prompt":
        let selected = promptFixtureID.map { id in fixtures.filter { $0.id == id } } ?? fixtures
        if selected.isEmpty {
            print("error: no fixture with id \(promptFixtureID ?? "-") in \(fixturesPath)")
            exit(1)
        }
        let override = loadInstructions(instructionsFile)
        for fx in selected {
            var requests: [(text: String, mode: PolishMode, target: SupportedLanguage)] = []
            if useSpans {
                let floor = PolishPostpass.cleanupFloor(fx.raw, language: nil)
                requests = PolishSpanDetector.spans(in: floor).filter(\.polishable)
                    .map { ($0.text, .auto, .english) }
            } else if let target = fx.language {
                let text = VerbalPunctuationPrepass.apply(fx.raw, language: target)
                if let detected = PolishPipeline.detectLanguage(in: text) {
                    requests = [(text, PolishMode.natural, target)]
                }
            } else if let code = PolishPipeline.detectLanguageCode(in: fx.raw) {
                requests = [(PolishPipeline.autoPreprocess(fx.raw, detectedCode: code), .auto, .english)]
            }
            if requests.isEmpty {
                print("[\(fx.id)] skipped: no eligible model request")
            }
            for (index, request) in requests.enumerated() {
                let engineInput = PolishPostpass.encodeForEngine(request.text)
                let resolved = PolishPromptEnvelope.resolve(raw: engineInput)
                let system = override?(request.mode, request.target) ?? resolved.instructions
                let user = resolved.userTurn
                print("━━ [\(fx.id)] lang=\(fx.lang) stt=\(fx.sttEngine ?? "PK") "
                      + "span=\(index) mode=\(request.mode.rawValue) "
                      + "systemChars=\(system.count) userChars=\(user.count)")
                if let dir = promptOutputDir {
                    let name = requests.count == 1 ? fx.id : "\(fx.id)-span\(index)"
                    let base = URL(fileURLWithPath: dir).appendingPathComponent(name)
                    do {
                        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                        try system.write(to: base.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)
                        try user.write(to: base.appendingPathComponent("user.txt"), atomically: true, encoding: .utf8)
                    } catch {
                        print("error: cannot write to \(base.path): \(error)")
                        exit(1)
                    }
                    print("  wrote \(base.path)/{system,user}.txt")
                } else {
                    print("──── system ────")
                    print(system)
                    print("──── user ────")
                    print(user)
                }
            }
        }

    default:
        break
    }
}

await runHarness()

#else

print("error: polish-harness runs on macOS only (it drives Apple Foundation Models on a Mac).")
exit(1)

#endif
