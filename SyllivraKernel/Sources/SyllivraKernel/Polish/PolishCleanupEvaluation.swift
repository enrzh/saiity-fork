// SyllivraKernel/Sources/SyllivraKernel/Polish/PolishCleanupEvaluation.swift
import Foundation

/// Host-side scoring for multilingual cleanup fixtures. Does not load models
/// or claim device behavior.
public enum PolishCleanupEvaluation {
    public struct Fixture: Codable, Equatable, Sendable {
        public let id: String
        public let raw: String
        public let languages: [String]
        public let expectPolishable: Bool
        public let floor: String
        public let mustContain: [String]
        public let mustNotContain: [String]
        public let acceptable: [String]
    }

    public struct Scores: Equatable, Sendable {
        public let artifactFree: Bool
        public let mixedPreserved: Bool
        public let floorMatch: Bool
        public let polishableMatch: Bool
    }

    public static func loadFixtures(from url: URL) throws -> [Fixture] {
        try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }

    public static func score(_ fixture: Fixture) -> Scores {
        let floor = PolishPostpass.cleanupFloor(fixture.raw, language: nil)
        let spans = PolishSpanDetector.spans(in: floor)
        let polishable = spans.contains(where: \.polishable)
        let artifactFree = fixture.mustNotContain.allSatisfy { !floor.contains($0) }
        let mixedPreserved = fixture.mustContain.allSatisfy { floor.contains($0) }
        return Scores(
            artifactFree: artifactFree,
            mixedPreserved: mixedPreserved,
            floorMatch: floor == fixture.floor,
            polishableMatch: polishable == fixture.expectPolishable
        )
    }
}
