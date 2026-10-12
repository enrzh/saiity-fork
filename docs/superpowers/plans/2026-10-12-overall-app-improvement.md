# sAiity Overall App Improvement Plan

> **Status: implementation authorized on October 12 and completed locally.** See the [implementation checkpoint](../../qa/2026-10-12-app-improvement.md) for changes, evidence, the preserved English-only UI policy and remaining device/accessibility/online gates. No phone operation or release action is authorized. The heartbeat must inspect this checkpoint before resuming only unfinished authorized work.

**Goal:** Make everyday dictation, text recovery and configuration easier to understand while preserving sAiity's keyboard feel and multilingual safety.

**Architecture:** Keep the current SwiftUI app, UIKit keyboard, shared DictusCore contracts and ActivityKit widgets. Edit the existing view owners and reuse their state and controls. No new Manager, Service, Factory, Coordinator, protocol layer, dependency or backend is proposed.

**Tech stack:** SwiftUI, UIKit, DictusCore, the existing Whisper/Parakeet/Qwen integrations, native Apple Translation and ActivityKit. iOS 17 remains the app minimum; individual engines retain their existing hardware, OS and foreground restrictions.

## Verified baseline and limits

Planning inspection on October 12, 2026 found a clean checkout on `cursor/keyboard-surface-fixes-a66e`, HEAD `963186e7`. History contains `963186e7 Ship build 241 to TestFlight`, `55737f79 WIP before TestFlight build 241`, and `0833fc2c Ship build 240 to TestFlight`. Those titles establish local history; they do not verify current Apple processing, tester availability or an installed phone build.

The October 10–11 multilingual pass is already committed. Its recorded checkpoint is 1,938 Core tests, one existing skip and zero failures, plus an app/keyboard/widget simulator build and native dictionary, recovery and result-layout checks. These results are historical evidence from `docs/qa/2026-10-10-multilingual-correctness.md`, not checks rerun for this plan. `docs/testflight-240-readiness.md` is historical preparation; its old local/upload statements must not be repeated as current release status. The preserved build 240 archive predates the later language changes.

This review used current source and existing QA documentation. It did not inspect a fresh complete app render or operate the phone. Hierarchy and discoverability findings below are grounded in view structure; physical quality and final visual judgments remain acceptance work.

## Global constraints

- Preserve user edits, untracked files, App Group preferences, model receipts and Git recovery metadata.
- Keep Speak and Settings as the two top-level tabs. Retain the blue voice mark and system typography.
- Preserve independent app/keyboard models, manual selections, Realtime text, cleanup/output/tone choices and selected/spoken-language dictionary protections.
- Keep native touch/scroll owners. Visible key plates and expanded touch rectangles remain separate; decoration never intercepts touches.
- Do not move recognition into the keyboard extension or change its memory budget. Model compatibility comes from current runtime capability metadata, not old architecture prose.
- Keep microphone, Full Access, installed-model and host-readiness checks distinct. Enabling keyboard dictation can warm the microphone session; explain standby microphone use separately from recording and saving dictated words.
- Recognition evaluation requires licensed or expressly consented files. No room audio, private transcripts, model downloads or permission changes during automated QA.
- Main owns serial project builds, tests and native inference. No duplicate workers, concurrent builds or Luna agents. Use bounded `sub2api/gpt-6.1-sol` only if a review warrants it.
- Reuse sAiity Product QA `3ED8FD55-D525-45D1-9E1A-4A1354000FC0`; prefer SimSlim when available. Do not operate hAiity's simulator or DeviceHub, and never exceed two booted simulators.
- Websites use Chrome Use and desktop interactions use Computer Use, with Chrome. This supersedes old ego-browser instructions. Report unavailable tools instead of substituting them. Use authorized password-manager autofill without reading credentials or cookies.
- No commits, pushes, uploads, publishing, release changes or tester invitations are authorized by this plan. Phone operation or installation requires explicit direction.

## Design direction and review

sAiity is a multilingual writing utility for people moving between speech and text fields. Its defining moment is the blue three-bar voice signal becoming useful, editable text. Give the words most of the screen; keep navigation, readiness and configuration quiet and native.

The recommended approach is an incremental refinement of the existing two-tab product. A cosmetic pass alone would leave model decisions and recovery explanations scattered. A full navigation/keyboard rewrite would expand risk without solving a missing capability. The incremental approach addresses those decisions in the current owners and can be accepted phase by phase.

Source review rating: **Needs work on hierarchy and discoverability.** No measured Critical accessibility failure is asserted from source alone.

| Priority | Source observation | Proposed change and reason |
| --- | --- | --- |
| High | Speak has a native large navigation title and a second `.largeTitle` readiness headline. | Use one navigation title and a `.title2` task/readiness heading. Give results more space; `layout.md › Best practices` says to give essential information sufficient space. |
| High | Recommendations and app/keyboard choices appear in Voice options and again at the top of Models. Recommended models can also repeat in catalog sections. | Keep one contextual configuration flow; make Models the inventory/download screen. `settings.md › Best practices`: "Minimize the number of settings you offer." |
| High | The Live Activity renders a transcript preview with `.privacySensitive()`. | Make system activity status-only and review all presentations on a phone. The current annotation is a safeguard, not proof that private text is always hidden. `live-activities.md › Best practices`: "Avoid displaying sensitive information." |
| Medium | Model descriptions use two-line limits; download metadata occupies a fixed-height region. | Let restrictions and progress text wrap at accessibility sizes. `typography.md › Supporting Dynamic Type`: "Keep text truncation to a minimum as font size increases." |
| Medium | Vocabulary hint approval/removal is primarily a context-menu action beside a long explanatory footer. | Expose a labeled native row action and shorten the explanation without weakening explicit approval. This is a discoverability judgment. |
| Medium | Recording, result, recovery and widget surfaces have separate text/layout owners. | Use the existing state mappings to align names, action order and fallback explanations; do not add a new state architecture. |

What works: the two tabs, native grouped Settings, bottom primary action, scoped voice-model choices, explicit recommended-settings action, persistent downloader ownership, result/original recovery, and native keyboard routing. Preserve them.

Craft critique: a repeated hero, card grid, new font and decorative gradient would obscure the words. The design therefore concentrates identity in the existing voice signal and action color. Remove the duplicated large headline and duplicated recommendation block; do not add another signature element.

## Visual specification

### Color roles

The following six roles define the palette. System-color hex values are **design reference snapshots**, not measured values from this runtime and not constants to hard-code. Keep UIKit semantic APIs so appearance and contrast traits remain dynamic. Brand hex values are rounded from the current source RGB values.

| Role | Light reference | Dark reference | Use and contrast |
| --- | --- | --- | --- |
| Canvas | `#FFFFFF` | `#000000` | `systemBackground`; primary ink against canvas is 21.00:1 in these reference pairs. |
| Reading surface | `#F2F2F7` | `#1C1C1E` | `secondarySystemBackground`; primary ink is 18.82:1 / 17.01:1. Settings retain grouped-background equivalents. |
| Primary ink | `#000000` | `#FFFFFF` | `.primary` / `label` for words, status and essential restrictions. Secondary labels remain semantic and require rendered contrast review. |
| Voice action | `#245DE3` | `#8CADFF` | Current `saiityAction`. Computed on-action contrast from exact source RGB is 5.60:1 / 7.80:1. |
| On voice action | `#FFFFFF` | `#101A35` | Current `saiityOnAction`, paired with the action fill. Increased-contrast source variants reach 7.45:1 / 9.95:1. |
| Recording signal | `#FF3B30` | `#FF453A` | `systemRed` as a dot/icon plus a primary-color Listening label. Reference signal contrast is 3.55:1 on white / 4.99:1 on dark reading surface; do not use the light red for small essential text. |

Contrasts use the WCAG sRGB relative-luminance formula. They apply to the listed opaque pairs, not translucent material, disabled controls or sampled screens. Require 4.5:1 for ordinary text and 3:1 for qualifying large text and essential non-text signals in rendered states. Preserve semantic success/error colors, pairing them with text and symbols.

### Type and layout

Use SF system styles and native language fallback; add no font. Default sizes below describe the ordinary Large category and must scale with Dynamic Type.

| Role | SwiftUI style | Default size and weight |
| --- | --- | --- |
| Navigation title | Native navigation title | System large title on Speak; inline titles on settings/detail screens. |
| Main task/result heading | `.title2` | 22 pt, semibold; one per workspace. |
| Group/action label | `.headline` | 17 pt, semibold. |
| Transcript and explanation | `.body` | 17 pt, regular; primary ink for important text. |
| Supporting detail | `.subheadline` / `.footnote` | 15 / 13 pt, regular; optional detail only. |
| Timer/download byte count | Existing style with `.monospacedDigit()` | Preserve digit alignment without introducing a monospace text face. |

Keep leading alignment and system RTL behavior. Use the current 24 pt main-page horizontal inset and 640 pt reading-width cap; use 8/12/16/24/32 pt gaps according to grouping. Keep the existing 58 pt minimum primary action and 20 pt radius. Other app controls need at least 44 by 44 pt; they may grow vertically. At large text sizes, stack metadata and actions, wrap restrictions, and permit scrolling rather than shrinking type.

For the keyboard, preserve `KeyGridPlacement`'s current 45 pt preferred plates, 9 pt row gap, 5.5 pt key gap, 6.5 pt edge inset and 8 pt key radius. Actual constrained heights and touch rectangles continue to come from the solver. Preserve `CommandKeyStyle` separately. These are current source constants, not proof of native-system parity or physical feel.

Use native navigation/sheets and their platform materials. Keep transcript, settings and model content on semantic solid surfaces. Respect Reduce Transparency and Reduce Motion; no ambient pulse while idle. While listening, reuse `SaiityVoiceSignal`; when recording ends, a brief state transition may explain the change without animation of every row.

### Compact Speak wireframe

```text
┌─────────────────────────────────┐
│ Speak                native nav │
│ Keyboard dictation        [Off] │
│                                 │
│ New dictation                   │
│ Your text appears when finished │
│ [Voice options                 ]│
│ Languages and active voice mode │
│                                 │
│ Your words             See all  │
│ Last finished text or a         │
│ truthful history empty state    │
│ [Copy] [Edit] [More]            │
│                                 │
│ [     blue Start dictation    ] │
│ Speak                  Settings │
└─────────────────────────────────┘
```

### Wide window or landscape wireframe

```text
┌───────────────────────────────────────────────────────────┐
│ Speak                                                     │
│          ┌──── one centered reading column ─────┐          │
│          │ Keyboard dictation            [Off] │          │
│          │ New dictation                      │          │
│          │ [Voice options]                    │          │
│          │ Your words                See all  │          │
│          │ Text wraps within the 640 pt cap    │          │
│          │ [Copy] [Edit] [More]               │          │
│          └────────────────────────────────────┘          │
│              [       Start dictation       ]             │
│ Speak                                           Settings │
└───────────────────────────────────────────────────────────┘
```

Keep one adaptable content column. A new sidebar or multicolumn editor is unnecessary. At low landscape heights, scroll the body and reduce expendable spacing; keep the bottom action and tab safe areas usable. RTL mirrors leading/trailing layout, not transcript content or numeric semantics.

## State and action specification

Use current readiness/state objects. The table is a presentation contract, not a proposal for a new enum or coordinator.

| State | Visible message | Primary action | Safety rule |
| --- | --- | --- | --- |
| Ready | New dictation; current language/mode summary | Start dictation | No microphone capture from simply opening Speak or applying advice. |
| Microphone denied | Microphone access is off | Existing Open Settings action | Do not repeatedly request a denied permission or claim Ready. |
| No usable model | A voice model is needed | Choose a model | Installation is an explicit separate action. |
| Downloading/preparing | Existing model name and truthful progress | Existing cancel/recovery control | Do not fabricate a percentage for indeterminate loading. |
| Listening | Listening; elapsed time and existing voice signal | Finish | Cancel remains separate. Listening marks dictation recording; standby microphone use must remain explicit. |
| Transcribing/processing | Preparing your text / Finishing your text | Existing cancellation action | Keep request identity; late callbacks cannot publish new text. |
| Result ready | Editable finished text | Copy in app; Insert in the originating keyboard field | Do not duplicate insertion or send text to a changed field. |
| Translation/cleanup fallback | Original kept, with the actual reason | Copy/Insert original | Keep exact original and existing recovery; never label it as successful translation. |
| No speech/failure | Current specific problem and next action | Try again or the relevant recovery action | Preserve any recoverable original/result. |

Expose Copy, Edit and the existing More/original actions with plain labels. Keep feedback next to the action and preserve the result; avoid timed banners as the only record of a failure or fallback. A disabled action must have an adjacent reason. Reuse existing app and keyboard result components so every presentation tells the same truth.

## Phased implementation proposal

Paths below are repository-relative to `/Users/enrico/Documents/GitHub/sAiity-dictus`. They identify existing owners. An implementation pass must inspect current callers before editing and may omit a listed file when its contract does not change.

### Phase 1 — Accessibility and system privacy

**Files:** `DictusApp/Views/ModelCardView.swift`, `HomeView.swift`, `RecordingView.swift`, `SettingsView.swift`; `DictusWidgets/DictusLiveActivity.swift`; existing `DictusApp/LiveActivityManager.swift` and Core activity mapping only if removing preview payload requires them.

**Consumes:** current semantic colors, Dynamic Type environment, state labels and ActivityKit content state. **Produces:** readable controls and status-only system activities without a new shared schema.

- [ ] Capture the touched production views using fabricated text at smallest supported width, ordinary text and Accessibility 5, light/dark, increased contrast and reduced transparency. Establish actual clipping/contrast defects before changing layout.
- [ ] Replace accessibility-size model-summary truncation and fixed-height progress text with wrapping/stacking in the existing view. Keep explicit Qwen, language and foreground restrictions visible at normal and large sizes.
- [ ] Keep every primary/recovery action reachable by VoiceOver with an action-specific name, logical reading order and at least 44 pt non-keyboard hit targets. Do not solve text fit by clamping app Dynamic Type.
- [ ] Remove transcript preview from system Live Activity presentations and avoid sending unused preview content there. Preserve Listening, processing, Ready, power and recovery actions. Review callers before changing payload population; no new privacy toggle is needed.

**Acceptance:** no clipped essential text/actions at Accessibility 5; contrast meets the stated thresholds for actual rendered pairs; Reduce Motion/Transparency remain usable; Live Activity source contains no rendered transcript. Its real Lock Screen, Island, power and OS-limited text behavior remain a separate physical gate.

### Phase 2 — Speak and result workspace

**Files:** `DictusApp/Views/HomeView.swift` (`HomeView`, `DictationTranscriptResult`, history components), `DictusCore/Sources/DictusCore/Design/SaiityVoiceControls.swift` only for shared action consistency; `DictusApp/Views/RecordingView.swift` for any shared result caller affected.

**Consumes:** `currentReadiness`, current history settings, `DictationTranscriptResult`, existing copy/edit/original actions. **Produces:** one hierarchy and a consistent result action order.

- [ ] Keep the native Speak title and reduce the routine readiness heading to `.title2.weight(.semibold)`; retain state-specific explanations and recovery actions.
- [ ] Keep keyboard power compact and separate from app readiness. Explain that On prepares the microphone for keyboard dictation while starting a dictation is separate; show preparing/available from current session state rather than assuming On means ready. Join the Voice options entry with a concise factual language/mode summary; suppress unrelated model/download explanations while ready.
- [ ] Give the most recent result a readable text region and stable Copy/Edit/More actions. Keep See all as navigation; do not add a History tab or another dashboard card.
- [ ] Make empty-state wording match history retention: an empty enabled history invites a dictation; disabled history does not promise that results are saved.
- [ ] Keep exact-original/fallback disclosure visible and original recovery reachable. Preserve scroll position, editing behavior, consented replay availability and long CJK/RTL/combining-character layout.

**Acceptance:** a ready user can identify Start immediately; an unready user sees one relevant recovery action. Copy/Edit/More do not hide the fallback or alter the source text. The bottom action does not obscure the last line or collide with tabs at compact widths, landscape height or Accessibility 5.

### Phase 3 — One model decision flow

**Files:** `DictusApp/Views/HomeView.swift` (`VoiceOptionsView`), `KeyboardModePicker.swift` (`DictationSettingsAdvisor`, `DictationModelQuickPicker`), `ModelManagerView.swift`, `ModelCardView.swift`, `ModelLanguageDetailView.swift`. Preserve `DictusApp/Models/ModelManager.swift` routing methods unless a reproduced problem requires a small fix.

**Consumes:** current spoken languages, app and keyboard scopes, `useRecommendedSettings()`, `chooseDictationModel`, `chooseKeyboardModel`, readiness, installed receipts and current runtime capabilities. **Produces:** the same preferences and explicit actions in a simpler presentation.

- [ ] Put spoken languages first in Voice options, followed by compact recommendation/current-choice information. Keep the explicit Use recommended settings action and disclose its routing-only effect.
- [ ] Show In sAiity and From your keyboard as distinct summaries. Keep specific model choices in the existing disclosures. Keep Realtime text independently reachable when Qwen is selected and show Keep sAiity open next to that mode.
- [ ] Make Models an inventory: installed first, downloadable second, existing cleanup models/storage tools afterwards. Sort recommendations within these groups and use current badges; show each catalog model once.
- [ ] Replace the repeated advisor/full selection block at the top of Models with navigation to Voice options. Keep meaningful per-model Download, Cancel, Retry, Use and confirmed Delete actions.
- [ ] Keep byte size, download state, selected versus actually running model, compatibility reason and language detail discoverable. Never portray a compatibility recommendation as measured accuracy, or Qwen as verified multilingual/background recognition.

**Acceptance:** each model appears once in inventory; current manual and pending choices survive navigation/restart; app and keyboard choices remain independent. Advice never downloads, records or changes writing/language preferences. Partial files do not become Ready, cancelled downloads remain resumable, and no unavailable engine becomes selectable through a UI-only refactor.

### Phase 4 — Settings, words and setup

**Files:** `DictusApp/Views/SettingsView.swift` (existing preference pages and `VocabularyView`), `KeyboardModePicker.swift`, `DictusApp/Onboarding/WelcomePage.swift`, `OnboardingView.swift`, `KeyboardSetupPage.swift`, `MicPermissionPage.swift`, `ModelDownloadPage.swift`, `OnboardingSuccessView.swift`. Copy/localization resources change only for the strings actually touched.

**Consumes:** existing App Group keys, learned words, explicitly approved hints, snippets, setup stages and permission checks. **Produces:** clearer labels and disclosure with unchanged preference/data contracts.

- [ ] Keep current Settings groups and routes. Lead Dictation with everyday cleanup/output/writing choices; disclose server/diagnostics explanations where they are used. Keep advanced controls reachable without repeating advice.
- [ ] In Vocabulary, replace long-press-only hint management with an explicit native Menu/button per word. Preserve Add, Edit/delete and Reset confirmation. Distinguish protected typing words from approved dictation hints in brief copy.
- [ ] Preserve the 32-hint, under-65-character and six-word limits, canonical Unicode handling and explicit approval. Never automatically promote learned words to recognition hints or send unrelated names to server cleanup.
- [ ] Shorten the welcome explanation around Speak here and Use in other apps. Keep Back, Set up later, explicit permission continuation, persistent inline download/cancel and cold-stage resume. Do not start capture or installation as an onboarding demonstration.
- [ ] Keep mic access, keyboard enabled, Full Access, model installation and host readiness as separate observable setup steps. Put technical explanations beside the step that needs them.

**Acceptance:** changed labels remain truthful in English/French and longer or RTL locales; VoiceOver exposes hint actions without a long press; editing settings preserves their stored values. App-only/deferred/denied setup remains usable and never claims a verified Full Access handshake from a presumed flag.

### Phase 5 — Recording and keyboard consistency

**Files:** `DictusApp/Views/RecordingView.swift`; `DictusCore/Sources/DictusCore/Design/SaiityVoiceControls.swift`; existing `DictusKeyboard/KeyboardViewController.swift`, `KeyboardKeyInput.swift`, `Next/KeyboardSurfaceView.swift` and `Next/NextKeyboardHost.swift` only when a reproduced presentation inconsistency warrants a change. Protect `InputView.swift`, `NextKeyGridPlacement.swift`, prediction and delivery owners.

**Consumes:** existing recording/readiness/result state, native key routing, field layouts and shared preferences. **Produces:** consistent state words and actions without replacing the keyboard grid or dictation coordinator.

- [ ] Align Listening, Preparing your text, Finishing your text, Ready and fallback wording in the app, keyboard and activity mapping. Listening means recording dictated words; keyboard standby keeps its own preparing/ready state and explanation of microphone use.
- [ ] Keep Finish as the prominent recording action and Cancel separate; maintain visible cancellation/recovery during long processing. Use determinate progress only when real progress exists.
- [ ] Reuse current shared voice controls and result disclosure. Check field-specific return keys, toolbar/settings/default-tone parity and denied Full Access before changing spacing or labels.
- [ ] Preserve geometry, hit-routing ownership, Space cursor movement, Emoji blank-area scrolling, key flash/hold behavior, sound/haptic preferences and exact enabled-language word protection. Do not retune key sizes or haptics from a simulator impression.

**Acceptance:** presentation changes pass the relevant existing native typing/result scripts; touch routes and visible plates remain invariant. Real typing, mic-on haptics, field parity, background delivery and landscape feel need separate phone evidence, not inferred from those scripts.

### Phase 6 — Evidence and release readiness

**Files:** the existing QA/readiness documents and the touched existing tests/native fixtures. Create a dated QA record only when new acceptance evidence exists; do not overwrite the historical build 240 checkpoint.

- [ ] Run only relevant checks after source changes; keep one serial build/test owner. Visual/copy-only edits need production-view/native review, not tests that merely duplicate view modifiers. Routing, retention or cancellation changes require a focused regression that fails before the fix.
- [ ] Capture the final touched states with fabricated text across compact/landscape, light/dark, ordinary/Accessibility 5, CJK/RTL, Reduce Motion/Transparency and denied setup. Preserve existing screenshots/fixtures when comparable.
- [ ] With separately authorized phone access, verify physical typing/mic-on haptics, field/settings/default-tone/Full Access parity, foreground/background delivery, PiP and every actual system Live Activity presentation. Record model/device/OS and exact build.
- [ ] With licensed/consented files and supported hardware, evaluate Qwen load/inference/cancel/foreground loss/memory and language-specific recognition, cleanup, translation and latency. Use independent native-language meaning review. Text guards are heuristics, not semantic-accuracy evidence.
- [ ] Before a separately authorized release, use Chrome Use to verify published privacy/support pages, Apple privacy answers, actual Translation pair availability where applicable, and next unused build number. Record Apple acceptance/processing and tester availability separately from local signing.

**Acceptance:** each gate is marked passed with evidence, failed with a reproducible issue, or pending with a concrete dependency. All local passes remain separate from physical quality and Apple release status. A plan, commit title, simulator or unit suite cannot close the latter gates.

## Verification commands for a future authorized implementation

Run from the explicit repository directory with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Create a fresh task-specific temporary output directory for future builds; commands below use a shell variable deliberately assigned with `mktemp -d`. These commands are listed for the implementer and were **not run to validate app changes during planning**.

```sh
# Run within DictusCore; one test owner.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --jobs 4
```

Expected: zero failures; retain and identify any pre-existing skip. The current recorded count is a checkpoint, not a required forever-fixed count.

```sh
# Run within the repository; no simultaneous Xcode build.
saiity_plan_qa_dir=$(mktemp -d /tmp/saiity-design-qa.XXXXXX)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project Dictus.xcodeproj -scheme DictusApp -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$saiity_plan_qa_dir/derived" \
  -disableAutomaticPackageResolution
codesign --verify --deep --strict \
  "$saiity_plan_qa_dir/derived/Build/Products/Debug-iphonesimulator/DictusApp.app"
git diff --check
```

Expected: app/keyboard/widget build succeeds, strict signature check and whitespace check exit zero. This produces local simulator evidence only.

For changed recovery, layout, keyboard or downloader behavior, use the appropriate existing script; inspect its arguments before running. Proven harness commands use the same dedicated simulator and the derived-data path, for example:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift \
  scripts/render-product-results.swift \
  3ED8FD55-D525-45D1-9E1A-4A1354000FC0 "$saiity_plan_qa_dir/derived"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift \
  scripts/test-dictation-result-recovery.swift \
  3ED8FD55-D525-45D1-9E1A-4A1354000FC0 "$saiity_plan_qa_dir/derived"
```

Existing relevant harnesses also include `test-key-grid-typing.swift`, `test-multilingual-autocorrect.swift`, `test-keyboard-text-safety.swift` and `test-model-downloads.swift`. Do not rerun all of them for an unrelated wording change. Do not run microphone capture, downloads or real inference as a side effect of UI QA.

## Review and completion gates

The first implementation review should cover Phase 1 and Phase 2 production-view evidence before proceeding to model/settings changes. Each later phase is independently acceptable; findings may narrow its file scope. Keep release work separate from this design sequence.

Planning is complete when the source plan and template document agree, the document renders cleanly, all recommendations map to current owners, and no claimed pass relies on a mockup. Implementation is complete only after the relevant phase acceptance checks. Product/release completion additionally requires the outstanding physical, language and online gates above.

## HIG basis

This plan uses the installed Apple Design reference set, not a fresh online HIG audit. Each citation names the local file and heading. Its snapshots may predate newer platform guidance.

- `accessibility.md › Vision / Mobility / Cognitive`: readable contrast, default 44 pt app controls, equivalent non-color signals and persistent recovery information.
- `layout.md › Best practices / Adaptability`: give essential content space; adapt to orientation, text size and locale.
- `typography.md › Using system fonts / Supporting Dynamic Type`: system styles, text wrapping and preserved hierarchy at larger sizes.
- `color.md › System colors`: "Avoid hard-coding system color values in your app."
- `designing-for-ios.md › Best practices`: focused controls, contextual detail and comfortable placement of primary actions.
- `buttons.md › Style`: reserve prominence for one or two actions; name the action clearly.
- `virtual-keyboards.md › Custom keyboards`: retain switching to the system keyboard and in-app setup guidance.
- `onboarding.md › Best practices / Additional requests`: brief optional teaching and delayed nonessential setup.
- `settings.md › Best practices / Task-specific options`: minimize settings and offer contextual choices.
- `tab-bars.md › Best practices`: tabs navigate; they do not perform dictation actions.
- `live-activities.md › Best practices`: concise status and avoidance of private information on shared system surfaces.
- `materials.md › Liquid Glass`: use platform material for controls/navigation; keep the content layer readable.
