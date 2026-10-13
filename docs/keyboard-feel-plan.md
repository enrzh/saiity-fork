# Keyboard feel plan

Date: 2026-09-22
Status: plan only. Do not implement until this plan is accepted.
Branch: `cursor/keyboard-surface-fixes-a66e` at `e275e1a1`.

Device evidence is pending. App Store Connect has sAiity 1.0.0 (147) Testing on sAiity Beta Testers. The tester row last showed Installed 1.0.0 (146). Reports below may still be from 146/144. Reproduce on 147 before treating a tree fix as done.

Visible contract stays: native-gapped letter/symbol plates, no equal-size key drawing, no suggestion bar. Invisible behavior may change.

## Direction

Five separate failures, one owner each. Do not mix them into a redesign.

1. Next-key bias should follow letter logic, not language.
2. Empty Recents space must page, and the category circle must still drag.
3. Open sAiity is a tap, not a hold.
4. Key feedback should feel like the system keyboard.
5. Solid material is chrome only. Hits stay the same as glass.

Use the smallest existing path. No second dictionary, no new overlay, no visual key-size change.

## 1. Typing lag and wrong next-letter bias

User: typing is not responsive; predicted next keys are wrong. Prefer common-letter logic over language.

What the tree does now:

- `SuggestionState.updateAdaptiveTouchPrediction` sets `adaptiveTouchPrediction = nil` on every keystroke, then rebuilds on `suggestionQueue` from word completions, frequency-word prefixes, n-grams, and language detection (`TextPredictionEngine.nextCharacterProbabilities`, `setLanguage(forRecentText:)`).
- `AdaptiveTouchResolver` only redirects in the seam when a letter is ≥55% with a 15-point lead, or grows the target when ≥75% with a 25-point lead. Centers stay static.
- Sentence start already refuses `"the"`/`"a"`/`"I"` by returning an empty distribution.

Why it feels wrong:

- Clearing the prior on every tap leaves the next finger on a static key until the worker finishes. That is lag, not cleverness.
- The worker is chasing words in a language. After space it leans on continuation words; mid-word it leans on dictionary completions. That is why the grown target is often the wrong neighbor.
- Letter frequency is cheap and stable: E T A O I N after a boundary, Q→U, T→H, and so on. It does not need language detection.

Smallest fix:

- Keep `AdaptiveTouchResolver` and the invisible-only rule.
- Replace the next-letter snapshot with a static letter-unigram plus letter-bigram table in `DictusCore`. No trie, no `frequencyDict.topWords`, no typed-language switch on this path.
- Do not nil the live prior until a replacement is ready. A miss uses the static key.
- Leave space-autocorrect and dictation facts on their own snapshot. This change is touch bias only.
- Keep command, space, delete, emoji, and secure/URL/email/search/number fields unredirected.

Acceptance:

- After space, grown targets follow common English-letter frequency, not `"the"`.
- After `q`, `u` is the only confident neighbor.
- A keystroke does not blank the prior before the next tap.
- Centers still type the visible key.
- Plates and gaps do not move.

Pending on device: type `q`, `t`, then a space, on 147. Confirm which neighbors actually steal the seam.

## 2. Empty Recents swipe and category bar

User: on Recents, swiping the blank area is ignored, and the emoji bar does not work either.

What the tree does now:

- Recents is a full page even with a few glyphs. Blank cells are non-interactive fillers (`EmojiPickerView` around the 4×N grid).
- `EmojiHoldGestureRecognizer` receives every touch and sets `.failed` when `canBeginVariantHold` is false, so `pan.require(toFail: hold)` can start.
- `cancelsTouchesInView` is still true on that hold.
- The category control only starts on `collapsedCircleFrame` (`EmojiCategoryScrubControl`). The SwiftUI bar is visual-only.
- `PassthroughControlsView` is a full-size overlay. It forwards the scrubber first, then other UIKit controls, then SwiftUI.

Likely leftover race: a failed hold that cancelled the touch, or the overlay eating the blank Recents pan before the pager sees it. The circle-only hit target is correct for grid swipes, but if the overlay owns the whole board, a drag that starts near the bar can miss both the pager and the circle.

Smallest fix:

- Empty Recents cells must never own a gesture. Keep fillers non-interactive.
- A hold that cannot begin must fail without cancelling the pan (`cancelsTouchesInView = false`, or fail before the pan waits).
- Confirm `PassthroughControlsView.hitTest` returns nil for blank Recents so the collection view pages.
- Category drags still start on the visible circle only. Do not enlarge the bar back into a full-width trap.
- If the circle itself is dead on Recents, it is an overlay/z-order bug, not a new scrubber.

Acceptance:

- Blank Recents space pages to Smileys.
- A swipe on a Recents glyph still inserts or pages; a hold still opens skin tones.
- Dragging the circle still scrubs Recents through Flags.
- A grid swipe that starts off the circle does not expand the bar.

Pending on device: Recents with 0, 3, and a full page of glyphs, on 147.

## 3. Open sAiity tap does nothing

User: the Open sAiity button does not respond.

What the tree does now:

- The visible label is the dictation capsule, not the gear. Gear accessibility text also says "Open sAiity" (`ToolbarView.settingsButton`) and is a different control.
- Recovery tap is supposed to fire on touch-down: SwiftUI `ImmediateKeyButton` with `holdDuration: nil` when `appNeedsAppAction`, and UIKit `handleMicTouchDown` calling `openDictusForRecovery()` without the hold timer.
- `openDictusForRecovery` refuses repeats inside 0.75s, then opens `saiity://dictate?source=keyboard&intent=prepare` on the next run-loop turn through the extension context, with SwiftUI `openURL` as fallback.
- Two hit owners exist: the SwiftUI capsule and the UIKit mic in `PassthroughControlsView`. A stale overlay can eat the tap. A readiness refresh can still flip recovery into an unrecognized hold on the UIKit path.

Smallest fix:

- One owner for the visible Open sAiity control. If UIKit is showing the mic, SwiftUI must not also claim it, and the reverse.
- A tap on the labeled control always calls `openDictusForRecovery()` on touch-down. No hold threshold, no 0.75s silent refuse without a visible result.
- If Full Access / `extensionContext.open` fails, keep the existing "Unable to open sAiity" status. Do not fail quietly.
- Do not change the Hold to dictate path.

Acceptance:

- With the capsule showing Open sAiity, one tap opens the app or shows the failure string.
- Hold to dictate still requires a hold.
- The gear still opens Settings, not the recovery URL.

Pending on device: Full Access on and off, on 147.

## 4. Haptics no longer feel like the native keyboard

User: haptic feedback is not native iOS keyboard-like anymore.

What the tree does now:

- Letter taps call `HapticFeedback.keyTapped()` from `handleLetterKeyBegan`. That is `UIImpactFeedbackGenerator(style: .rigid)` plus `prepare()` before and after.
- `KeyboardInputView.enableInputClicksWhenVisible` is true, but nothing calls `UIDevice.current.playInputClick()`.
- Native keyboard click is the input-click path, not a custom rigid impact. Rigid plus extra `prepare()` reads as a thunk, and it drifts during fast typing.

Smallest fix:

- On key down, call `playInputClick()` for letters, symbols, space, and commands.
- Stop using `keyTapped()` rigid impact for those keys. Keep recording / dictation / variant-popup generators as they are.
- Do not add a Settings haptic redesign.

Acceptance:

- A letter tap matches the system keyboard click more closely than a rigid thunk.
- Rapid typing does not stack delayed impacts.
- Dictation hold and skin-tone popup stay distinct.

Pending on device: compare side by side with the Apple keyboard, haptics on, sounds on and off.

## 5. Solid material makes the keyboard dead

User: in solid material mode the keyboard is totally different, unresponsive, buttons do not work.

What the tree does now:

- Setting is `SharedKeys.liquidGlassEnabled` false via `KeyboardMaterialPicker`.
- `KeyboardGlassSurface` still does `plate(content).allowsHitTesting(false)` for every chrome path. The comment already says a hittable solid fill swallowed taps, which is why solid felt dead.
- Letter keys are a ZStack of a visual plate plus `ImmediateKeyButton`. That split is right if the button stays above a non-hittable plate.
- `appleControlSurface` in the non-glass branch applies `allowsHitTesting(false)` to the whole control, not just the fill.
- `commandKeyPlate` still requests interactive glass. Interactive glass competes with `ImmediateKeyButton`. Solid must not take a different hit path than glass.

Smallest fix:

- Chrome is visual in both materials. Hits stay on `ImmediateKeyButton` / `ImmediateVariantKey` / UIKit voice controls.
- Solid fill and glass plate both use `allowsHitTesting(false)` on the fill only, never on the key control.
- Do not special-case solid in the adaptive router or the passthrough overlay.
- Add/keep a contract test that solid and glass share the same button owner.

Acceptance:

- Solid letters, symbols, space, delete, emoji, and Open sAiity tap the same as glass.
- Switching material does not change key size or gaps.
- No second tap or missed tap unique to solid.

Pending on device: toggle Solid on 147, type, delete, space, emoji, and Open sAiity.

## Out of scope

- Visible key-size or gap changes.
- Suggestion bar.
- New languages or a second prediction engine.
- TestFlight upload, commit, or push unless asked.
- Development install that wipes the app container.

## Verification

- Source tests around `AdaptiveTouchRouting`, Recents hold/pan, Open sAiity touch-down, `playInputClick`, and solid hit owners.
- Device pass on 147 for all five. Until that pass, each item stays pending.

## Execution prompt

Continue sAiity-dictus in /Users/enricomini/Documents/Github/sAiity-dictus on branch cursor/keyboard-surface-fixes-a66e. Read docs/keyboard-feel-plan.md and the current tree before editing. Do not commit or push unless asked. Preserve dirty/untracked files. Do not change visible key gaps or the dictation board layout.

For coding, use the local grok CLI with --sandbox off. Do not use GPT Web. Review and test Grok edits before keeping them.

Fix only the five items in that plan, smallest path each:

1. Next-letter bias from letter unigram/bigram logic, not language. Do not nil the live prior on every keystroke.
2. Empty Recents pages; category drag still starts on the circle.
3. Open sAiity responds on tap-down, one hit owner, visible failure if the URL cannot open.
4. Native key click via playInputClick; no rigid key thunk.
5. Solid material uses the same hit owners as glass; plates stay visual-only.

Keep the plate revert: visualFrame for drawing, frame for hits. If a TestFlight build is needed later, it must be 147 or higher and must not ship equal-size key containers. Device confirmation on 詹。手机air is pending until 147 is installed.
