# sAiity for iOS

sAiity is a privacy-first iOS keyboard for voice dictation. Hold the
dictation control, speak naturally, and release to insert polished text into
the active text field. Speech recognition runs locally through
[WhisperKit](https://github.com/argmaxinc/WhisperKit), with no account or
required server.

This project is based on [Dictus](https://github.com/getdictus/dictus-ios),
an open-source iOS dictation keyboard released under the MIT License. sAiity
retains the original MIT attribution and builds on its keyboard, on-device
model, and app-extension architecture.

## Features

- Press-and-hold voice dictation from the system keyboard
- On-device speech recognition and optional local text cleanup
- Multilingual model support with automatic language detection
- App Group communication between the app and keyboard extension
- No subscription, account, or cloud speech service required

## Project structure

| Target | Responsibility |
| --- | --- |
| `DictusApp` | Onboarding, settings, model management, and processing |
| `DictusKeyboard` | Compact system keyboard extension and dictation control |
| `DictusCore` | Shared preferences, model metadata, and App Group storage |

The keyboard extension stays lightweight. Audio capture and model processing
remain in the containing app where iOS permits the required resources.

## Requirements

- Xcode 16 or newer
- iOS 17 or newer
- A physical iPhone is recommended for keyboard and microphone validation

## Build

Open `Dictus.xcodeproj`, select the `DictusApp` scheme, choose a signed iOS
device, and build. Then enable the keyboard in **Settings > General >
Keyboard > Keyboards > Add New Keyboard**.

For shared package tests:

```bash
cd DictusCore
swift test
```

## Attribution and license

sAiity is based on Dictus by PIVI Solutions and contributors. Dictus is
licensed under the MIT License; see the original attribution and license
notices included in this repository. sAiity changes are provided under the
same MIT terms unless stated otherwise.

## Privacy

Voice recordings and transcripts are processed and stored locally on the
device. sAiity does not require an account or send dictated text to a server.
