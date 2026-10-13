# Processing prompt and budget checkpoint

October 13, 2026. Implemented locally on `cursor/keyboard-surface-fixes-a66e`, based on `b696d880`. The preceding processing-speed, first-party-core, slimming and responsiveness changes remain intact. No commit, push, upload, publication or tester invitation occurred.

## Changes

All production cleanup backends use the same shorter `cleanup-v3` contract and JSON transcript envelope. Balanced, formal, casual and concise each add one short style instruction. The contract retains facts, names, identifiers, numbers, dates, units, negation, languages, paragraphs, lists, indentation, `<<NL>>` markers and approved vocabulary. It prohibits summaries, translation, invented completion, reasoning and output wrappers. Concise removes speech clutter without authorizing omitted facts. The revision change invalidates old cached cleanup results. Historical per-language evaluation templates remain available.

Blank input and expired deadlines now exit before context preparation or inference. Apple Foundation Models checks cancellation before preparation/generation and after its response. The Ollama request/resource timeout now matches cleanup's existing eight-second ceiling, replacing its thirty-second network allowance. Greedy/zero-temperature generation, no-reasoning request options, context checks, output reserves, the 64-token minimum, the 2,048-token maximum, truncation rejection and single-inference ownership remain.

Native translation uses its separate Apple API. One eight-second deadline now covers all clauses instead of restarting eight seconds per clause. Host work receives the remaining budget. Installed-source work receives deadline/parent cancellation, and completed calls retire their timer. Already-cancelled requests do not create an SDK session. Expired, cancelled or rejected translation returns the entire original transcript. Source/target checks, Simplified Chinese conversion, client/generation identity and output guards remain.

## Measured prompt work

The measurement uses the existing first-party tokenizer and the public Qwen 2.5 0.5B tokenizer fixture pinned to `7ae557604adf67be50417f59c2c2f167def9a775`. Seven fabricated inputs across four styles cover short dictation, facts/negation, French, mixed languages, structured code/lists, instruction-like data and long prose. Saved prompts include the exact JSON envelope. Re-executing the preserved baseline binary reproduces the original measurements byte-for-byte.

For the short input, raw text occupies eight tokens. Its user turn falls from 28 to 14 tokens; its output cap remains 64.

| Style | Instruction tokens before / after | Complete input tokens before / after | Input reduction |
| --- | ---: | ---: | ---: |
| Balanced | 287 / 225 | 315 / 239 | 24.1% |
| Formal | 298 / 227 | 326 / 241 | 26.1% |
| Casual | 294 / 228 | 322 / 242 | 24.8% |
| Concise | 293 / 232 | 321 / 246 | 23.4% |

All 28 cases have fewer instruction/user-turn tokens with identical raw token counts and output caps. These counts exclude backend chat templates. They establish reduced prompt work, not model quality or a corresponding percentage reduction in phone latency.

## Executed verification

- Debug and Release each pass 1,955 Core tests plus 35 Inference tests: 1,990 tests, one existing ASR capture skip, zero failures. The skip requires a captured recognition run; none was recorded.
- Focused failing-before/passing-after checks cover blank/expired preparation, the HTTP timeout, prompt size and JSON round-trip. Existing style/vocabulary, cancellation, noncooperative cleanup ownership, context/truncation, fact/language/structure and fallback checks pass.
- The production translation method bodies compile against a stalled SDK fixture. The baseline fails deadline/cancellation checks. The final code passes shared clause deadlines, remaining host timeout, expired-work refusal, pre-cancellation, installed-session cancellation, complete original fallback and timer retirement. Fixture behavior does not establish Apple's actual SDK cooperation or installed translation pairs.
- Apple Foundation Models reports `unavailable(...modelNotReady)` on the Mac. No settings or downloads were changed; no real-model semantic or speed evaluation ran.
- Debug app/keyboard/widget simulator build passes. Strict signatures pass separately for all three bundles. No simulator was booted or operated: the available simulator slots were occupied by other projects.
- Signed Release device build passes. App/keyboard/widget each pass strict signature verification and retain 1.0.0 (242), iOS 17.0, the expected bundle IDs, team `H8FW6W6K2D` and signed App Group `group.de.aiity.saiity.ios.beta`. Simulator signatures have empty entitlements; the configured App Group is checked separately rather than inferring device entitlement behavior from a simulator.
- Both generated bundles retain exact compact frequency counts/cutoff ties, all eight original n-gram/spellcheck files, all 29 CAF feedback names and byte-identical open-source notices. All source resource hashes still match after the builds. Main executable and dSYM UUID match: `984B2AA0-B75C-3656-933A-387D4CC662B7`.
- The 41 original frequency, n-gram, spellcheck and sound source SHA-256 checks pass. Project plist syntax and diff whitespace checks pass.

The previously authorized paired iPhone Air received the same-bundle development update. Apple's installer reports success, and filtered inventory confirms Syllivra 1.0.0 (242) at the exact new installer bundle URL. No uninstall, app-data deletion, phone launch, physical interaction automation, microphone recording or permission change occurred. Allocated bundle size remains 63,888 KiB (approximately 62.4 MiB), including a 30,688 KiB keyboard, matching the preceding responsiveness build.

Existing SDK deprecation, unused-value and actor-isolation warnings remain. The malformed/missing frequency fixtures intentionally emit diagnostics. The temporary bundle checker initially assumed simulator signatures contain device App Group entitlements; inspection showed empty simulator signing entitlements, so its platform-specific assertion was corrected. Device entitlement assertions remain strict. No distribution archive/export or Apple/TestFlight processing status was refreshed by this pass.

## Remaining limits

An eight-second translation deadline requests cancellation and rejects late output. Installed SDK work that ignores cancellation can still delay return; availability lookup is checked after suspension rather than forcibly interrupted. Slow models/servers or long translations can therefore fall back more often. The original transcript remains available.

Physical model latency, memory, cancellation/foreground loss, actual translation pair availability, multilingual semantic accuracy and independent native-language review remain unverified. Licensed or expressly consented recordings are required for recognition evaluation. Physical keyboard/haptics, background delivery, field/Full Access parity, landscape, PiP/system Live Activity and the unfinished first-party runtime migration remain separate gates. No room audio, private transcript, model download or permission change was used.

## Evidence

`/tmp/saiity-processing-prompts.oQM4VK` contains prompt measurement source/binaries, `prompts-before.json`, `prompts-before-recheck.json`, `prompts-after.json`, `token-comparison.tsv`, red/green logs, final Debug/Release logs, translation baseline and checks, Apple availability, source/resource checks, build/signature logs, final simulator/device bundle checks and installation/inventory JSON. `scripts/test-translation-budget.swift` reruns the translation fixture without loading any model. The existing recovery heartbeat was not changed.

## Typed-ready dictation follow-up

The user's reference to “Whisper flow” was interpreted as Wispr Flow. Read through Chrome on October 13: [Typeless](https://www.typeless.com/) describes filler/repetition removal, final self-correction, formatting, personal vocabulary and multilingual dictation; [Wispr Flow features](https://wisprflow.ai/features) describes the same cleanup, punctuation, lists and backtracking (for example, “at 2… actually 3”). These are public product descriptions, not a benchmark of either product or access to their internal prompts/models.

This follow-up improves the existing edited-transcript path:

- The shared `cleanup-v4` prompt asks for ready-to-send text, final explicit corrections and clear spoken lists as bullets, without adding or reordering items. Balanced/formal/casual/concise and approved vocabulary retain their existing owners. The original recovery and translation paths remain separate.
- Validated monolingual English Auto cleanup removes “um” and grammatical pronoun stutters. It does not remove German/Portuguese function words, meaningful emphasis or uncertain/mixed-language fragments. Very short Auto text retains its lexical repeats; unusually repetitive recognition fragments can still fail language validation and remain recoverable.
- Immediate grammatical stutters use one regex replacement instead of repeatedly scanning a long run. This reduces repeated work; no phone timing percentage is inferred.
- English and French gain paragraph/bullet commands in the existing deterministic pre-pass, matching the German/Spanish formatting support. No model call is needed for those explicit commands. Numbered output and implicit-list structure still depend on a model producing output that passes the existing fact/structure guards.
- Adjacent, explicit English corrections of bare integer/simple decimal values and clock times retain only the corrected value. Complex number lists, dates, codes, URLs, signed values and nonadjacent/different-unit phrases stay recoverable. All text containing backticks bypasses deterministic lexical/formatting edits to preserve code; surrounding prose then receives no deterministic cleanup. This is a deliberate conservative limit, not a code parser.
- The fact guard previously allowed a correction cue to justify dropping any preceding amount or name. It now permits replacing only the nearest preceding fact of that kind and retains unrelated earlier facts. Conservative rejection can retain multiple corrections as original/fallback text; the guard does not establish semantic equivalence.

Fabricated failing-before/passing-after regressions cover a ready-to-send message, hesitation/stutters, adjacent corrections, unrelated amounts/names, negation, multilingual/uncertain text, code literals, invoice/date/URL protection, compact numeric lists, explicit paragraphs/bullets and complete-pipeline rejection fallback. The changed multilingual fixture records the improved English fallback rather than the old retained stutter.

Final Debug and Release each pass 1,962 Core tests plus 35 Inference tests: 1,997 tests, one existing ASR capture skip and zero failures. Relevant source and resource checks remain unchanged after verification. Final simulator and signed Release iPhone builds pass; strict signatures pass separately for app/keyboard/widget. All three retain 1.0.0 (242), iOS 17.0 and the existing signed App Group/team. Final bundle checks retain compact counts/cutoff ties, every n-gram/spellcheck source byte, all feedback names and open-source notices. Main executable/dSYM UUID match: `FF086CE4-D1D3-38D6-86F8-5E0E7DF84B74`. Earlier build logs preceding the final compact-number-list safeguard are historical checks.

The same 28 pinned-tokenizer cases have identical raw/user-turn token counts and output caps. Instruction counts increase by 15 tokens per style versus `cleanup-v3`: Balanced 225 to 240, Formal 227 to 242, Casual 228 to 243, Concise 232 to 247. The shared 240-token character estimator check still passes; it is an estimate rather than the exact Qwen token count. Instructions remain smaller than the pre-optimization 287–298 tokens. The extra instruction cost covers spoken formatting and an explicit correction example, not lower output reserves.

Apple's Mac model still reports `modelNotReady`. No real-model semantic/accuracy/latency comparison, room recording, private-transcript access, permission change, model download or acoustic-model replacement occurred. Auto editing does not automatically enable the user's disabled cleanup toggle. Competitor parity, physical recognition quality, model cancellation/memory/foreground loss and native-language meaning review remain unverified.

Filtered phone inventory initially failed with a CoreDevice tunnel timeout. Connectivity recovered and Apple's installer successfully updated the same bundle; inventory matches the final installation URL and Syllivra 1.0.0 (242). No app launch, microphone, private transcript, permission change or phone interaction QA occurred. Final allocated package size is 63,888 KiB (approximately 62.4 MiB), including a 30,688 KiB keyboard, matching the previous development build.

The generic-device package had grown to 68,336 KiB. Rebuilding for the paired iPhone restored the smaller package. Switching build destinations exposed Xcode's incremental resource-signing issue: the widget's shared `Assets.car` changed without widget re-signing. The generated top-level widget product was moved recoverably to the evidence directory; Xcode regenerated/signed it, and final strict verification passed for app and both embedded extensions. No manual re-signing or source/build-policy change was used as a workaround. Future destination changes should repeat strict signature checks. Existing SDK warnings remain.

Evidence: `/tmp/saiity-typed-dictation.5gqNhh`, including preserved pre-change diff/prompt measurements, cleanup/fact/literal/number-list red logs, final `core-debug-number-final.log`/`core-release-number-final.log`, final source checkpoint, same-tokenizer comparison, Apple availability, final app builds, signing/resource checks and `install-iphone-final.json`/`installed-after.json`. All source changes remain uncommitted. No push, upload, publication or release alteration occurred; the recovery heartbeat was not changed.
