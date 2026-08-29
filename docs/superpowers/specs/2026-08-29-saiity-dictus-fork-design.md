# sAiity Dictus Fork Design

## Goal

Use Dictus as sAiity's iOS implementation base so keyboard dictation inherits its proven recording, background-audio, transcription, processing, and text-insertion lifecycle.

## Product Boundary

Keep Dictus's audio and handoff pipeline intact. Replace its general-purpose typing keyboard with sAiity's voice-only keyboard. Preserve required attribution under the MIT license, but remove the user-facing About destination.

## Identity

All visible product copy, display names, app and extension bundle identifiers, App Group identifiers, URL schemes, and Live Activity labels become sAiity. Internal source type names may remain Dictus where renaming has no user-visible value and would increase regression risk.

## Keyboard

The keyboard contains no alphabetic or numeric key grid. It uses sAiity's compact voice layout with a centered press-and-hold microphone, automatic-language indicator, delete, return, keyboard switch, and dismiss controls. The surface uses native iOS materials and Liquid Glass styling where available, with readable fallbacks.

## Models

Retain every Dictus model and add sAiity catalog entries only where Dictus already has a compatible runtime. WhisperKit-compatible variants join the Whisper catalog; Parakeet-compatible variants join its catalog. Models requiring unsupported runtimes are not falsely exposed as functional.

## Settings

Remove Keyboard language, layout, number row, haptic feedback, sounds, and autocorrect from the Keyboard settings category. Transcription language is fixed to automatic and its selector is removed. Remove the About destination while retaining privacy and license text where legally required.

## Safety

The existing sAiity-iOS checkout remains untouched. Development happens on branch `saiity-fork` in `/Users/enrico/Documents/GitHub/sAiity-dictus`.
