# Keyboard fixes after TestFlight 79

## Changes

- Removed the Open sAiity / Hold to dictate control from the top accessory bar, including its transparent UIKit hit target. Auto, clipboard and keyboard-down remain.
- Letter Caps/Delete and symbol #+=/123/Delete use the dictation board delete face dimensions (40 pt high, board-derived width), with the same 18 pt continuous glass corner radius. Character-row height no longer stretches these faces; command highlight layers stay within their visual faces.
- Emoji tone selection is independent of the key-popup preference. Popup anchoring converts collection-view content coordinates into viewport coordinates after any horizontal scroll. A stationary hold reveals tones, dragging selects, and release inserts one emoji. Cancellation inserts nothing, a hold without movement preserves the original tone, and VoiceOver exposes tone actions. Pager panning and long-press selection no longer recognize simultaneously.
- Cold microphone starts use a foreground handoff through SwiftUI's public URL action. A loaded model/Live Activity alone is not evidence that iOS permits background microphone activation. An already-running audio engine retains the background Darwin route.
- Keyboard touch cancellation caused by that intentional handoff no longer cancels the recording request. A real release still stops/cancels it. Leaving a held control's bounds no longer counts as lifting the finger.
- A cold Darwin request stays pending for foreground recovery instead of immediately attempting a background activation that can fail before the fallback runs. Audio-session activation errors now propagate instead of being swallowed. Idle suspension interruptions cannot cancel an awaiting start or post-capture transcription. Genuine recording interruptions still invalidate the generation, cancel recording and publish an error.

## Validation

- DictusCore: 1499 tests passed, zero failures, including a new command geometry invariant across five widths and varying row heights. Existing routing assertions were updated for the intentional URL and accessory-bar changes.
- Xcode 27 RC simulator build of DictusApp and embedded extensions succeeded; final incremental verification log: `/tmp/saiity-keyboard-fixes-build.log`.
- `git diff --check` passed. Existing unrelated dirty and untracked work remains preserved.
- Installed the simulator build and enabled sAiity in the simulator keyboard list. iOS 27 registered the extension, but kept the software keyboard (including Apple's own keyboard) off-screen, preventing live gesture verification. No microphone recording was attempted in the simulator.

## Phone checks still required

1. With the model loaded and microphone idle, hold the board mic: the app should open and begin recording, rather than showing an immediate failed/interrupted state. Complete recording in the app and return for insertion. A fresh background microphone start is not promised; keeping the mic off between dictations requires this handoff.
2. During an actual recording, an incoming call must still interrupt and report the failure. Releasing a normal board hold must stop once; dragging just outside the button must not stop early.
3. On emoji pages after multiple swipes, hold a hand/person emoji, drag across tones and release. Verify one insertion, correct popup position, unchanged original tone on a stationary release, and normal swiping before a hold. Repeat with key popups disabled and on Recents.
4. Compare large command faces on ABC/123/#+= with the dictation-board delete face, including the pressed appearance. The top accessory bar must have no hidden dictation target.

These changes are local and are not included in the already-uploaded build 79. No new archive, upload, GitHub push or CI run was performed for this follow-up.
