import Foundation

/// A contiguous portion of a 16 kHz mono recording.
public struct SpeechRegion: Equatable, Sendable {
    public let startSample: Int
    public let endSample: Int

    public init(startSample: Int, endSample: Int) {
        self.startSample = startSample
        self.endSample = max(startSample, endSample)
    }

    public var sampleCount: Int { endSample - startSample }

    public func durationSeconds(sampleRate: Int = 16_000) -> Double {
        guard sampleRate > 0 else { return 0 }
        return Double(sampleCount) / Double(sampleRate)
    }
}

/// Coverage diagnostics for one segmented recording.
///
/// Leading and trailing silence is intentionally not treated as dropped speech.
/// `uncoveredWithinSpeechSpan` is the value that detects a real hole between two
/// decoded regions; `overlapSampleCount` detects duplicated work at boundaries.
public struct SpeechRegionCoverage: Equatable, Sendable {
    public let totalSampleCount: Int
    public let coveredSampleCount: Int
    public let overlapSampleCount: Int
    public let uncoveredSampleCount: Int
    public let uncoveredWithinSpeechSpan: Int
    public let firstCoveredSample: Int?
    public let lastCoveredSample: Int?

    public var hasDroppedSpeech: Bool { uncoveredWithinSpeechSpan > 0 }
    public var hasOverlap: Bool { overlapSampleCount > 0 }

    public init(regions: [SpeechRegion], totalSampleCount: Int) {
        let total = max(0, totalSampleCount)
        let normalized = regions.compactMap { region -> Range<Int>? in
            let start = min(total, max(0, region.startSample))
            let end = min(total, max(start, region.endSample))
            guard start < end else { return nil }
            return start..<end
        }.sorted { $0.lowerBound < $1.lowerBound }

        var unionLength = 0
        var summedLength = 0
        var currentStart: Int?
        var currentEnd: Int?

        for range in normalized {
            summedLength += range.count
            guard let activeStart = currentStart, let activeEnd = currentEnd else {
                currentStart = range.lowerBound
                currentEnd = range.upperBound
                continue
            }
            if range.lowerBound <= activeEnd {
                currentEnd = max(activeEnd, range.upperBound)
            } else {
                unionLength += activeEnd - activeStart
                currentStart = range.lowerBound
                currentEnd = range.upperBound
            }
        }
        if let activeStart = currentStart, let activeEnd = currentEnd {
            unionLength += activeEnd - activeStart
        }

        let first = normalized.first?.lowerBound
        let last = normalized.last?.upperBound
        let spanLength = if let first, let last { max(0, last - first) } else { 0 }

        self.totalSampleCount = total
        self.coveredSampleCount = unionLength
        self.overlapSampleCount = max(0, summedLength - unionLength)
        self.uncoveredSampleCount = max(0, total - unionLength)
        self.uncoveredWithinSpeechSpan = max(0, spanLength - unionLength)
        self.firstCoveredSample = first
        self.lastCoveredSample = last
    }
}

/// Finds speech regions using short-term energy and meaningful silence.
///
/// This is deliberately a small, deterministic boundary detector rather than a
/// second speech recognizer. WhisperKit still performs the authoritative language
/// detection for each returned region.
public struct SpeechRegionSegmenter: Sendable {
    public struct Configuration: Equatable, Sendable {
        public let sampleRate: Int
        public let frameDurationMilliseconds: Int
        public let silenceDurationMilliseconds: Int
        public let contextDurationMilliseconds: Int
        public let minimumRegionDurationMilliseconds: Int
        public let maximumRegionDurationMilliseconds: Int
        public let silenceRMS: Float
        public let noiseFloorMultiplier: Float
        public let noiseFloorMargin: Float
        public let speechReleaseMultiplier: Float

        public init(
            sampleRate: Int = 16_000,
            frameDurationMilliseconds: Int = 20,
            silenceDurationMilliseconds: Int = 350,
            contextDurationMilliseconds: Int = 200,
            minimumRegionDurationMilliseconds: Int = 800,
            maximumRegionDurationMilliseconds: Int = 10_000,
            silenceRMS: Float = 0.01,
            noiseFloorMultiplier: Float = 2.0,
            noiseFloorMargin: Float = 0.004,
            speechReleaseMultiplier: Float = 0.65
        ) {
            self.sampleRate = max(1, sampleRate)
            self.frameDurationMilliseconds = max(1, frameDurationMilliseconds)
            self.silenceDurationMilliseconds = max(1, silenceDurationMilliseconds)
            self.contextDurationMilliseconds = max(0, contextDurationMilliseconds)
            self.minimumRegionDurationMilliseconds = max(1, minimumRegionDurationMilliseconds)
            self.maximumRegionDurationMilliseconds = max(1, maximumRegionDurationMilliseconds)
            self.silenceRMS = max(0, silenceRMS)
            self.noiseFloorMultiplier = max(1, noiseFloorMultiplier)
            self.noiseFloorMargin = max(0, noiseFloorMargin)
            self.speechReleaseMultiplier = min(1, max(0, speechReleaseMultiplier))
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Returns no regions when the recording contains no detectable speech.
    /// Leading and trailing silence is omitted; every sample between region
    /// boundaries remains covered, with context shared at each boundary.
    public func regions(in samples: [Float]) -> [SpeechRegion] {
        guard !samples.isEmpty else { return [] }

        let frameSize = samplesPerMilliseconds(configuration.frameDurationMilliseconds)
        let silenceFrames = max(
            1,
            Int(ceil(Double(configuration.silenceDurationMilliseconds)
                / Double(configuration.frameDurationMilliseconds)))
        )
        let frameRMS = makeFrameRMS(samples: samples, frameSize: frameSize)
        let activeFrames = makeActivityMap(frameRMS: frameRMS)
        guard let firstActive = activeFrames.firstIndex(of: true),
              let lastActive = activeFrames.lastIndex(of: true) else {
            return []
        }

        let speechStart = firstActive * frameSize
        let speechEnd = min(samples.count, (lastActive + 1) * frameSize)
        let minimumSamples = samplesPerMilliseconds(configuration.minimumRegionDurationMilliseconds)
        let maximumSamples = samplesPerMilliseconds(configuration.maximumRegionDurationMilliseconds)
        let contextSamples = samplesPerMilliseconds(configuration.contextDurationMilliseconds)
        // Context belongs to the decoded region too. Reserve room for it on
        // both sides of hard cuts so the configured maximum is a true upper
        // bound for the samples sent to WhisperKit.
        let maximumDecodedSamples = max(
            maximumSamples,
            minimumSamples + (2 * contextSamples)
        )
        let maximumCoreSpan = max(
            minimumSamples,
            maximumDecodedSamples - (2 * contextSamples)
        )

        var silenceCuts: [Int] = []
        var frame = firstActive
        while frame <= lastActive {
            guard !activeFrames[frame] else {
                frame += 1
                continue
            }

            let runStart = frame
            while frame <= lastActive && !activeFrames[frame] {
                frame += 1
            }
            let runLength = frame - runStart
            guard runLength >= silenceFrames else { continue }

            let midpointFrame = runStart + runLength / 2
            let cut = min(speechEnd, midpointFrame * frameSize)
            if cut > speechStart && cut < speechEnd {
                silenceCuts.append(cut)
            }
        }

        // Walk every natural silence boundary first. When the next boundary is
        // too far away, insert a hard cut before it and continue from there.
        // Candidate boundaries that would leave a tiny region are skipped, so
        // short speech islands are absorbed by their neighbor. If the final
        // remainder after a hard cut would be tiny, move that cut backwards to
        // keep the final decode reliable.
        var coreBoundaries = [speechStart]
        var cursor = speechStart
        var nextSilenceIndex = 0
        while cursor < speechEnd {
            while nextSilenceIndex < silenceCuts.count {
                let candidate = silenceCuts[nextSilenceIndex]
                guard candidate - cursor >= minimumSamples,
                      speechEnd - candidate >= minimumSamples else {
                    nextSilenceIndex += 1
                    continue
                }
                break
            }

            let nextSilence = nextSilenceIndex < silenceCuts.count
                ? silenceCuts[nextSilenceIndex]
                : speechEnd
            let maximumCut = min(speechEnd, cursor + maximumCoreSpan)
            let cut: Int

            if nextSilence <= maximumCut {
                cut = nextSilence
                nextSilenceIndex += 1
            } else if maximumCut < speechEnd && speechEnd - maximumCut < minimumSamples {
                cut = max(cursor + minimumSamples, speechEnd - minimumSamples)
            } else {
                cut = maximumCut
            }

            guard cut > cursor else { break }
            coreBoundaries.append(cut)
            cursor = cut
        }

        return coreBoundaries.indices.dropLast().map { index in
            let coreStart = coreBoundaries[index]
            let coreEnd = coreBoundaries[index + 1]
            let start = index == 0 ? coreStart : max(speechStart, coreStart - contextSamples)
            let end = index == coreBoundaries.count - 2
                ? coreEnd
                : min(speechEnd, coreEnd + contextSamples)
            return SpeechRegion(startSample: start, endSample: end)
        }
    }

    private func samplesPerMilliseconds(_ milliseconds: Int) -> Int {
        max(1, Int((Double(configuration.sampleRate) * Double(milliseconds) / 1_000).rounded()))
    }

    private func makeFrameRMS(samples: [Float], frameSize: Int) -> [Float] {
        stride(from: 0, to: samples.count, by: frameSize).map { start in
            let end = min(samples.count, start + frameSize)
            let count = end - start
            guard count > 0 else { return 0 }

            var sum: Double = 0
            for sample in samples[start..<end] {
                let value = Double(sample)
                sum += value * value
            }
            let rms = sqrt(sum / Double(count))
            return Float(rms)
        }
    }

    private func makeActivityMap(frameRMS: [Float]) -> [Bool] {
        guard !frameRMS.isEmpty else { return [] }

        // Use the quietest tenth of the recording as a local noise estimate. The
        // fixed floor remains the lower bound, so clean recordings keep the old
        // behavior while noisy microphones get a higher speech boundary.
        let sortedRMS = frameRMS.sorted()
        let quietCount = max(1, Int(ceil(Double(sortedRMS.count) * 0.1)))
        let noiseFloor = sortedRMS[min(sortedRMS.count - 1, quietCount - 1)]
        let rawAdaptiveThreshold = max(
            configuration.silenceRMS,
            max(
                noiseFloor * configuration.noiseFloorMultiplier,
                noiseFloor + configuration.noiseFloorMargin
            )
        )
        // A recording can contain speech continuously, so its quietest frames
        // may still be speech. Keep the adaptive threshold below a useful
        // fraction of the observed signal instead of classifying that entire
        // recording as silence.
        let signalCeiling = max(
            configuration.silenceRMS,
            (frameRMS.max() ?? configuration.silenceRMS) * 0.4
        )
        let adaptiveThreshold = min(rawAdaptiveThreshold, signalCeiling)
        let startThreshold = Double(adaptiveThreshold)
        let releaseThreshold = startThreshold
            * Double(configuration.speechReleaseMultiplier)

        var speechActive = false
        return frameRMS.map { rms in
            let threshold = speechActive ? releaseThreshold : startThreshold
            speechActive = Double(rms) >= threshold
            return speechActive
        }
    }
}

/// Output from one independent speech-region decode.
public struct SpeechRegionTranscript: Equatable, Sendable {
    public let region: SpeechRegion
    public let text: String
    public let detectedLanguage: String?
    /// A script-validated language token. The raw detector result above is
    /// retained for diagnostics, but cleanup and translation should use this
    /// value so short or incompatible detections cannot relabel a region.
    public let validatedLanguage: String?
    public let overlapsPreviousRegion: Bool
    /// Optional decode diagnostics. These remain nil for compatibility
    /// decoders that only return text.
    public let decodeDurationSeconds: Double?
    public let averageLogProbability: Double?
    public let fallbackReason: String?
    /// Script-aware consistency score for the detected Whisper language.
    /// Optional so non-Whisper engines keep their existing metadata contract.
    public let languageEvidenceScore: Double?

    public var characterCount: Int { text.count }

    public init(
        region: SpeechRegion,
        text: String,
        detectedLanguage: String? = nil,
        validatedLanguage: String? = nil,
        overlapsPreviousRegion: Bool = false,
        decodeDurationSeconds: Double? = nil,
        averageLogProbability: Double? = nil,
        fallbackReason: String? = nil,
        languageEvidenceScore: Double? = nil
    ) {
        self.region = region
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.validatedLanguage = validatedLanguage
        self.overlapsPreviousRegion = overlapsPreviousRegion
        self.decodeDurationSeconds = decodeDurationSeconds
        self.averageLogProbability = averageLogProbability
        self.fallbackReason = fallbackReason
        self.languageEvidenceScore = languageEvidenceScore
    }
}

/// Runs region decodes one at a time and checks cancellation between them.
/// The decoder receives an ArraySlice so the caller does not need to copy the
/// complete recording for every region.
public enum SpeechRegionTranscriptionRunner {
    public static func run(
        audioSamples: [Float],
        segmenter: SpeechRegionSegmenter = SpeechRegionSegmenter(),
        decode: @escaping @Sendable (ArraySlice<Float>, SpeechRegion) async throws -> SpeechRegionTranscript
    ) async throws -> [SpeechRegionTranscript] {
        let regions = segmenter.regions(in: audioSamples)
        return try await run(audioSamples: audioSamples, regions: regions) { _, slice, region in
            try await decode(slice, region)
        }
    }

    /// Runs an already computed region list and exposes the stable region index
    /// to instrumentation without recalculating the activity map.
    public static func run(
        audioSamples: [Float],
        regions: [SpeechRegion],
        decode: @escaping @Sendable (Int, ArraySlice<Float>, SpeechRegion) async throws -> SpeechRegionTranscript,
        onRegion: (@Sendable (SpeechRegionTranscript) -> Void)? = nil
    ) async throws -> [SpeechRegionTranscript] {
        var results: [SpeechRegionTranscript] = []
        results.reserveCapacity(regions.count)

        for (index, region) in regions.enumerated() {
            try Task.checkCancellation()
            let slice = audioSamples[region.startSample..<region.endSample]
            let decoded = try await decode(index, slice, region)
            try Task.checkCancellation()
            let result = SpeechRegionTranscript(
                region: decoded.region,
                text: decoded.text,
                detectedLanguage: decoded.detectedLanguage,
                validatedLanguage: decoded.validatedLanguage,
                overlapsPreviousRegion: index > 0
                    && region.startSample < regions[index - 1].endSample,
                decodeDurationSeconds: decoded.decodeDurationSeconds,
                averageLogProbability: decoded.averageLogProbability,
                fallbackReason: decoded.fallbackReason,
                languageEvidenceScore: decoded.languageEvidenceScore
            )
            results.append(result)
            onRegion?(result)
        }
        return results
    }
}

/// Deterministically joins independently decoded regions without an LLM.
public enum SpeechTranscriptMerger {
    public static func merge(_ regions: [SpeechRegionTranscript]) -> String {
        regions.reduce(into: "") { output, region in
            output = mergePair(output, region.text, allowOverlap: region.overlapsPreviousRegion)
        }
    }

    public static func merge(_ texts: [String]) -> String {
        texts.reduce(into: "") { output, text in
            output = mergePair(output, text, allowOverlap: false)
        }
    }

    private struct Token {
        let text: String
        let key: String
        let cjkContext: Bool
        let punctuation: Bool
    }

    private static func mergePair(_ left: String, _ right: String, allowOverlap: Bool) -> String {
        let leftTokens = tokenize(left)
        var rightTokens = tokenize(right)
        guard !rightTokens.isEmpty else { return render(leftTokens) }
        guard !leftTokens.isEmpty else { return render(rightTokens) }

        if allowOverlap {
            let overlapCount = matchingSuffixPrefixCount(leftTokens, rightTokens)
            if overlapCount > 0 {
                let significant = rightTokens.indices.filter { !rightTokens[$0].key.isEmpty }
                if let lastDropped = significant.dropFirst(overlapCount - 1).first {
                    let suffix = Array(rightTokens.dropFirst(lastDropped + 1))
                    rightTokens = removeDuplicateBoundaryPunctuation(
                        suffix,
                        after: leftTokens
                    )
                }
            }
        }

        return render(leftTokens + rightTokens)
    }

    private static func matchingSuffixPrefixCount(_ left: [Token], _ right: [Token]) -> Int {
        let leftSignificant = left.indices.filter { !left[$0].key.isEmpty }
        let rightSignificant = right.indices.filter { !right[$0].key.isEmpty }
        let limit = min(8, min(leftSignificant.count, rightSignificant.count))
        guard limit > 0 else { return 0 }

        for count in stride(from: limit, through: 1, by: -1) {
            let leftKeys = leftSignificant.suffix(count).map { left[$0].key }
            let rightKeys = rightSignificant.prefix(count).map { right[$0].key }
            guard leftKeys == rightKeys else { continue }
            // Do not erase one-character Latin words such as "I" or "a"
            // solely because two overlapping decodes happened to contain them.
            // A single CJK character is a meaningful speech token and may be
            // the complete overlap at a region boundary.
            if count == 1,
               let leftIndex = leftSignificant.last,
               !left[leftIndex].cjkContext,
               let key = leftKeys.first,
               key.count < 2 {
                continue
            }
            return count
        }
        return 0
    }

    private static func tokenize(_ text: String) -> [Token] {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var tokens: [Token] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\n" {
                tokens.append(Token(text: "\n", key: "", cjkContext: false, punctuation: false))
                index += 1
                continue
            }
            if character.isWhitespace {
                index += 1
                continue
            }
            if isCJKContext(character) {
                let value = String(character)
                tokens.append(Token(
                    text: value,
                    key: isPunctuation(character) ? "" : value,
                    cjkContext: true,
                    punctuation: isPunctuation(character)
                ))
                index += 1
                continue
            }
            if isPunctuation(character) {
                tokens.append(Token(text: String(character), key: "", cjkContext: false, punctuation: true))
                index += 1
                continue
            }

            var end = index + 1
            while end < characters.count {
                let next = characters[end]
                guard !next.isWhitespace,
                      next != "\n",
                      !isCJKContext(next) else { break }
                if isPunctuation(next) && !isInternalWordPunctuation(
                    next,
                    previous: characters[end - 1],
                    next: end + 1 < characters.count ? characters[end + 1] : nil
                ) {
                    break
                }
                end += 1
            }
            let value = String(characters[index..<end])
            tokens.append(Token(
                text: value,
                key: value.lowercased(),
                cjkContext: false,
                punctuation: false
            ))
            index = end
        }
        return tokens
    }

    private static func render(_ tokens: [Token]) -> String {
        var output = ""
        var previous: Token?
        for token in tokens {
            guard !token.text.isEmpty else { continue }

            if token.text == "\n" {
                output += token.text
                previous = nil
                continue
            }

            if let previous, needsSpace(before: token, after: previous) {
                output += " "
            }
            output += token.text
            previous = token
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func needsSpace(before token: Token, after previous: Token) -> Bool {
        guard !token.punctuation else { return false }
        guard previous.text != "\n" else { return false }
        if token.cjkContext || previous.cjkContext {
            return false
        }
        if previous.punctuation {
            return !isOpeningPunctuation(previous.text)
                && !isWordJoiningPunctuation(previous.text)
        }
        return true
    }

    private static func removeDuplicateBoundaryPunctuation(
        _ suffix: [Token],
        after left: [Token]
    ) -> [Token] {
        var result = suffix
        let leftTrailing = trailingPunctuation(in: left)
        guard !leftTrailing.isEmpty else { return result }

        let rightLeading = result.prefix { $0.punctuation }.map(\.text)
        var duplicateCount = 0
        while duplicateCount < leftTrailing.count,
              duplicateCount < rightLeading.count,
              leftTrailing[duplicateCount] == rightLeading[duplicateCount] {
            duplicateCount += 1
        }
        guard duplicateCount > 0 else { return result }

        result.removeFirst(min(duplicateCount, result.count))
        return result
    }

    private static func trailingPunctuation(in tokens: [Token]) -> [String] {
        var result: [String] = []
        for token in tokens.reversed() {
            guard token.punctuation else { break }
            result.append(token.text)
        }
        return result.reversed()
    }

    private static func isInternalWordPunctuation(
        _ character: Character,
        previous: Character,
        next: Character?
    ) -> Bool {
        // Keep numeric and address punctuation inside its original token.
        if character == ",", previous.isNumber, next?.isNumber == true { return true }
        let addressPunctuation = ".:@/_%&=?#"
        if addressPunctuation.contains(character), let next,
           previous.isLetter || previous.isNumber || addressPunctuation.contains(previous),
           next.isLetter || next.isNumber || addressPunctuation.contains(next) {
            return true
        }
        guard "'\u{2019}\u{2027}-\u{2010}\u{2011}".contains(character),
              previous.isLetter,
              next?.isLetter == true else {
            return false
        }
        return true
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        String(character).rangeOfCharacter(from: .punctuationCharacters) != nil
    }

    private static func isCJKContext(_ character: Character) -> Bool {
        let cjkPunctuation = "，。！？；：、（）「」『』【】《》〈〉"
        if cjkPunctuation.contains(character) { return true }
        return character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xAC00...0xD7AF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private static func isOpeningPunctuation(_ value: String) -> Bool {
        "([{\"\u{201C}\u{2018}（【《〈「『".contains(value)
    }

    private static func isWordJoiningPunctuation(_ value: String) -> Bool {
        "'\u{2019}\u{2027}-\u{2010}\u{2011}".contains(value)
    }
}
