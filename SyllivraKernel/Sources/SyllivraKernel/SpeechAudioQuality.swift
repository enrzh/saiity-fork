import Foundation

/// Small, allocation-light diagnostics for one 16 kHz mono recording.
///
/// This is deliberately a measurement and policy value, not a second speech
/// recognizer. It lets the decoder distinguish quiet input from clipped or
/// mostly-noise input without retaining another copy of the recording.
public struct SpeechAudioQuality: Equatable, Sendable {
    public enum Condition: String, Equatable, Sendable {
        case silent
        case quiet
        case noisy
        case clipped
        case usable
    }

    public let rms: Float
    public let peak: Float
    public let clippingRatio: Float
    public let estimatedNoiseFloor: Float
    public let signalToNoiseRatioDB: Float
    public let recommendedGain: Float
    public let condition: Condition

    public init(rms: Float,
                peak: Float,
                clippingRatio: Float,
                estimatedNoiseFloor: Float,
                signalToNoiseRatioDB: Float,
                recommendedGain: Float,
                condition: Condition) {
        self.rms = rms
        self.peak = peak
        self.clippingRatio = clippingRatio
        self.estimatedNoiseFloor = estimatedNoiseFloor
        self.signalToNoiseRatioDB = signalToNoiseRatioDB
        self.recommendedGain = recommendedGain
        self.condition = condition
    }

    public static func analyze(_ samples: [Float], sampleRate: Int = 16_000) -> SpeechAudioQuality {
        analyze(samples[...], sampleRate: sampleRate)
    }

    public static func analyze(_ samples: ArraySlice<Float>, sampleRate: Int = 16_000) -> SpeechAudioQuality {
        guard !samples.isEmpty else {
            return SpeechAudioQuality(
                rms: 0, peak: 0, clippingRatio: 0, estimatedNoiseFloor: 0,
                signalToNoiseRatioDB: 0, recommendedGain: 1, condition: .silent
            )
        }

        var squareSum: Double = 0
        var peak: Float = 0
        var clipped = 0
        for sample in samples {
            let magnitude = abs(sample)
            squareSum += Double(sample) * Double(sample)
            peak = max(peak, magnitude)
            if magnitude >= 0.98 { clipped += 1 }
        }

        let count = Float(samples.count)
        let rms = Float(sqrt(squareSum / Double(samples.count)))
        let clippingRatio = Float(clipped) / count

        let frameSize = max(1, sampleRate / 100)
        var frameRMS: [Float] = []
        frameRMS.reserveCapacity(max(1, samples.count / frameSize))
        var frameStart = samples.startIndex
        while frameStart < samples.endIndex {
            let frameEnd = min(frameStart + frameSize, samples.endIndex)
            var frameSquares: Double = 0
            for index in frameStart..<frameEnd {
                let sample = Double(samples[index])
                frameSquares += sample * sample
            }
            frameRMS.append(Float(sqrt(frameSquares / Double(max(1, frameEnd - frameStart)))))
            frameStart = frameEnd
        }

        frameRMS.sort()
        // The lower quintile is a stable enough noise estimate for a short
        // dictation and avoids treating one click as the noise floor.
        let noiseIndex = min(frameRMS.count - 1, max(0, frameRMS.count / 5))
        let noiseFloor = frameRMS[noiseIndex]
        let snr = 20 * log10(max(rms, 0.000001) / max(noiseFloor, 0.000001))

        let candidateGain: Float
        if peak <= 0.001 || rms <= 0.001 {
            candidateGain = 1
        } else {
            let peakLimited = 0.9 / peak
            let rmsLimited = rms < 0.06 ? 0.12 / rms : 1
            candidateGain = min(4, max(1, max(peakLimited, rmsLimited)))
        }

        let condition: Condition
        if rms <= 0.001 {
            condition = .silent
        } else if clippingRatio >= 0.01 || peak >= 0.999 {
            condition = .clipped
        } else if rms < 0.02 {
            condition = .quiet
        } else if snr < 6 {
            condition = .noisy
        } else {
            condition = .usable
        }

        // Only lift genuinely quiet speech. Amplifying a noisy or clipped
        // capture makes recognition less reliable and can turn room noise into
        // a false speech signal.
        let gain = condition == .quiet ? candidateGain : 1

        return SpeechAudioQuality(
            rms: rms,
            peak: peak,
            clippingRatio: clippingRatio,
            estimatedNoiseFloor: noiseFloor,
            signalToNoiseRatioDB: snr,
            recommendedGain: gain,
            condition: condition
        )
    }
}
