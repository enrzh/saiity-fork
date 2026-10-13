import Foundation

/// Identifies the latest asynchronous suggestion request.
///
/// Cancellation stops queued work when possible, but a worker may already be
/// running when a newer request arrives. The generation check closes that race
/// before a stale result reaches the published keyboard state.
public struct SuggestionRequestGate: Sendable {
    public struct Token: Equatable, Sendable {
        fileprivate let generation: UInt
    }

    private var generation: UInt = 0

    public init() {}

    public mutating func begin() -> Token {
        generation &+= 1
        return Token(generation: generation)
    }

    public func isCurrent(_ token: Token) -> Bool {
        token.generation == generation
    }
}
