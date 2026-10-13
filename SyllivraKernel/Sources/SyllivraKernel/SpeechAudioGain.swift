import Foundation

/// Raises quiet microphone captures toward a usable peak without clipping loud speech.
public enum SpeechAudioGain {
    public static let quietPeak: Float = 0.25
    public static let quietRMS: Float = 0.06
    public static let targetPeak: Float = 0.9
    public static let targetRMS: Float = 0.12
    public static let maximumGain: Float = 4
    public static let silencePeak: Float = 0.001

    public static func amplifyIfQuiet(_ samples: [Float]) -> [Float] {
        applying(gain(for: samples), to: samples[...])
    }

    /// Returns one conservative gain for a recording. RMS prevents a single
    /// click from deciding the gain, while the peak limit prevents clipping.
    public static func gain(for samples: [Float]) -> Float {
        gain(for: samples[...])
    }

    public static func gain(for samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 1 }
        return SpeechAudioQuality.analyze(samples).recommendedGain
    }

    /// Applies gain to one region and clips only the numerical overshoot that
    /// can occur at the Float boundary. Regions are copied one at a time.
    public static func applying(_ gain: Float, to samples: ArraySlice<Float>) -> [Float] {
        guard gain != 1 else { return Array(samples) }
        return samples.map { min(1, max(-1, $0 * gain)) }
    }
}
