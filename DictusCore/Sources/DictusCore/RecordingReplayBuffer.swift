import Foundation

/// One opt-in, bounded recording in memory. Nothing is written to disk.
public struct RecordingReplayBuffer: Sendable {
    public static let sampleRate = 16_000
    public static let maximumSeconds = 60
    public static let lifetime: TimeInterval = 300
    private var samples: [Float] = []
    private var recordedAt: TimeInterval?
    public private(set) var session: Int?
    public private(set) var trimmed = false

    public init() {}
    public mutating func retain(_ audio: [Float], session: Int, enabled: Bool, now: TimeInterval) {
        clear()
        guard enabled, !audio.isEmpty else { return }
        let limit = Self.maximumSeconds * Self.sampleRate
        samples = Array(audio.suffix(limit))
        trimmed = audio.count > limit
        recordedAt = now
        self.session = session
    }
    public func isAvailable(now: TimeInterval) -> Bool {
        guard let recordedAt else { return false }
        return !samples.isEmpty && now >= recordedAt && now - recordedAt < Self.lifetime
    }
    public mutating func clear() {
        samples = []
        recordedAt = nil
        session = nil
        trimmed = false
    }
    public func wavData(now: TimeInterval, isCancelled: () -> Bool = { false }) -> Data? {
        guard isAvailable(now: now) else { return nil }
        var audio = Data(capacity: samples.count * 2)
        for (index, sample) in samples.enumerated() {
            if index % 1024 == 0, isCancelled() { return nil }
            let finite = sample.isFinite ? sample : 0
            var pcm = Int16(min(1, max(-1, finite)) * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &pcm) { audio.append(contentsOf: $0) }
        }
        guard !isCancelled() else { return nil }
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + audio.count)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(Self.sampleRate)); number(UInt32(Self.sampleRate * 2))
        number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(audio.count))
        data.append(audio)
        return data
    }
}
