import Foundation

/// Sample-clock pause/forced-cut storage, ported from macOS QwenSpeechBuffer.
/// Only closed regions are decoded; unfinished words never become final text.
public struct StreamingSpeechBuffer: Sendable {
    public enum Event: Sendable { case started(Int), ended(Int) }
    public struct Slice: Sendable {
        public let samples: [Float]
        public let region: SpeechRegion
    }
    public static let sampleRate = 16_000
    public static let maximumSamples = sampleRate * 10
    private var audio: [Float] = []
    private var origin = 0
    private var speechStart: Int?
    private var transcribedThrough = 0
    public var retainedSampleCount: Int { audio.count }
    public init() {}

    public mutating func append(_ samples: [Float], events: [Event], flush: Bool = false) -> [Slice] {
        audio.append(contentsOf: samples)
        var slices: [Slice] = []
        for event in events {
            switch event {
            case .started(let sample): speechStart = max(origin, sample - Self.sampleRate / 5)
            case .ended(let sample):
                slices += takeSlices(endingAt: sample + Self.sampleRate / 5)
                speechStart = nil
            }
        }
        while let start = speechStart,
              origin + audio.count - max(start, transcribedThrough) >= Self.maximumSamples {
            slices += takeSlices(endingAt: max(start, transcribedThrough) + Self.maximumSamples)
            speechStart = transcribedThrough
        }
        if flush, speechStart != nil {
            slices += takeSlices(endingAt: origin + audio.count)
            speechStart = nil
        }
        if speechStart == nil { drop(through: max(origin, origin + audio.count - Self.sampleRate)) }
        return slices
    }

    private mutating func takeSlices(endingAt end: Int) -> [Slice] {
        var slices: [Slice] = []
        let availableEnd = min(end, origin + audio.count)
        while max(origin, max(speechStart ?? transcribedThrough, transcribedThrough)) < availableEnd {
            let start = max(origin, max(speechStart ?? transcribedThrough, transcribedThrough))
            let stop = min(availableEnd, start + Self.maximumSamples)
            slices.append(Slice(samples: Array(audio[(start - origin)..<(stop - origin)]),
                                region: SpeechRegion(startSample: start, endSample: stop)))
            transcribedThrough = stop
            drop(through: stop)
        }
        return slices
    }

    private mutating func drop(through end: Int) {
        let count = min(max(0, end - origin), audio.count)
        guard count > 0 else { return }
        audio.removeFirst(count)
        origin += count
        transcribedThrough = max(transcribedThrough, origin)
    }
}
