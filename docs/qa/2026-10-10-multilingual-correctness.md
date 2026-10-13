# Mobile multilingual correctness — 10 October 2026

This implements the seven requested mobile language priorities against clean
`cursor/keyboard-surface-fixes-a66e` at `0833fc2cab240757dd93b07d7ade419494524f0e`.
The desktop language plan supplied policy and examples, not mobile capability
claims. Existing build-240 delivery, cancellation, model receipts and keyboard
dictionary work was retained. Changes are local and uncommitted. The existing
TestFlight archive/export does not contain these changes.

## Behavior

- Speech evidence distinguishes writing systems from language. Kana/kanji,
  halfwidth kana and Korean/Han remain coherent; identifiers are ignored only
  for classification, and uppercase sentences remain sentences. Short/shared
  fragments and contradictory/shared Arabic or Serbian Cyrillic evidence stay
  uncertain. Clear local Japanese/Chinese or Hebrew/Arabic grammar can correct
  a stale tag.
- Mixed speech can occur inside one ASR region. Translation uses coherent
  clauses and strong same-script boundaries, with automatic source recognition
  for unresolved text. Cleanup revalidates region hints and preserves mixed or
  unknown text. It never treats missing language identity as no speech.
- Translation never reuses a rejected raw ASR tag. Source and output-script
  checks are separate. Explicit Simplified Chinese uses local ICU conversion
  for coherent Chinese and cannot be skipped on the shared `zh` prefix.
- The deterministic floor gates English grammar/restart/time rules on English
  evidence, and gates the existing French/German/Spanish rules by language.
  Unknown callers pass `language:nil`; Portuguese `a escola`, `um` and `hum`
  do not receive English article/filler rules. Existing whitespace and initial
  capitalization behavior remains. Content-word repetitions survive.
  Unhandled explicit languages also skip English name-correction and verbal
  punctuation rules. Bracketed identifiers remain content; only known ASR
  event markers are stripped.
- Each translation clause is checked for target language, untranslated grammar,
  identifiers, numeric values, amount/currency association, dates/times, negation
  and detectable omissions. Explicit parallel instructions get independent
  clauses. Combined validation retains clause-specific numeric locales and
  checks the complete target output. It never uses overlap merging to assemble
  translated text, so separators and repeated speech survive.
- Failure is all-or-original rather than a result mixing translated and fallback
  clauses. Cleanup and the grammar floor cannot rewrite a translation fallback.
  Originals remain available in existing recovery. Speak and the keyboard's
  result menu disclose fallback; timing metadata records `notRequested`,
  `accepted` or `originalKept:<reason>` without transcript content.
- Session/request/client checks remain in place. Host preparation, response,
  cancellation and timeout are checked against their request and pending ID;
  a late cancellation cannot cancel a newer pending translation.

## Separate capability evidence

| Path | Source-language evidence | Automatic input | Exposed audio-language tag | Translation/dictionary/quality distinction |
| --- | --- | --- | --- | --- |
| Classic multilingual Whisper | 99 tokenizer languages; no Cantonese token | Yes | Adapter exposes the Whisper result tag, subject to text validation | Source coverage is independent of the target menu and phone accuracy |
| large-v3 Whisper | Classic set plus `yue`; selected export still needs real evaluation | Yes | Same adapter | Upstream FLEURS tiers are references, not measurements of this export |
| English-only Whisper/Distil | English only | No multilingual Auto promise | Tag cannot expand model coverage | Existing English-only restrictions retained |
| Parakeet v2/v3 | v2 English; v3 declares 25 European languages | v3 automatic recognition; requested source parameter ignored | None in the current adapter/result | Existing restrictions retained; no inferred Chinese support |
| Qwen3-ASR | Existing candidate language list is not a verified complete set | Runtime accepts automatic input | Mobile adapter exposes no audio-language tag | Foreground, compatible physical iOS 18+ phone required; full coverage and quality remain unverified |
| Apple Translation | Current native pair availability after source recognition | Automatic source recognition when evidence is unresolved | Text recognition, not audio evidence | Existing 12 targets retained; Auto cannot promise that the actual source→target pair is installed |
| Keyboard | 12 selectable typing languages; bundled tries for en/de/fr/es | Typing/context policy, separate from ASR | Not applicable | Remaining typing dictionaries use system facilities; selected/spoken exact-word protection retained |

Pinned evidence checked locally, without weights or websites:

- WhisperKit `0.18.0`, revision `e2adabbe7d98dc4d0ab9a5b75424ecc42a9cdbef`:
  `Utilities/ModelUtilities.swift` distinguishes vocabularies 51864/51865/51866;
  `Core/Models.swift` supplies language tokens. The model catalog now filters
  `yue` for classic checkpoints.
- FluidAudio `0.12.4`, revision `9830ce835881c0d0d40f90aabfaae3a6da5bebfb`:
  `Documentation/Models.md` documents v2/v3 scope; the result/adapter does not
  supply a detected audio-language tag.
- `Vendor/QwenASRRuntime/README.md` records speech-swift
  `e8f459d9b3689fe324125eeaafcf2617799808a5`; existing MLX `0.30.6` and
  Transformers `1.1.9` pins and vendored runtime are unchanged. No fixed local
  checkpoint metadata established the complete advertised language set.

Qwen cards now identify Qwen and its foreground/hardware limits. Unpublished
Whisper reference results have a separate unmeasured group; model cards do not
claim measured phone accuracy. Auto translation checks pair readiness after
source recognition rather than taking an installed union over guessed sources.

## Verification checkpoint

Regressions were observed failing before behavior fixes: the initial 83-test
run had 35 assertion failures; later focused runs reproduced wrong-language,
currency association, localized numbers, Chinese variants, literal fallback,
parallel-instruction omissions and cancellation-identity failures.

Final Core command:

```sh
cd /Users/enrico/Documents/GitHub/sAiity-dictus/DictusCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

11 October completion: **1,938 tests executed, one existing skip, zero failures**.
This includes the existing selected/spoken dictionary, session-generation and
delivery tests.
The previous assertion allowing a strongly mixed region to use one cleanup
language was updated to require passthrough after revalidation.

App/keyboard/widget Debug simulator build succeeded with the pinned dependencies;
`codesign --verify --deep --strict` succeeded. Build products and command logs
are in `/tmp/saiity-mobile-language.nxZiwA/`. Local version remains 240; no new
archive, commit, push, upload or release mutation was made.

Final source checks on 11 October use `core-final.log`, `build-verified.log`,
`native-recovery-final.log` and `native-result-layout-final.log` in that directory.
The final build command was:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Dictus.xcodeproj -scheme DictusApp -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/saiity-mobile-language.nxZiwA/derived -disableAutomaticPackageResolution
codesign --verify --deep --strict /tmp/saiity-mobile-language.nxZiwA/derived/Build/Products/Debug-iphonesimulator/DictusApp.app
git diff --check
```

The app, keyboard and widget report build 240. These are local Debug simulator
products, separate from the preserved distribution archive/export. The October
9 readiness document describes its original checkpoint; later Git history
contains an upload-titled commit, which is not current Apple processing or
tester-availability evidence. This language pass performs no upload.

Native verification uses only `sAiity Product QA`
`3ED8FD55-D525-45D1-9E1A-4A1354000FC0`, iOS 26.5. SimSlim is unavailable;
no hAiity simulator, DeviceHub or phone is operated.
The final verification occurred with the existing hAiity simulator also booted;
only the dedicated sAiity device was operated (two simulators system-wide).
Native checks passed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/test-dictation-result-recovery.swift 3ED8FD55-D525-45D1-9E1A-4A1354000FC0 /tmp/saiity-mobile-language.nxZiwA/derived
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/test-multilingual-autocorrect.swift 3ED8FD55-D525-45D1-9E1A-4A1354000FC0 /tmp/saiity-mobile-language.nxZiwA/derived
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/render-product-results.swift 3ED8FD55-D525-45D1-9E1A-4A1354000FC0 /tmp/saiity-mobile-language.nxZiwA/derived
```

- Production keyboard delivery/recovery: Unicode and exact separators, truthful
  fallback menu, original restoration, field handoff, pending delivery and
  at-most-once notifications passed. The same native harness exercises iOS text
  evidence/cleanup/Chinese amount and script policies and the Qwen card wording.
- Production prediction: exact bilingual words, contextual protection,
  selected-language mixed fallback, scoped dictionary additions/removal, retained
  map reuse and rapid latest-request replacement passed.
- Shared production result component: 320/402-point widths at ordinary text and
  Accessibility 3/5 passed. Normal and largest-text renders were inspected for
  readable CJK/combining/RTL content and fallback-message wrapping. These are
  component layout checks, not complete physical-app visual verification.
  Images are saved under `derived/multilingual-result-renders/` so later runs do
  not depend on this particular scratch-directory name.

Simulator logs include an unavailable German system lexicon and a sysroot warning
from the script launcher. Bundled AOSP dictionary assertions and the native
executables passed; no phone dictionary quality or native translation inference
claim follows from those results.

## Remaining gates and limits

These guards are conservative text heuristics, not semantic equivalence or
measured multilingual accuracy. NaturalLanguage can return confidently wrong
shared-script readings. Names, locale-specific number/currency/date formats,
negation scope and language boundaries have long-tail ambiguity. Strict ISO-date
checks can reject a legitimate reformatted date/time; unsupported currency wording
can also cause recoverable fallback. Retained content is safer than a falsely
successful translation, and no heuristic pass establishes full meaning.

Still required: licensed or expressly consented recordings, independent native
source/target/meaning review, real Whisper/Parakeet/Qwen inference, Qwen load and
cancellation/foreground-loss/memory checks on compatible hardware, actual Apple
Translation asset availability/automatic recognition, and physical typing,
haptics, microphone/background delivery, Full Access, PiP and Live Activity
verification. Model coverage, transcript accuracy, cleanup quality, translation
quality and latency must be measured separately.

No weights were downloaded, room audio recorded, private transcripts accessed,
permissions changed or physical phone operated. Synthetic/unit/simulator results
do not close any of those gates.

The completion heartbeat was updated to this checkpoint, including the new QA
document, current local evidence and remaining gates. It remains active because
the accepted physical/model/release-verification gates are still open, and must
stay quiet on unchanged state rather than repeat passed checks.
