# Dictation reliability execution checklist

Authorized: 2026-09-07 by the user via PC & Web task delegation. Implement the
reviewed plan locally; preserve unrelated changes, secrets and recovery metadata.
User subsequently authorized scoped commits/pushes for Xcode Cloud. A successful
cloud build/test run for the exact final commit is required. No release
distribution, purchases or provider changes are included.

## Baseline and constraints

- Branch `saiity-fork`, starting HEAD `40705fa64757f3b85f12feca0a53faa7a3d9c227`.
- Existing untracked `.superpowers/brainstorm/` (11 files) must remain untouched.
- Shared/project AGENTS.md, INFRA_NOTES.md and INTEGRITY.md read.
- Berlin stage start: 2026-09-07 23:26 CEST. After 2026-09-08 03:00 CEST,
  remain token-efficient; use relevant Core tools/recordings. Do not retry-loop
  rate limits or bypass worker identity requirements.

## Agreed stages

- [x] Recheck Git integrity; recover objects reversibly without replacing checkout.
- [x] Establish core test and iOS build baseline; record environmental limitations.
- [x] Extend CI to `saiity-fork`, core tests and required build prerequisites.
- [x] Align Home readiness, explanation and actions with disabled/active/ready state.
- [x] Behavioral dictation tests: cold start, quick release, cancel, failure/retry,
  delayed results and at-most-once live consumption (crash boundary documented).
- [x] Narrow lifecycle extraction integrated into production after regression tests.
- [x] Fix accessible dictation activation; test large text, Reduce Motion,
  emoji scrolling and symbols switching where runtime tooling permits.
- [x] Final review, proportionate checks and explicit remaining device limitations.
- [ ] Scoped commit/push and successful Xcode Cloud run: verify app, workflow,
  branch, exact SHA and final build/test results. Queued is not complete.

## Evidence and next step

- Initial status matches the earlier read-only review.
- Git recovery complete at 23:29 CEST: independently cloned public upstream,
  verified objects, added its pack and quarantined the damaged pack/index/rev plus
  stale multi-pack-index. Full `git fsck --full --no-dangling` passes. HEAD/index
  hashes and full status unchanged by recovery. Entire original Git metadata and
  quarantined files preserved under `.git/recovery-reliability-20260907/`.
- Private origin HTTPS credentials unavailable to terminal; public upstream
  supplied all missing objects. Browser login may resolve cloud/push access later.
- Xcode 26.6 (17F113) available at `/Applications/Xcode.app`. Use command-local
  `DEVELOPER_DIR`; leave global CommandLineTools selection alone. Initial CLT core
  baseline failed because XCTest was unavailable; rerunning with full Xcode.
- Available simulators are migrated Mac mini devices; historical SimSlim UDID
  absent. Use one existing iOS 26.5 device for authorized runtime verification.
- Scratch logs: `/tmp/saiity-reliability-4qlxyn/`. Readiness worker uses isolated
  detached worktree there; bounded accessibility review used a read-only worker.
- Next: core/Xcode baseline, lifecycle regression extraction and cloud access.

### 23:43 CEST checkpoint

- Full-Xcode baseline: 1,366 tests, one existing failure in legacy German language
  migration. Corrected migration to retain supported explicit language choices.
- First signed simulator build passed; updated signed simulator build also passed
  (Xcode 26.6, iPhone 17 iOS 26.5). Logs `build.log`, `build-current.log` in scratch.
- New delivery tests failed before implementation (missing policy), then 10/10
  passed. Added an additional independent app/keyboard generation regression.
- Integrated the readiness worker; corrected missing explicit returns during
  integration and retained the real error message on retry.
- Full interim suite: 1,379 tests, one source-string contract failure for the
  deliberately removed mic hit-target expansion; updated that obsolete assertion.
- Delivery is now a single request-bound payload, consumed only by a visible
  attached keyboard. Cancel unbinds synchronously; stale callbacks cannot consume
  a successor's result. App-local cancellation and keyboard request identities
  are checked independently, including translation. Early release cancels startup.
- Independent read-only review found no additional lifecycle regression. Documented
  limitation: iOS text proxy has no insertion acknowledgement; no promise of
  exactly-once insertion across crashes. App retains last result for manual copying.
- VoiceOver mic now has an explicit accessibility activation toggle, separate
  from touch-down/up; UIKit uses the tested policy frame without 8pt expansion.
- SwiftLint 0.65.1 installed locally. Pristine HEAD has 22 violations; changed
  checkout has 23, including extra startup complexity. CI pins 0.63.2. Fix new
  complexity and check the pinned version rather than broad unrelated reformatting.
- App Store Connect in ego task space 13 requires Apple sign-in. No appropriate
  autofill was offered; handed page to user (done=true). Do not reclaim until
  explicit confirmation. Cloud gate blocked by login; not a rate-limit pause.
- Continue: runtime keyboard/accessibility checks, focused tests, reduce startup
  branching, final checks, scoped commit/push and exact-SHA cloud gate when login
  and private-origin credentials are available. No credentials were printed.

### 02:33 CEST checkpoint — 2026-09-08

- Full core suite: **1,381 tests, zero failures**, `core-verified.log`. After the
  final visual fix, all **64 keyboard contract tests passed** in
  `contracts-accessibility.log`. Core behavior did not change after the full run.
- Final signed simulator builds passed: `build-final.log`, followed by
  `build-accessibility.log` for the runtime-discovered text clipping fix.
- SwiftLint **0.63.2** reports the same **17 inherited violations** as pristine
  HEAD; no new violation category/location was introduced. Strict lint therefore
  remains a known failing gate. See `lint-pinned-baseline.log` and
  `lint-accessibility.log`. A run without full Xcode could not load SourceKit;
  the recorded comparison uses command-local `DEVELOPER_DIR` correctly.
- `git diff --check` and cloud-hook shell syntax checks passed. Lifecycle diff
  reviewed; misplaced cold-start documentation restored to its own method.
- Simulator: iPhone 17, iOS 26.5, `2EC03686-15B2-4EB5-A1C4-3EFEBDA057EA`.
  Installed the signed app and keyboard, allowed microphone and Full Access,
  downloaded/compiled/loaded Tiny. Full Access verified by both Settings and
  extension log (`fullAccess=true`). Simulator stayed in the background.
- Runtime screenshots verify both symbol pages, return to dictation, horizontal
  emoji scrolling, and category selection/scrolling with Reduce Motion enabled.
  Evidence: `symbols-1.png`, `symbols-2.png`, `emoji-1.png`,
  `emoji-scrolled.png`, `emoji-reduce-motion-category.png`,
  `emoji-reduce-motion-scroll.png` in the scratch directory.
- Largest Dynamic Type revealed clipped AUTO/microphone labels. Limited only
  those fixed-frame labels to standard-size growth and allowed fitting; full
  VoiceOver labels remain available. Rebuilt and visually verified the complete
  labels at the largest accessibility size: `keyboard-large-settled.png`.
- Physical quick-release runtime probe passed: request started at 02:31:26,
  release canceled startup at 02:31:27, both sides returned to idle and sample
  count was zero. No delayed recording or empty transcription was observed.
- Restored original content size `large` and Reduce Motion off; screenshots
  `motion-before.png`, `motion-enabled.png`, `motion-restored.png` verify settings.
- Device-only limitations: real VoiceOver activation is not exercised by AXe
  taps; this simulator's Accessibility settings do not offer VoiceOver. Validate
  the new accessibility toggle with VoiceOver on an iPhone. Real audio quality,
  timing, memory pressure, cross-process scheduling and crash interruption still
  need a device. The text proxy offers no atomic insertion acknowledgement.
  At maximum text size the onboarding content requires scrolling; keyboard
  controls remain complete and usable.
- Apple sign-in works. Verified App Store Connect app **sAiity**, Apple ID
  **6803843831**, bundle **de.aiity.saiity.ios**. Existing `Default` workflow
  targets another repository; left untouched. Existing Internal TestFlight
  workflow is manual and was not triggered.
- Created and saved **Reliability Validation**, workflow
  **773e7886-59e6-4f73-a4b3-c2c0c1b837c9**, in this app: primary repository
  `enrzh/saiity-fork`, project `Dictus.xcodeproj`, scheme `sAiity-iOS`, manual
  branch start, Build for Any iOS Device, latest release Xcode (currently 26.6),
  no archive/distribution or post-actions. Core tests run in `ci_post_clone.sh`.
  Configuration is verified; no final-commit Cloud build has run yet.
- GitHub web session is signed in as `enrzh`, but CLI authorization is blocked
  at GitHub's Confirm access step. No matching Bitwarden autofill was offered;
  unrelated suggestions were not used. The earlier device-login process has
  expired. This is an authentication blocker, not a rate-limit pause.
- Next: complete GitHub confirmation and CLI login, check remote branch before
  pushing the scoped commit, then start Reliability Validation for its exact SHA.
  Inspect core-test hook and build logs through terminal success. Do not claim
  plan completion until that cloud gate passes. Preserve all 11 original
  `.superpowers/brainstorm/` files and `.git/recovery-reliability-20260907/`.
