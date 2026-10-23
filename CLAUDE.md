# Syllivra — Agent guide

## Project and identity

Syllivra is this fork's native iOS dictation app and keyboard. The minimum deployment target is **iOS 17.0**. Swift, SwiftUI and UIKit power the app; speech recognition is WhisperKit, and cleanup uses Apple Intelligence on the device. Audio capture and model inference belong in the containing app, not the lightweight keyboard extension.

Existing Xcode target and directory names remain unchanged:

| Target or package | Purpose | Bundle identifier |
| --- | --- | --- |
| `DictusApp` | Syllivra app, capture, models and processing | `de.aiity.saiity.ios.beta` |
| `DictusKeyboard` | Keyboard extension and text insertion | `de.aiity.saiity.ios.beta.keyboard` |
| `DictusWidgets` | Widgets and Live Activity UI | `de.aiity.saiity.ios.beta.widgets` |
| `SyllivraKernel` / `SyllivraInference` | Shared contracts, storage and processing | Swift package products; no app bundle ID |

All three bundled targets use App Group **`group.de.aiity.saiity.ios.beta`**. Preserve bundle IDs, signing identities, stored keys and cross-process contracts. Do not use the upstream App Group or bundle IDs. The keyboard must use extension-safe APIs, keep `RequestsOpenAccess` enabled, and reach the app through the existing extension handoff; never use `UIApplication.shared` inside the extension.

## Repository, branches and external writes

- The fork integration branch is `saiity-fork`. The current work branch is `cursor/keyboard-surface-fixes-a66e`; confirm it with `git branch --show-current` before work.
- Continue on the current work branch. Do not switch branches, impose an upstream `develop`/`main` flow, reset, stash or discard existing work without an explicit request.
- **Never create or modify issues or PRs on `getdictus/dictus-ios`, or push to upstream.** Upstream links are attribution and historical references, not workflow destinations.
- Before any separately authorized fork issue, PR or push, inspect the remote and confirm the fork repository. Pass `--repo <owner/repo>` explicitly to `gh issue` and `gh pr` commands; never rely on implicit upstream selection.
- Do not commit, push, publish, invite testers or change releases unless the user explicitly requests that action. Keep plans and findings local when no fork destination is confirmed.
- Older instructions in `DEVELOPMENT.md`, `docs/GIT_WORKFLOW.md`, `docs/VERSIONING.md`, issue-tracker docs and scripts may describe upstream. They do not override this guide's fork identity, branch policy or authorization limits.

## Implementation conventions

- Prefer the smallest complete change in an existing owner. Use native platform APIs and existing helpers before adding dependencies or types.
- Do not add speculative Manager, Service, Factory, Strategy, Protocol, Adapter, Coordinator, Provider, Resolver or Registry layers.
- Use camelCase for values/functions, PascalCase for types, English comments and localized user-facing strings. Avoid force unwraps unless justified.
- Preserve unrelated edits, untracked files, Git recovery metadata, shared model/package caches and existing license notices. Do not broadly clean or reset the checkout.
- Use Chrome Use for websites and Computer Use for desktop UI with Chrome. If unavailable, report the limitation. Never extract or print credentials or authentication stores.

## Build, tests and lint

- Project: `Dictus.xcodeproj`. Build scheme `DictusApp` (or the existing `sAiity-iOS` scheme) includes the keyboard, widgets and shared packages.
- Shared tests: `cd SyllivraKernel && swift test`. These run on the Mac; no simulator boot is needed. Run other relevant repository checks when the changed component requires them.
- Strict lint: `swiftlint lint --strict` (equivalently, `swiftlint --strict`). Fix introduced violations; any narrow suppression needs a written reason. Do not create a baseline to hide failures.
- Preserve pinned package revisions and reuse existing caches.
- Xcode can rewrite `Localizable.xcstrings` extraction state or its final newline. Exclude only verified build-generated noise from the change; preserve intentional translations and pre-existing user edits. Never restore the entire file merely to remove build noise.
- Use `/Users/enrico/.codex/bin/codex-task` for new build/test/package commands with disposable output. Use a child shell to expand `CODEX_TASK_TMP` and `CODEX_TASK_ARTIFACTS`; explicitly place DerivedData under `$CODEX_TASK_TMP/derived` and retained logs, result bundles, archives, apps and screenshots under `$CODEX_TASK_ARTIFACTS`. Reuse shared dependency caches, wait for child work, and do not restart active work to adopt the wrapper.
- Keep project builds/tests serial and check for an existing worker before starting another. Report the exact checks run and their limits.

## TestFlight and release gates

- **Only prepare a TestFlight cut through `scripts/cut-testflight.sh`, and only when the user explicitly asks.** A completed feature, passing CI or a recurring check is not release authorization.
- Keep app, keyboard and widget version/build numbers aligned. Do not manually bump release numbers or bypass the script with alternate tagging, pushing, archiving or upload workflows.
- **The current script is not fork-ready:** it requires `develop`, fetches `origin/develop`, creates a version commit/tag and pushes them to `origin`. It prepares a cut; it does not upload a build.
- Treat release execution as blocked until the script is adapted and reviewed for the verified fork branch and remote under a separate authorized change. Do not switch to `develop`, rewrite remotes or bypass safety checks to make it run.
- Report local packaging, Apple upload acceptance, processing and tester availability as separate states. Claim only directly verified states.

## Headless simulator rules

Read [`docs/agents/simulator.md`](docs/agents/simulator.md) before simulator work. It contains historical upstream examples: substitute this guide's bundle IDs, App Group and dedicated simulator, and do not treat its old device observations as current proof. This guide's identity and safety rules take precedence.

- Reuse **`sAiity Product QA`**, UDID `3ED8FD55-D525-45D1-9E1A-4A1354000FC0`. Check `xcrun simctl list devices booted` and the available list first; never use hAiity's simulator or Xcode DeviceHub.
- Keep at most two simulators booted system-wide. If other projects occupy the budget, report the block; do not operate or shut down their devices. Prefer SimSlim when available.
- Boot with `xcrun simctl boot <udid>`, then wait for `xcrun simctl bootstatus <udid>`. Package tests and generic simulator compilation do not require a booted device.
- Stay headless. Never foreground Simulator with `open -a Simulator`. If AXe needs an attached Simulator.app, use `open -g -a Simulator` after boot readiness and confirm attachment. Do not quit Simulator.app to reset it; that can stop other devices.
- Use `simctl` for installation, launch and capture, and AXe for supported UI inspection/input. Read accessibility frames before tapping; screenshots use pixels, while touch coordinates use points.
- Compilation, extension registration and screenshots do not establish physical keyboard touch delivery, latency or app handoff. Check actual event delivery before drawing conclusions.
- Keep screenshots and recordings in retained artifacts outside the source tree. Do not uninstall/reset an app or erase its simulator to recover a test; that can destroy App Group state and Full Access setup.
- Never record room audio, inspect private transcripts, download voice models or change permissions during automated QA. Recognition evaluation requires licensed or explicitly consented files.

## Manual physical-device checklist

Do not operate or install on a physical phone as part of automated QA. Anything requiring a phone belongs on a manual checklist with exact steps and expected results. Leave it unchecked until the user supplies a result; never claim physical validation from tests, simulator output, compilation or installation.

Keep these gates separate when relevant to a change:

- [ ] Physical typing, hit targets, emoji swipes/holds and microphone-on haptics.
- [ ] Cross-app/background delivery, field/settings/default-tone behavior and denied Full Access.
- [ ] Landscape interaction, physical PiP and system Live Activity behavior.
- [ ] Real-model load, inference, cancellation, foreground loss, memory, multilingual accuracy and latency.

## Dictus MIT attribution

Syllivra is based on [Dictus](https://github.com/getdictus/dictus-ios) by PIVI Solutions and contributors, under the MIT License. Keep the original copyright and permission notice in [`LICENSE`](LICENSE), the README attribution and the distributed/in-app notices wherever inherited source or resources require them. Renaming a module or replacing part of the core does not establish source independence or permit removing attribution. Preserve the separate licenses for other dependencies and resources.
