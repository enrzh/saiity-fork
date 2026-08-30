# Keyboard Actions and Language Design

**Date:** 2026-08-30  
**Status:** Design specification  
**Scope:** DictusKeyboard presentation and its existing shared language/model preferences. Existing recording, transcription, insertion, emoji, number-layer, and extension lifecycle owners remain authoritative.

## 1. Goals and boundaries

- Keep the keyboard canvas at **216pt** high, with the microphone control centered in the available central area.
- Use the existing `KeyboardAreaMode` for mutually exclusive keyboard-area states. Do not add a Manager, Service, Protocol, Factory, Strategy, Adapter, Coordinator, Provider, Resolver, or Registry.
- Reuse the existing `EmojiPickerView`, existing number/symbol layer, shared App Group defaults, and existing model metadata. A view action may call an existing owner directly.
- Use native iOS 26 Liquid Glass where available, with the existing semantic/material fallback on earlier supported OS versions. Geometry, contrast, hit regions, and state meaning must remain equivalent; no decorative glow, fake reflection, or gradient is added.

## 2. Language and AUTO menu

The top-left language control displays the current transcription mode and opens one menu:

- `Transcribe` runs transcription only.
- `Translate to [target]` runs translation to the selected target language.
- `Translate to [target]` opens a submenu containing only targets whose source/target pair is ready in the independent translation backend/runtime. This readiness is not derived from ASR model metadata.

`AUTO` is shown only when the active ASR model genuinely supports multilingual automatic input-language detection. A fixed-language or otherwise explicitly source-language ASR never shows `AUTO`; it shows its actual source language (for example `FR`/French), and the menu must not offer automatic detection. Translation targets are a separate capability: a fixed-language ASR can still offer translation when the independent translation backend/runtime reports that source/target pair ready. The menu must not claim either ASR detection capability or translation-pair readiness that the corresponding runtime does not provide.

The keyboard writes the shared translation mode and selected target into the existing dictation request. The keyboard extension does not run translation. Because this repository currently has no translation implementation, the main App is the future owner of translation execution: after the authoritative final transcript, it invokes the ready independent translation backend/runtime, then returns the translated (or explicitly failed/fallback) result through the existing insertion and acknowledgement flow. The ASR source-language display and translation target readiness remain separate decisions.

The keyboard language setting defaults to **Automatic (System)**. Resolve the initial layout language from the system locale using the existing supported-language mapping. An explicit user selection is persisted and takes precedence over later locale changes. Existing installations whose implicit/default keyboard language is French must migrate safely: treat the legacy French value as an unset implicit default only when there is no evidence of an explicit user choice; preserve a genuinely explicit French selection. Migration is idempotent, uses the existing shared defaults, and never changes the separate transcription-language preference without an explicit user action.

## 3. Keyboard actions

The right rail contains stable **88x44pt** delete and return controls. Their visual layout may be compact, but each control's UIKit-backed hit area is exactly 88x44pt and must not overlap adjacent actions.

- Delete calls the existing `textDocumentProxy.deleteBackward()` bridge.
- Return calls the existing newline insertion bridge.
- `@` moves to the left-side utility position and inserts the literal `@` through the existing proxy bridge.
- The left-side emoji action opens the existing local `EmojiPickerView`. It must not claim to force or open Apple's system emoji keyboard.
- The left-side `123` action opens the existing number/symbol page. `ABC` returns to the voice/letter surface, not to an unrelated app screen.
- Bottom `next` and `dismiss` actions use explicit UIKit-backed controls with a minimum and declared **44pt** hit height. `next` invokes the existing next-input-mode callback; `dismiss` invokes the existing keyboard dismissal callback. SwiftUI styling may wrap these controls, but the actual action and hit target must remain UIKit-backed for reliable extension response.

Every action has a concise accessibility label, stable identifier, pressed state, and a visible disabled/error state when its existing owner cannot perform it.

## 4. Surface and state flow

The 216pt surface contains, in stable non-overlapping regions, the language control, centered microphone, status text, left utility actions, and right rail. Status changes must not resize the keyboard or move the action hit targets. Liquid Glass controls use system materials and remain legible in light/dark appearance, increased contrast, Reduce Transparency, and large Dynamic Type.

The state flow is:

`ready -> starting -> recording -> stopping -> transcribing -> translating/polishing -> inserting -> acknowledged -> ready`

Cancellation, interruption, missing/loading/failed model, permission denial, unavailable microphone, timeout, translation unsupported, insertion failure, memory pressure, and extension dismissal are explicit recoverable failure paths. The UI never reports insertion before the existing proxy acknowledgement. A failure leaves the next recording and relevant retry/action path available without corrupting the selected language or keyboard layer. `KeyboardAreaMode` returns to `.keys` only after the existing in-flight state has ended.

## 5. Testing

Add focused tests only for new contracts:

- active ASR model capability determines whether AUTO is shown and which actual source language is displayed for fixed/source-language models;
- independent translation backend/runtime readiness determines the target submenu contents, including translation from a fixed-language ASR source;
- keyboard request propagation records the shared translation mode/target, while App-side post-transcript execution and existing insertion/acknowledgement are tested separately from the keyboard;
- system-locale defaulting, explicit selection persistence, idempotent French migration, and separation from transcription language;
- delete, return, `@`, emoji, `123`/`ABC`, next, and dismiss call the existing bridges and expose 44pt/88x44pt hit contracts;
- state transitions cannot acknowledge insertion before proxy acknowledgement and recover correctly from each listed error class;
- `KeyboardAreaMode` remains the single area-state authority.

Verify light/dark, Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, Increased Contrast, and the exact 216pt canvas in host text fields. Automated tests and simulator checks are supplemental only.

## 6. Physical iPhone acceptance and release gate

On a physical iPhone, in a real host text field, verify: keyboard activation, system-locale default and explicit language persistence, AUTO/active-ASR capability truthfulness, fixed/source-language display, Transcribe and Translate target selection, independent translation-backend target-pair readiness and target submenu behavior, hold/release recording, transcription/translation when an implementation is available, insertion acknowledgement, delete, return, `@`, local emoji picker, `123`/`ABC`, next, dismiss, interruption/background return, and every recoverable error path that can be induced safely. Confirm that the 216pt surface remains collision-free and all hit targets respond reliably.

**TestFlight is prohibited until the physical iPhone acceptance checklist passes and is recorded as release evidence.** Passing unit, UI, or simulator tests alone is not sufficient.

## 7. Self-check

This specification contains no unresolved TBD/TODO items. It does not introduce a new abstraction layer, does not confuse local emoji presentation with Apple's system emoji keyboard, does not expose AUTO for ASR models without multilingual automatic input-language detection, does not derive translation targets from ASR metadata, does not run translation in the keyboard extension, and does not weaken the physical-device/TestFlight gate.
