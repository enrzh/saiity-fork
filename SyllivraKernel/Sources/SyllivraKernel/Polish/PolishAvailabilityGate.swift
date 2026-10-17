/// Two consecutive rate refusals suppress that engine for this process; a fresh instance resets the gate.
public struct PolishAvailabilityGate: Sendable, Equatable {
    public static let consecutiveRefusalsBeforeUnavailable = 2
    public private(set) var unavailableEngine: String?
    private var lastRefusalEngine: String?
    private var refusals = 0

    public init() {}
    public func allowsCall(engine: String) -> Bool { engine != unavailableEngine }

    @discardableResult
    public mutating func record(outcome: PolishMetrics.Outcome,
                                reason: PolishFailureReason?, engine: String) -> Bool {
        if unavailableEngine != nil { return false }
        switch outcome {
        case .engineFailed, .success, .rejectedGuardrail:
            if outcome == .engineFailed && reason == .rateLimited {
                refusals = lastRefusalEngine == engine ? refusals + 1 : 1
                lastRefusalEngine = engine
                if refusals == Self.consecutiveRefusalsBeforeUnavailable {
                    unavailableEngine = engine
                    return true
                }
            } else {
                lastRefusalEngine = nil
                refusals = 0
            }
        case .cancelled, .exceededContextBudget, .engineUnavailable, .skipped, .skippedShort, .skippedAutoMode:
            break // These outcomes do not tell us whether the engine accepted a call.
        }
        return false
    }
}
