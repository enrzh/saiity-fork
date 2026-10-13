import Foundation

/// Shared schema and scorer for captured ASR runs.
///
/// This is the capture path used by an app-hosted runner: fill `emptyRun`,
/// transcribe identical 16 kHz mono files, then `validate` and `score`.
/// It does not load models or prove device quality by itself.
public enum ASREvaluation {
    public struct Fixture: Codable, Equatable, Sendable {
        public let id: String
        public let languages: [String]
        public let metric: String
        public let reference: String
        public let expectedFinal: String?
        public let mustPreserve: [String]?

        public init(id: String, languages: [String], metric: String, reference: String,
                    expectedFinal: String? = nil, mustPreserve: [String]? = nil) {
            self.id = id
            self.languages = languages
            self.metric = metric
            self.reference = reference
            self.expectedFinal = expectedFinal
            self.mustPreserve = mustPreserve
        }
    }

    public struct CapturedRun: Codable, Equatable, Sendable {
        public var modelIdentifier: String
        public var device: String
        public var osVersion: String
        public var modelRevision: String
        public var runtimeRevision: String
        public var audioSHA256: [String: String]
        public var transcripts: [String: String]
        public var loadFailed: Bool?
        public var notes: String?
        public var finalTranscripts: [String: String]?
        public var outcomes: [String: Outcome]?
        public var acceptedWithoutEdits: [String: Bool]?
        public var stopToProxyMs: [String: Double]?
        public var cold: [String: Bool]?

        public init(
            modelIdentifier: String,
            device: String,
            osVersion: String,
            modelRevision: String,
            runtimeRevision: String,
            audioSHA256: [String: String] = [:],
            transcripts: [String: String] = [:],
            loadFailed: Bool? = nil,
            notes: String? = nil
        ) {
            self.modelIdentifier = modelIdentifier
            self.device = device
            self.osVersion = osVersion
            self.modelRevision = modelRevision
            self.runtimeRevision = runtimeRevision
            self.audioSHA256 = audioSHA256
            self.transcripts = transcripts
            self.loadFailed = loadFailed
            self.notes = notes
        }
    }

    public enum Outcome: String, Codable, Sendable { case inserted, failed, cancelled, timedOut, noSpeech, pending }

    public struct ProductSummary: Sendable {
        public let cases: Int
        public let inserted: Int
        public let failures: Int
        public let cancelled: Int
        public let protectedFactFailures: [String]
        public let hallucinatedSilence: [String]
        public let rated: Int
        public let acceptedUnchanged: Int
        public let coldLatencyMs: [Double]
        public let warmLatencyMs: [Double]
    }

    public struct CaseScore: Equatable, Sendable {
        public let id: String
        public let metric: String
        public let errors: Int
        public let units: Int
        public var rate: Double { units == 0 ? 0 : Double(errors) / Double(units) }
    }

    public enum CaptureError: Error, Equatable {
        case emptyMetadata
        case missingEligibleCases
        case invalidAudioHash(String)
        case hashTranscriptMismatch
        case incompleteProductCase(String)
    }

    /// NFC, lowercasing, punctuation-to-space. Accents and numbers stay.
    /// Not the FLEURS/Whisper official normalizer.
    public static func tokens(_ text: String, metric: String) -> [String] {
        let normalized = text.precomposedStringWithCanonicalMapping.lowercased()
            .components(separatedBy: .punctuationCharacters).joined(separator: " ")
        if metric == "cer" {
            return normalized.filter { !$0.isWhitespace }.map(String.init)
        }
        return normalized.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public static func editDistance(_ reference: [String], _ hypothesis: [String]) -> Int {
        var previous = Array(0...hypothesis.count)
        for (i, expected) in reference.enumerated() {
            var row = [i + 1]
            for (j, actual) in hypothesis.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1,
                               previous[j] + (expected == actual ? 0 : 1)))
            }
            previous = row
        }
        return previous[hypothesis.count]
    }

    public static func documentedLanguages(for model: ModelInfo) -> Set<String> {
        let support = model.languageSupport
        return Set(support.highlights.map(\.code) + support.additionalCodes
                   + support.tierGroups.flatMap(\.codes))
    }

    public static func eligibleFixtures(_ fixtures: [Fixture], for model: ModelInfo) -> [Fixture] {
        let languages = documentedLanguages(for: model)
        return fixtures.filter { Set($0.languages).isSubset(of: languages) }
    }

    /// Empty run a device runner fills in. Failed cases stay as empty transcripts.
    public static func emptyRun(
        model: ModelInfo,
        fixtures: [Fixture],
        device: String,
        osVersion: String,
        modelRevision: String,
        runtimeRevision: String
    ) -> CapturedRun {
        let ids = eligibleFixtures(fixtures, for: model).map(\.id)
        return CapturedRun(
            modelIdentifier: model.identifier,
            device: device,
            osVersion: osVersion,
            modelRevision: modelRevision,
            runtimeRevision: runtimeRevision,
            audioSHA256: Dictionary(uniqueKeysWithValues: ids.map { ($0, "") }),
            transcripts: Dictionary(uniqueKeysWithValues: ids.map { ($0, "") })
        )
    }

    public static func validate(_ run: CapturedRun, fixtures: [Fixture], model: ModelInfo) throws {
        for field in [run.device, run.osVersion, run.modelRevision, run.runtimeRevision] {
            if field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || field.hasPrefix("FILL_") {
                throw CaptureError.emptyMetadata
            }
        }
        let eligible = eligibleFixtures(fixtures, for: model)
        let ids = Set(eligible.map(\.id))
        guard !ids.isEmpty else { throw CaptureError.missingEligibleCases }
        guard run.modelIdentifier == model.identifier else { throw CaptureError.emptyMetadata }
        guard Set(run.transcripts.keys) == ids, Set(run.audioSHA256.keys) == ids else {
            throw CaptureError.hashTranscriptMismatch
        }
        for fixture in eligible {
            let hash = run.audioSHA256[fixture.id] ?? ""
            guard hash.count == 64, hash.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                throw CaptureError.invalidAudioHash(fixture.id)
            }
        }
    }

    public static func score(_ run: CapturedRun, fixtures: [Fixture], model: ModelInfo) throws -> [CaseScore] {
        try validate(run, fixtures: fixtures, model: model)
        return eligibleFixtures(fixtures, for: model).map { fixture in
            let reference = tokens(fixture.reference, metric: fixture.metric)
            let hypothesis = tokens(run.transcripts[fixture.id] ?? "", metric: fixture.metric)
            let errors = editDistance(reference, hypothesis)
            return CaseScore(id: fixture.id, metric: fixture.metric, errors: errors, units: reference.count)
        }
    }

    /// Human acceptance remains explicit. Empty/missing/failed runs cannot be
    /// silently counted as good results, and silence hallucination is separate
    /// from WER because its reference has zero words.
    public static func productSummary(_ run: CapturedRun, fixtures: [Fixture], model: ModelInfo) throws -> ProductSummary {
        try validate(run, fixtures: fixtures, model: model)
        let eligible = eligibleFixtures(fixtures, for: model)
        let ids = Set(eligible.map(\.id))
        guard Set(run.outcomes?.keys.map { $0 } ?? []) == ids,
              Set(run.finalTranscripts?.keys.map { $0 } ?? []).isSubset(of: ids),
              Set(run.acceptedWithoutEdits?.keys.map { $0 } ?? []).isSubset(of: ids),
              Set(run.stopToProxyMs?.keys.map { $0 } ?? []).isSubset(of: ids),
              Set(run.cold?.keys.map { $0 } ?? []).isSubset(of: ids) else {
            throw CaptureError.incompleteProductCase("unexpected-or-missing-case")
        }
        var inserted = 0, failures = 0, cancelled = 0, rated = 0, accepted = 0
        var factFailures: [String] = [], silence: [String] = [], cold: [Double] = [], warm: [Double] = []
        for fixture in eligible {
            guard let outcome = run.outcomes?[fixture.id], outcome != .pending else {
                throw CaptureError.incompleteProductCase(fixture.id)
            }
            let raw = run.transcripts[fixture.id] ?? ""
            let final = run.finalTranscripts?[fixture.id] ?? ""
            if fixture.reference.isEmpty && (!raw.isEmpty || !final.isEmpty) { silence.append(fixture.id) }
            if outcome == .inserted {
                guard run.loadFailed != true, !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let latency = run.stopToProxyMs?[fixture.id], latency.isFinite, latency >= 0,
                      let isCold = run.cold?[fixture.id] else { throw CaptureError.incompleteProductCase(fixture.id) }
                inserted += 1
                if isCold { cold.append(latency) } else { warm.append(latency) }
                if let usable = run.acceptedWithoutEdits?[fixture.id] {
                    rated += 1
                    if usable { accepted += 1 }
                }
                if !(fixture.mustPreserve ?? []).allSatisfy({ final.localizedCaseInsensitiveContains($0) }) {
                    factFailures.append(fixture.id)
                }
            } else {
                if run.acceptedWithoutEdits?[fixture.id] != nil { throw CaptureError.incompleteProductCase(fixture.id) }
                if outcome == .cancelled { cancelled += 1 }
                else if outcome != .noSpeech || !fixture.reference.isEmpty { failures += 1 }
            }
        }
        return ProductSummary(cases: eligible.count, inserted: inserted, failures: failures, cancelled: cancelled,
            protectedFactFailures: factFailures, hallucinatedSilence: silence, rated: rated,
            acceptedUnchanged: accepted, coldLatencyMs: cold, warmLatencyMs: warm)
    }
}
