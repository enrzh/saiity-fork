# Keyboard Auxiliary Surface Design

## Goal

Make every sAiity keyboard mode use one inset rounded Liquid Glass surface with the native iOS keyboard background visible around it, then simplify Emoji and symbols pages around direct, fixed controls.

## Root cause

`DictusKeyboard/InputView.swift` currently makes the outer `UIInputView` opaque and fills it with `systemGroupedBackground`. The SwiftUI surface is inset inside that rectangle, so the outer fill becomes a solid square layer between the inset surface and the system keyboard backdrop. Auxiliary pages also retain an older top accessory row owned by UIKit, which creates a second coordinate and background layer.

## Decisions

### Background ownership

`KeyboardInputView` is transparent and non-opaque on every initializer path. `KeyboardRootView` owns exactly one inset rounded surface for voice, Emoji, and symbols modes. The area outside that surface remains transparent so the system keyboard backdrop is visible. Reduced transparency and increased contrast use the existing semantic fallback fills inside the same shape.

### Voice controls

The voice page keeps its current controls and press-and-hold microphone behavior. The `Emoji, 123` order is the default. A shared App Group enum controls whether the bottom-left pair is `Emoji, 123` or `123, Emoji`; UIKit hit frames and SwiftUI glyph frames consume the same value.

### Emoji page

The top accessory row is removed. The Emoji grid uses the shared inset surface. The category bar remains at the bottom. Its leftmost 44-point control is a fixed `mic.fill` button that returns to the voice page; the category `ScrollView` begins beside it and scrolls independently. Category buttons have no individual glass backgrounds. There is no Emoji search control.

### Symbols page

The top accessory row is removed. The custom symbols grid fills the content area of the shared inset surface. The lower-left control cluster contains `face.smiling` at the bottom-left and a `mic.fill` return control immediately to its right. A `#+=` or `ABC` page switch control sits above the Emoji control. Delete and Return remain real symbol-grid actions. No floating controls are drawn outside the surface.

### Ownership and interaction

UIKit owns voice-page hit targets. SwiftUI owns Emoji and symbols page controls so their visual frames and hit targets share one coordinate system. Auxiliary-mode UIKit controls are hidden and do not intercept SwiftUI touches. All controls retain at least a 44 by 44 point target, semantic labels, pressed feedback, reduced-motion support, and light/dark semantic colors.

## Error and accessibility behavior

Returning to voice clears auxiliary-only state and any auxiliary glass views. A failed dictation continues to use the existing red error lane outside the microphone. The new return microphones are labeled as returning to the voice keyboard, and the order Picker exposes both choices to VoiceOver. No action relies on color alone.

## Verification

Core tests cover the order preference, invalid-value fallback, frame order, surface containment, auxiliary bottom controls, and absence of the old top-row contract. SimSlim verifies light and dark voice, Emoji, and symbols pages, category scrolling, Emoji return, symbols page switching, control hit targets, and no rectangular background layer between the surface and system keyboard backdrop.

## Constraints

- Preserve all existing dirty, untracked, and ahead-of-origin work.
- Do not add a manager, service, factory, or provider layer.
- Use the existing `VoiceOnlyKeyboardPolicy`, App Group defaults, SwiftUI/UIKit targets, and semantic system materials.
- Use only SimSlim device `AC636497-5EC6-4AD4-BD83-E5E2458FA702` on iOS 26.5 for runtime verification.
- Do not use DeviceHub, a physical iPhone, iPhone Mirroring, extra simulators, TestFlight, or release publishing for this task.
