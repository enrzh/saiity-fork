// Run: swift scripts/summarize-dictation-timings.swift <app-or-keyboard-log> [...]
// Verify the parser without reading user data: append --self-test instead.
import Foundation

struct Run {
    var outcome: String
    var fields: [String: String]
    var stages: [String: Double]
}

func parse(_ text: String) -> [String: Run] {
    // The regex is a fixed literal; an invalid pattern is a programmer error.
    let pattern = try! NSRegularExpression(pattern: "component=DictationTiming instanceID=(\\S+) action=stopToProxy details=(.*)")
    var runs: [String: Run] = [:]
    for line in text.split(separator: "\n") {
        let line = String(line)
        guard let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let idRange = Range(match.range(at: 1), in: line),
              let details = Range(match.range(at: 2), in: line) else { continue }
        let id = String(line[idRange])
        var fields: [String: String] = [:]
        var stages: [String: Double] = [:]
        for item in line[details].split(separator: " ") {
            let pair = item.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = String(pair[0]), value = String(pair[1])
            fields[key] = value
            if value.hasSuffix("ms"), let number = Double(value.dropLast(2)) { stages[key] = number }
        }
        guard let outcome = fields["outcome"] else { continue }
        if runs[id]?.outcome == "inserted" { continue }
        runs[id] = Run(outcome: outcome, fields: fields, stages: stages)
    }
    return runs
}

func percentile(_ values: [Double], _ fraction: Double) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return .nan }
    return sorted[max(0, min(sorted.count - 1, Int(ceil(Double(sorted.count) * fraction)) - 1))]
}

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--self-test"] {
    let fixture = """
    component=DictationTiming instanceID=a action=stopToProxy details=outcome=published asrModel=fixture published=10.0ms
    component=DictationTiming instanceID=a action=stopToProxy details=outcome=inserted asrModel=fixture proxyInserted=15.0ms
    component=DictationTiming instanceID=b action=stopToProxy details=outcome=cancelled finished=5.0ms
    """
    let runs = parse(fixture)
    precondition(runs.count == 2 && runs["a"]?.stages["proxyInserted"] == 15)
    precondition(runs["b"]?.outcome == "cancelled")
    precondition(percentile([1, 2, 3, 4], 0.5) == 2 && percentile([1, 2, 3, 4], 0.95) == 4)
    print("PASS: session deduplication, failure retention and percentiles")
} else {
    guard !args.isEmpty else { fatalError("Pass exported logs or --self-test") }
    let text = try args.map { try String(contentsOfFile: $0, encoding: .utf8) }.joined(separator: "\n")
    let runs = parse(text)
    let keys = ["os", "asrModel", "cleanupEngine", "style", "thermal", "asrResident"]
    let groups = Dictionary(grouping: runs.values) { run in
        keys.map { "\($0)=\(run.fields[$0] ?? "unknown")" }.joined(separator: " ")
    }
    for group in groups.keys.sorted() {
        let values = groups[group] ?? []
        print(group)
        let counts = Dictionary(grouping: values, by: \.outcome).mapValues(\.count)
        print("  sessions=\(values.count) outcomes=\(counts)")
        let inserted = values.filter { $0.outcome == "inserted" }
        for stage in ["sampleDrain", "modelReady", "asrAndMerge", "translation", "cleanup", "published", "proxyInserted"] {
            let samples = inserted.compactMap { $0.stages[stage] }
            guard !samples.isEmpty else { continue }
            print(String(format: "  %@ n=%d p50=%.2fms p95=%.2fms", stage, samples.count,
                         percentile(samples, 0.5), percentile(samples, 0.95)))
        }
        if inserted.count < 20 { print("  Too few insertions for a reliable p95 comparison.") }
    }
    if runs.isEmpty { print("No correlated timing events found; no latency result is available.") }
}
