# Build 134 — 2026-09-16

Version 1.0.0 (134).

## Changes since 133

- **Reverted build 133 keyboard design** (unified glass panel, native key metric pass). UI matches **build 132** again.
- Keeps 132 behavior: typing hit targets, no word suggestions in accessory bar, emoji lane/scrubber, autocorrect-on-space when enabled.

## Verification

- Archive: `/tmp/sAiity-archive-134/DictusApp.xcarchive` (`CFBundleVersion` 134).
- IPA export attempted 2026-09-16 ~12:33 local — **failed**: App Store Connect “upload limit reached; wait 1 day”. Re-upload with:
  `xcodebuild -exportArchive -archivePath /tmp/sAiity-archive-134/DictusApp.xcarchive -exportPath /tmp/sAiity-export-134 -exportOptionsPlist /tmp/sAiity-export-134-ExportOptions.plist -allowProvisioningUpdates`
  or Xcode Organizer → Distribute App.
