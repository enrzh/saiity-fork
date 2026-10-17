# Emoji Delete and app UI refinement

Latest installed implementation checkpoint: [October 14 Dictus source replacement](2026-10-14-dictus-source-independence.md). It retains this native UI and the earlier spelling/language changes, passes the final 2,024-test Release package run with one existing skip and zero failures, and has verified Debug/Release builds plus same-bundle installation. Full source independence is unfinished and the Dictus notice remains.

## October 14: dictation icon, Settings/model polish and license audit

Start dictation explicitly uses the native title-and-icon label style so a containing list cannot choose a text-only label. Settings retains its six destinations, two quiet groups and inline title, with consistent SF Symbols on the native navigation rows. No icon tiles, custom controls or additional settings were introduced.

Voice and processing rows align the model name and storage on the same heading line, with a vertical layout at accessibility sizes. Selection remains a labeled checkmark. Descriptions and language coverage use the row's full width; primary actions and the native More menu sit below. Download, cancellation, selection and retry actions use SF Symbols and text. Voice rows rely on their Installed/Downloads section for ordinary installation status; loading, preparation, incompatibility, preview warnings, progress, byte counts and failures remain explicit. Processing rows retain installation status because installed and available choices share a section. Existing selectors, lifecycle owners, Qwen warnings, remote-processing disclosure and deletion confirmations/guards remain.

The license audit distinguishes runtime dependencies from source provenance:

| Area | Verified state |
| --- | --- |
| DictusCore/DictusInference modules | No imports in live app, keyboard, widget or package sources, and no references in the Xcode/package build graph. The current shared package is SyllivraKernel. |
| Dictus-derived source | Inherited app, keyboard and shared code remain. The PIVI Solutions copyright and complete MIT notice are retained. The in-app notice and README explain this attribution; removing the module name did not independently author the inherited implementation. |
| giellakbd-ios | Six vendored Swift files remain. Upstream offers MIT or Apache-2.0. The old generator reconstructed MIT text from DeviceKit and changed its copyright line. It now reads the upstream MIT permission text and both original copyright lines from `DictusKeyboard/Vendored/LICENSE-MIT`. |
| Swift Crypto and Swift ASN.1 | Complete root `NOTICE.txt` attributions were missing. They are now appended to their unchanged Apache license texts. Other package licenses are read from the pinned local checkouts. |
| Remaining notices | All 23 existing source/library notices remain, including WhisperKit, FluidAudio, Qwen runtime, MLX and keyboard resources. No attribution or permission text was removed. Downloaded model checkpoints and their individual licenses were not inspected. |

giellakbd's MIT text and dual-license option were read in Chrome. The license file's last-change commit is `b09df1e2a452d69476220532167270243f30b520`; its source is [LICENSE-MIT](https://github.com/divvun/giellakbd-ios/blob/b09df1e2a452d69476220532167270243f30b520/LICENSE-MIT). The local copy preserves the license content while omitting trailing whitespace. Full separation from inherited source requires replacing the remaining inherited implementation and auditing retained resources before removing attribution. No source-ownership or license change was made here.

Fresh evidence:

- `/private/tmp/codex-task.9_s_55ok/artifacts/notices-red.log` reproduces the incorrect giellakbd text and two missing notices: one regression test, three failures. Its failed-run scratch is preserved.
- `/private/tmp/codex-task.zgyzkhzr/artifacts` contains notice regeneration and 112 passing focused checks with zero failures, covering app/keyboard contracts, model metadata/languages, model preferences and readiness. The added regression protects inherited license text and the two Apache attributions.
- `/private/tmp/codex-task.qhybboeo/artifacts/notices-audit.log` confirms all 23 notices remain, 20 license texts are unchanged, and the Swift notices were appended without altering their license text. Generated notices SHA-256: `582d25ad6a4913181f3157df80e3225b8d9071008db92eef230f0544cef560df`.
- `/private/tmp/codex-task.8slojffb/artifacts` contains the successful Debug simulator build, independent strict app/keyboard/widget signatures and production app fixture compilation. Bundled notices match the source byte for byte. Compilation did not render screens or run actions.

`/private/tmp/codex-task.dqn_1f7g/artifacts` contains the successful signed Release build and retained `DictusApp.app`. Strict signatures pass independently for app, keyboard and widget. Metadata checks confirm 1.0.0 (243), minimum iOS 17.0, team `H8FW6W6K2D` and the existing beta App Group on all three bundles. The bundled notices match the source and recorded SHA-256. The retained signed app measures 63,904 KiB with `du -sk`.

The first installation attempt returned CoreDevice error 4016; its log is in `/private/tmp/codex-task.0w4b5wqh/artifacts`. The device list then showed a disconnected local-network tunnel. A subsequent app query succeeded, with evidence in `/private/tmp/codex-task.2122pshm/artifacts`; the next installation completed. `/private/tmp/codex-task.o6mz9508/artifacts` contains the successful installer receipt, independent installed-app listing and identity checks for Syllivra 1.0.0 (243). The newly installed bundle URL matches the receipt, and App Group identity/container remain unchanged. The app data-container path changed; private contents and migration were not inspected. The app was not launched or operated. Installation used the user's existing same-bundle authorization and performed no uninstall.

Caller/source review and `git diff --check` passed. Successful commands cleaned their own scratch and retained evidence; failed runs remain preserved. No additional dependency, runtime owner or app layer was introduced.

Native screenshots, small-screen/accessibility layouts, VoiceOver and physical interaction remain unverified. hAiity, Day QA, Day Tests and Day iPad were already booted, exceeding the two-simulator budget. None was operated or shut down, and the dedicated sAiity simulator was not booted. SimSlim was unavailable. No room audio, private transcripts, model downloads, permission changes, commits, pushes, uploads or release operations were used for this pass.

## October 14: minimal Settings, direct model selection and spelling overrides

The current refinement keeps the native iOS direction. Settings now has six single-line rows in two groups: Dictation, Keyboard, Models & downloads, History, Help and About. Its title is inline. Words & shortcuts remains available inside Keyboard; spoken languages, writing and voice choices remain inside Dictation. Speak groups languages and keyboard power together and shows microphone footer text only when preparation or recovery needs attention. The history link uses its destination name.

The Models page's In app and Keyboard rows are native menu pickers backed by the existing `selectModel` and `chooseKeyboardModel` handlers. Choices include installed models available on this device and OS. Keyboard excludes Qwen, retains its Automatic option and shows the resolved automatic model. Search does not filter these selectors. Runtime changes remain disabled during dictation; selecting a row does not start a model download.

The autocorrect investigation found three failures in `SuggestionState`: restoring the original spelling was explicitly excluded from override learning; deleting the whole corrected word or receiving duplicate host callbacks discarded the pending edit; and Space could still use a correction prepared before the spelling was learned. Reconciliation now retains the same edit, learns a deliberate restored or alternative spelling at a stable boundary, and checks current learned vocabulary before applying a cached correction. It validates document identity, field policy, caret context and the exact preceding text. The existing safe-word guard excludes numbers, codes and other unsafe tokens. The shared user dictionary remains the persistence owner; ordinary correction and its nonblocking Space path remain.

`scripts/test-autocorrect-overrides.swift` runs the production Space/reconciliation methods off-device with in-memory proxy, dictionary and prediction doubles. `/private/tmp/codex-task.0y_gvtl9/artifacts/overrides-red.log` reproduced repeated correction and missing learning for direct restoration, delete/retype and duplicate callbacks. `/private/tmp/codex-task.c5rdads1/artifacts/overrides-final.log` passes those cases plus replacing a selected correction, stale cached correction, deliberate alternative spelling, changed/unknown document identity, moved caret, secure fields, changed prefix and unsafe-token exclusion. This is source-derived behavior evidence, not physical keyboard typing. The same directory's `focused-tests.log` records 218 tests with zero failures, including dictionary persistence/cost, replacement safety, prediction responsiveness, model preferences, readiness and app/keyboard contracts.

`/private/tmp/codex-task.bj8ac61q/artifacts` contains the successful Debug simulator build, strict app/keyboard/widget signatures and production app/result fixture compilation reports. The updated model fixture isolates its selection preferences in the sample-data suite. No rendered or interactive simulator check ran. `/private/tmp/codex-task.nw60unlp/artifacts` contains the successful signed Release build, retained `DictusApp.app`, independent strict signatures and metadata checks for all three bundles: 1.0.0 (243), minimum iOS 17.0, team `H8FW6W6K2D`, development signing and the existing beta App Group. The signed app measures 63,872 KiB with `du -sk`.

The refinement was installed in place on the iPhone Air under the user's existing installation authorization. `/private/tmp/codex-task.wjpau8q3/artifacts/installed-before.json` records the prior bundle. `/private/tmp/codex-task.h1rwct14/artifacts` contains the successful installer receipt, independent installed-app listing and identity checks. The new installed bundle URL matches the receipt and reports 1.0.0 (243); App Group identity and container remain unchanged. The app data-container path changed; private contents and migration were not inspected. The app was not launched or operated for QA.

Caller/source review and `git diff --check` passed. No room audio, private transcripts, model downloads, permission changes, commits, pushes, uploads or release operations were used. The failed red-check scratch was preserved; successful runs cleaned their own scratch and retained their evidence. Native rendered layout, real typing/override behavior and VoiceOver remain pending while the dedicated simulator is unavailable within the shared simulator budget. No audio, model inference or accuracy claims follow from these checks.

## October 14: native iOS revision

The user explicitly requested native iOS elements. The custom navy recorder proposal and its off-device design study are superseded. The current implementation uses system SwiftUI navigation, grouped lists, forms, labels, switches, buttons, menus, pickers and toolbars. The custom app button style, custom action-label wrapper and recorder palette were removed after checking their callers. The Live Activity's existing passive voice signal remains.

Speak uses an inset grouped list with one real readiness summary, a system prominent dictation button, a native spoken-language navigation row, a native keyboard switch and recent text. Recording uses a native navigation stack and list for its status, duration and transcript. Its primary action lives in the system bottom toolbar at normal portrait sizes and joins the list at accessibility sizes or compact height. Finish remains red, cancellation remains driven by the live coordinator state, and original recovery, editing, copy, sharing and feedback retain their existing owners.

Settings uses native grouped rows and `LabeledContent` for current choices; its destinations use `Form`. Voice options and Models use grouped lists and native pickers/menus. Model download, preparation, failure and deletion guards remain. Setup uses standard buttons, labels, progress indicators, group boxes and the existing real native text fields. Instructional video and keyboard illustrations retain their existing owners. Speak and Settings remain the only tabs; Models stays inside Settings and Voice options. The keyboard's native More menu and top-left More/top-right power positions are unchanged by this app revision.

Apple Design informed the platform choice: `buttons.md › Style` states that system buttons provide “built-in interaction states, accessibility support, and appearance adaptation”; `typography.md › Supporting Dynamic Type` states “Make sure your app’s layout adapts to all font sizes.” Ponytail keeps the existing actions and state owners and removes the app styling wrappers without adding dependencies or new app layers. The system owns control geometry, interaction states, surfaces and foreground adaptation.

Fresh focused evidence: `/private/tmp/codex-task.xyunu7ec/artifacts/focused-tests.log` records 100 tests with zero failures (48 app-foundation, six model-preference, seven readiness, 11 product-completion, six recent-dictation and 22 stage-hold checks). The existing app-foundation contracts now require the native Home list and keyboard switch; their readiness, navigation, history, recovery and cancellation coverage remains.

`/private/tmp/codex-task.h_yg3akw/artifacts` contains the successful Debug simulator build, independent strict app/keyboard/widget signatures and the native app/result fixture compilation reports. The fixtures use production view bodies with isolated sample data and inert speech/model actions; compilation did not render screens or test touches. Their generated source, binaries and module caches now explicitly use the task scratch directory, and rendered output uses the artifact directory. No off-device mockup was used as evidence for this native revision.

`/private/tmp/codex-task.41uapemg/artifacts` contains the successful signed Release build and retained `DictusApp.app`. Independent strict signatures, 1.0.0 (243) parity, minimum iOS 17.0, Apple Development signing, team `H8FW6W6K2D` and `group.de.aiity.saiity.ios.beta` were verified for app, keyboard and widget. The retained iPhone Air build measures 63,872 KiB with `du -sk`. Caller/source review and `git diff --check` passed. The speech, processing, keyboard touch/menu and cancellation owners retain the prior fixes.

Under the user's existing same-bundle phone-installation authorization, this native revision was installed on the iPhone Air without uninstalling or launching it. `/private/tmp/codex-task.pjcs7kme/artifacts/installed-before.json` records the prior installation. `/private/tmp/codex-task.0zvqwhhm/artifacts` contains the installer receipt, independent installed-app listing and identity checks: the new installed bundle URL matches the receipt, differs from the prior bundle URL and reports 1.0.0 (243). App Group identity and container remain unchanged. iOS changed the application data-container path; private contents and migration were not inspected.

Source remains local and uncommitted on `cursor/keyboard-surface-fixes-a66e` at `4c2f6c8a`. This revision performed no room-audio recording, private-transcript access, voice-model download, permission change, commit, push, upload, release operation or tester invitation. Successful wrapper runs cleaned only their own scratch and retained the evidence above; existing recovery metadata and other tasks' files were preserved.

The dedicated sAiity simulator remains shut down while other projects occupy the simulator budget. No additional simulator was booted or another project's simulator operated. Native rendered screens, VoiceOver, physical interactions and visual acceptance remain unverified. The earlier off-device study is historical proposal evidence and is not evidence for the current native UI. The physical/model/translation/latency release gates remain separate.

Local source changes based on `4c2f6c8a` (`cursor/keyboard-surface-fixes-a66e`). The checkout was clean before this pass. Build number remains 243.

## Changes

Emoji Delete previously drew the full command envelope while the letter/symbol renderer subtracted its 5.5-point inner gap. The earlier geometry checks compared the envelope rather than the rendered face. At a 402-point surface this produced a 57.9-point emoji face beside a 52.4-point grid face.

`VoiceOnlyKeyboardPolicy.Layout.commandKeyVisualFrame` now reserves that gap on the inside and retains the right edge. Emoji and the native dictation-board Delete configure their passive faces from that frame. The SwiftUI fallback aligns its face to the trailing edge. Touch rectangles, repeat deletion, press feedback, cursor routing and neighboring keys keep their existing owners.

Speak now leads with dictation readiness, using the existing voice mark. Keyboard power and Voice options form one secondary group; recent transcripts have a separate reading surface. The primary dictation action remains reachable in the bottom inset. Settings uses the native grouped list, clearer row descriptions, quiet symbol tiles, a large root title and the familiar gear tab icon. Preference keys, navigation destinations, microphone preparation, model selection and transcript actions are unchanged.

## Design basis

The direction is a familiar native voice utility: system typography, grouped surfaces, restrained brand blue and one prominent dictation action. It is a design choice for approachability, not a measured claim about majority preference.

Background and content surfaces use `systemGroupedBackground` and `secondarySystemGroupedBackground`; labels use semantic primary/secondary styles. The existing action colors remain approximately `#245DE3` in light appearance and `#8CADFF` in dark appearance. White on the light action has 5.60:1 contrast; the dark action foreground (`#101A35`) has 7.80:1. These ratios come from the existing source RGB values, not screenshots. System colors remain dynamic API values.

Titles use the system large-title/title2 styles; rows and text use body, headline and subheadline styles. Decorative marks disappear at accessibility text sizes so content can expand vertically. No extra motion or glass layer was added to content.

Relevant Apple references: `layout.md › Visual hierarchy` (grouping, alignment and relative importance), `typography.md › Supporting Dynamic Type` (adapt layouts rather than truncate), `lists-and-tables.md › Style` (native grouped lists), `tab-bars.md › Best practices` (familiar labeled navigation) and `materials.md › Liquid Glass` (keep glass in the functional layer). The existing Apple/frontend design guidance informed the choice of native controls and a restrained voice-specific signature.

## Verification

Evidence directory: `/tmp/saiity-ui-refresh.A7YZPa`.

- `delete-red.log`: the regression reproduced the 5.5-point face mismatch and the center difference.
- `kernel-final.log`: 1,962 kernel tests plus 41 inference tests, one existing ASR-capture skip, zero failures. Geometry checks use the grid renderer's inset formula and cover 320, 375, 402, 420 and 440-point phone widths, two keyboard heights and both five/seven-key middle rows. The visible face stays inside its original Delete target and retains the target's right edge.
- `simulator-build.log`: Debug simulator app, keyboard and widget build succeeded with pinned dependencies.
- Strict `codesign --verify --strict` succeeded independently for the app and each embedded extension.
- `app-fixture-compile.log` and `keyboard-fixture-compile.log`: production native fixtures compiled and linked. Both renderers now support `--compile-only`, matching the existing probes. Compilation did not execute their UI, microphone or model actions.
- `git diff --check`: passed. Main-agent caller and diff review completed.

## Remaining checks

Rendered light/dark screens, small-screen and Accessibility 5 layouts, VoiceOver navigation, wide/landscape keyboard parity and physical Delete press/hold feel remain unverified in this pass. hAiity and Day occupy both permitted simulator slots; neither was operated or shut down, and the dedicated sAiity simulator was not booted as a third device. Compiling fixtures is not evidence of rendered layout or physical behavior.

The implementation pass performed no phone installation, room-audio recording, private-transcript access, permission change, model download, commit, push or release operation. Its simulator build is a local development artifact.

## Phone installation follow-up

At the user's explicit request, the updated source was built in Release configuration for the connected physical iPhone Air and installed as Syllivra 1.0.0 (243). The existing bundle identifier and App Group were retained; no uninstall was performed.

`device-build-final.log` records the successful build. The command applied `DEVELOPMENT_TEAM=H8FW6W6K2D` and `CODE_SIGN_IDENTITY=Apple Development` to include package resources in the signing configuration. Strict signature verification passed independently for the app, keyboard and widget. `device-verify.log` confirms all three bundle identifiers, version parity, iOS minimum, development entitlements, team and App Group.

`install-result.json` records successful CoreDevice installation. `installed-after.json` independently confirms the installed Syllivra bundle/version at the new bundle-container URL returned by the installer, distinct from `installed-before.json`. All logs are in `/tmp/saiity-ui-refresh.A7YZPa`.

The app was not launched or operated during installation verification. Phone UI, typing, haptics and the other runtime gates above remain untested; no room audio or private transcripts were accessed.

## Canvas revision after design feedback

The user rejected the repeated rounded surfaces and decorative icon tiles. This revision follows the existing `PRODUCT.md` anti-references and the Apple/frontend/Impeccable product guidance: the transcript is the main content, recording is the single prominent action, and setup choices remain secondary.

Speak now uses a flat system background with an inline navigation title. Voice options opens from the native toolbar. Recent text has more readable title3 typography and quiet text actions; copy, edit, original comparison, restore and sharing retain their existing behavior. Keyboard power and microphone-preparation status remain reachable below the recording control. Settings returns to plain native rows without icon tiles or repeated explanatory subtitles. Home and Recording use the same native circular control vocabulary, with a red Stop during recording and explicit Finish/Cancel/Retry labels.

Semantic colors, Dynamic Type, error recovery, original-text safeguards, model/language preferences, and the keyboard Delete fix are retained. The only changed test assertion replaces the old decorative heading requirement with ownership of the shared readiness title. No dependency or new app abstraction was added.

Evidence: `/tmp/saiity-canvas-ui.pstF21`.

- `ui-contracts.log`: 69 focused readiness, app-foundation, product-completion and recent-dictation checks passed.
- `simulator-final.log` and `device-build.log`: Debug simulator and signed Release device builds succeeded.
- `native-fixture-final.log`: production Home, Recording, transcript and newly included Settings-root fixtures compiled and linked. Settings lifecycle callbacks and destinations are inert in the fixture.
- Strict signatures and bundle metadata passed independently for app, keyboard and widget. Development team, App Group and version parity remain 1.0.0 (243).
- The device build retains iPhone Air asset filtering. Both the preserved prior app and this revision measure 63,924 KiB with `du -sk`.
- `install-result.json` and `installed-after.json`: successful in-place installation and independent installed-app verification at the new installer-reported bundle URL. The iPhone reconnected after the first availability check. No app launch, recording or phone UI operation was performed.
- `git diff --check`: passed. Source/caller review included every use of the shared transcript component and the live-status cancellation/recovery paths.

`layout-study.png` is a light/dark layout study rendered with fabricated text. It was inspected to review hierarchy and spacing; it is not a UIKit device screenshot or runtime-layout evidence. Native rendering, Accessibility 5, VoiceOver and physical interaction remain pending because the shared hAiity and Day simulators occupied the available simulator budget. No additional simulator was booted or another project's simulator operated.

## Models revision

Models now separates Voice and Processing with a native segmented picker. At accessibility text sizes it becomes a menu to keep both choices readable. Voice shows the actual app and keyboard choices first, followed by installed models and downloads. Processing opens directly to Apple Intelligence, downloaded local models and any existing custom cleanup configurations. Search follows the selected category and distinguishes an empty installation from no matching results.

The native grouped list retains its ordinary row separators. Decorative section icon tiles, runtime-library footers and large button strips are removed. Model names and sizes lead each row; selection labels distinguish app, keyboard, both and the selected processing backend. Rows show a main text action when needed and a 44-point actions menu containing details and deletion. Local processing says “Download & use” because its existing owner downloads, prepares and then selects the model. Details start with the model description, size and language coverage instead of another oversized page header.

Download percentages, byte counts, cancellation, preparation, failures, retry/repair, compatibility reasons, experimental and Qwen coverage warnings, active/last-model deletion guards and parent-owned confirmation alerts retain their existing paths. Local processing still states that Syllivra must remain open. Custom processing still discloses that dictated text goes to the configured server. No model lifecycle, inference owner, preference key, dependency or new app layer was introduced.

The existing Apple/frontend/Ponytail guidance informed the native category picker, secondary-action menu, Dynamic Type layouts, semantic colors and removal of decoration. Relevant Apple references are `lists-and-tables.md › Content and Style`, `menus.md › Labels`, and `progress-indicators.md › Best practices`. This is a design decision for easier model management; no speed or accuracy improvement is claimed.

Evidence: `/tmp/saiity-models-ui.PBWt78`.

- `foundation-final.log`: 47 focused app-foundation checks passed with zero failures. Existing presentation assertions were updated to the new native sections and menu; deletion confirmations/guards, model states, determinate progress and remote processing disclosure remain covered. The unaffected full kernel/inference suite was not repeated.
- `simulator-latest.log` and `device-build.log`: final Debug simulator and signed Release iOS builds succeeded with pinned dependencies. The Release build retains iPhone Air asset filtering and build number 1.0.0 (243).
- `simulator-signatures.log` and `device-verify-final.log`: strict signatures passed independently for app, keyboard and widget. Device metadata confirms version parity, minimum iOS 17.0, Apple Development signing, team `H8FW6W6K2D`, and `group.de.aiity.saiity.ios.beta` on all three bundles.
- `fixture-final.log`: the production Models page and model/processing row bodies compiled and linked with inert lifecycle dependencies. Fixtures now include both categories, no matches, empty installations, distinct app/keyboard selection, preparation and cleanup download/error states. Fixture compilation did not execute rendering or actions; Apple availability in the fixture is intentionally fabricated.
- Source/caller review and `git diff --check` passed. All prior UI/keyboard edits and Git recovery state are preserved. No commit, push, upload, release change or tester invitation was performed.

The phone reconnected after the initial availability check. `install-result.json` records successful same-bundle installation of the signed Models revision. `installed-after.json` and `installation-identity-check.log` independently confirm the exact bundle/version at the new installer-reported bundle URL and the unchanged App Group container. No uninstall was performed. iOS reported a different application data-container path; the first path-equality probe therefore failed. Private data contents and migration were not inspected. Installation does not prove rendered UI or physical interaction.

The dedicated sAiity simulator remains shut down because hAiity, Day QA and Day Tests were already booted. None was operated or shut down. Rendered light/dark screens, small-screen and Accessibility 5 layouts, VoiceOver, and physical menu/action interaction remain unverified. The app was not launched during installation verification, and no room audio, private transcripts, model downloads or permission changes were used for QA.

## Dictation-board More and Emoji/ABC follow-up

The user reported that More did not react on the dictation board when the top bar was disabled. Source inspection found that the board always kept More in a 32-point target at `y=0`, despite removing the top bar's window extension. That boundary placement is a concrete concern, but the installed-phone failure was not independently reproduced in this pass.

When the top bar is disabled, More now uses a 46-by-44-point target inside the board beside its power control. The existing controls overlay routes points inside this menu target before the microphone/recovery controls' expanded hit areas. The button retains its native deferred `UIMenu` and primary-action behavior. The previous top-lane placement stays in use when the top bar is enabled; geometry too small to hold the interior target retains the existing accessory fallback.

Emoji and ABC swap only on the dictation board: `123`, Emoji, Space, ABC, Return. Both the active UIKit controls and retained SwiftUI board positions use this order. The shared geometry and other keyboard pages retain their positions, sizes and navigation owners.

Evidence: `/tmp/saiity-board-touch.kf3v2s`.

- `board-red.log`: two new source-contract checks failed against the old unconditional menu target and Emoji/ABC positions. This is source-contract evidence, not a physical touch reproduction.
- `board-green.log`: 92 focused ownership, accessory and appearance checks passed. The interior target is at least 44 points in each direction, stays inside the surface, and clears power, dictation, Delete and Space across 320, 375, 402 and 440-point portrait widths plus 667 and 852-point landscape widths.
- `geometry-routing.log`: 121 further affected policy, input-layer and key-geometry checks passed. Total focused evidence is 213 tests with zero failures.
- `simulator-build.log` and `device-build.log`: Debug simulator and signed Release iOS builds succeeded. `simulator-signatures.log` and `device-verify.log` verify app/keyboard/widget signatures, version 1.0.0 (243), team and App Group parity.
- `keyboard-fixture.log`: the production keyboard fixture compiled and linked. It now checks the actual window's More recipient at center and corners, the menu configuration, and Emoji/ABC positions around Space when executed. It was not executed because the other three simulators still occupied the simulator budget; fixture compilation is not native touch or rendering evidence.
- Caller review covered UIKit, retained SwiftUI positions and shared auxiliary-page geometry. `git diff --check` passed. All prior Models, app and keyboard changes are preserved.

`install-result.json` records the successful same-bundle update under the user's prior phone-install authorization. `installed-after.json` and `installation-identity-check.log` independently confirm 1.0.0 (243) at the exact new installer-reported bundle URL, with the same App Group container. No uninstall or app launch was performed.

Physical menu presentation, VoiceOver activation and keyboard gesture behavior remain unverified. No microphone action, model download, private-text access, permission change, commit, push or release operation was used for verification.

## Flatter app surfaces and stable history timestamps

The user requested less rounding in the app and reported moving numbers under Your words. Both recent-history branches used SwiftUI's `Text(date, style: .relative)`, which automatically changes elapsed time, including seconds. These were timestamps rather than word counts. Both now format the entry's saved `createdAt` as a fixed, locale-aware abbreviated date and shortened time. History identity, ordering, text, editing, restoration, copying and storage are unchanged; no timer or date helper was introduced.

Settings and its subpages, Models, voice options, history, model details and licenses now use native plain lists. Settings and Models use the same semantic system background as Speak. Start, Finish, Cancel, Close and keyboard-power app controls use rounded rectangles with 10-point corners instead of circles or default pill shapes. The existing shared app action style changes from 20 to 10 points, covering recovery and onboarding actions through their current callers. Setup/verification panels change from 24 to 12 points; the model-preparation panel changes from 28 to 12 points.

Apple/frontend/Ponytail guidance informed the flatter list hierarchy, small control corners, semantic colors and reuse of the shared app button style. Relevant references are `lists-and-tables.md › Style and Content` and `buttons.md › Best practices`. Native navigation and controls, button labels and accessibility, existing minimum touch dimensions, recording/stop colors, preferences and recovery paths remain in place. Keyboard key shapes and the preceding board fixes are untouched by this presentation pass.

Evidence: `/tmp/saiity-flat-ui.8Eri1h`.

- `history-red.log`: the existing app-foundation test failed twice against the live relative label and missing fixed-date format before implementation.
- `app-checks.log`: 60 focused app-foundation, history and readiness checks passed with zero failures. Obsolete rounded-list assertions were updated to the requested plain-list presentation. Unaffected full kernel/inference checks were not repeated.
- `simulator-build.log` and `device-build.log`: Debug simulator and signed Release iOS builds succeeded. `simulator-signatures.log` and `device-verify.log` independently verify app, keyboard and widget signatures plus bundle/version/team/App Group parity. Build number remains 1.0.0 (243).
- `app-fixture.log`: production app view bodies compiled and linked with inert data/lifecycle dependencies. The existing fixture now supplies three fabricated recent dictations so future rendering covers both timestamp branches. No screenshots or view actions were executed.
- Caller/source review and `git diff --check` passed. All previous app, Models and keyboard changes and Git recovery state are preserved. No dependency, new layer, commit, push, upload or release change was added.

`install-result.json` records a successful same-bundle phone update under the existing installation authorization. `installed-after.json` and `installation-identity-check.log` independently confirm the new installer-reported bundle URL, version 1.0.0 (243), and the unchanged App Group container. No uninstall or app launch was performed.

Native rendering and physical visual/VoiceOver acceptance remain pending. The dedicated sAiity simulator remains shut down while the three other project simulators are booted; none was operated or stopped. No room audio, model download, private transcript access or permission change was used for this pass.

## In-app rework and top-left More

The user rejected the app's visual hierarchy and requested a complete, coherent in-app rework plus restoration of the dictation board's More control to the top left. The design centers on a writing surface and a fixed, labeled recording strip. Speak shows the newest transcript prominently; secondary transcript tools stay quiet. Models becomes a native root tab, using the existing shared model owner. Settings stays a native preference list with clearer grouping and row hierarchy. Recording uses the same control shape and typography as Speak.

This direction was reviewed against `PRODUCT.md`, Apple Design, frontend-design and Impeccable's product register. It keeps SF system text, the existing blue action colors and semantic backgrounds. The voice mark belongs in the recording control/status, where it communicates the product's purpose. There is no additional display font, decorative motion, illustration, gradient or repeated card system. The design's distinction comes from the transcript and recording interaction rather than added branding.

The palette is the existing semantic canvas/content pair (reference white `#FFFFFF` / black `#000000`, with system-managed dark/contrast variants), secondary system surface (reference `#F2F2F7`, resolved through the platform), action blue `#245DE3` / `#8CADFF`, and on-action white / `#101A35`. Existing action contrast remains 5.60:1 in light appearance and 7.80:1 in dark appearance. Recording retains system red. System colors are API values, not hard-coded reference hex values. Typography uses native large titles for root navigation, title2/title3 for transcript/content hierarchy, body for rows, subheadline for actions and footnote/caption for metadata. Content and action widths are bounded on wider screens; accessibility layouts stack and remain scrollable.

Compact layout:

```text
Speak                         Voice options
Readiness / keyboard power

Your words                          History
Saved date and time
Latest transcript, readable at a glance
Copy                         Edit   More
Other recent dictations

           Start dictation
Speak               Models         Settings
```

Regular-width layouts use the same reading order with a centered, bounded content column and recording action. More returns to the board's top-left edge with a full 44-point target; power clears that target below it. Native menu ownership, prioritized touch routing and the board-only Emoji/ABC swap remain in place.

Implementation is local and uncommitted on `cursor/keyboard-surface-fixes-a66e`, based on `4c2f6c8a`. Build number remains 1.0.0 (243). All prior app, keyboard and multilingual changes and Git recovery state are preserved. The rework uses the existing views, shared action style and root model owner; no dependency or app layer was added.

Speak's newest transcript now has title2 reading typography, a clear Copy action and quieter edit/menu controls. Original comparison, restoration, editing, sharing, feedback and translation-fallback notices remain reachable. Saved timestamps retain fixed, localized formatting. Keyboard power and its truthful microphone-preparation status move into the scrollable content, leaving a single labeled Start dictation action in the bottom strip. Recording shares that action style, keeps red Finish during recording and stage-specific cancellation/recovery, and separates the transcript from its status/timer. Its status stacks and decorative mark disappears at accessibility sizes. Root Models navigation shares the existing `ModelManager`; Settings removes the duplicate Models destination and gives its remaining native rows readable title/detail hierarchy. Model selection and download/error/delete lifecycle owners are unchanged.

The hidden-bar board's More target is 46 by 44 points at `x=8`, `y=4`. Power clears it below; the existing native deferred menu and prioritized hit routing are retained. Top-bar-enabled accessory placement and the board-only Emoji/ABC swap remain. This is verified geometry and source ownership, not physical menu-presentation evidence.

Relevant Apple references: `layout.md › Visual hierarchy` ("Align components with one another" and group controls), `typography.md › Supporting Dynamic Type` ("Consider adjusting your layout at large font sizes"), `buttons.md › Best practices` ("a hit region of at least 44x44 pt"), and `tab-bars.md › Best practices` ("Use a tab bar to support navigation, not to provide actions"). Frontend-design and Impeccable's product register influenced the restrained palette, use of familiar native controls, transcript hierarchy and removal of repeated branding. The visual direction is a design decision; acceptance has not been measured.

Evidence directory: `/tmp/saiity-ui-rework.mH0fKP`.

- `more-red.log`: the new regression failed against the prior location beside power before implementation.
- `focused-final.log`: 230 affected app-foundation, readiness, recent-history, keyboard ownership, appearance and geometry checks passed with zero failures. More stays top left, fully inside keyboard bounds and clear of other controls at 320, 375, 402, 420 and 440-point portrait widths and 667, 852 and 912-point landscape widths, with 0/32-point accessory budgets. The unaffected full recognition/inference suites were not repeated.
- `simulator-final.log` and `device-build.log`: Debug simulator and signed Release iOS builds succeeded with pinned dependencies and serial main-agent builds. The device build retains iPhone Air resource filtering.
- `simulator-signatures.log` and `device-verification-final.log`: strict signatures passed independently for app, keyboard and widget. Device metadata confirms 1.0.0 (243) parity, minimum iOS 17.0, team `H8FW6W6K2D`, development signing/entitlements and `group.de.aiity.saiity.ios.beta` on all three bundles.
- `app-fixture.log` and `keyboard-fixture.log`: production native bodies compiled and linked. The app fixture now covers populated/empty Speak and the three root destinations. The keyboard fixture retains actual window hit-recipient checks and adds full-size top-left bounds when executed. These fixtures were compiled only; no rendering or touch checks ran.
- Caller/source review and `git diff --check` passed. No commit, push, upload, release change or tester invitation was performed.

The phone reconnected after the initial availability check. Under the user's earlier same-bundle installation authorization, the signed combined UI and selected-language revision was installed on the iPhone Air. `install-result.json` records success; `installed-after.json` and `installation-identity-check.log` independently match the new bundle URL to the installer receipt and confirm the unchanged App Group identifiers/container. No uninstall was performed. iOS changed the application data-container path; private contents and migration were not inspected.

The dedicated sAiity simulator remained shut down while hAiity, Day QA and Day Tests were already booted. None was operated or shut down. Rendered light/dark screens, small-screen/accessibility layouts, VoiceOver, physical More taps/presentation and the user's visual acceptance remain unverified. The installed app was not launched for QA. No room audio, private transcripts, model downloads or permission changes were used. Recognition accuracy, actual inference/latency and the other physical release gates remain separate from these UI/build/installation checks.

## October 14: recorder-led redesign and explicit More actions

The user reported More still did not respond and rejected Models as a root tab. The preceding check verified rectangles and compilation, not menu presentation. The existing More control only configured `UIButton.menu`/`showsMenuAsPrimaryAction`; it had no explicit app-owned tap action. Its position alone therefore did not establish a working action. This revision replaces that popup-dependent presentation with a native scrollable action list inside the input view. It reuses the existing field-aware `UIAction` menu contents, including guarded original/undo actions, Paste, output languages and dismissal. Native action rows, submenu navigation, closure, host resizing and input-owner priority are checked separately. The installed failure has not yet been reproduced in an authorized physical session.

The app direction is a compact voice recorder above a recent-text library. A single functional recorder surface groups actual readiness, selected languages and Start dictation. The familiar voice mark is part of that instrument; it does not become a repeated header. Recent transcripts use consistent previews and saved timestamps, opening their existing full edit/comparison view. Keyboard power remains a separate, truthful status/action. Recording mirrors the recorder's surface and control geometry while keeping its transcript readable. Settings groups voice, keyboard, saved text and support. Models moves inside Settings and Voice options, uses inline navigation and puts row actions next to their models. Speak and Settings are the only tabs.

The palette keeps the existing semantic canvas, secondary surface, primary/secondary text, adaptive action blue and system recording red. SF body, headline and title2 styles establish hierarchy; metadata uses footnote/caption. Controls keep 10-point corners and the single recorder surface uses 12 points. The design has no gradients, glass content, card grids or automatic decorative motion. Accessibility layouts stack and scroll. No inference/language owner, model selection preference or safety guard is changed by the presentation work.

This design follows the user's request and the existing `PRODUCT.md` direction. Apple Design and frontend-design informed the recorder/library separation, platform navigation, shared action geometry and readable state hierarchy. Impeccable's product register is used to critique consistency. Native grouped Settings and Voice options retain full-width row grouping without adding rounded card containers. Model action menus move beside the name at ordinary text sizes and below it at accessibility sizes; active/last-model deletion guards, parent-owned confirmations, all download/progress/error states, language caveats and remote-processing disclosures remain. The expanded transcript editor still owns original comparison, restoration, feedback and sharing. History rows gain the same fixed localized timestamp used on Home.

Initial evidence directory: `/tmp/saiity-full-rework.ZdxWZp`.

- `contracts-red.log`: four source-contract checks failed with eleven assertions against the old Models tab and popup-only More path. This was not a reproduction of the physical tap failure.
- `focused-tests.log`: 154 affected app-foundation, readiness, history, keyboard appearance, accessory and ownership checks passed with zero failures.
- `routing-checks.log`: 39 additional native input/surface ownership checks passed with zero failures. Total focused evidence is 193 tests; the unaffected full speech/inference suites were not repeated.
- `simulator-final.log`: final Debug simulator app/keyboard/widget build succeeded.
- `app-fixture.log`, `keyboard-fixture.log` and `native-input-checks.log`: production native fixtures compiled and linked. More checks now dispatch the real primary action and assert its native list, touch owner and closure rather than inspecting only menu configuration. The final keyboard fixture also checks language-submenu/back navigation without selecting a translation or starting a download. Execution/rendering remain pending.

The user installed an automatic task-cleanup workflow during this pass. The active Debug build was allowed to finish. Remaining disposable build/test work used `/Users/enrico/.codex/bin/codex-task`, with explicit output paths, dependent steps in one `set -eu` shell and retained deliverables outside scratch. The existing shared package checkout cache was reused. No old temporary builds, source, user changes, shared caches or Git recovery data were deleted.

Final retained artifacts:

- `/private/tmp/codex-task.5naz10dj/artifacts`: successful Release build log/result bundle, independently verified retained `DictusApp.app`, app/keyboard/widget entitlements and `device-verification.log`. All three bundles retain 1.0.0 (243), minimum iOS 17.0, team `H8FW6W6K2D`, Apple Development signing and `group.de.aiity.saiity.ios.beta`.
- `/private/tmp/codex-task.nboyb55e/artifacts`: final app/keyboard fixture compilation logs and strict Debug app/keyboard/widget signature checks. The final app fixture uses an isolated fabricated German/Chinese/English selection; the keyboard fixture checks explicit More activation, native target ownership, output-language/back navigation, toggle closure and Close actions. It never selects a translation, starts a download or records audio. These assertions compiled but were not executed.
- `/private/tmp/codex-task.c4szcjd4/artifacts`: successful same-bundle phone installation, before/after metadata and `installation-identity-check.log`. The independent installed-app query matches the new installer-reported bundle URL and confirms the unchanged App Group identifiers/container. No uninstall was performed. The app-data container path changed; private contents and migration were not inspected.

All three wrapper commands completed successfully, removed only their disposable scratch and retained their outputs. The signed app remains available outside scratch. Source remains local/uncommitted on `cursor/keyboard-surface-fixes-a66e` at `4c2f6c8a`; all earlier language/keyboard changes and recovery state remain. Main performed serial builds and fixture compilations; no worker, commit, push, upload, release change or tester invitation was created.

The iPhone Air update used the user's existing installation authorization and was not launched or operated for QA. Physical More taps/presentation and VoiceOver behavior still require a separately authorized phone session. Light/dark, small-screen, landscape and Accessibility 5 rendering also remain unverified: the dedicated sAiity simulator stayed shut down while hAiity, Day QA, Day Tests and Day iPad were already booted. None of those simulators was operated or stopped. No room audio, private transcripts, model downloads or permission changes were used. Text correctness, native ASR/model behavior, background delivery, PiP/Live Activity and release readiness remain separate pending gates.

## October 14: native dropdown and top-right dictation power

The user explicitly requested More on the left, dictation enable/disable at the top right, and the native dropdown instead of the custom in-keyboard action list. This request supersedes the preceding custom-list presentation. The app redesign and two-tab navigation remain intact.

The board's existing layout now mirrors More's 46-by-44-point rectangle into the top-right corner. Both targets use `y=4` and 8-point side insets, including when the ordinary top bar is enabled. Power uses its actual target on the board rather than expanding into the adjacent Delete key; auxiliary-page hit expansion and placement keep their existing behavior. The controls clear dictation, Delete, Return and each other at the covered portrait/landscape dimensions.

More is a standard system `UIButton` with `UIButton.Configuration` drawing its own ellipsis image, `showsMenuAsPrimaryAction` and an uncached deferred `UIMenu`. The prior native implementation used the custom keyboard button subclass/passive face; this implementation gives UIKit its ordinary button content and interaction. Native hit priority is retained. Existing field-aware Paste, output-language, original/undo and dismissal actions are reused. The custom panel, row builder, submenu navigation and panel input owner are removed. The remaining native dropdown still needs physical tap/presentation verification; configuration and hit geometry alone do not establish it.

`/private/tmp/codex-task.zo9dc_95/artifacts/native-menu-red.log` records the regressions failing against the custom menu and left-side power before the change. `/private/tmp/codex-task.owug5xd0/artifacts/native-menu-checks.log` records 209 affected geometry, appearance, keyboard ownership and input/surface checks passing with zero failures. The unaffected full speech/inference suites were not repeated.

`/private/tmp/codex-task.5ja_l_tb/artifacts` contains the successful Debug keyboard/host-app build log/result bundle, strict keyboard signature verification and both native fixture compilation logs. The keyboard fixture now checks native system button type/image, attached `UIContextMenuInteraction`, native menu configuration and window-level More/power touch recipients. Power/More geometry is checked in the actual controller when the fixture runs. No synthetic menu action is used as proof of system popup presentation. Fixtures compiled and linked; they were not executed because the dedicated simulator's budget remained occupied by other projects. The wrapper cleaned its disposable scratch and retained these outputs.

`/private/tmp/codex-task.i6f5anox/artifacts` contains the successful Release build log/result bundle, standalone retained signed app, entitlements and independent strict app/keyboard/widget signature/bundle verification. Version remains 1.0.0 (243), minimum iOS 17.0, Apple Development team `H8FW6W6K2D`, with `group.de.aiity.saiity.ios.beta` on all three bundles. The existing shared package cache was reused. The wrapper removed only its disposable scratch after build, app retention and validation completed successfully. Existing code, user changes, caches and Git recovery state were preserved.

`/private/tmp/codex-task.wqqegc09/artifacts` records the successful same-bundle update on the iPhone Air under the user's existing installation authorization. The independent installed-app query matches the new installer-reported bundle URL and confirms unchanged App Group identifiers/container. No uninstall was performed. The app-data container path changed; private contents and migration were not inspected. The wrapper retained the installation reports and removed only its empty disposable scratch.

Source/caller review and `git diff --check` passed. Source remains local/uncommitted at `4c2f6c8a` on `cursor/keyboard-surface-fixes-a66e`. No commit, push, upload, release change or tester invitation occurred. The installed app was not launched or operated for QA. Actual native dropdown presentation/taps, VoiceOver and physical landscape behavior remain unverified. Four other project simulators remained booted; none was operated or stopped, and the dedicated sAiity simulator was not booted. No room audio, private transcripts, model downloads or permission changes were used. The preceding in-app redesign, selected-language changes and separate model/physical/release gates remain.

## October 14: larger emoji and fuller four-row layout

The user requested larger emoji and less unused height above the list. The active owner is the UIKit `EmojiPagerView` and its `EmojiPageCell`, rather than the retained SwiftUI picker. The pager already fills the available canvas. Its existing glyph sizing now has a 26-point cap instead of 22, with a row-height multiplier of 0.72 instead of 0.62 and the existing 16-point compact floor. The same native `UILabel` uses its intrinsic height and a row-dependent center constraint to spread the outer rows toward the canvas edges. The offset uses font line height to leave a two-point allowance inside the outer row cells. The shared Delete, category and bottom-control geometry remains intact; no new UI owner, dependency or abstraction was added.

`scripts/test-emoji-tone-selection.swift` now reads the active UIKit surface and category control. Its prior assertions expected these controls in the old SwiftUI host. The failed assertion logs and scratch are preserved in `/private/tmp/codex-task.r65g0643` and `/private/tmp/codex-task.7wdxpc8_`. The existing appearance contract now checks the native label instead of pinning the old 22-point default.

`/private/tmp/codex-task.z7qnb09u/artifacts` contains the passing production tone-geometry checks, 133 affected emoji/navigation/surface-policy tests with zero failures, successful Debug simulator build and independent strict app/keyboard/widget signature checks. The production keyboard fixture compiled and linked. Its added runtime assertions measure native glyph frames, require four rows, check clipping and top/bottom spacing, and require larger glyphs when portrait height permits them. These runtime assertions were not executed: four other project simulators occupied the simulator budget, so the dedicated sAiity simulator stayed shut down. No other project's simulator was operated or stopped.

`/private/tmp/codex-task.lba8mab0/artifacts` contains the passing updated appearance contract, bringing this scoped run to 134 tests with zero failures, the successful signed Release build, independent strict signatures, entitlements and bundle verification. The retained app is `/private/tmp/codex-task.lba8mab0/artifacts/DictusApp.app`, measuring 63,908 KiB. All three bundles retain version 1.0.0 (243), minimum iOS 17.0, team `H8FW6W6K2D` and `group.de.aiity.saiity.ios.beta`. The existing shared package cache was reused, and the wrapper cleaned only its successful disposable scratch.

`/private/tmp/codex-task.5ntx6kh_/artifacts` records the successful same-bundle update on the iPhone Air under the existing installation authorization. Before/after metadata and `installation-identity-check.log` independently match the installed bundle URL to the installer receipt and confirm the existing App Group identity and container. The phone app was not launched or operated for QA; private contents and migration were not inspected. Installation reports remain outside scratch.

Emoji appearance, physical taps, skin-tone holds, VoiceOver and landscape rendering still need native execution or an authorized phone session. Compilation, Mac geometry tests and installation do not establish those outcomes. No room audio, private transcripts, voice-model downloads, permission changes, commit, push, upload or release operation occurred. The Dictus source-independence plan and the existing physical/model/release-readiness gates remain open; the recovery heartbeat remains active.
