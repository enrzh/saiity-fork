# Syllivra for iOS

Syllivra is a privacy-first iOS keyboard for voice dictation. Hold the
dictation control, speak naturally, and release to insert polished text into
the active text field. Speech recognition runs locally through
[WhisperKit](https://github.com/argmaxinc/WhisperKit), with no account or
required server.

This project is based on [Dictus](https://github.com/getdictus/dictus-ios),
an open-source iOS dictation keyboard released under the MIT License. Syllivra
retains the original MIT attribution and builds on its keyboard, on-device
model, and app-extension architecture.

## Features

- Press-and-hold voice dictation from the system keyboard
- On-device speech recognition and optional Apple Intelligence cleanup
- Multilingual model support with automatic language detection
- App Group communication between the app and keyboard extension
- No subscription, account, or cloud speech service required

## Project structure

| Target | Responsibility |
| --- | --- |
| `DictusApp` | Onboarding, settings, model management, and processing |
| `DictusKeyboard` | Compact system keyboard extension and dictation control |
| `SyllivraKernel` | Shared preferences, model metadata, and App Group storage |

The keyboard extension stays lightweight. Audio capture and model processing
remain in the containing app where iOS permits the required resources.

## Requirements

- Xcode 27 for the current Apple Intelligence/runtime integration
- iOS 17 or newer
- A physical iPhone is recommended for keyboard and microphone validation

## Build

Open `Dictus.xcodeproj`, select the `sAiity-iOS` scheme, choose a signed iOS
device, and build. Then enable the keyboard in **Settings > General >
Keyboard > Keyboards > Add New Keyboard**.

For shared package tests:

```bash
cd SyllivraKernel
swift test
```

Keep the checked-in package pins. The local candidate
plan is [the October 9 product plan](docs/superpowers/plans/2026-10-09-product-quality-and-testflight.md).

## Attribution and license

sAiity is based on Dictus by PIVI Solutions and contributors. Dictus is
licensed under the MIT License; see the original attribution and license
notices included in this repository. sAiity changes are provided under the
same MIT terms unless stated otherwise.

The current shared package is the locally maintained `SyllivraKernel`;
`DictusCore` is no longer linked by the app, keyboard or widget. Inherited app,
keyboard and shared source still require the Dictus copyright and MIT notice.
Replacing or renaming a module does not remove that source attribution.

## Privacy

Recognition and cleanup run on the device; only installing models uses the
network. History, vocabulary and diagnostics have separate controls. See
[PRIVACY.md](PRIVACY.md) for storage, Full Access and sharing details.
