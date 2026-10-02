> Archived scope. Current product decisions are in `PRD.md` and
> `docs/product-quality-plan.md`; runtime/keyboard evidence is in their current
> plans. Historical instructions below about excluding Qwen, removing the
> suggestion bar or removing the Settings model entry are superseded. Preserve
> this document as evidence; do not execute its old implementation prompt.

# sAiity: product, design, and behavior improvement plan

Date: 2026-09-21
Status: proposed; implementation and release are not part of this review.

## Direction

Make sAiity a dependable multilingual keyboard with private dictation, rather than a model-management app that also types. Keep the two existing tabs, Speak and Settings. Improve everyday interactions before adding more features or models.

This plan combines a main-app source review with an independent `sub2api/gpt-5.6-luna` keyboard review. It uses Apple Design guidance for native hierarchy/accessibility and Ponytail for small changes to existing ownership paths. No product source was modified. Current rendered appearance, physical gestures, ASR accuracy, and latency have not been verified by this review.

## What already exists and should stay

- Native grouped lists and navigation in Speak and Settings.
- Keyboard dictation enable/disable, preparation failure/retry, cancellation, and recent dictations.
- Searchable history, copy/share, individual deletion, and confirmed clearing.
- Searchable model catalog, download progress/cancellation, and deletion confirmation.
- Local multilingual transcription and cleanup guardrails; Qwen stays removed.
- Autocorrection controls, undo, user vocabulary, and conservative correction learning.
- Static key visuals, invisible adaptive touch handling, and the custom floating emoji-category interaction.
- No suggestion/autocomplete bar. Optional post-dictation suggestions remain disabled by default and require explicit acceptance.

## Priorities

| Order | Change | User benefit |
| --- | --- | --- |
| 1 | Truthful readiness and reliable gesture ownership | A visible action does exactly what it promises |
| 2 | Simpler Speak, Settings, and Models hierarchy | Less searching and less technical clutter |
| 3 | More recoverable results and corrections | Confidence that words and languages are preserved |
| 4 | Consistent keyboard/emoji navigation and accessibility | Faster daily use without relearning controls |
| 5 | Measured multilingual quality and speed | Better results rather than a larger model catalog |

## 1. Make readiness and actions trustworthy

### Speak status

`DictusApp/Views/HomeView.swift:93` hardcodes “Ready when you are” inside the readiness panel. Derive the heading, detail, and single next action from the existing readiness state. Distinguish disabled, setup incomplete, model preparing, ready, recording, processing, and recoverable failure. Do not introduce a second readiness state machine.

Keep the requested keyboard-dictation switch visible. Explain the difference between enabling keyboard dictation and actively recording. A ready status must not imply that audio is being captured.

### Touch and lifecycle consistency

The Luna review identified shared UIKit/SwiftUI ownership as an audit priority: `DictusKeyboard/KeyboardRootView.swift:84` disables SwiftUI delete hit testing conditionally, while `KeyboardViewController.swift` owns additional controls. That is evidence of a complex routing contract, not proof that two handlers currently fire.

Trace each live mic, delete, dismiss, return, and emoji-category path. Preserve the existing owner when it works; remove duplicate handling only when demonstrated. Use bounded debug timing to locate delays before changing thresholds or adding recognizers.

Preserve tap-to-open, hold-to-speak, finger-release processing with the existing capture tail, and processing cancellation. Every success, error, interruption, timeout, or host-field replacement must leave a usable keyboard. Never display successful recording feedback before the relevant state is acknowledged.

Acceptance:

- Readiness heading and action agree in every existing readiness state.
- Each touch triggers at most one command; release/cancellation cannot leave a held state stuck.
- Switching material changes rendering, not gesture ownership or control identity.
- Cancellation prevents late transcript insertion; recovery offers one useful next action.
- Device verification includes rapid taps, overlapping fingers, material changes, and host re-entry. Report observed latency instead of promising exact native parity.

## 2. Simplify the app without another wholesale redesign

### Speak

Keep a compact status section, the existing main recording action, one active-model row, and recent dictations. Use standard navigation and semantic colors; avoid another dashboard, hero card, or duplicate launch control. Keep transcript content visually primary after recording.

`RecordingView.swift:319` advances onboarding after 1.5 seconds. Replace that onboarding-only timer with an explicit Continue action so users can read their test result. Normal recording already keeps its result; do not “fix” it as though it auto-dismissed.

### Settings

`SettingsView.swift:20` still has a Models section even though Models is reachable from Speak. Remove that duplicate entry and place model selection policy with the model controls.

Organize existing options into native navigation rows:

- Dictation: language/output behavior, cleanup, writing style.
- Keyboard: default mode, layouts/languages, autocorrection, haptics, appearance.
- Personalization: vocabulary and text replacements.
- Privacy and Help: history controls, permissions, troubleshooting, privacy, licenses, version.

Move advanced cleanup-engine/server configuration and diagnostics into secondary destinations. Preserve current values during any preference migration. Keep required attribution and licenses in their detail screen; remove redundant promotional/fork styling, not legal notices.

Replace the unverified “same tap feedback as the iPhone keyboard” accessibility hint (`SettingsView.swift:83`) with factual wording. Audit the correction-suggestions hint at line 78 against what is actually exposed; don't imply a suggestion bar. Replace the generic GitHub-profile support destination with a verified project-specific support route when one is available.

### Models

`ModelCardView.swift:95–101` shows numerical Accuracy/Speed indices and gauges for both. Use a compact native row: name, selected state, download size, supported-language summary, and one primary action. Put engine details and tradeoffs in model details. Remove redundant score presentation; do not present catalog estimates as measured accuracy.

Keep a small recommended section and an All Models destination. Recommend only from known compatibility and measured language/device performance. Do not silently switch models or download anything.

`ModelManagerView.swift:131` presents preparation full-screen. Prefer inline preparation status that allows navigation while the existing manager retains ownership. Keep full-screen presentation only if a demonstrated lifecycle constraint requires it. Replace generic Error/OK recovery with actionable descriptions and retry where safe.

Acceptance:

- One obvious path from Speak to model management; no duplicate Models section in Settings.
- Download, use, preparing, selected, retry, and delete remain distinguishable.
- Deletion retains confirmation and active-model safety; leaving the page cannot orphan preparation.
- Dynamic Type, dark/light appearance, VoiceOver, Reduce Motion, and Reduce Transparency are checked on the changed screens.

## 3. Make text recoverable and personalization understandable

`RecentDictations.swift:4` currently stores final text, ID, and timestamp; history is bounded to 30 entries. Improve existing history with a native detail view, readable full transcript, edit/copy/share, and a clear local-storage explanation. Add a Save history control without deleting existing history implicitly; Clear history remains explicit.

If exposing “Original / Cleaned,” first trace existing transient raw-result ownership. Do not promise history comparison from data that is not stored. Persist both versions only under the history preference, with backward-compatible decoding and the existing storage bounds; do not start saving audio.

The Luna review found correction reconciliation at `SuggestionState.swift:550`: overrides are learned at a word boundary. Keep conservative learning rather than learning every partial edit. Verify immediate undo, caret movement, repeated rejection, mixed scripts, punctuation, and numbers. Provide a way to inspect/remove learned words through existing vocabulary UI; do not add a parallel learning system.

Acceptance:

- Corrected text can be undone without changing unrelated text or spacing.
- Stale asynchronous results cannot overwrite newer typing or a different caret context.
- History-disabled mode does not persist new history entries; clearing cannot resurrect migrated legacy content.
- Mixed-language input is retained by default. Translation is explicit and labelled.
- Suggestions never replace output silently and remain optional/off by default.

## 4. Finish keyboard and emoji behavior as one coherent system

Keep shared geometry and the current category-bar design. Audit synchronization among `EmojiPickerView`, `EmojiCategoryBar`, `KeyboardRootView`, and UIKit routing in `KeyboardViewController`. Use one source of truth for visible category and explicit category-jump requests; ordinary scroll updates must not generate another jump.

Preserve free scrolling with momentum, a separate stable Recents area, reachable Flags, and blank-area swiping. Keep variant tracking alive until finger release/cancel even outside the popup. Popup materials follow the existing preference and accessibility fallback. Maintain the user's requested category-bar movement rather than replacing it with a different interaction.

Do not change key dimensions based on intuition. Compare the actual supported device widths and host field types; preserve static visible key positions during prediction. Improve touch targets without allowing neighbors to steal direct center taps or accessibility activation.

Acceptance:

- Scrubbing and grid scrolling stay synchronized without feedback loops or snapping back.
- Empty Recents, populated Recents, first/last category, narrow layouts, and keyboard recreation work.
- Variant selection commits exactly once; cancel does not insert the base emoji.
- Delete and dismiss remain in the shared positions with usable hit regions.
- VoiceOver offers an accessible category-selection action even though the visual control is drag-based.
- App controls aim for 44-point targets; dense key grids retain nonoverlapping, usable routing rather than mechanically forcing every key to 44 points.
- Protected fields/system-forced keyboards are documented honestly; no promise to override iOS restrictions.

## 5. Improve the product through multilingual quality, not model count

Build on the existing segmentation, sequential inference, cleanup guardrails, and evaluation harness. Profile capture-end, ASR, cleanup, and insertion separately. Use short, long, quiet, noisy, names/numbers, and German/English/Chinese code-switch samples to identify the next actual bottleneck.

Prioritize preserving names, dates, numbers, and language boundaries over stylistic rewrites. Keep raw text available when cleanup fails. Recommend the fastest model that meets measured quality for a user's language needs, without silent downloads or automatic preference changes. Existing vocabulary and text replacements are the first personalization tools; avoid another model or cloud service until evidence demands it.

Acceptance:

- Record ASR real-time factor, end-of-speech-to-insertion median/tail latency, and transcript errors on the same device and samples before/after.
- Single-language quality, mixed-language preservation, cancellation, and memory remain explicit gates.
- No concurrent Core ML inference, no new mandatory service/account, and no Qwen restoration.

## Implementation sequence and verification

1. Small state/copy fixes, onboarding Continue, and removal of duplicate Settings navigation.
2. Compact model rows and actionable preparation/recovery.
3. Trace and fix demonstrated touch/lifecycle defects; retain working routing.
4. History detail/privacy and correction-reversibility refinements.
5. Emoji/geometry/accessibility checks and measured dictation improvements.

For each phase, inspect current callers first and extend relevant existing checks only where behavior changes. Run applicable Core tests and the supported app build. Use a physical device for keyboard gestures, microphone lifecycle, and latency; simulator/build success is not proof of those behaviors. Record unverified cases honestly. Deployment requires a subsequent user request.

## Review corrections and evidence limits

- The subagent flagged `RecordingOverlay.swift` as non-cancellable. A repository search found no construction of `RecordingOverlay` in the keyboard; the live recording branch calls `centerSurface`. Do not infer a live cancellation bug from that apparently unused view. Trace the active surface before editing or deleting it.
- Conditional UIKit/SwiftUI routing is not itself a confirmed race. Reproduce and measure before refactoring.
- The onboarding timer does not apply to normal results.
- HIG-based recommendations are native list hierarchy, restrained materials, and accessibility. Priorities, grouping, and product direction are review judgments, not Apple requirements.

## Design references

- Apple HIG, Settings / Best practices: “Minimize the number of settings you offer.” https://developer.apple.com/design/human-interface-guidelines/settings
- Apple HIG, Settings / Task-specific options: prefer contextual options without requiring a trip to Settings. Same source above.
- Apple HIG, Materials / Liquid Glass: use glass for controls/navigation sparingly; keep transcript and model content readable. https://developer.apple.com/design/human-interface-guidelines/materials
- Apple HIG, Accessibility: semantic labels, alternate interaction paths, readable type, and system accessibility preferences. https://developer.apple.com/design/human-interface-guidelines/accessibility

## Copy-paste execution prompt

> Implement `docs/product-design-and-behavior-plan.md` in priority order. Preserve all existing uncommitted/untracked work. Read current repository guidance and Apple Design/Ponytail skills. Use only Sub2API Luna for bounded subagents. Revalidate each finding against current callers; do not revive unused UI or duplicate existing features. Keep sAiity branding, local multilingual preservation, existing keyboard/emoji interaction choices, cancellation, and conservative personalization. No Qwen, suggestion bar, silent replacements, mandatory cloud service, or model-download expansion. Make focused changes, run relevant existing tests and the supported app build, and distinguish physical-device verification from source/build evidence. Report completed work and remaining gaps. Do not commit, upload, or deploy without a new user instruction.
