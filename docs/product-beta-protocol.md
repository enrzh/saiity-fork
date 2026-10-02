# Seven-day sAiity beta

Status: ready to run once participants, device access and distribution are set.
No invitations, recordings or release uploads have been made by creating this protocol.

## Participants and consent

Use 5–10 volunteers, participant aliases rather than contact details in results,
several supported iPhones including an older supported phone, English/German and
mixed-language speakers, and people using accessibility features. Ask which
languages and host apps matter to them. Participation and sharing are optional.

Explain local processing and the foreground limit of MLX. Choosing a configured
server is a separate conscious choice; the baseline beta uses local models.
Nobody must enable transcript-bearing diagnostics. Audio is never captured by an
automated room recording. Use explicitly consented scripted files or licensed
public audio. Keep provenance/license/consent with the audio manifest.

## Invitation draft

> Would you try sAiity as your everyday keyboard for seven days? The goal is to
> learn where typing or dictation gets in your way. You can switch back whenever
> you want. Please note when you do and why, and optionally rate delivered
> dictations as Usable unchanged or Needs editing. Feedback stays on your phone
> until you choose to share a report. We’ll explain setup and provide a verified
> build before you start.

Do not send until the intended people and the build/link are approved. An upload,
Apple processing, tester assignment and an installed build are separate checks.

## Day 0: first-use test

Give the participant an installed, identified build and let them complete setup
without coaching first. Time launch to the first successful real-keyboard
dictation. Record setup confusion, permission refusal/return, download waiting,
keyboard switching and whether feedback accurately explains readiness.
Then show the existing help only where needed. Do not hide a failure by manually
changing their preferences; retain the original outcome and recovery steps.

## Days 1–6: daily use

- Use Notes, Messages, Mail and browser fields that participants already use.
  Verify draft-only actions; never send test messages or submit forms.
- Check rapid typing, overlapping fingers, Space, Period, delete repeat,
  cursor movement, variants, emoji gaps/empty Recents, categories and page changes.
- Check Solid/Glass, portrait/landscape, small/large text and accessibility.
- Dictate short/long messages, names, amounts, negation, self-corrections,
  mixed languages and unfinished sentences. Rate the delivered result explicitly.
- Try interruptions, app/field changes, cancellation, denied Full Access,
  offline mode and supported model switches. Watch for stuck states, late insertion,
  unrelated text deletion and lost drafts. These are release blockers.
- Note when the participant switches back to the system keyboard and why.
  Distinguish typing feel, setup, recognition, cleanup, waiting and battery issues.

Do not claim phone-field/password-field support where iOS uses its own keyboard.
Do not keep private message content in the shared checklist.

## Repeatable quality run

The 40-case manifest is
`DictusCore/Tests/DictusCoreTests/Fixtures/product-quality.json`. Case text is a
script/reference, not an existing audio recording. Obtain licensed/consented
16 kHz mono files, including accent/noise variants and genuine silence/noise-only
clips. Name them by fixture ID; retain each real SHA-256. Never invent hashes.

From `DictusCore`, make an empty capture template:

```sh
swift run polish-harness quality-template Tests/DictusCoreTests/Fixtures/product-quality.json --model openai_whisper-tiny
```

Save its JSON through the normal editor. Fill actual device/OS/model/runtime
revisions, audio hashes, raw/final outputs and each outcome. `pending` means not
run. Each inserted case needs a measured Stop-to-proxy value and a cold/warm
label; missing facts are rejected. Failed/cancelled/timed-out cases stay in the
run. Human acceptance is recorded only when someone actually rated that result.

Score without a model download or Apple Intelligence:

```sh
swift run polish-harness quality Tests/DictusCoreTests/Fixtures/product-quality.json captured-run.json
```

The scorer reports raw WER/CER, protected-term failures, silence hallucinations,
explicit acceptance, failure counts and cold/warm p50/p95. Strict protected-term
flags may include legitimate alternative formatting; review them against audio.
Expected final text guides review and is not the only acceptable wording. Do
not compare different devices/styles as one speed distribution. Use at least
20 insertions per timing group before relying on p95.

Use `scripts/summarize-dictation-timings.swift` for the correlated app/keyboard
timings. Its stage times are cumulative from Stop. Simulator synthetic key timings
are a separate input-path measurement. MetricKit supplies later aggregated memory,
hang and power-related evidence; it does not establish per-dictation peak memory.

## Day 7: decision

For each participant record: first-use completion, rated/accepted/needs-editing
counts, switches back and reasons, interruption failures, battery concerns, and
which controls or concepts remained confusing. Keep unrated results separate.
Use the findings to pick the next three fixes. A cohort with unresolved lost text,
wrong-field edits or repeated missed controls cannot pass based on good average speed.

Suggested private checklist columns: participant alias, build, phone/OS,
languages, host app, scenario, outcome, issue class, recovery, optional timing,
and consented report reference. Share only what the participant has approved.
