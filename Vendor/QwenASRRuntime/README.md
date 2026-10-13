# Qwen ASR runtime

The four library modules are copied from soniqo/speech-swift revision
`e8f459d9b3689fe324125eeaafcf2617799808a5`. The original Apache 2.0 license
is retained in LICENSE. Model checkpoints are downloaded separately by the app.

Local changes: annotate optional Core ML state APIs as iOS 18+/macOS 15+ while
the package remains linkable by the iOS 17 app; support cooperative cancellation
in both generation loops and wait for submitted GPU work before returning.
Qwen remains a foreground-only feature on compatible iOS 18+ phones.

This package contains no server/CLI/TTS targets or binary artifact dependencies.
Normal Xcode/SPM resolution builds it directly; no checkout patch is needed.
When updating, compare the four upstream modules against the recorded revision,
retain these small changes and run the cancellation, Core and signed-build checks.
