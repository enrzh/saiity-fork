// DictusCore/Sources/DictusCore/Polish/PolishSpanPipeline.swift
import Foundation

/// Sequential, span-aware polish for multilingual dictation.
///
/// Whole-document Auto polish rewrites mixed speech into one language. This
/// pipeline strips ASR artifacts first, then runs the engine on each confident
/// monolingual sentence span and leaves mixed/low-confidence slices on the
/// deterministic floor. Engine calls stay sequential.
public enum PolishSpanPipeline {

    public struct Result: Sendable {
        public let text: String
        public let outcome: PolishMetrics.Outcome
        public let engineMs: Int
        public let postprocessMs: Int
        public let polishedSpanCount: Int
        public let passthroughSpanCount: Int
        public let detectedLanguages: [String]
        public let failureReason: PolishFailureReason?

        public init(text: String,
                    outcome: PolishMetrics.Outcome,
                    engineMs: Int,
                    postprocessMs: Int,
                    polishedSpanCount: Int,
                    passthroughSpanCount: Int,
                    detectedLanguages: [String],
                    failureReason: PolishFailureReason? = nil) {
            self.text = text
            self.outcome = outcome
            self.engineMs = engineMs
            self.postprocessMs = postprocessMs
            self.polishedSpanCount = polishedSpanCount
            self.passthroughSpanCount = passthroughSpanCount
            self.detectedLanguages = detectedLanguages
            self.failureReason = failureReason
        }
    }

    /// Internal flag. Absent defaults to on; set `false` to fall back to the
    /// language-neutral floor for multilingual output.
    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: SharedKeys.polishSpanAwareMultilingual) != nil else {
            return true
        }
        return defaults.bool(forKey: SharedKeys.polishSpanAwareMultilingual)
    }

    public static func polish(raw: String,
                              engine: PolishEngineProtocol,
                              gate: PolishAvailabilityGate = PolishAvailabilityGate(),
                              skipEngine: Bool = false,
                              placeholderLanguage: SupportedLanguage = .english,
                              style: WritingStyle = .balanced,
                              deadline: PolishDeadline = PolishDeadline()) async -> Result {
        let floor = PolishPostpass.cleanupFloor(raw, language: nil)
        let spans = PolishSpanDetector.spans(in: floor)
        let polishable = spans.filter(\.polishable)
        let passthroughCount = spans.count - polishable.count
        let languages = Array(Set(polishable.compactMap(\.languageCode))).sorted()

        if skipEngine {
            return Result(
                text: floor, outcome: .skippedShort, engineMs: 0, postprocessMs: 0,
                polishedSpanCount: 0, passthroughSpanCount: spans.count,
                detectedLanguages: languages
            )
        }
        guard gate.allowsCall(engine: engine.identifier) else {
            return Result(
                text: floor, outcome: .engineUnavailable, engineMs: 0, postprocessMs: 0,
                polishedSpanCount: 0, passthroughSpanCount: spans.count,
                detectedLanguages: languages
            )
        }
        guard !polishable.isEmpty else {
            return Result(
                text: floor, outcome: .skipped, engineMs: 0, postprocessMs: 0,
                polishedSpanCount: 0, passthroughSpanCount: max(spans.count, 1),
                detectedLanguages: languages
            )
        }

        var assembled = ""
        var engineMs = 0
        var postprocessMs = 0
        var polishedCount = 0
        var lastFailure: PolishFailureReason?
        var sawSuccess = false
        var sawEngineFailure = false
        var sawGuardrail = false

        for span in spans {
            guard span.polishable else {
                assembled += span.text
                continue
            }
            if Task.isCancelled {
                return Result(
                    text: floor, outcome: .cancelled, engineMs: engineMs,
                    postprocessMs: postprocessMs, polishedSpanCount: polishedCount,
                    passthroughSpanCount: passthroughCount,
                    detectedLanguages: languages
                )
            }
            let transform = await PolishPipeline.transform(
                preprocessed: span.text,
                engine: engine,
                target: placeholderLanguage,
                mode: .auto,
                style: style,
                gate: gate,
                deadline: deadline
            )
            engineMs += transform.engineMs
            postprocessMs += transform.postprocessMs
            assembled += PolishPipeline.resolvedOutput(
                transform,
                preprocessed: span.text,
                target: placeholderLanguage,
                mode: .auto
            )
            switch transform.outcome {
            case .success:
                sawSuccess = true
                polishedCount += 1
            case .cancelled:
                return Result(
                    text: floor, outcome: .cancelled, engineMs: engineMs,
                    postprocessMs: postprocessMs, polishedSpanCount: polishedCount,
                    passthroughSpanCount: passthroughCount,
                    detectedLanguages: languages
                )
            case .engineFailed:
                sawEngineFailure = true
                lastFailure = transform.failureReason
            case .rejectedGuardrail, .exceededContextBudget:
                sawGuardrail = true
            case .engineUnavailable:
                return Result(
                    text: floor, outcome: .engineUnavailable, engineMs: engineMs,
                    postprocessMs: postprocessMs, polishedSpanCount: polishedCount,
                    passthroughSpanCount: passthroughCount,
                    detectedLanguages: languages,
                    failureReason: transform.failureReason
                )
            case .skipped, .skippedShort, .skippedAutoMode:
                break
            }
        }

        let outcome: PolishMetrics.Outcome
        if sawSuccess {
            outcome = .success
        } else if sawEngineFailure {
            outcome = .engineFailed
        } else if sawGuardrail {
            outcome = .rejectedGuardrail
        } else {
            outcome = .skipped
        }
        return Result(
            text: assembled,
            outcome: outcome,
            engineMs: engineMs,
            postprocessMs: postprocessMs,
            polishedSpanCount: polishedCount,
            passthroughSpanCount: passthroughCount,
            detectedLanguages: languages,
            failureReason: lastFailure
        )
    }

    /// Region-aware multilingual cleanup. ASR regions are the strongest
    /// language evidence available, so clean each validated region separately
    /// and merge the results with the same overlap and script-aware rules used
    /// for transcription. Unknown or mixed regions stay on the deterministic
    /// floor instead of being offered to one dominant-language model prompt.
    public static func polish(regions: [SpeechRegionTranscript],
                              engine: PolishEngineProtocol,
                              gate: PolishAvailabilityGate = PolishAvailabilityGate(),
                              skipEngine: Bool = false,
                              placeholderLanguage: SupportedLanguage = .english,
                              style: WritingStyle = .balanced,
                              deadline: PolishDeadline = PolishDeadline()) async -> Result {
        guard !regions.isEmpty else {
            return await polish(
                raw: "",
                engine: engine,
                gate: gate,
                skipEngine: skipEngine,
                placeholderLanguage: placeholderLanguage,
                style: style,
                deadline: deadline
            )
        }

        let floorRegions = regions.map { region in
            SpeechRegionTranscript(
                region: region.region,
                text: PolishPostpass.cleanupFloor(region.text, language: nil),
                detectedLanguage: region.detectedLanguage,
                validatedLanguage: region.validatedLanguage,
                overlapsPreviousRegion: region.overlapsPreviousRegion,
                decodeDurationSeconds: region.decodeDurationSeconds,
                averageLogProbability: region.averageLogProbability,
                fallbackReason: region.fallbackReason,
                languageEvidenceScore: region.languageEvidenceScore
            )
        }
        let floor = floorRegions.count == 1 ? floorRegions[0].text : SpeechTranscriptMerger.merge(floorRegions)
        let detectedLanguages = Array(Set(floorRegions.compactMap { $0.validatedLanguage })).sorted()

        if skipEngine {
            return Result(
                text: floor,
                outcome: .skippedShort,
                engineMs: 0,
                postprocessMs: 0,
                polishedSpanCount: 0,
                passthroughSpanCount: floorRegions.count,
                detectedLanguages: detectedLanguages
            )
        }
        guard gate.allowsCall(engine: engine.identifier) else {
            return Result(
                text: floor,
                outcome: .engineUnavailable,
                engineMs: 0,
                postprocessMs: 0,
                polishedSpanCount: 0,
                passthroughSpanCount: floorRegions.count,
                detectedLanguages: detectedLanguages
            )
        }

        var cleanedRegions: [SpeechRegionTranscript] = []
        cleanedRegions.reserveCapacity(floorRegions.count)
        var engineMs = 0
        var postprocessMs = 0
        var polishedCount = 0
        var passthroughCount = 0
        var lastFailure: PolishFailureReason?
        var sawSuccess = false
        var sawEngineFailure = false
        var sawGuardrail = false

        for region in floorRegions {
            if Task.isCancelled {
                return Result(
                    text: floor,
                    outcome: .cancelled,
                    engineMs: engineMs,
                    postprocessMs: postprocessMs,
                    polishedSpanCount: polishedCount,
                    passthroughSpanCount: passthroughCount,
                    detectedLanguages: detectedLanguages
                )
            }

            let evidence = SpeechLanguageEvidence.analyze(
                text: region.text,
                detectedLanguage: region.validatedLanguage ?? region.detectedLanguage
            )
            guard !PolishSpanDetector.looksMixedScript(region.text),
                  evidence.validatedLanguageCode != nil else {
                cleanedRegions.append(region)
                passthroughCount += 1
                continue
            }

            let transformed = await PolishPipeline.transform(
                preprocessed: region.text,
                engine: engine,
                target: placeholderLanguage,
                mode: .auto,
                style: style,
                gate: gate,
                deadline: deadline
            )
            let transformedText = PolishPipeline.resolvedOutput(
                transformed,
                preprocessed: region.text,
                target: placeholderLanguage,
                mode: .auto
            )
            engineMs += transformed.engineMs
            postprocessMs += transformed.postprocessMs
            if transformed.outcome == .success {
                polishedCount += 1
            } else {
                passthroughCount += 1
            }
            if let failureReason = transformed.failureReason {
                lastFailure = failureReason
            }
            switch transformed.outcome {
            case .success:
                sawSuccess = true
            case .engineFailed:
                sawEngineFailure = true
            case .rejectedGuardrail, .exceededContextBudget:
                sawGuardrail = true
            case .cancelled:
                return Result(
                    text: floor,
                    outcome: .cancelled,
                    engineMs: engineMs,
                    postprocessMs: postprocessMs,
                    polishedSpanCount: polishedCount,
                    passthroughSpanCount: passthroughCount,
                    detectedLanguages: detectedLanguages,
                    failureReason: lastFailure
                )
            case .engineUnavailable:
                return Result(
                    text: floor,
                    outcome: .engineUnavailable,
                    engineMs: engineMs,
                    postprocessMs: postprocessMs,
                    polishedSpanCount: polishedCount,
                    passthroughSpanCount: passthroughCount,
                    detectedLanguages: detectedLanguages,
                    failureReason: lastFailure
                )
            case .skipped, .skippedShort, .skippedAutoMode:
                break
            }
            cleanedRegions.append(SpeechRegionTranscript(
                region: region.region,
                text: transformedText,
                detectedLanguage: region.detectedLanguage,
                validatedLanguage: region.validatedLanguage ?? evidence.validatedLanguageCode,
                overlapsPreviousRegion: region.overlapsPreviousRegion,
                decodeDurationSeconds: region.decodeDurationSeconds,
                averageLogProbability: region.averageLogProbability,
                fallbackReason: region.fallbackReason,
                languageEvidenceScore: region.languageEvidenceScore
            ))
        }

        let outcome: PolishMetrics.Outcome
        if sawSuccess {
            outcome = .success
        } else if sawEngineFailure {
            outcome = .engineFailed
        } else if sawGuardrail {
            outcome = .rejectedGuardrail
        } else {
            outcome = .skipped
        }
        return Result(
            text: cleanedRegions.count == 1 ? cleanedRegions[0].text : SpeechTranscriptMerger.merge(cleanedRegions),
            outcome: outcome,
            engineMs: engineMs,
            postprocessMs: postprocessMs,
            polishedSpanCount: polishedCount,
            passthroughSpanCount: passthroughCount,
            detectedLanguages: detectedLanguages,
            failureReason: lastFailure
        )
    }

}
