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

The October 13 selected-language follow-up below supersedes the earlier recommendation-only behavior of Spoken languages. Earlier evidence remains historical; the follow-up is local and uncommitted.

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

## October 13: selected spoken languages across recognizers

The user reported French in dictation with German, Chinese and English selected, then requested a fix across every model. Source inspection confirmed that Spoken languages only constrained recommendations; the per-dictation policy, batch recognition and Qwen streaming paths did not capture those choices. This pass changes the shared language path rather than requiring the user to identify one model.

`TranscriptionLanguagePolicy` now captures normalized spoken-language choices when a dictation is accepted. The snapshot survives engine fallback and scopes recognition through the existing task-local pattern. A single selected language reaches Whisper and Qwen as the source hint. Multiple selections preserve multilingual recognition; an empty selection keeps broad Auto.

Whisper keeps its ordinary decode when detection stays within the choices. An out-of-selection detection or confident outside-language clause gets one repair: an acoustic language-token prediction is ranked only among the selected candidates, followed by a fresh transcription prompt for that source. Regions remain independent. The repair adds an encoder pass only on this exceptional path; latency has not been measured on real recordings.

Qwen's existing decoder now selects its language prefix from the allowed language names before the text marker, using the same audio embeddings and cache. Prefix choices cannot generate an unselected header token path. The transcript still uses its existing greedy fast path and cooperative cancellation. Explicit source codes are converted to the model's English language names. Both batch and pause-based streaming use the captured selection.

Every model also shares the final recognition check before cleanup, translation and delivery. A confident unselected-language clause stops automatic delivery and retains the unverified recognition for manual review in the app. Short Latin fragments, names such as “François Dupont”, identifiers and uncertain evidence remain conservative; this is a text heuristic, not a claim that every foreign word can be identified. If cleanup introduces a confidently detected unselected language, the pipeline keeps the original recognized text. Explicit translation targets remain independent of spoken input languages.

Manual model selection can no longer bypass selected-language coverage at runtime. The existing resolver uses a compatible installed Whisper fallback where available, including for Qwen coverage mismatch. Without one, the existing recovery flow asks for a compatible model. No download starts from recognition or automated verification. Model selection preferences are preserved. Parakeet's source-language parameter remains ineffective; unsupported choices and confident unselected output are handled through these shared checks rather than inventing a language-forcing capability.

Evidence directory: `/tmp/saiity-selected-languages.CCNNf6`.

- `language-red.log`: two regressions failed with four assertions against the old behavior: a manual Parakeet model could ignore selected Chinese, and a single German selection never reached the Whisper/Qwen snapshot.
- `kernel-final.log`: 1,970 kernel tests and 41 inference tests passed, with one existing ASR-capture skip and zero failures. This includes selected-language isolation, continuous selected-language text, names, French clause rejection, compatible fallback, shared delivery-path ownership, cancellation and original recovery safeguards.
- `qwen-final.log`: all five native decoder tests passed, covering allowed prefix progression through multi-token names, termination at the text marker, exclusion of an unselected path, and existing cancellation checks. These use synthetic token/model data and do not evaluate Qwen speech accuracy.
- `simulator-build.log` and `device-build.log`: Debug simulator and signed Release iOS app/keyboard/widget builds succeeded with the existing pinned app dependencies. `simulator-signatures.log` and `device-verify.log` independently verify strict signatures. Device metadata remains 1.0.0 (243), Apple Development, team `H8FW6W6K2D`, and `group.de.aiity.saiity.ios.beta` on all three bundles.
- `app-fixture.log`: production app view bodies compiled and linked with inert dependencies, including the unverified-recognition disclosure. Rendering was not run.
- `git diff --check` and main-agent caller/source review passed. Prior app/Models/keyboard changes and Git recovery metadata are preserved. No commit, push, upload, release change, room audio, private-transcript access, model download or permission change occurred.

At this selected-language checkpoint, the signed development app was ready at `/tmp/saiity-kernel.2JRaLK/device/Build/Products/Release-iphoneos/DictusApp.app`. `phone-final.log` reported the paired iPhone Air unavailable, so the follow-up was not installed then. Earlier build-243 installations contained the preceding UI and keyboard work only. Existing same-bundle installation authorization remained available when the phone reconnected.

Real Whisper/Parakeet/Qwen speech accuracy, same-utterance language switches, full selected-language metadata, false-positive rates of the text guard, cleanup meaning preservation and latency still require licensed or expressly consented recordings and native-language review. Physical microphone/background delivery, Qwen memory/foreground loss, PiP/Live Activity and VoiceOver acceptance remain separate gates. Three other project simulators remain booted; the dedicated sAiity simulator was not booted or substituted, and no other project's simulator was operated.

### October 13 installation with the in-app rework

The phone reconnected during the subsequent in-app UI pass. The combined selected-language and UI source was rebuilt in Debug simulator and signed Release iOS configurations, verified for app/keyboard/widget signatures and version/team/App Group parity, and installed on the iPhone Air under the existing same-bundle authorization. Build number remains 1.0.0 (243); source remains local and uncommitted at baseline `4c2f6c8a`.

Evidence is in `/tmp/saiity-ui-rework.mH0fKP`. `install-result.json`, `installed-after.json` and `installation-identity-check.log` confirm the new installed bundle matches the installer receipt and the App Group container is unchanged. The application data-container path changed; private contents and migration were not inspected. The installed app was not launched for QA. See `docs/qa/2026-10-13-ui-refinement.md` for the UI scope and 230 passing focused checks. The unaffected full recognition/inference and Qwen decoder suites were not repeated; installation does not verify real speech accuracy or close the remaining physical/model gates above.

On October 14, the subsequent recorder/library redesign and explicit in-keyboard More action list were built and installed with the same selected-language source. Retained Release/build evidence is under `/private/tmp/codex-task.5naz10dj/artifacts` and independent installation evidence under `/private/tmp/codex-task.c4szcjd4/artifacts`. The new installed bundle matches its installer receipt and the App Group container is unchanged. This pass did not change recognition or processing owners or rerun the unaffected full speech suites. See the October 14 checkpoint in `docs/qa/2026-10-13-ui-refinement.md`; real speech and physical runtime gates remain unverified.
