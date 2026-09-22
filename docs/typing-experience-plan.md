# Typing experience plan

Date: 2026-09-22
Status: implemented in the working tree on 2026-09-22. Not committed, and not yet installed on the phone. A device pass is still required for the resting keyboard, Recents paging, and the category drag.

Branch: `cursor/keyboard-surface-fixes-a66e` at `ba2c3117`, plus the uncommitted hint removal in `DictusKeyboard/KeyboardRootView.swift` and `DictusKeyboard/Views/AuxiliaryBottomBar.swift`.

The phone currently runs sAiity 1.0.0 (144). That install is older than `ba2c3117`. Behavior reported on the phone is not proof of what this tree does until the same build is on the device.

Landed in the working tree:

- Hit rectangles are no longer drawn. Invisible targets stay the same size, and a confident next letter owns a wider slice without taking a key's center.
- Facts, restored spellings, and an empty word-pair table leave the seam neutral. A name already in the field pulls the next letter.
- Space uses that prepared correction when it is ready, and does not wait while the dictionary is loading. A commit is an accent, an apostrophe, a one-character split, or a one-letter slip.
- Dictation cleanup keeps names, clock times, amounts, and codes.
- A swipe on empty Recents space pages. The category drag starts on the visible circle, and VoiceOver describes a horizontal swipe.
- Recent dictations open the full transcript. Vocabulary deletions reach the keyboard. Settings copy matches space-to-correct and sentence language. The keyboard handoff idle title matches Speak.

## Direction

Prediction is there so a fast typist lands on the letter and the word they meant. The keys stay where they are. A likely next letter gets a larger invisible hit target. When the word ends, the same prediction may commit one correction. Dictation uses the same facts and the same language, and it does not insert a word the person did not say.

There is no suggestion bar. `SuggestionBarView` stays unmounted. `update` and `updatePredictions` keep feeding nothing on screen.

## What already works and stays

- Autocorrect on space, one language dictionary at a time: the AOSP trie, `UITextChecker`, and the frequency list. French accent, contraction, and apostrophe fixes stay.
- A name, an all-caps token mid-sentence, a digit token, and a word the user just restored are left alone.
- Adaptive touch redirects only in the seam between two letter keys, and only when the other letter is at least 55% likely and leads by 15 points. The center of a key types that key. `AdaptiveTouchResolver` in `DictusCore` owns that rule.
- Secure, URL, email, search, and number fields get neither autocorrect nor a touch prior.
- Key artwork does not move.
- The emoji category control stays a drag scrubber. The grid stays free-scrolling.

## 0. Hitbox hints

Done in the working tree. Not committed.

Each key was drawing its hit target. `KeyHitTarget.prepare` filled every control with a 1% label wash, so the expanded cell was faintly visible at rest. A press then stroked a 1-point border around that same cell.

The wash is clear. The border width stays 0. Press darkening is allowed only when a caller passes an explicit `highlightSize`, which is the visual plate. `ImmediateVariantKey` fills the hit target itself, so it no longer paints on press. `point(inside:)` and the 6-point expansion are unchanged, so the invisible target is the same size.

Letter pages currently set `visualFrame` equal to the gap-absorbed hit frame (`KeyboardRootView` letter positioning). A press can still darken that whole cell. On device, confirm the resting keyboard has no rectangle around the glyphs. If a press still reads as a hitbox, the follow-up is to darken the glyph only. That follow-up is a separate keyboard ask.

Acceptance:

- At rest, letter, symbol, command, and variant keys show no hit rectangle.
- A touch in the seam and a touch in the key center still hit the same keys as before.
- Command plates still darken their own face while pressed.

## 1. One prediction snapshot

Build this in the existing engine (`TextPredictionEngine`, `SuggestionState`, `AdaptiveTouchRouting`). Do not add a second dictionary or a bar.

The snapshot is what both touch and autocorrect read:

- the language in force
- the partial word, or the fact that the caret is after a boundary
- the one or two committed words before it, inside the current sentence
- tokens marked as facts
- a next-letter distribution already in memory
- at most one correction candidate for the word that just ended

Facts are tokens the dictionary must not rewrite: a name, an amount, a time, a date, an invoice or product code, a mixed letter-digit token, a second script, and a spelling the user restored after a correction. `Peter`, `125.50`, `AB-120`, `4am`, and `我确认` are facts. While one of those is being typed, that token gets no prior and no correction. The words around it still can.

Once a fact is committed it becomes context. After `invoice AB-120`, the next-letter prior follows `invoice` and the code. After `125.50`, a likely next word comes from the local word pairs and from earlier text in this field. The amount stays `125.50`. A name already in the field, or dictated a moment ago, is a candidate when those letters start again, ahead of a common dictionary word with the same prefix.

Timing is part of the interaction. The prior for the next touch is computed while the current key is going down, from the snapshot already in memory. If that work is not finished when the finger lands, the touch uses the static key. A late prior never changes a key that has already been accepted. `SuggestionState.updateAdaptiveTouchPrediction` already cancels stale work. Keep that gate. Do not move the resolver onto the main thread's dictionary load.

After a space, the prior is the first letter of a real continuation. If the local word-pair table has nothing, the seam stays neutral. `TextPredictionEngine.nextCharacterProbabilities(after:)` currently fills that hole with `frequencyDict.topWords`, and `predictNextWords` does the same when the trigram is empty. That fallback is what makes the keyboard lean toward letters the user did not mean. Touch and autocorrect stop using it. An empty distribution means a static key.

Language: the selected keyboard covers the first few words. Once the sentence is clearly German, English, Spanish, or French, completions and corrections follow that language until another supported language clearly takes over. A Chinese, Japanese, or Korean word is left untouched. `shouldAbstainFromPrediction` and `shouldSkipTokenPrediction` stay the gates. Do not reload the trie on every keystroke. The selected language resets only when the setting changes or the field is cleared.

Acceptance:

- A touch that arrives before the snapshot publishes types the static key.
- `the` and the other top unigrams never appear as a touch prior after an unknown word or a fact.
- `AB-120` and `125.50` round-trip unchanged, and the following word can still be corrected.
- The first letters of a name already in the field pull toward that name, including in the seam.
- A mixed-script token ends prediction for that token only.

## 2. Larger invisible targets for predicted keys

This is the typing product. Autocorrect is the extra.

Today the likely letter wins only inside a 9-point seam, and only with a 55% probability and a 15-point lead (`AdaptiveTouchResolver.resolve`). The center third of either key is never redirected. That rule stays for an uncertain prior.

When the snapshot is confident, the predicted letter's invisible target grows into the seam and a bounded slice of the neighbor. The neighbor's center still types the neighbor. Two confident neighbors never both own the same point: the higher probability wins, and a tie keeps the static key. Command keys, space, delete, and the emoji key do not grow. Secure, URL, email, search, and number fields do not grow.

Nothing about the growth is drawn. The hint removal in section 0 is the visual contract for this phase. Key caps, gaps, and corner radii stay as they are.

The growth has a ceiling so a very likely letter cannot swallow the key beside it. Start from the existing seam and the existing center exclusion, and widen only the predicted side. Measure on the real grid before picking a larger number. A wrong ceiling makes fast typing worse than a static keyboard.

Acceptance:

- A touch in the middle of a key types that key, including when the neighbor is very likely.
- A touch in the grown region of a confident letter types that letter, and types the static key when the snapshot is missing or below the existing confidence floor.
- Overlapping fingers, a hold for accents, and a cancelled touch still belong to the control that received them.
- VoiceOver and Switch Control keep the static key. The router already returns nil while those are running.

## 3. Autocorrect, from the same snapshot

Space and punctuation commit one correction, or none, in the same turn as the space. The replacement is a small, high-confidence change: an accent, a missed apostrophe, a split the neighboring keys explain, or a one-letter slip the dictionary and the previous word both agree on. A name, an acronym, a fact, or a word the dictionary already knows stays as typed.

The correction is reversible from the place just typed. Changing it makes that spelling the user's immediately. Repeating a word the dictionary does not know can teach it later. One undone autocorrect must not teach the dictionary a name. `rejectedWords`, `pendingAutocorrection`, and `UserDictionary` already own this. Extend them. Do not add a parallel learner.

`handleSpace` currently spell-checks on the main thread through `performSpellCheck`, which syncs onto the suggestion queue. That is acceptable only while the snapshot from section 1 is already computed. A space must not wait on a dictionary load.

Acceptance:

- Space inserts the space and at most one replacement before the next frame the typist can see.
- Undo restores the typed word and the spacing around it, and a second space does not put the rejected word back.
- Digits, codes, and a second script are never the thing that gets replaced.

## 4. Dictation uses the same facts

Dictation cleanup and the keyboard read one fact list. A name, amount, time, date, or code in the transcript is kept through cleanup. When cleanup is unsure, the raw text remains available. Dictation does not append a predicted next word.

A name that was just dictated is a candidate the next time those letters are typed or spoken. That candidate lives in the existing vocabulary path, with a way to remove it from Vocabulary in Settings. Learning still requires the user to keep the spelling. A single cleanup pass must not invent a vocabulary entry.

`localContinuationCandidates` already refuses the frequent-word fallback. Keep that split. Do not point dictation at `predictNextWords`.

Acceptance:

- A dictated `Peter`, `125.50`, and `AB-120` survive cleanup on the existing fixtures.
- The following typed word can still be corrected.
- Cancelling dictation inserts nothing, including a late prediction.

## 5. Emoji paging and the category control

Keyboard files. Reproduce on this tree before editing. The phone report is from build 144. `ba2c3117` already tries to treat blank Recents cells as swipeable, and the bug can still be in that attempt.

### Empty space on Recents

`EmojiPagerCollectionView` sets `pan.require(toFail: hold)`. `shouldReceive` returns false for the hold when the finger is not on an emoji that has skin tones. A recognizer that never receives the touch never fails, so the pan waits. A swipe that starts on an emoji works, because the hold receives it and then fails the 8-point jitter test. A swipe that starts in a blank Recents cell does not.

The hold should see the blank-cell touch and fail immediately (`gestureRecognizerShouldBegin` returns false). It should begin only on an emoji that actually has variants. Blank cells and the gaps between them belong to the page, which `EmojiPageCell.hitTest` already tries to do.

Confirm on device: empty Recents, a few Recents with blank cells, a full page, a swipe that starts on a glyph, a swipe that starts between glyphs, and a long-press that opens tones. A tone commit stays one insert. Cancelling the popup inserts nothing.

### Category control

The artwork is a circle. The hit target is the full-width track above the spacebar (`floatingEmojiCategoryFrame`, `interactionBounds`). A stationary touch does nothing. The bar expands only after a horizontal move of 7 points that is at least as large as the vertical move. The VoiceOver hint says to swipe up or down. The icons inside the expanded capsule do not receive touches (`EmojiCategoryBar` is `allowsHitTesting(false)`). UIKit's `EmojiCategoryScrubControl` is the only owner, which is the right split. The gesture itself is why the control feels unusable.

Keep the scrubber. Make the visible circle the place a drag starts, so the invisible track stops eating grid swipes beside it. A horizontal drag still scrubs Recents through Flags with the current travel. Once the bar is expanded, a release on an icon selects that category. VoiceOver keeps increment and decrement, and the hint matches the horizontal drag.

The grid and the scrubber stay in sync through the existing `emojiCategoryJump` token. A scroll must not schedule another jump.

Acceptance:

- Blank Recents space pages horizontally.
- A long-press on a tone-capable emoji still opens the popup, including after the hold-failure change.
- Dragging the visible category control reaches the first and last category.
- A swipe on the grid next to the circle pages the grid.
- Delete and the bottom bar stay where they are.

## 6. App polish

App targets only. Continue `docs/product-design-and-behavior-plan.md` where `ba2c3117` has not already landed the work. Speak readiness, the model rows, and onboarding are already on this branch. Leave them unless a device pass shows the status text disagreeing with the action.

Still worth doing, in this order:

1. Speak's recent rows open the transcript they name. History keeps copy, share, and delete. Add a detail only where the list currently dead-ends. Do not store audio. Do not promise an Original / Cleaned pair unless both strings are already stored.
2. Settings copy matches behavior. Autocorrection's hint can say it corrects on space. It must not mention a suggestion bar. The Keyboard footer says language follows the iPhone, while prediction can stay on a detected language for the rest of a sentence. Say that.
3. Vocabulary shows words the keyboard has learned, and deleting one removes it from later prediction. Text replacements stay the separate list they already are.
4. `SwipeBackOverlayView` still uses "Ready when you are" for idle. Use the same readiness title as Speak.
5. Dynamic Type, dark and light, and VoiceOver on those screens. Reduce Motion and Reduce Transparency where a material changed.

Key containers stay a setting. This plan does not turn plates on or off.

## Order

1. Section 0 is in the working tree. Device-check the resting keyboard, then commit only if asked.
2. Section 1, the snapshot, behind tests in `DictusCore` and the prediction contract tests. No key geometry changes.
3. Section 2, invisible growth, after section 1 is publishing a snapshot on time.
4. Section 3, autocorrect, on that snapshot.
5. Section 4, dictation facts, which can proceed beside section 2 once the fact list exists.
6. Section 5, after a device reproduction on this tree.
7. Section 6 whenever app-only work is asked for. It does not need a keyboard edit.

Signing this Mac onto team `H8FW6W6K2D` is still required before a new build can be installed on **詹。手机air**. A development install replaces the app container.

## Out of scope

- Moving key caps, drawing likely keys, or mounting `SuggestionBarView`.
- A cloud prediction service, a new model, or bringing Qwen back.
- Changing the default branch `saiity-fork`.
- Committing, pushing, or installing, until asked.
