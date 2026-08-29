# Native Utility Visual Redesign

## Goal

Make sAiity feel like a considered Apple utility: native hierarchy first, quiet
content surfaces, clear state feedback, and Liquid Glass used only where it
communicates an active control or system layer.

## Approved Direction

Use the Native Utility direction. The app keeps sAiity's identity in the app
icon and wordmark, but the interface relies on iOS system colors, SF Pro text
styles, standard navigation, inset grouped lists, SF Symbols, and semantic
control states. The keyboard remains voice-only and visually subordinate to the
host text field.

## Design Rules

- Use `systemBackground`, `systemGroupedBackground`,
  `secondarySystemGroupedBackground`, `label`, `secondaryLabel`, and the system
  tint for content and controls; do not use the teal brand color as a surface
  fill or as a decorative gradient.
- Use SwiftUI text styles (`.largeTitle`, `.title2`, `.headline`, `.body`,
  `.subheadline`, `.caption`) so Dynamic Type remains functional. Avoid custom
  fixed-size text except for icon sizing and stable keyboard geometry.
- Keep radii between 12 and 16 points for app surfaces. Do not nest cards or
  turn every row into a floating glass card.
- Keep tappable controls at least 44 points in both dimensions and provide
  accessibility labels for icon-only controls.
- Use Liquid Glass or material only for a functional floating control layer,
  the active microphone control, and the iOS 17 fallback. Content lists remain
  native grouped surfaces.
- Keep Reduce Transparency and Reduce Motion behavior explicit and readable.
- Use sentence case for visible labels. Do not use all-caps labels except the
  compact keyboard language indicator `AUTO`.

## App Surfaces

### Main navigation and Home

Keep three native tabs: Home, Models, and Settings. Show the native navigation
bar and use a large navigation title instead of a custom branded header. Home
uses a system grouped background, one compact readiness section, one prominent
native dictation action, and a recent-result section only when data exists.

### Models

Keep all seven current model choices, installed/available sections, progress,
download errors, language details, active state, and confirmation-gated deletion.
Use native inset grouped list rows with compact metadata and disclosure to the
language detail page. Do not replace the catalog with a reduced card grid.

### Settings

Use native grouped settings sections and preserve the minimal set of
transcription, feature, permission, privacy, and help controls. Do not add back
keyboard layout, keyboard language, number row, haptics, sounds, autocorrect,
transcripts, or About controls.

### Recording

Keep the recording surface stable while the status changes. Use a system
background, a single centered microphone/stop action, restrained waveform
feedback, and a readable status label for recording, transcribing, processing,
success, and failure. Avoid decorative full-screen gradients and large custom
glass panels.

## Keyboard Surface

Keep the voice-only geometry and existing command behavior. Remove the logo and
app name. Use the system keyboard background, a centered 56-64 point primary
microphone control, and compact 40-44 point SF Symbol utility controls on the
rails. The left rail contains the automatic language indicator and keyboard
switch control; the right rail contains delete, return, at-sign, and dismiss in
the existing order. Active recording uses the system recording color; idle and
secondary controls use semantic labels and secondary labels. The layout must
remain symmetric and stable at narrow widths.

## Acceptance Criteria

- App navigation bars are visible and native on Home, Models, Settings, and
  detail screens.
- No app content surface uses a decorative teal fill, gradient, nested card, or
  custom dashboard header.
- The model screen still exposes all seven models and confirmation-gated delete
  actions.
- The keyboard has no logo/header, keeps the microphone horizontally centered,
  preserves all four right-rail commands, and remains readable in light/dark
  mode and with Reduce Transparency enabled.
- Dynamic Type does not truncate or overlap primary labels at the tested sizes.
- Existing DictusCore tests remain green and both iOS device and simulator
  targets build successfully.

