# sAiity app improvement checkpoint

Implementation authorized on October 12, 2026 against the [overall-app plan](../superpowers/plans/2026-10-12-overall-app-improvement.md). Work remains local and uncommitted on `cursor/keyboard-surface-fixes-a66e`, baseline `963186e7`. Build number remains 241. No commit, push, archive, upload, publication, release change or tester invitation was made by this pass.

## Implemented

- Speak uses one native navigation title and a smaller task heading. Voice options shows spoken-language preferences and the chosen model. Keyboard standby explains microphone preparation independently of recording. History-off copy does not promise to save new dictations.
- The latest saved result reuses the existing Copy, Edit and original/recovery component; older results retain their detail navigation. Transcript text uses the native body style and retains selection, fallback disclosure and Unicode rendering. The existing stores and original-text fields remain unchanged.
- Models has installed/downloadable/cleanup inventory, without a duplicate recommended catalog or repeated advisor. Recommendations sort within the existing groups. Voice options owns model decisions; app/keyboard selections and Realtime text retain their existing routing and keys.
- Model headings, descriptions, download counts and actions wrap or stack at accessibility sizes. Qwen restrictions remain visible at ordinary text size. Errors and unavailable reasons remain readable; disabled deletion has a reason. Cleanup actions also stack and use the shared on-action color for dark-mode contrast.
- Vocabulary has an explicit per-word hint menu and a disclosed explanation of recognition/cleanup/server behavior. The existing approval, validation, Unicode, hint limits, reset confirmation and delete paths remain intact. Settings leads with writing choices; welcome copy is shorter while the setup state machine, permission checks, defer/back and download ownership remain intact.
- Listening, Preparing your text and Finishing your text share the existing Core status vocabulary, including keyboard accessibility and recording announcements. Key geometry, native touch/scroll owners, prediction, haptics and delivery identity were not changed.
- Live Activity payloads and views no longer contain transcript previews. Old persisted JSON with the retired preview key still decodes its phase/power/mute state, and re-encoding omits the private content. App and widget power updates retain the other state fields.

The current product explicitly exposes English-only UI (`CFBundleLocalizations` and `testAppExposesOnlyEnglishLocalization`). The plan's French UI assumption was corrected rather than shipping a partial localization. UI-language policy is unchanged; multilingual transcript, keyboard and spoken-language support remains intact.

## Verified local evidence

Logs and generated artifacts: `/tmp/saiity-app-improvement.dAZE5t`.

| Check | Evidence |
| --- | --- |
| Core suite | `core-final.log`: 1,938 tests, one existing ASR-results skip, zero failures. |
| Shared progress labels | `status-red.log` reproduced the three old labels; `status-green.log` passed all five status tests after the change. |
| Simulator app/keyboard/widget build | `build-final.log`: Debug build succeeded with pinned dependencies and normal signing. |
| Signature | `codesign --verify --deep --strict` passed for the final simulator app and embedded bundles. |
| Activity payload privacy | `privacy-red.log` reproduced transcript exposure using fabricated legacy JSON. `privacy-green.log` passed with phase, mute and power preserved and preview content omitted. |
| Production view fixtures | Portrait, landscape body, voice options, speech/cleanup model rows and vocabulary rendered using inert dependencies and fabricated text, normal text and Accessibility 5, light/dark. Representative outputs were inspected. |
| Multilingual result component | `result-layout.log`: 320/402-point widths, ordinary and Accessibility 3/5 layouts passed for Japanese, combining accents, identifiers, Hebrew/Arabic and explicit original fallback. |
| Scope/whitespace | `git diff --check` passed; no dependency, preference-key, keyboard geometry or prediction change. |

The existing native renderer was updated for the already-committed fallback state and extended with model, vocabulary, landscape and privacy cases. Vocabulary reload uses fabricated words and redirects its preferences to a disposable suite. No room audio, private transcript inspection, voice-model download or permission change was used. Only sAiity Product QA `3ED8FD55-D525-45D1-9E1A-4A1354000FC0` was operated. The already-booted hAiity simulator was left alone; no third device was booted.

View fixtures establish component layout, not full app or system-surface behavior. Largest model rows were measured/rendered in full; native Lists still need scroll/VoiceOver operation checks. The layer renderer cannot reliably draw native navigation/materials. Landscape Speak was therefore checked as its production body rather than interpreting the renderer's blank navigation-container output as a product failure. Increase Contrast/Reduce Transparency/Reduce Motion operation and complete VoiceOver navigation remain unverified; existing adaptive colors and motion policies were preserved.

Main-agent source/caller review was completed. A separate reviewer was not dispatched: the available worker tool does not advertise the required `sub2api/gpt-6.1-sol` route. No alternate worker model or obsolete provider retry was used.

## Separate pending gates

- Physical typing, mic-on haptics, landscape feel, field/settings/default-tone/denied Full Access parity and cross-app/background delivery.
- Actual PiP, Lock Screen/Dynamic Island/Live Activity presentation and power behavior, including restored activities across an app update.
- Qwen load/inference/cancellation/foreground loss/memory, language-specific recognition/cleanup/translation/latency, licensed or expressly consented recordings and independent native-language meaning review. No semantic-accuracy claim follows from text guards or UI fixtures.
- Actual Apple Translation pair availability/automatic source recognition and complete pinned Qwen source-language metadata.
- Published privacy/support pages, Apple privacy answers, next unused build number, Apple processing and tester availability. Chrome Use was attempted; Chrome is not connected (only Codex in-app/MCP-app browsers were available). No substitute browser was used.

Phone operation and release mutations still require explicit direction. The completion heartbeat must remain active and quiet on unchanged state; this checkpoint does not authorize repeated passed checks, phone use, microphone capture, downloads or release actions.
