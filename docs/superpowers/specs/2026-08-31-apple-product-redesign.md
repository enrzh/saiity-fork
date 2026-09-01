# sAiity Apple Product Redesign

## Product Goal

sAiity must feel like a first-party iOS utility: calm, legible, predictable, and built from native system behaviors. The redesign preserves every working dictation, model, translation, cleanup, keyboard, diagnostics, purchase, and onboarding capability while replacing fragmented styling and inconsistent interaction patterns.

## Shared Design Language

- Use system semantic backgrounds, labels, fills, tint, materials, typography, navigation, lists, sheets, alerts, menus, progress indicators, and controls.
- Liquid Glass is reserved for interactive chrome on iOS 26 and newer. Content is not placed into decorative glass cards.
- Every interactive target is at least 44 by 44 points. Icons remain visually compact inside those targets.
- Use one primary action per screen or state. Secondary actions use menus, toolbar items, links, or bordered controls according to their meaning.
- Use semantic text styles and support Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, Increase Contrast, light mode, and dark mode.
- State is communicated with text and symbols, never color alone.
- Destructive actions use native confirmation alerts that name the affected item and consequence.
- Existing business logic and state ownership remain unchanged. Do not add design managers, factories, services, protocols, or parallel state stores.

## Keyboard

The keyboard remains exactly 216 points high and uses the system keyboard semantic background. It has one stable outer chrome in every mode.

### Voice Surface

- Top row at 8 points: `AUTO` or the resolved source/translation menu at the leading edge; an aligned delete/Return group at the trailing edge.
- Center: one dominant 54-point-high dictation capsule, 160 to 180 points wide when space permits. Its symbol and short status are inside the capsule. The control never moves between idle, listening, processing, ready, or failed states.
- Bottom row at 172 points: `@`, emoji, `123`/`ABC`, and the input-mode globe in one horizontal leading group; dismiss keyboard at the trailing edge.
- The input-mode globe appears exactly once, only when `needsInputModeSwitchKey` requires it. Its icon is 18 points inside a 44-point target and routes the complete touch stream through `handleInputModeList(from:with:)`.
- Delete, Return, and dismiss use 88 by 44 point hit regions with compact SF Symbols.
- Control surfaces use native regular interactive glass on iOS 26+, semantic fill fallback before iOS 26, and opaque semantic fills when Reduce Transparency is enabled.

### Alternate Modes

- Emoji and numbers replace only the content region. They do not create a second keyboard surface or hide the common chrome.
- Emoji uses a compact native-density grid and category navigation inside the available content region. Global delete, mode, globe, and dismiss actions are not duplicated inside the picker.
- Numbers/symbols retain familiar native key geometry and semantic key colors. Their layout is constrained to the content region and cannot add a second globe, Return, dismiss, or emoji action.
- `123` changes to `ABC` while an alternate mode is active and returns directly to the voice surface.

## App Information Architecture

- Keep the three native tabs: Home, Models, Settings.
- Each tab owns a `NavigationStack`; pushed pages use native titles, toolbars, back behavior, lists, sheets, and alerts.
- Remove decorative nested cards and repeated borders. Use grouped sections, unframed content, and system separators.
- The floating iOS 26 tab bar must never cover the last row or primary action.

## Home And Dictation

- Home presents one readiness summary and one primary action. A blocker shows one reason and its direct recovery action.
- The active model is a concise labeled row, not a dashboard card.
- Recent dictation is readable and scannable, with an explicit copy action and confirmation feedback.
- Dictation is a focused native full-screen task with a stable microphone control, clear state title, live/raw transcript, processed result, retry, and close actions.
- Processing feedback remains useful with Reduce Motion enabled. Errors always provide an actionable recovery path.

## Models

- Present models as native list rows with name, concise capability summary, size, current state, and one contextual action.
- Download progress is determinate with percentage and downloaded bytes. Preparing is indeterminate but named. Failures expose retry and diagnostics.
- Active, downloaded, unavailable, and incompatible states use labels and symbols in addition to color.
- Deletion moves behind an overflow menu and requires a native confirmation naming the model and consequence.
- Language coverage opens a native detail page with semantic section headers and scannable rows.

## Settings And Secondary Screens

- Settings is a grouped native `List` organized by Dictation, Keyboard, Translation and cleanup, Feedback, Privacy, and Support.
- Controls use their native form: toggle for binary settings, picker/menu for option sets, slider with visible value for numeric feedback, navigation row for detail pages.
- Remove duplicate or obsolete keyboard options. Keep only controls that affect the shipped voice keyboard.
- Debug logs, diagnostics, licenses, paywall, and model details use standard navigation and toolbar actions, readable typography, and safe-area-correct scrolling.
- Clear/delete actions confirm; copy/export actions report completion; purchase UI clearly shows price, period, restore state, loading, failure, and success.

## Onboarding

Use one native setup container with four understandable stages:

1. Welcome and on-device privacy expectation.
2. Microphone permission with clear granted, denied, and recovery states.
3. Availability checklist for keyboard installation, Full Access verification, model download/preparation, and optional cleanup.
4. A real first dictation inserted through the keyboard, followed by a lightweight completion state.

The flow cannot claim readiness unless required gates are met. It uses semantic progress, standard back behavior where safe, one primary action, scrollable content for large text, and explicit accessibility announcements for state changes.

## Acceptance

- Verify keyboard idle, listening, processing, failed, emoji, and number modes on a physical iPhone.
- Verify one globe, exact 216-point height, stable microphone position, correct insertion, delete, Return, `@`, emoji, numbers, keyboard switching, and dismissal.
- Verify all app tabs and onboarding in light/dark mode, default and accessibility text sizes, Reduce Motion, Reduce Transparency, and VoiceOver labels.
- Run DictusCore tests, focused UI/layout contract tests, generic iOS build, signed physical-device build, installation, and fresh screenshots.
- Do not push or upload TestFlight until the physical keyboard flow and screenshots pass.
