import Foundation

/// Capture ownership is independent of delayed UI updates. Stop waits for a
/// callback already admitted to conversion, then transfers its complete buffer.
public final class AudioCaptureBuffer: @unchecked Sendable {
    public struct Capture: Sendable {
        public let sessionID: UInt64
        public let samples: [Float]
        public let totalSampleCount: Int
    }

    private let lock = NSLock()
    private var sessionID: UInt64?
    private var samples: [Float] = []

    public init() {}

    public func start(sessionID: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        samples = []
        self.sessionID = sessionID
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }

    /// Incremental preview reads never consume the authoritative Stop buffer.
    public func read(after sampleCount: Int, maximumSamples: Int = 8_000) -> Capture? {
        lock.lock()
        defer { lock.unlock() }
        guard let sessionID, sampleCount >= 0, sampleCount < samples.count, maximumSamples > 0 else { return nil }
        let end = sampleCount + min(maximumSamples, samples.count - sampleCount)
        return Capture(sessionID: sessionID, samples: Array(samples[sampleCount..<end]),
                       totalSampleCount: samples.count)
    }

    /// Only conversion and accumulation belong inside this short critical
    /// section. Never call UI, disk, or audio-session APIs from the closure.
    public func capture(_ convert: () -> [Float]?) -> Capture? {
        lock.lock()
        defer { lock.unlock() }
        guard let sessionID, let chunk = convert() else { return nil }
        samples.append(contentsOf: chunk)
        return Capture(sessionID: sessionID, samples: chunk, totalSampleCount: samples.count)
    }

    public func stop() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        sessionID = nil
        let captured = samples
        samples = []
        return captured
    }
}
