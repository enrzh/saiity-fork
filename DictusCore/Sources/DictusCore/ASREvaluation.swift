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

        public init(id: String, languages: [String], metric: String, reference: String) {
            self.id = id
            self.languages = languages
            self.metric = metric
            self.reference = reference
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
            if field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CaptureError.emptyMetadata
            }
        }
        let eligible = eligibleFixtures(fixtures, for: model)
        let ids = Set(eligible.map(\.id))
        guard !ids.isEmpty else { throw CaptureError.missingEligibleCases }
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
}
