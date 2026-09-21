# Optional post-dictation suggestions and Settings cleanup

## Objective

Offer local, explicitly accepted continuations after dictation without delaying insertion or changing the authoritative cleaned transcript. Simplify Settings to necessary controls.

## Product decisions

- Suggestions after dictation is off by default.
- This does not restore general typing suggestions.
- Cleanup continues to handle grammar and punctuation; prediction offers a next word or short continuation.
- Preserve mixed languages. Never translate, silently replace text, or invent corrections to names or numbers.
- Low confidence means no suggestion.
- No new account, cloud inference, or model download.

## Implementation sequence

1. Inspect the existing prediction engine, transcript insertion, host-context access and cancellation paths. Reuse working local components; UILexicon supplements vocabulary but is not itself a next-word model.
2. Simplify Settings. Keep dictation cleanup, output language, default keyboard surface, layout, haptics, key popups, Live Activity and setup access. Model management stays on Models; the dictation enable switch stays on Speak. Move device diagnostics and logs into one Troubleshooting destination. Keep support, privacy, app version and required licenses. Preserve existing preference keys and values.
3. Implement bounded local continuation generation using available contextual vocabulary. Evaluate language support before exposing results; abstain for unsupported or ambiguous contexts. Do not add persistent personal-word collection in the first version.
4. Trigger only after successful dictation insertion. Run outside the insertion critical path. Invalidate results on edits, host-context changes, new recordings, page changes or dismissal. Guard against stale session results.
5. Add an accessible, opt-in suggestion surface and the Suggestions after dictation setting together. Accept only on explicit tap after rechecking context. Preserve the original transcript. Do not expose a nonfunctional toggle during development.
6. Add regression coverage for default-off behavior, mixed languages, names/numbers, acceptance, cancellation, stale context and unsupported languages. Test Settings upgrades without resetting preferences.
7. Run core tests and app build. Measure added latency and memory, then verify interactions on an iPhone. Record separately what is source-tested, simulator-tested and device-tested.

## Acceptance

- Disabled users see no suggestion UI and pay no prediction computation cost.
- Dictation inserts without waiting for prediction.
- Prediction never silently edits the transcript.
- Stale suggestions cannot insert into a changed context.
- Unsupported languages get no misleading fallback to English.
- Settings exposes necessary controls without duplicate model management or obsolete features.
- Legal acknowledgements remain available.

## Release and monitoring

The hourly completion monitor checks implementation and verification evidence; a plan or partial test run is not completion. Delete it when the accepted scope is verified complete, or pause it if deletion is unavailable. A TestFlight upload is a separate release action and must be reported separately from build success.

## Status

- Plan saved.
- Settings cleanup implemented; existing preference values retained.
- Optional post-insertion suggestions connected to explicit acceptance. Default off.
- Reuses loaded n-gram dictionary; no generic frequency fallback. Languages without a matching loaded dictionary abstain.
- Document identity, exact context, selection, page transitions and disappearance invalidate offers.
- Core acceptance/default-off tests added. Device interaction, prediction quality and performance verification remain pending.
