import CoreGraphics
import Foundation

/// Turns a sampled swipe path into a dictionary-friendly letter string.
///
/// The keyboard reports every letter key the finger crossed. Consecutive
/// duplicates are collapsed so "h-h-j-j-k-l-l-o" becomes "hjklo", unless a
/// dwell on the same key is long enough to request a repeated letter.
/// A candidate word matches when it starts and ends with the path's first
/// and last letters and the remaining letters appear in order as a subsequence.
public enum SwipeTypingDecoder {
    public static let minimumPathLetters = 2
    /// Pause on one key long enough to emit one extra letter (hello, letter).
    /// Passing through a key is typically much shorter than this.
    public static let dwellRepeatThreshold: TimeInterval = 0.18

    public struct Key: Equatable, Sendable {
        public let letter: Character
        public let frame: CGRect

        public init(letter: Character, frame: CGRect) {
            let folded = letter.lowercased()
            self.letter = folded.first ?? letter
            self.frame = frame
        }

        public var center: CGPoint {
            CGPoint(x: frame.midX, y: frame.midY)
        }
    }

    public struct Touch: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let time: TimeInterval

        public init(x: Double, y: Double, time: TimeInterval) {
            self.x = x
            self.y = y
            self.time = time
        }

        public var point: CGPoint { CGPoint(x: x, y: y) }
    }

    public static func sampledLetters<S: Sequence>(from characters: S) -> String
    where S.Element == Character {
        var out = ""
        out.reserveCapacity(16)
        for character in characters {
            let folded = character.lowercased()
            guard let letter = folded.first, letter.isLetter else { continue }
            if out.last != letter {
                out.append(letter)
            }
        }
        return out
    }

    public static func sampledLetters(from string: String) -> String {
        sampledLetters(from: Array(string))
    }

    /// Map a timed path onto key geometry. Dwell on one key past
    /// `dwellRepeatThreshold` keeps one extra copy of that letter.
    public static func sampledLetters(from touches: [Touch], keys: [Key]) -> String {
        guard !touches.isEmpty, !keys.isEmpty else { return "" }
        var stays: [(letter: Character, start: TimeInterval, end: TimeInterval)] = []
        for touch in touches {
            guard let nearest = nearestKey(to: touch.point, keys: keys) else { continue }
            if let last = stays.last, last.letter == nearest.letter {
                stays[stays.count - 1].end = touch.time
            } else {
                stays.append((nearest.letter, touch.time, touch.time))
            }
        }
        var out = ""
        for stay in stays {
            out.append(stay.letter)
            if stay.end - stay.start >= dwellRepeatThreshold {
                out.append(stay.letter)
            }
        }
        return out
    }

    public static func shouldCommit(path: String) -> Bool {
        path.count >= minimumPathLetters
    }

    public static func matches(_ word: String, path: String) -> Bool {
        let word = word.lowercased()
        let path = path.lowercased()
        guard word.count >= minimumPathLetters,
              path.count >= minimumPathLetters,
              word.first == path.first,
              word.last == path.last else {
            return false
        }
        return isSubsequence(word, of: path)
    }

    /// Lower is better. `nil` when the word cannot be produced by the path.
    /// Scores the sampled path against the polyline through the word's keys so a
    /// dwell on L prefers "hello" over "hero" even when frequency disagrees.
    public static func spatialScore(word: String, touches: [Touch], keys: [Key]) -> Double? {
        let sampled = sampledLetters(from: touches, keys: keys)
        guard matches(word, path: sampled), !touches.isEmpty else { return nil }
        let lookup = Dictionary(uniqueKeysWithValues: keys.map { ($0.letter, $0) })
        let polyline = word.lowercased().compactMap { lookup[$0]?.center }
        guard polyline.count == word.count else { return nil }
        var total = 0.0
        for touch in touches {
            total += distance(touch.point, toPolyline: polyline)
        }
        let scale = max(keys.first?.frame.width ?? 1, 1)
        return total / (scale * Double(touches.count))
    }

    private static func nearestKey(to point: CGPoint, keys: [Key]) -> Key? {
        var best: Key?
        var bestDistance = Double.greatestFiniteMagnitude
        for key in keys {
            let deltaX = point.x - key.center.x
            let deltaY = point.y - key.center.y
            let distance = hypot(deltaX, deltaY)
            let limit = max(key.frame.width, key.frame.height) * 1.5
            guard distance <= limit, distance < bestDistance else { continue }
            best = key
            bestDistance = distance
        }
        return best
    }

    private static func distance(_ point: CGPoint, toPolyline polyline: [CGPoint]) -> Double {
        guard polyline.count >= 2 else {
            guard let only = polyline.first else { return 0 }
            return hypot(point.x - only.x, point.y - only.y)
        }
        var best = Double.greatestFiniteMagnitude
        for index in 0..<(polyline.count - 1) {
            best = min(best, distance(point, segmentFrom: polyline[index], to: polyline[index + 1]))
        }
        return best
    }

    private static func distance(_ point: CGPoint, segmentFrom start: CGPoint, to end: CGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared < 0.5 {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    private static func isSubsequence(_ word: String, of path: String) -> Bool {
        var index = path.startIndex
        for character in word {
            var found = false
            while index < path.endIndex {
                let current = path[index]
                index = path.index(after: index)
                if current == character {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }
}
