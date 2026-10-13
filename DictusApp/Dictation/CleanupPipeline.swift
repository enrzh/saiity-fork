import Foundation
import SyllivraKernel

/// The cleanup call used after transcription. `DictationCoordinator` stays the
/// facade; this type is the only place that asks `PolishCoordinator` to run.
enum CleanupPipeline {
    static func clean(
        raw: String,
        languagePolicy: TranscriptionLanguagePolicy,
        recordingDuration: TimeInterval,
        translationTarget: TranslationLanguage?,
        regions: [SpeechRegionTranscript],
        settings: PolishCoordinator.Settings? = nil,
        onEngineWillRun: (() -> Void)?
    ) async -> String {
        await PolishCoordinator.shared.polish(
            raw: raw,
            languagePolicy: languagePolicy,
            recordingDuration: recordingDuration,
            translationTarget: translationTarget,
            regions: regions,
            settings: settings,
            onEngineWillRun: onEngineWillRun
        )
    }
}
