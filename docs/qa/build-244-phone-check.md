# Build 244: 15-minute manual phone check

Status: **not run; every box below is unverified**. This is a manual acceptance plan for the next candidate, not evidence that build 244 exists or is installed. The current project version is still **1.0.0 (243)**. This task does not bump versions, install a phone build, cut TestFlight or upload anything.

## Before the timer

The owner performs these checks on their own iPhone. Use only new disposable Notes and an unsent Messages draft; do not share private history or send a message. Speak the fixed test sentences yourself, or use an expressly consented/licensed recording. No agent records the room.

- Install the intended candidate only under separate explicit direction. Record the actual installed version/build and source revision; an older installed build cannot validate these commits.
- Have two Whisper models already downloaded (for example Base and Small). Downloads and initial installation are outside the 15-minute budget.
- Confirm iPhone Settings > General > Keyboard > Text Replacement has at least one entry (English iPhones include `omw` → `On my way!`) and note its shortcut.
- Prepare Notes and an unsent Messages conversation. Confirm Syllivra is enabled under iPhone Settings > General > Keyboard > Keyboards, and record the original Full Access/microphone permissions.
- Record current model choices, spoken/output languages, writing style, Show top bar, haptics and presence settings so they can be restored. Set English as a typing/spoken language for the fixed English phrase.
- Set Syllivra > Keyboard > Show Top Bar to Off. Enable Autocorrection there. Have the iOS VoiceOver shortcut ready.
- Fill in: phone/OS ___; installed version/build ___; source revision ___; voice models ___; tester/date ___.

For every item, record Pass, Fail or Blocked, the observed result and elapsed time. Mark a box only after the physical steps succeed. A missing control, unsupported feature or timeout is not a pass.

## Timed checks

### 00:00–01:00 — More menu and board power

- [ ] In Notes, focus an empty note and choose Syllivra with the globe. Hold the bottom-left 123/ABC key to open the dictation board. Tap the ellipsis at the top left with Show top bar Off; dismiss by tapping outside and repeat. Open Output language, return to the menu and choose Dismiss keyboard. Reopen the keyboard and toggle board power at the top right.
- **Expected:** the ellipsis opens an iOS dropdown on each tap; menu items are usable and dismissal works. Ellipsis stays left, power stays right, and neither control starts dictation, deletes text or shifts into the other control's target. Power visibly reflects its state.

### 01:00–03:00 — Emoji, skin tones and Delete

- [ ] Tap Emoji. Swipe through two categories, then tap a category icon and insert one emoji from each of the four rows. Long-press 👍, slide to a skin tone and release; then begin another hold and switch to Home with a second finger before releasing. Reopen Notes, check that the cancelled hold inserted nothing, then reopen Emoji and tap the same base emoji. Compare Delete's size with ABC and 123 pages; delete one inserted emoji.
- **Expected:** four rows use the available height, larger glyphs remain unclipped, and category taps/swipes work. A successful hold inserts exactly one chosen variant, never an additional base emoji. Cancellation inserts nothing; the next tap remains usable. Delete retains the shared command-key dimensions and removes one complete emoji without corrupting nearby text. Record any emoji obscured by its overlay.

### 03:00–04:00 — Landscape and ordinary typing

- [ ] Rotate Notes to landscape with Syllivra open. Type `hello 123`, tap Space and Return, and use Delete. Switch ABC > 123 > Emoji, insert 😀, open/close More on the board, then return to portrait.
- **Expected:** rows and controls fit, remain touchable and do not overlap the system globe/microphone area. Space/Return/Delete remain stable between pages. No clipped content, dead zone, lost text or height oscillation appears.

### 04:00–05:00 — VoiceOver

- [ ] Enable VoiceOver using the prepared shortcut. Swipe focus through board More, power, ABC/123 and Delete. Double-tap More, inspect/dismiss its items, then open Emoji, focus a glyph and inspect its available skin-tone actions. Turn VoiceOver off.
- **Expected:** controls have meaningful labels, focus order is usable, More is announced as an action with accessible menu items, and emoji/skin-tone actions insert only the chosen character. Focus does not become trapped or activate adjacent controls. Record inaccessible items separately.

### 05:00–07:00 — Cross-app/background delivery and permission parity

- [ ] In Syllivra, enable Keyboard dictation and wait for readiness. In Notes, dictate “Tomorrow at ten, bring two green folders.” Release/finish, then switch to the unsent Messages draft and dictate “The second draft stays here.” While that request is finishing, briefly switch away and return to Messages.
- [ ] Note the output-language/writing-style choices, reopen More in both apps and confirm they match the configured settings. In iPhone Settings, temporarily turn Syllivra's Allow Full Access off; return to Notes, type `abc` and try dictation. Restore Full Access and re-verify readiness.
- **Expected:** each result appears once in its intended field with the same meaning, no text leaks into the other app, and backgrounding produces either the correct result or explicit recoverable status. Settings agree across the app/keyboard. With Full Access denied, typing remains usable and dictation explains the restriction instead of claiming readiness or inserting stale text. Restoration recovers without reinstalling. Do not send the draft.

### 07:00–08:00 — Microphone-on haptics and cancellation

- [ ] With microphone access already granted and keyboard haptics at Default, begin two short dictations in Notes, one by tap and one by hold. Observe the recording state and feel when the mic becomes active. Cancel one before insertion. Turn Keyboard haptics Off, repeat a start, then restore the original setting.
- **Expected:** feedback corresponds to actual microphone activation, with no premature or duplicated mic-on pulse. Hold/release and cancel finish cleanly; cancellation produces no late insertion. The app's Off setting suppresses app-generated haptics. Record OS/hardware haptic settings if feedback is absent.

### 08:00–09:00 — System Live Activity

- [ ] Turn on Syllivra > Dictation > Live Activity. Enable keyboard dictation, background the app and inspect Lock Screen/Dynamic Island where supported. Run a brief dictation, stop it and observe that recording state ends. Turn Live Activity off again.
- **Expected:** the real system activity reflects standby/recording/finishing accurately, never remains stuck as Recording, and ends when the setting or the service is turned off.

### 09:00–10:00 — Text replacements and autocorrect

- [ ] In a new Notes paragraph, type the iOS text replacement shortcut noted before the timer, then Space. Type `teh`, `goign` and `becuase`, each followed by Space.
- **Expected:** the shortcut expands to its phrase followed by one space. The three words become `the`, `going` and `because`. If Syllivra Replacements appears under Syllivra > Keyboard (snippets from an earlier version), one of those shortcuts also expands.

### 10:00–12:00 — Voice model switch and foreground loss

- [ ] Open Syllivra > Models and pick the second downloaded Whisper model in Voice Model. Measure time from selection to Ready. Tap New Dictation and say the fixed “Tomorrow at ten…” sentence; record first-result and final-result delays. Start another dictation, cancel before completion, then start again. During the last request, briefly background and reopen Syllivra. Set Voice Model back to its recorded choice.
- **Expected:** the model reaches Ready or shows an actionable failure, without a crash or endless spinner, and the keyboard keeps working. Output keeps the sentence's meaning. Cancellation never delivers an old result into the next session. Foreground loss stops or recovers truthfully. Record actual timings; no speed or memory claim follows from this short check.

### 12:00–15:00 — Intentional spelling overrides and restoration

- [ ] In a new Notes paragraph, type an unfamiliar spelling followed by Space. Try `bonjor`; if it is not corrected, choose another token that visibly autocorrects and record the typed/replacement pair. Backspace away the inserted space and correction, retype the original spelling at the same caret position, and press Space. Repeat the original spelling three times, dismiss/reopen the keyboard and type it once more.
- [ ] Repeat one override in the unsent Messages draft. Move the caret to an earlier word and make a normal edit; confirm it does not unexpectedly rewrite trailing text. Check Syllivra > Keyboard > Vocabulary if the override appears as a learned word. Restore the initial model, permissions, language/style, top-bar, haptic and presence choices; leave no recording running.
- **Expected:** deliberate restoration is respected immediately and is not repeatedly changed back by a cached correction. The chosen spelling remains protected after reopening and in the other app where learning applies. Unrelated text/caret edits remain intact. If no token autocorrected, the override path was not exercised: mark it blocked, not passed. Do not clear the entire dictionary to make this test work.

## Follow-up gates this smoke check cannot close

Keep these separate and unchecked; 15 minutes cannot establish full release readiness:

- [ ] Repeat More/emoji/landscape with top bar On, light and dark, large text, other screen sizes and additional host apps.
- [ ] Exercise URL/search, numeric, secure and one-time-code fields; secure fields may correctly use the system keyboard. Confirm field-aware actions, default writing style and all denied/restored permission paths.
- [ ] Use licensed/consented multilingual files and independent native-language review for English/German/Chinese switches, cleanup, translation meaning, Apple Translation pair availability and out-of-selection language handling. Text guards are not semantic proof.
- [ ] Measure repeated cold/warm loads of the larger Whisper models, inference, sustained latency, memory/thermal pressure, interruption and foreground-loss recovery on the phone, including long recordings and cancellation during loading.
- [ ] Check long background/Lock Screen sessions, interruption recovery, delivery/undo and Live Activity cleanup beyond the timed smoke check.

## Local verification

On 22 Oct 2026, branch `claude/slim-native` (4d39fcd2): 1,811 kernel tests passed; `scripts/test-key-grid-typing.swift`, `scripts/test-multilingual-autocorrect.swift` and `scripts/test-autocorrect-overrides.swift` passed on the iOS 26.5 simulator; `scripts/test-aosp-trie-concurrency.mm` passed under ASan/UBSan and TSan. See `2026-10-21-slim-native.md`. These are Mac and simulator results, not physical acceptance.
