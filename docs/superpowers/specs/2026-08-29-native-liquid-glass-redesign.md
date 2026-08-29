# sAiity Native Liquid Glass Redesign Specification

**Date:** 2026-08-29  
**Status:** Approved design specification  
**Scope:** DictusApp UI and DictusKeyboard UI only. The existing recording, background-audio, transcription, processing, App Group, and text-insertion pipeline remains unchanged.

## 1. Source Of Truth

The three supplied reference attachments are the sole visual source of truth:

- **Home / Models / Settings reference:** use its hierarchy, spacing rhythm, density, typography scale, grouped content, dark visual hierarchy, and bottom-tab structure.
- **Keyboard reference 1:** use its 390x220 voice-only geometry and control placement.
- **Keyboard reference 2:** use its Liquid Glass material treatment and light/dark contrast relationship.

Do not combine these references with a third visual direction. The target is a native SwiftUI translation of the supplied references, not a new brand system or a marketing redesign.

The old macOS sAiity logo is permitted only for the app icon and app-level branding. It must not be rendered in the keyboard surface and must not be used as a decorative in-app logo when the reference calls for the sAiity wordmark/header.

## 2. Product And Data Boundaries

The redesign keeps real sAiity functionality. It must not replace live state with preview fixtures, invented rows, fake model sizes, or placeholder settings.

The app exposes the seven currently loadable model catalog entries from `ModelInfo` and its existing model manager:

1. `openai_whisper-tiny` / Tiny
2. `openai_whisper-base` / Base
3. `openai_whisper-small` / Small
4. `openai_whisper-small_216MB` / Small (Quantized)
5. `openai_whisper-medium` / Medium
6. `parakeet-tdt-0.6b-v3` / Parakeet v3
7. `openai_whisper-large-v3_turbo_954MB` / Turbo

The Models screen reads installation, download, loading, engine, size, recommendation, error, and availability state from the existing catalog and manager. A model is never displayed as ready unless the existing runtime reports it as installed and usable. Download and delete actions continue through the existing model manager and retain progress, cancellation, retry, and failure behavior.

The language control is **Auto** / automatic detection. It uses the existing transcription-language preference and engine behavior: Whisper receives automatic detection when no explicit language is selected, and Parakeet retains its native automatic detection. No fake fixed-language preview is allowed.

Settings continue to read and write the real App Group-backed preferences. Existing settings that remain product-valid, including Live Activity and conditional local transcription polish, retain their existing availability and side effects. Debug-only settings remain excluded from release UI. Removed keyboard-layout, number-row, keyboard-language, haptic, sound, and autocorrect controls are not reintroduced merely to fill space.

The Dictus recording/background pipeline is outside the migration boundary. UI state observes and invokes its current contracts; it does not rewrite audio capture, background execution, model preparation, transcription, post-processing, App Group handoff, or `textDocumentProxy.insertText` behavior.

## 3. Platform And SwiftUI Architecture

### 3.1 Required primitives

Use native SwiftUI primitives:

- `NavigationStack` for pushed app destinations and detail screens.
- `TabView` for the Home, Models, and Settings top-level tabs shown in the reference.
- `List` for grouped, dynamic rows and model collections.
- `Form` only for genuinely form-like preference editing or a focused settings detail screen.
- `Toolbar` for contextual actions, including model management and screen-level commands.
- `sheet` for transient selectors, model details, permission explanations, and other modal content represented by the product flow.
- `NavigationSplitView` is not required for this phone-first design and must not be introduced solely as an architectural abstraction.

Keep existing view models, managers, catalog types, and App Group keys where they already provide the required behavior. Add a new type only when an existing type cannot own the responsibility directly. Do not add Manager, Service, Factory, Strategy, Protocol, Adapter, Coordinator, Provider, Resolver, or Registry layers for styling or navigation.

### 3.2 Liquid Glass availability

On iOS 26 and iOS 27, use the system Liquid Glass APIs and materials appropriate to the SDK available at compile time. Glass is used for navigation surfaces, grouped surfaces, controls, capsules, and sheets where the reference shows translucency.

On iOS 17 through iOS 25, use a graceful native fallback based on `Material`, system colors, opacity, separator rules, and semantic foreground styles. The fallback preserves geometry, hit targets, hierarchy, and state meaning. It does not simulate glass with custom glow, fake reflections, 3D bevels, excessive blur, layered overdraw, or animated gradients.

The implementation must compile under the repository's iOS 17 minimum deployment target. Availability checks isolate iOS 26/27 APIs at the smallest call sites. All visual states remain legible when transparency is reduced.

## 4. App Shell And Navigation

The app shell is a three-tab `TabView` matching the attachment:

- **Home:** primary dictation entry point and recent real activity.
- **Models:** installed and available model management.
- **Settings:** real product preferences, privacy, help, and legal/about information as applicable.

Each tab owns a `NavigationStack`. The tab bar remains visually quiet and dense, with selected-state emphasis matching the reference. Tab labels and accessibility labels are localized through the existing localization system.

Use `NavigationLink` for destinations and `ToolbarItem` for actions. Avoid custom navigation bars that duplicate system behavior. Sheets dismiss with standard gestures and the system close affordance. Deep links and existing app-entry flows land on the corresponding tab without bypassing current onboarding or permission requirements.

No visible copy, navigation title, accessibility label, alert, sheet, or toolbar may identify the product as Dictus. User-facing product identity is sAiity; internal source names may remain unchanged when they are not visible.

## 5. Home Screen

The Home screen follows the attachment's order and density:

1. Compact sAiity header using the app branding treatment from the reference.
2. Greeting and short readiness subtitle.
3. A prominent voice-input surface with live duration, readiness/processing state, and microphone action.
4. A real recent-activity list, shown only when the existing product has corresponding data; empty state is intentional and compact.
5. Standard bottom tab bar.

The voice-input surface is a real control connected to the existing recording lifecycle. It must represent at least these states: ready, permission required, starting, recording, stopping, transcribing, processing/polishing, insertion complete, model unavailable, microphone unavailable, and recoverable failure. State text is concise and never claims success before the pipeline reports success.

The main action has a stable hit target and a visible pressed/recording state. Recording feedback uses semantic color and system animation only. It does not add waveform decoration, fake audio meters, glow, or depth effects absent from the attachments.

## 6. Models Screen

The Models screen matches the reference's compact grouped sections:

- **Installed:** every currently installed model, with real name, engine-relevant status, size, active selection, and actions.
- **Available:** every catalog model that can be downloaded on the current OS/device, with real size and download state.

Rows use native `List` semantics and remain readable at large Dynamic Type sizes. A row may open a detail `NavigationStack` destination or sheet for supported-language information already available in the product. Download, cancel, retry, delete, and select actions preserve the current manager behavior and state transitions.

The active model is clearly identifiable without relying only on color. Loading, unavailable, failed, and queued states have explicit text and accessibility values. A failed download provides the existing retry path and does not silently disappear. Model ordering follows the existing catalog/recommendation rules, not invented reference data.

The seven model entries above are the complete current product set for this redesign. The UI may filter by runtime availability, but it may not invent an eighth entry or label an unsupported runtime as functional.

## 7. Settings Screen

Settings follows the attachment's section density and row hierarchy while retaining actual settings. The screen uses `List` with grouped sections; a `Form` may be used inside a pushed detail editor where it improves native behavior.

The visible structure is:

- **Dictation:** automatic language indication and the existing conditional transcription-polish setting/status, when the current build makes it available.
- **Keyboard:** only real keyboard-related product controls that remain supported, such as Live Activity where currently implemented. Do not expose removed layout, number-row, keyboard-language, haptic, sound, or autocorrect controls.
- **Privacy:** local-processing status and the existing privacy explanation.
- **About / Help:** real legal, license, privacy, and help destinations that exist in the product. Do not add a fake account, subscription, support, or analytics destination.

Every toggle writes to the existing App Group-backed key and preserves side effects. Permission rows show the current authorization state and the existing route to system settings where applicable. Conditional settings follow the current availability checks; unavailable functionality is explained accurately rather than represented by a permanently disabled decorative control.

## 8. Voice-Only Keyboard

### 8.1 Fixed geometry

The keyboard is voice-only and is laid out for a real **390x220 pt** keyboard-safe canvas. The declared keyboard height remains a hard boundary. Content must fit within safe insets and must not depend on the surrounding host app's layout.

Reference geometry, from back to front:

- **Top-left:** `Auto` language control, with compact disclosure affordance and a real automatic-detection action.
- **Center:** one large horizontal microphone capsule, centered in the available safe region. The capsule is the primary press-and-hold control.
- **Above/below center capsule:** concise recording instruction and live status, matching the reference's hierarchy without adding explanatory panels.
- **Right rail:** vertically aligned, equally sized native controls for delete, return, `@`, and dismiss. Each has a stable hit target and a spoken accessibility label.
- **Left-bottom:** next-keyboard/system keyboard switch control at the reference position.
- **Keyboard identity:** no keyboard logo, no app name, no Dictus branding, and no visible product wordmark.

The layout uses stable dimensions and safe-area-aware constraints. It must not resize or overlap when status text changes, when an error appears, or when Dynamic Type increases. The keyboard remains usable in the actual extension host, not only in a SwiftUI preview.

### 8.2 Behavior and states

The microphone preserves the existing press-to-talk and recording/background pipeline. Required visible states are:

- idle / ready;
- touch-down pending start;
- recording;
- stopping and waiting for audio finalization;
- transcribing;
- processing or polishing;
- successful insertion acknowledgement;
- microphone permission denied or unavailable;
- model missing, loading, or failed;
- insertion or handoff failure;
- keyboard extension memory or lifecycle interruption.

The status must never imply that text was inserted when the proxy acknowledgement has not occurred. Recoverable errors remain concise, accessible, and dismissible without destroying the next recording opportunity.

Delete inserts the real delete action through the current proxy bridge. Return inserts the real newline action. `@` inserts the literal character. Dismiss ends the current keyboard presentation through the existing extension context. Next-keyboard uses the system-provided control and does not launch the app.

### 8.3 Materials

Use native Liquid Glass APIs on iOS 26/27 for the capsule, rail controls, language control, and bottom controls when the system supports them. On older supported OS versions use system materials and semantic borders with the same geometry. Use a near-black semantic base behind the controls to preserve the reference's dark hierarchy.

There is no pseudo-glow, custom 3D treatment, fake glass reflection, ornamental gradient, or avoidable overdraw. Recording emphasis is communicated through the system accent and state transition, not a decorative halo.

## 9. Accessibility And Adaptation

- All controls have concise, action-oriented accessibility labels and values. Icon-only controls expose their meaning; decorative branding is hidden from VoiceOver.
- VoiceOver focus order follows reading order: Auto, instruction/status, microphone, right rail controls, next-keyboard/dismiss controls as spatially appropriate.
- Do not use color alone for active, recording, ready, failed, or unavailable states. Pair color with text, symbol, or accessibility value.
- Support Dynamic Type through semantic fonts and flexible layout. No fixed text frame may clip, truncate a critical state, or cover another control at the largest supported accessibility size.
- Support light and dark appearance. The supplied references establish dark hierarchy, but light mode must preserve contrast and material meaning using system colors rather than forcing a dark-only canvas.
- When Reduce Transparency is enabled, replace translucent glass with opaque or sufficiently solid semantic surfaces while retaining borders and hierarchy.
- When Reduce Motion is enabled, remove nonessential movement and use instantaneous or cross-fade state changes. Recording feedback remains understandable without animation.
- Respect Bold Text, Increased Contrast, button shapes, and Voice Control through system controls and semantic labels.
- Minimum interactive hit regions are 44x44 pt where the host and keyboard-safe geometry permit. The 390x220 layout reserves these regions without rail overlap.

## 10. Migration Boundaries

In scope:

- replacing the app's presentation layer with the reference-matched SwiftUI navigation and surfaces;
- replacing the keyboard's visual/layout layer with the reference-matched voice-only geometry;
- adding availability-gated Liquid Glass presentation with iOS 17 fallback;
- mapping existing real data and state into the new surfaces;
- removing visible Dictus branding from app/keyboard UI, while retaining the old macOS logo only for app icon/app branding.

Out of scope and must remain untouched:

- recording and background-audio lifecycle;
- WhisperKit and FluidAudio/Parakeet runtime behavior;
- model download/storage contracts and App Group paths;
- transcription, language detection, post-processing, and insertion semantics;
- keyboard extension lifecycle, memory budget, and `extensionContext` handoff;
- unrelated app targets, release metadata, version/build numbers, and legal license obligations.

The migration is complete only when the new UI can be removed without requiring a rewrite of those existing pipelines. Any necessary bridge is a thin call from the view to an existing owner.

## 11. Testing And Acceptance

### 11.1 Unit and integration coverage

Add focused tests only where a UI change introduces a new state mapping or accessibility contract. Verify that:

- all seven current model identifiers appear exactly once in the catalog-backed Models UI;
- installed, downloading, cancelling, failed, unavailable, and active states map to truthful labels and actions;
- Auto language remains automatic through the existing transcription contract;
- Settings reads and writes the real App Group values and preserves existing side effects;
- keyboard actions call the existing proxy bridge for delete, return, `@`, dismiss, next-keyboard, and insertion acknowledgement;
- recording status never reports insertion before the existing acknowledgement;
- no user-visible string contains `Dictus`.

### 11.2 UI and device verification

Run previews and UI tests for Home, Models, Settings, and every keyboard state in light/dark appearance, large Dynamic Type, VoiceOver-oriented accessibility identifiers, Reduce Transparency, Reduce Motion, and 390x220 keyboard geometry. Verify that List/Form rows remain scrollable and that sheets dismiss correctly.

Verify the keyboard in a real host text field on a physical iPhone or an equivalent device test: switch to the keyboard, hold and release the microphone, observe the real pipeline, confirm insertion, test delete/return/@/dismiss/next-keyboard, and repeat after the app is backgrounded. Simulator checks do not replace this extension-host gate.

### 11.3 Visual acceptance

Compare screenshots against the supplied attachments for hierarchy, density, geometry, and dark visual balance. Acceptance requires native system controls and materials, no pseudo-glow or 3D overdraw, no keyboard logo/app name, no visible Dictus branding, no clipped text, and no collision inside the 390x220 safe layout. The iOS 17 fallback must remain a coherent material-based rendering with equivalent geometry and semantics.

## 12. Self-Review Record

- Source of truth is explicitly limited to the supplied attachments.
- Native SwiftUI primitives and iOS 26/27 Liquid Glass with iOS 17 fallback are explicit.
- Seven real model identifiers are listed and tied to the existing catalog.
- Auto language, real settings, and the recording/background pipeline boundary are explicit.
- Keyboard geometry, controls, branding removal, accessibility, adaptation, testing, and migration limits are explicit.
- This document contains no unresolved placeholder, no invented product data, and no conflicting visual direction.
