# ASR catalog evaluation — 2026-09-12

No new model rows were added. The shared working tree already contained 23 unique
identifiers, including the compact exports below. Those preexisting entries and
Parakeet routing were preserved. Qwen is retired from the product runtime and
is not evaluated here. No weights were downloaded and no physical
device ASR benchmark was executed in this audit. Catalog gauges are editorial
estimates unless a specific measurement is cited, not comparable WER results.

## Official-source checks

Sources were inspected with ego-browser on 2026-09-12. Upstream `main` links can
change; capture exact artifact revisions and hashes for any subsequent benchmark.

| Existing option | Export and language evidence | Evaluation decision |
| --- | --- | --- |
| Small English compact, `openai_whisper-small.en_217MB` | [Argmax tree](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small.en_217MB), folder commit `b58713c`: encoder, decoder, mel `.mlmodelc` bundles and config; English only | Useful storage candidate, already present. Not a multilingual upgrade. |
| Compact Turbo, `openai_whisper-large-v3-v20240930_547MB` | [Argmax tree](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_547MB), folder commit `04e5c42`: same bundle layout, about 550 MB; [config](https://huggingface.co/argmaxinc/whisperkit-coreml/raw/main/openai_whisper-large-v3-v20240930_547MB/config.json) has four decoder layers and 128 mel bins | Multilingual storage candidate, already present. Quantization does not prove better accuracy or speed. |
| Medium English | [Argmax tree](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-medium.en), folder commit `ad3241c`, about 1.53 GB, same bundles | Already present; not compact. |
| Distil-large-v3 variants | [Official Distil model card](https://huggingface.co/distil-whisper/distil-large-v3) explicitly identifies the English series; MIT | Preserve the preexisting English-only metadata correction. A large-v3 ancestor does not confer multilingual support. |
| Parakeet v2/v3 | [v2 Core ML card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml), [v3 Core ML card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml), [NVIDIA v3 card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) | Existing FluidAudio adapters: v2 English only; v3 exactly 25 European languages, no Chinese. Preserve both. |

[Argmax's repository](https://huggingface.co/argmaxinc/whisperkit-coreml) declares MIT.
Its [device matrix](https://huggingface.co/argmaxinc/whisperkit-coreml/raw/main/config.json)
does **not** explicitly list the three preview exports above for iPhones. Bundle
layout compatibility is verified; iPhone load success and quality are not.
Existing experimental flags and RAM gates are not a certification.

Parakeet's weight license is CC-BY-4.0 according to NVIDIA and the conversion
metadata. The v3 conversion card's prose also says Apache 2.0 for FluidAudio;
do not substitute the SDK license for the upstream model's attribution terms.

## Reproducible smoke evaluation

`DictusCore/Tests/DictusCoreTests/Fixtures/asr-evaluation.json` contains original
recording prompts for English, German, French, Spanish, Mandarin and Japanese,
plus German/English and English/Mandarin switching. These are **text prompts**,
not recorded audio or benchmark results. Code switching is a stress test, not
a promised capability. Do not use this tiny corpus as a public model ranking.

1. Record each prompt verbatim with consent, keeping the same files for every
   model. Store 16 kHz mono audio and SHA-256 hashes; note speaker/accent and
   recording conditions separately. Do not regenerate speech per model.
2. In an app-hosted runner, use the existing `SpeechModelProtocol.prepare` and
   `transcribe(audioSamples:language:)` with `language: nil`. Capture raw output
   before postprocessing. Run one model at a time. Record load failures and empty
   outputs, device identifier, OS, app/runtime revision, artifact revision,
   cold load time, warm decode time, audio duration and peak memory. At least
   three warm repetitions are needed for latency medians; report cold separately.
3. Export a JSON object matching `ASREvaluation.CapturedRun` in
   `DictusCore/Sources/DictusCore/ASREvaluation.swift`. Required fields:
   `modelIdentifier`, `device`, `osVersion`, `modelRevision`,
   `runtimeRevision`, `audioSHA256` and `transcripts`.
   The last two fields are objects keyed by fixture ID. Include exactly the
   cases whose languages the selected model documents: English-only models get
   `en-reminder`; Parakeet v3 also gets de/fr/es and de-en. Whisper multilingual
   candidates get the documented multilingual fixtures.
   Use an empty transcript for a failed case and retain failure details in the
   run notes. Do not drop failures to improve the score. `ASREvaluation.emptyRun`
   builds the template; `ASREvaluation.validate` / `score` check it.
4. Score that captured file without loading weights:

```sh
cd /Users/enricomini/Documents/Github/sAiity-dictus/DictusCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer DICTUS_ASR_RESULTS=/absolute/path/run.json swift test --filter ASREvaluationTests
```

The existing XCTest resource mechanism handles the fixture; no package or app
target changes are required. Without `DICTUS_ASR_RESULTS`, the captured-run test
explicitly skips, while the fixture/scorer checks still run. This is an output
scorer integration only: an app-hosted audio runner remains outside this change.
The scorer checks hash syntax, not audio contents or device provenance.

Scoring uses NFC, lowercasing and punctuation-to-space normalization while
retaining accents and numbers. WER uses whitespace-separated tokens; CER uses
Swift grapheme clusters without whitespace, including the mixed CJK case.
Rates are edit distance / reference units and may exceed 1. No blended CER/WER
average is produced. These normalization rules differ from published FLEURS
and Whisper evaluations, so their percentages cannot be compared directly.

Promote a candidate only after the exact Core ML export loads on target iPhones
and improves measured accuracy, storage or latency against the existing Small,
Small Quantized, Turbo and appropriate FluidAudio baseline on identical audio.
