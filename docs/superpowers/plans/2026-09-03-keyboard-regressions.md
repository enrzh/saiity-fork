# Keyboard Regression Repair

## Scope

Repair the current `saiity-fork` checkout without disturbing existing dirty
artifacts. Use SimSlim only for runtime verification.

## Task 1: Dictation handoff

- Trace the current keyboard microphone path through App Group state, Darwin
  notifications, URL fallback, and app-side recording startup.
- Reproduce the failure with the existing SimSlim device/log path before
  changing production code.
- Add a regression test for the observed broken handoff or status transition.
- Make the smallest fix that restores a normal press-and-hold session and keeps
  retry behavior available after a failed attempt.

## Task 2: Auxiliary pages and geometry

- Keep emoji selection on the emoji page after insertion.
- Make symbol keys commit on a normal tap; do not let the drag gesture consume
  a tap.
- Make the vertical `@` to emoji gap equal to the horizontal emoji to `123`
  gap.
- Increase the shared dictation/keyboard surface height by exactly 10% from its
  current fallback while preserving runtime bounds safety.
- Add regression coverage before implementation and verify light/dark layout
  behavior through the SimSlim build.

## Verification gate

- `swift test --package-path DictusCore` focused tests, then full suite.
- `xcodebuild` build for the existing `sAiity-iOS` scheme in `Dictus.xcodeproj`.
- SimSlim `AC636497-5EC6-4AD4-BD83-E5E2458FA702` only; no DeviceHub, physical
  iPhone, iPhone Mirroring, or TestFlight until the keyboard flow is verified.
