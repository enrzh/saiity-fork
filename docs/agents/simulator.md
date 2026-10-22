# Headless Simulator

How an agent gets DictusApp running on an iOS Simulator and produces a screenshot, without opening a window.

Every command below was executed on this machine (Xcode 26.4.1, iOS 26.5 runtime, iPhone 17). The outputs shown are the ones they produced.

**Never bring a Simulator window to the front.** Pierre works on this machine and a foregrounded window steals his focus. `open -a Simulator` is therefore forbidden — but `open -g -a Simulator` is not, and section 5 needs it: `-g` starts the app without foregrounding it. Verified 2026-08-22 by reading the frontmost process before and after; it did not change. If a command foregrounds a window anyway, stop and record it here.

## 1. Choose and boot a device

Check for a booted device before booting another:

```bash
xcrun simctl list devices booted
```

```
== Devices ==
-- iOS 26.5 --
    iPhone 17 (231991C2-5F6E-4A2B-8BC3-0C729DFD2B2A) (Booted)
```

Reuse it. If nothing is booted, pick a UDID from the available list:

```bash
xcrun simctl list devices available
```

```
-- iOS 26.5 --
    iPhone 17 Pro (1720B34A-F21A-4E22-9F44-A7BB663D8004) (Shutdown)
    iPhone 17 (231991C2-5F6E-4A2B-8BC3-0C729DFD2B2A) (Booted)
    iPhone 13 (D80C795A-6FB6-421B-98F7-18E878A14E7D) (Shutdown)
```

```bash
xcrun simctl boot <udid>
xcrun simctl bootstatus <udid>
```

`bootstatus` blocks until the device is usable. Its last lines look like a failure and are not:

```
[2026-08-03 11:39:37 +0000] Status=4294967295, isTerminal=YES, Elapsed=00:04.
	Finished
```

On an already-booted device it prints `Device already booted, nothing to do.`

## 2. Build for that simulator

A fresh worktree resolves its packages from zero, so both steps are needed the first time:

```bash
xcodebuild -resolvePackageDependencies \
  -project Dictus.xcodeproj -scheme DictusApp \
  -derivedDataPath build/DerivedData

xcodebuild build \
  -project Dictus.xcodeproj -scheme DictusApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=<udid>' \
  -derivedDataPath build/DerivedData
```

Building `DictusApp` builds the embedded keyboard, widgets and core. The product lands at:

```
build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app
build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app/PlugIns/DictusKeyboard.appex
build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app/PlugIns/DictusWidgets.appex
```

**Do not copy CI's signing flags into a build you intend to run.** `.github/workflows/ci.yml` passes `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_IDENTITY=""`, which is right for a compile-only check and wrong here. That build is unsigned:

```bash
codesign -d --entitlements - build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app
```

```
Executable=/Users/…/DictusApp.app/DictusApp
```

With that build, `AppGroup.containerURL` comes back nil on the device, so `dictus_debug.log` is never written and nothing crossing the App Group can be observed. Built without those flags, the app is ad-hoc signed and the container resolves. Drop the flags.

Do not read a mechanism into that. The ad-hoc signed build carries an *empty* entitlements dictionary — no `application-groups` key — and its container resolves anyway, so the simulator is not gating on the entitlement the way a device does. Signed-versus-unsigned is what was observed to matter here, not why.

## 3. Install and launch

```bash
xcrun simctl install <udid> build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app
xcrun simctl launch <udid> com.pivi.dictus
```

```
com.pivi.dictus: 84714
```

Bundle identifiers: app `com.pivi.dictus`, keyboard `com.pivi.dictus.keyboard`, widgets `com.pivi.dictus.widgets`.

**A launch failure** exits non-zero and names the domain:

```bash
xcrun simctl launch <udid> com.pivi.nope
```

```
An error was encountered processing the command (domain=FBSOpenApplicationServiceErrorDomain, code=4):
Simulator device failed to launch com.pivi.nope.
```

**A crash after launch** looks like a success: `launch` exits 0 and prints a pid, because the process did start. Check the pid:

```bash
ps -p <pid> -o pid,comm
```

Nothing but the header means the process is gone. The reason is in the device log:

```bash
xcrun simctl spawn <udid> log show --last 10m --style compact \
  --predicate 'process == "SpringBoard" AND eventMessage CONTAINS "Process exited"' \
  | grep pivi.dictus
```

```
… [app<com.pivi.dictus>:24394] … status:<RBSProcessExitStatus| domain:frontboard(10) code:force-quit(0xfbfbfbfb)>
… [app<com.pivi.dictus>:31271] … status:<RBSProcessExitStatus| domain:signal(2) code:SIGSEGV(11)>
```

`force-quit` is `simctl terminate`; a signal is a crash. Do not wait for a `.ips`: a SIGSEGV killed here produced no crash report under `~/Library/Logs/DiagnosticReports/`.

Container paths, when you need the app's own state:

```bash
xcrun simctl get_app_container <udid> com.pivi.dictus groups
```

```
group.solutions.pivi.dictus	/Users/…/Devices/<udid>/data/Containers/Shared/AppGroup/3B7549C4-…
```

`dictus_debug.log` sits at the root of that directory.

## 4. Capture

```bash
xcrun simctl io <udid> screenshot /path/outside/the/repo/shot.png
```

```
Wrote screenshot to: /…/shot.png
```

**Screenshots do not belong in the repository.** Write them to a scratch directory and report the absolute paths.

`simctl launch` returns as soon as the process spawns, not when the UI is on screen. A screenshot taken immediately captures the launch animation or a black frame. Let the UI settle, then shoot; repeating the screenshot a few times and keeping the last one is enough.

Video recording works headlessly. It runs until SIGINT:

```bash
xcrun simctl io <udid> recordVideo --codec=h264 --force /path/outside/the/repo/demo.mp4
```

```
Recording started
Recording completed. Writing to disk.
Wrote video to: /…/demo.mp4
```

## 5. Drive the UI

`simctl` has no touch injection. **`axe` does** — it is installed on this machine (`/opt/homebrew/bin/axe`, v1.8.0, `brew install cameroncooke/axe/axe`) and it taps, swipes, types and dumps the accessibility tree.

**The catch, and it is the whole section:** every point-based command needs Simulator.app to be running *with the target device attached*. Simulator.app merely being alive is not enough — a device booted after it started is not attached to it. The order matters and so does the wait:

```bash
xcrun simctl boot <udid>
xcrun simctl bootstatus <udid>     # blocks until the device is usable — do not skip
open -g -a Simulator               # -g starts it without foregrounding it
```

Then poll rather than assume. Attachment takes a few seconds, and firing `open -g` before `bootstatus` returns leaves the device unattached — that failure was reproduced here twice before the order was pinned down:

```bash
for i in 1 2 3 4 5 6; do
  sleep 5
  axe describe-ui --udid <udid> >/dev/null 2>&1 && break
done
```

**Do not quit Simulator.app to reset the attachment.** Quitting it shuts down every device it owns — observed here, a booted device went straight to `Shutdown`. Re-run `open -g -a Simulator` instead.

Without the attachment, every point-based command fails with a message that misattributes its own cause:

```
Error: No translation object returned for simulator. This means you have likely
specified a point onscreen that is invalid or invisible due to a fullscreen dialog
```

There is no dialog. The point-translation bridge is simply not connected. Measured 2026-08-22 on Xcode 26.4.1 / iOS 26.5, on a clean Home screen, by label and by coordinates, with `--tap-style simulator` and `physical` alike. Run `open -g -a Simulator` and the same command succeeds.

| Needs Simulator.app attached | Works with `simctl` alone |
| --- | --- |
| `tap`, `touch`, `swipe`, `drag`, `describe-ui`, `slider` | `button`, `key`, `key-sequence`, `type`, `gesture`, `screenshot`, `record-video` |

Read the screen before you tap it. `describe-ui` returns the full accessibility tree as JSON, with an `AXFrame` per element in **points** (402×874 on an iPhone 17, not the 1206×2622 pixels a screenshot has):

```bash
axe describe-ui --udid <udid>
```

Tap by accessibility label rather than by coordinate wherever the label is stable — it survives layout changes:

```bash
axe tap --label "Commencer" --udid <udid>
```

`--label`/`--id` **locate** the element and then deliver a real touch at its activation point; they are not accessibility activation. Always pass `--tap-style physical` to get a HID touch-down/up, which is the only way to test hit testing honestly — activation will happily report success for a control that no finger can reach.

Two coordinate traps, both of which silently produce nonsense results:

- **Never scale screenshot pixels to decide a tap.** `axe tap -x/-y` lives in the same space as the `AXFrame`s, and that space is *not* the screenshot's pixel grid. Dividing a screenshot by 3 lands hundreds of points off and taps whatever happens to be there — a neighbouring key, the Home indicator, or nothing. Read the frame, tap its centre.
- **A keyboard extension's controls are absent from the tree.** Its SwiftUI content contributes no nodes, so `--label` cannot reach its keys and `AXFrame`s do not exist for them. Derive the offset once from the extension's own logs (it reports the local point each touch arrived at), then add that fixed offset. On the iPhone 18 Pro, `axe_y = extension_local_y + 530`, verified against a logged `point=(58.0, 68.0)` from a tap at `y=598`.

```
✓ Tap at resolved tap point at (201.0, 716.0) completed successfully
```

When two elements share a label and neither exposes an `AXUniqueId`, `axe` refuses rather than guessing:

```
Warning: Multiple (2) accessibility elements matched --label 'Continuer', and none of
the matches expose AXUniqueId on this screen. Use coordinates for this step … No tap performed.
```

That is the right behaviour, and it is a nudge: give controls an agent is expected to drive an `.accessibilityIdentifier("…")` and target them with `--id`. Coordinates still work when there is no usable label, and the tab bar is the usual case:

```bash
axe tap -x 201 -y 815 --udid <udid>    # Models tab
```

Verified end to end on 2026-08-22: installing DictusApp, tapping through the onboarding pages by label, and reaching the Models and Settings tabs by coordinate. The frontmost application stayed the terminal throughout.

Xcode 27 replaces this attachment dance with Device Hub and drops the Simulator.app requirement, per AXe's own compatibility notes. Until this machine moves to it, `open -g -a Simulator` is the price of a tap.

## 6. Control the frame

This project ships a dark-first design in French and English, so all three of these matter.

**Appearance** — read, then set:

```bash
xcrun simctl ui <udid> appearance         # light
xcrun simctl ui <udid> appearance dark
```

**Status bar** — a fixed status bar keeps screenshots comparable:

```bash
xcrun simctl status_bar <udid> override \
  --time "09:41" --batteryState charged --batteryLevel 100 --cellularBars 4
```

**App language, per launch** — the cheapest way to shoot both locales:

```bash
xcrun simctl launch <udid> com.pivi.dictus -AppleLanguages '(en)' -AppleLocale en_US
```

Verified: the same screen renders `Commencer` without it and `Get started` with it. This changes the app only; the system UI stays in the device language.

**Device language, system-wide** — needed when the system UI or date formats are part of what you are looking at. Shut the device down, edit its global preferences, boot again:

```bash
xcrun simctl shutdown <udid>
python3 - "$HOME/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/Preferences/.GlobalPreferences.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
d['AppleLanguages'] = ['en-US']
d['AppleLocale'] = 'en_US'
plistlib.dump(d, open(sys.argv[1], 'wb'))
PY
xcrun simctl boot <udid>
```

Two traps here, both observed while writing this file. `defaults write` from the host against a plist inside a device's data directory silently does not stick — the host `cfprefsd` owns the write and it never reaches the file. `plutil -replace` fails on a key the file does not have yet. Editing the plist with `plistlib` while the device is shut down is what works.

Put the device back the way you found it. This one is `fr_FR` with `AppleLanguages = (fr-FR, en-GB)`.

## 7. Clean up

```bash
xcrun simctl status_bar <udid> clear
xcrun simctl ui <udid> appearance light
xcrun simctl uninstall <udid> com.pivi.dictus
```

`uninstall` also deletes the App Group container, so `dictus_debug.log` and every persisted preference go with it. Read what you need first.

Revert any `defaults write` you made on the device — those survive uninstall.

Leaving a device booted between runs is fine and is the cheaper default; boot is the slow part. Shut down only a device you booted yourself:

```bash
xcrun simctl shutdown <udid>
```

## 8. What the simulator cannot show

**Update 2026-10-21 (Xcode 27, iOS 26.5 runtime, `sAiity Product QA`): taps do reach the keyboard extension.** `axe tap --tap-style physical` opened More, its Output language submenu, the emoji board and the letters page; emoji, Delete and letters reached the host field, and `axe touch --down` then `axe swipe` chose a skin tone. The 2026-09-24 measurement below is kept as history. Read the extension's frames from a screenshot (pixels ÷ 3 on this device) because its controls are absent from `describe-ui`.

**Never leave a touch down.** An `axe touch --down` without a matching `--up` blocks every later tap, swipe and Home press without an error. Shutting the device down and booting it again cleared it.

**Do not hold Delete with `axe touch --down --up --delay`.** Twice on 2026-10-21 a 3-second hold on the keyboard's Delete left the same silent block even though the command released, and relaunching the app did not clear it; a reboot did. Holding letter keys for up to 2 seconds (press popup, accent row) was fine. To clear a field, tap Delete repeatedly. On 2026-10-22 holding 123 to switch to the dictation board did the same once; after any hold that changes the page, check input with a harmless tap before trusting later results.

**Tapping and typing are no longer on this list.** They were, until 2026-08-22, on the grounds that `simctl` has no touch injection. That is still true of `simctl` and was never true of the machine: see section 5. Do not re-derive the old limit from the `simctl` man page.

**The Dictus keyboard CAN be enabled in a simulator.** This file said the opposite until 2026-08-23. It was wrong. Enabling it takes taps, and section 5 taps: Settings → Général → Clavier → Claviers → Ajouter un clavier → Dictus. Read each screen with `describe-ui` and tap the row centre from the reported `AXFrame` — these rows carry labels but no identifiers, so coordinates are what work.

The extension does register on install, which was never the question:

```bash
xcrun simctl spawn <udid> pluginkit -m -v -p com.apple.keyboard-service
```

```
     com.pivi.dictus.keyboard(1.8.0)	657D5A4D-…	/Users/…/DictusApp.app/PlugIns/DictusKeyboard.appex
```

After the taps, the device's own keyboard list carries it:

```bash
xcrun simctl spawn <udid> defaults read -g AppleKeyboards
```

```
(
    "fr_FR@sw=AZERTY-French;hw=Automatic",
    "en_US@sw=QWERTY;hw=Automatic",
    "emoji@sw=Emoji",
    "com.pivi.dictus.keyboard"
)
```

Note the format: a third-party keyboard is a bare bundle identifier, not the `locale@sw=` shape the built-ins use. That is the entry to write if you want to skip the tapping. `AppleKeyboards` lives in the device's `.GlobalPreferences.plist`, and editing it with `plistlib` while the device is shut down lands — section 6's technique. Writing it from the host with `defaults write` does not, and neither does the `com.apple.Preferences` domain; the previous version of this file made both mistakes at once and concluded from them that the keyboard could not be enabled.

iOS loads the extension too. `pkd` logs `Created plugin` for `com.pivi.dictus.keyboard(1.8.0)`, and SpringBoard lists it under `com.apple.keyboard-service`.

**Rendering needs two separate switches, and only one of them is `Connect Hardware Keyboard`.** With the third-party keyboard enabled *and* Full Access granted, the extension does run and present. Proven 2026-09-24: process `de.aiity.saiity.ios.beta.keyboard` came up, and `dictus_debug.log` gained 29 `<KBD>` lines including `inputContext_settled details=fullAccess=true` and `layoutSnapshot_2000ms … status=idle mode=keys onScreen=true hasWindow=true memMB=28`, with no errors.

**`AutomaticMinimizationEnabled` is the switch that hides every keyboard.** This is the cause of "the field is focused, the caret blinks, and no keyboard appears at all", and it is invisible in screenshots taken before focus. iOS auto-minimizes the software keyboard because a hardware keyboard has been seen. `ConnectHardwareKeyboard` is a *different*, host-side setting and is not the culprit — but it is easy to blame, because both are off by the time you look:

```bash
xcrun simctl spawn <udid> defaults write com.apple.keyboard.preferences \
  AutomaticMinimizationEnabled -bool false
xcrun simctl spawn <udid> defaults write com.apple.keyboard.preferences \
  HardwareKeyboardLastSeen -int 0
```

With `AutomaticMinimizationEnabled = 1`, every software keyboard is suppressed; with it `false`, the full layout appears immediately. Always set this before concluding that tapping a field does nothing.

**Selection must go through Settings; preference writes only set the list.** `AppleKeyboards` can be edited with `plistlib` while shut down (below) and it lands, but iOS still refuses to *present* a third-party keyboard that the user never added through Settings, and it repoints `KeyboardLastUsed` at a system layout. `KeyboardsCurrentAndNext` and `KeyboardLastUsed` in `com.apple.keyboard.preferences` are caches, not the selection: writing them changes nothing. Re-adding the keyboard in Settings and re-granting Full Access after every reinstall is mandatory, and an uninstall silently loses both.

**Reinstalls are not safe mid-session.** `simctl uninstall` and a fresh `simctl install` drop the App Group container (new UUID, `dictus_debug.log` gone) and the Full Access grant. Re-resolve the group path rather than caching it, and expect to redo the Settings taps.

Enabling and rendering are both solved. **Touch delivery is not, and it is not the app's fault.**

Measured 2026-09-24 with a purpose-built four-stage trace (`TouchPath`, DEBUG-only) that logs `hitTest` on the input view, on the UIKit overlay, inside the SwiftUI-host fallback, and in the per-key `UIControl`, plus the `extensionContext.open` result. The keyboard was fully presented and stable — `keyboardDidAppear`, `viewDidAppear_settled`, `inputContext_settled fullAccess=true`, `layoutSnapshot_2000ms` — and then **six taps across the surface produced zero log lines of any kind**, not even the periodic state refreshes that run on a timer.

Stage 1 (`KeyboardInputView.hitTest`) never fires, so UIKit is not hit-testing the extension's view hierarchy at all. Ruled out along the way:

- **Not a system keyboard stealing the input.** With `AppleKeyboards` set to the third-party bundle id *only*, so no native keyboard existed as a fallback, taps still produced nothing.
- **Not the injection method.** Physical HID drag, physical HID tap, and `--tap-style simulator` (`FBSimulator tapAt`) all behaved identically.
- **Not a hidden or stale frame.** The extension process was alive, `onScreen=true hasWindow=true hasInputWindow=true`, and no `viewDidDisappear` had fired.
- **Not the input stack.** Tapping ordinary app UI worked, and `axe type "Hello"` into a normal text field worked.
- **Not the old logging gate.** Earlier traces were gated to a `40...220` y band, which made "no log lines" indistinguishable from "no touch". Conclusions drawn from a missing trace before that gate was removed are unsound — this is the second time that mistake nearly cost a diagnosis.

**Consequence: the simulator can verify layout and visuals, and nothing about touch.** Judge key responsiveness, popups, press animation, swipes, and the app handoff on a device. A third-party keyboard that renders but never receives `hitTest` looks exactly like a dead keyboard, and no amount of app-side code will change that.

**Reinstalls are not safe mid-session.** `simctl uninstall` and a fresh `simctl install` drop the App Group container (new UUID, `dictus_debug.log` gone) and the Full Access grant. Re-resolve the group path rather than caching it, and expect to redo the Settings taps.

**A stray UI-test runner uninstalls the app.** `com.aiity.haiity.uitests.xctrunner` was found alive on the device and had removed the app between runs, which looks identical to "the build didn't install". Check `simctl listapps` for it and uninstall it before trusting any state on a shared simulator.

Enabling and rendering are both solved. What remains untested on a simulator is anything that depends on real touch latency, memory, or the microphone.

**The software keyboard appears, and `Connect Hardware Keyboard` did not stop it.** A widely repeated claim says a connected hardware keyboard suppresses the on-screen one and that this is why keyboard testing fails in simulators. Measured here with `ConnectHardwareKeyboard = 1`: tapping Safari's address bar brought up the full AZERTY keyboard, globe key included. The setting is real and headless-controllable —

```bash
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
```

— but on Xcode 26.4.1 / iOS 26.5 it is not what stands between an agent and a software keyboard. Check section 5's attachment first.

**Even a rendering keyboard would not give you the numbers.** Memory and timing are device figures. Dead zones, the declared height constraint and the keyboard-to-app handoff still need a physical iPhone.

**Custom-scheme URLs prompt.** `simctl openurl` raises a confirmation the user must accept — though section 5 can now accept it:

```bash
xcrun simctl openurl <udid> "dictus://dictate?source=keyboard"
```

exits 0 and raises an `Ouvrir dans « Dictus » ?` confirmation alert, which needs a tap. It behaves the same whether Dictus is frontmost or the device is on the Home screen.

**Microphone and dictation were not exercised, and the reason is structural.** The audio session does configure:

```
[…] INFO    [audio] <APP> audioSessionConfigured category=playAndRecord
[…] WARNING [audio] <APP> engineWarmUpFailed context=didBecomeActive error=modelReady=false
```

No transcription model is installed, and installing one means the Models tab — a tap — plus a download. Recording never starts, so nothing was proven about capture. `xcrun simctl privacy <udid> grant microphone com.pivi.dictus` exits 0, but it was never put to use.

Two things to know before trying: the simulator captures the **Mac's** input device, so a recording started here records the room Pierre is sitting in; and transcription runs on Mac silicon, so any timing measured in a simulator says nothing about the phone.

**StoreKit is inert.** The paywall and subscription state cannot be exercised without a StoreKit configuration:

```
[…] ERROR   [lifecycle] <APP> subscriptionError action=loadProducts error=empty result (StoreKit configuration missing or product ID unknown)
```

**What does work**, beyond plain screens: the App Group container and `dictus_debug.log` (with a signed build), and Live Activities — one started and rendered in the Dynamic Island during this run.
