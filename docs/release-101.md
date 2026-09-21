# Build 101 — 2026-09-14

Version 1.0.0 (101), archived from the existing dirty `saiity-fork` checkout.
Existing changes were preserved; no GitHub push or CI run was performed.

Includes the suggestion-bar and keyboard-layout work on top of build 100:

- AUTO opens a stable language sheet instead of a Menu that reset while scrolling.
- With full access, the suggestion lane shows a native-style Paste/Code chip for clipboard text or OTP-looking codes. Image-only pasteboard still cannot be inserted.
- ABC page hides ABC and uses one wide 123. Letter, shift and delete keys share keycaps and row height.
- Emoji page hides the smiling-face control and gives that width to space.
- 123/#+= keys use the same keycap treatment as letters.

Verification:

- Release archive and App Store Connect export passed.
- App, keyboard and widget archive metadata all report build 101.
- IPA: `/tmp/sAiity-export-101/DictusApp.ipa`.
- SHA-256: `db115e4667bf6bfe6d43e6fdef4e52e19aa787d7e252910136ecdb1e7bcb16f7`.

Limitations: this is a TestFlight candidate for device testing. Simulator compile does not prove AUTO sheet scrolling, the clipboard chip with full access, or native-like key feel on iPhone.

Distribution: App Store Connect upload succeeded on 2026-09-14 at 14:54 local time.
Apple then reported that the uploaded package was processing. TestFlight typically shows the build after that processing finishes.
