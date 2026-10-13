# Keyboard touch targets and emoji reliability

## Accepted scope

Fix empty-recents landing, category tap/scrub navigation, uninterrupted emoji scrolling, tone selection, and top-row blur. Bring the ABC/123/#+= character geometry closer to the supplied native iPhone reference. Add local next-character prediction exclusively to the invisible touch layer. Preserve existing work and existing page functions.

No suggestion bar, word preview, or autocomplete UI is introduced. Prediction must never resize, reposition, animate, or recolor a key. Ordinary user-requested press feedback and accent menus remain independent of probability updates. No cloud calls, model downloads, silent word replacement, or new dependencies.

## Implementation order

1. Repair emoji navigation lifecycle and gesture ownership. An empty Recents collection opens Smileys. A requested category remains pending until collection data and bounds are ready. UIKit owns each gesture once. Category controls receive only touches inside their actual lane and retain an initiated drag outside it.
2. Use shared static character metrics for letters and symbols: 6.5pt horizontal inset, 6pt horizontal gap, 11pt row gap, up to 45pt face height. The 420pt-wide native reference yields approximately 35pt-wide top-row keys. Compact surfaces reduce height when necessary; commands retain their shared accessible targets. These are reference-calibrated values, not a claim that Apple publishes these exact keyboard metrics.
3. Add pure, testable probability-to-coordinate resolution and integrate it into the active SwiftUI keyboard's UIKit touch owner. The vendored Giella view is currently hidden and cannot serve as the sole integration point.
4. Verify pure geometry/routing, emoji navigation, cancellation, multitouch, long press, accessibility, and static visuals. Build the app and embedded extension. Report device-only evidence separately.

## Architecture

### Static rendering

`KeyboardRootView` produces visual key frames from `VoiceOnlyKeyboardPolicy`. The same frames are inputs to the touch resolver, but prediction is never an input to layout. Character labels, glass plates, and command geometry are stable throughout typing.

### Local context processing

Use the existing local prediction dictionaries and bounded recent context. Compute a normalized next-character distribution away from touch dispatch, on a serialized worker. Coalesce requests; reject stale generations after further typing, cursor moves, field changes, language/layout changes, or dismissal. Passwords and other fields excluded by existing host-field policy use static routing. Do not log context or candidates.

The baseline is a lightweight dictionary/context model, not an LLM or a full grammar parser. Unknown words, mixed-language ambiguity, missing host context, and unsupported scripts must degrade to geometric routing rather than confident guessing.

### Invisible target resolution

At touch-down, the UIKit owner resolves the coordinate against immutable visual frames and a cached probability snapshot. Gaussian spatial scoring permits a likely adjacent character to win a small boundary region. Direct key centers remain authoritative regardless of probability. Commands, delete, space, shift, layout switches, and accessibility activation bypass adaptive bias.

Freeze the chosen key for that touch session; background probability updates cannot redirect an existing hold. A second finger has independent ownership. Accent selection uses the chosen key's existing variants and cancellation rules. Never insert both the original character and a predicted replacement.

The implementation is `AdaptiveLetterTouchRouter.RoutingView.hitTest(_:with:)` in `KeyboardRootView.swift`. It returns an existing `ImmediateKeyButton` or `ImmediateVariantKey` control from a weak, per-page registry; it never inserts text itself. UIKit retains that target for the touch lifetime. Registry lookup requires the same window, page scope, and visible ancestors. VoiceOver and Switch Control bypass the router.

Only horizontally adjacent non-command keys in the same row compete, within 9pt of their shared midpoint and their common vertical extent. The center region (within 34% of a key's width from its center) is protected. An alternate needs probability at least 0.55 and a prior lead of at least 0.15. Its score is `sqrt(p + 0.05) * exp(-0.5 * (distance / sigma)^2)`, with `sigma = 0.42 * min(key widths)`. It must strictly beat the static owner's score. Otherwise ordinary static routing wins. Numeric and symbol keys keep static targets.

The context snapshot is capped at 240 characters. Existing local completions and up to eight n-gram candidates provide the next-character weights; punctuation resets sentence context. This is a conservative heuristic, not a calibrated probability model or grammatical guarantee. Unknown context falls back to static routing. No touch-history storage or personal-text logging is added.

### Emoji ownership

The collection view owns horizontal scrolling and its tone recognizer; the category strip owns category scrubbing. Neither control may consume touches from the other region. Canceling a tone gesture restores scrolling. Four rows fit within the content area above the bottom controls. The fixed delete control has a reserved rail outside the scrolling viewport: blank cells alone would still let moving emojis slide beneath it. The collection's system scroll-edge effects must not blur the first row; remove negative positioning that places content under the toolbar.

## Verification gates

- Empty and populated Recents; category taps and continuous scrubbing.
- At least ten consecutive horizontal swipes beginning directly on emoji glyphs.
- Tone hold, drag to choice, cancel, and scroll again; no duplicate insertion.
- Top and bottom rows visible in light/dark appearance and narrow/wide layouts.
- All supported letter layouts, optional number row, 123 and #+= pages.
- Center taps never stolen; bounded boundary bias; stale/empty predictions use static routing.
- No probability-dependent view changes; no suggestion UI.
- Rapid and overlapping fingers, accent holds, delete, shift, cursor drag, dismissal, VoiceOver.
- Existing Core tests and simulator build; physical-device latency/typo improvement remains an explicit measurement gate.

## Execution prompt

Continue this plan in the existing dirty sAiity-dictus checkout. Inspect current changes and agent status first. Use only GPT-5.6 Luna subagents with disjoint ownership. Implement and verify the active keyboard paths; preserve all unrelated edits. Do not count source-string tests as proof of runtime gestures. Record test/build results and pending physical-device checks. Use ego-browser for any website work. If a TestFlight release is requested, verify the next unused build number and confirm processing plus internal-group availability separately.

## Status

Implementation is present in the worktree. Verification on 2026-09-16:

- `xcodebuild build -project Dictus.xcodeproj -scheme sAiity-iOS -configuration Debug` for the iOS 27 iPhone Air simulator: **BUILD SUCCEEDED**, including the embedded keyboard. Log: `/tmp/saiity-keyboard-build-final.log`.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` in `DictusCore`: **1,667 tests, one skipped, zero failures**. Log: `/tmp/saiity-keyboard-final-tests.log`.
- The held-dictation regression was fixed while finalizing verification: direct start now fails closed and exposes the explicit recovery state; it no longer opens sAiity from the hold gesture.
- Standalone `scripts/test-emoji-tone-selection.swift`: passed all tone, scroll-offset, Recents, cancellation, and overlap checks.
- Simulator visual harness uses the real keyboard views, with a substitute prediction state and category overlay equivalent to the controller's overlay. It is not proof of extension lifecycle, host-field delivery, or actual contextual inference. Four rows and the first row render unobscured after reserving the delete rail. Letter geometry was inspected at 420pt width.
- Harness runtime checks: empty Recents opened Smileys; category tap and scrub changed categories; ten consecutive horizontal grid swipes advanced pages; a tone hold displayed six skin-tone options. Evidence screenshots are under `/tmp/saiity-emoji-harness.dM2Pv8/` (`runtime-initial-fixed.png`, `runtime-category-scrub-fixed.png`, `runtime-ten-swipes-fixed.png`, `runtime-tone-hold.png`). Tone selection/cancellation is covered by geometry checks, but a complete production-host gesture lifecycle is still pending.
- Physical-iPhone overlapping touches, accessibility use, host transitions, and measured latency/typo reduction remain pending. No TestFlight release was performed for this change.

Ponytail guided reuse of existing key controls, local dictionaries, and UIKit scrolling; no dependency or second insertion pipeline was added.
