import Foundation
import CoreGraphics

/// A bounded, normalized next-character distribution from local prediction data.
public struct NextCharacterProbabilities: Equatable {
    public let values: [String: Double]

    public init(_ rawValues: [String: Double], maxEntries: Int = 8) {
        let normalized = rawValues.reduce(into: [String: Double]()) { result, item in
            let key = item.key.lowercased()
            guard key.count == 1, item.value.isFinite, item.value > 0 else { return }
            result[key, default: 0] += item.value
        }
        let bounded = normalized
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(max(0, maxEntries))
        let total = bounded.reduce(0) { $0 + $1.value }
        values = total > 0
            ? Dictionary(uniqueKeysWithValues: bounded.map { ($0.key, $0.value / total) })
            : [:]
    }

    public subscript(character: String) -> Double {
        values[character.lowercased()] ?? 0
    }

    public var isEmpty: Bool { values.isEmpty }
}

/// Geometry and safety metadata for one key in the currently rendered letter grid.
public struct AdaptiveTouchKey: Equatable {
    public let id: String
    public let label: String
    public let frame: CGRect
    public let row: Int
    public let column: Int
    public let isCommand: Bool
    public let hasVariants: Bool

    public init(
        id: String,
        label: String,
        frame: CGRect,
        row: Int,
        column: Int,
        isCommand: Bool,
        hasVariants: Bool
    ) {
        self.id = id
        self.label = label
        self.frame = frame
        self.row = row
        self.column = column
        self.isCommand = isCommand
        self.hasVariants = hasVariants
    }
}

/// Resolves only a confident redirect across one horizontal key boundary.
/// Returning nil is the deliberate static fallback: the normal key owner keeps the touch.
public enum AdaptiveTouchResolver {
    public enum Decision: Equatable {
        case keep(String)
        case redirect(String)
    }

    /// Resolves a boundary touch using prediction priors and key-center
    /// likelihoods. `keep` is the static owner and `redirect` is the only
    /// result the UIKit overlay is allowed to forward.
    public static func resolve(
        at point: CGPoint,
        keys: [AdaptiveTouchKey],
        probabilities: NextCharacterProbabilities,
        boundaryWidth: CGFloat = 9,
        minimumProbability: Double = 0.55,
        minimumLead: Double = 0.15
    ) -> Decision? {
        guard !probabilities.isEmpty, boundaryWidth > 0 else { return nil }
        let confidenceFloor = max(minimumProbability, 0.55)
        let requiredLead = max(minimumLead, 0.15)

        let safeKeys = keys.filter { !$0.isCommand && !$0.frame.isEmpty }
        for left in safeKeys {
            guard let right = safeKeys.first(where: {
                $0.row == left.row && $0.column == left.column + 1
            }) else { continue }

            let boundary = (left.frame.maxX + right.frame.minX) / 2
            let alternateForZone = point.x <= boundary ? right : left
            let staticForZone = point.x <= boundary ? left : right
            let alternateProbability = probabilities[alternateForZone.label]
            let staticProbability = probabilities[staticForZone.label]
            // A confident next letter owns a wider invisible slice of the
            // neighbor. The neighbor's center still types the neighbor.
            let confidentHit = alternateProbability >= 0.75
                && alternateProbability - staticProbability >= 0.25
            let activeBoundary = confidentHit
                ? max(boundaryWidth, min(left.frame.width, right.frame.width) * 0.46)
                : boundaryWidth
            guard abs(point.x - boundary) <= activeBoundary,
                  point.y >= max(left.frame.minY, right.frame.minY),
                  point.y <= min(left.frame.maxY, right.frame.maxY) else {
                continue
            }

            let staticKey = staticForZone
            let alternateKey = alternateForZone
            let staticCenterRatio: CGFloat = confidentHit ? 0.24 : 0.34
            guard abs(point.x - staticKey.frame.midX) > staticKey.frame.width * staticCenterRatio,
                  abs(point.x - alternateKey.frame.midX) > alternateKey.frame.width * 0.34 else { continue }

            guard alternateProbability >= confidenceFloor else {
                return .keep(staticKey.id)
            }
            // Spatial likelihood may refine a confident prior, but it cannot
            // manufacture confidence from equal or near-equal priors.
            guard alternateProbability - staticProbability >= requiredLead else {
                return .keep(staticKey.id)
            }
            if confidentHit {
                return .redirect(alternateKey.id)
            }

            let sigma = max(Double(min(left.frame.width, right.frame.width)) * 0.42, 1)
            let alternateDistance = Double(abs(point.x - alternateKey.frame.midX))
            let staticDistance = Double(abs(point.x - staticKey.frame.midX))
            let alternateLikelihood = exp(-0.5 * pow(alternateDistance / sigma, 2))
            let staticLikelihood = exp(-0.5 * pow(staticDistance / sigma, 2))
            let alternateScore = sqrt(alternateProbability + 0.05) * alternateLikelihood
            let staticScore = sqrt(staticProbability + 0.05) * staticLikelihood
            guard alternateScore > staticScore else {
                return .keep(staticKey.id)
            }
            return .redirect(alternateKey.id)
        }
        return nil
    }

    public static func redirectedKey(
        at point: CGPoint,
        keys: [AdaptiveTouchKey],
        probabilities: NextCharacterProbabilities,
        boundaryWidth: CGFloat = 9,
        minimumProbability: Double = 0.55,
        minimumLead: Double = 0.15
    ) -> String? {
        guard case .redirect(let id) = resolve(
            at: point,
            keys: keys,
            probabilities: probabilities,
            boundaryWidth: boundaryWidth,
            minimumProbability: minimumProbability,
            minimumLead: minimumLead
        ) else {
            return nil
        }
        return id
    }
}
