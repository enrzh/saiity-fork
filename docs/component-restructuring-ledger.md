# Component restructuring ledger

Date: 2026-09-22. Branch `cursor/keyboard-surface-fixes-a66e` at `e275e1a1`, dirty worktree preserved. Nothing was committed, pushed, installed, or uploaded.

This pass moved ownership. It did not change key geometry, key spacing, emoji layout, popup timing, hold-to-speak, or the rule that Liquid Glass and solid materials share one touch owner. `KeyboardState` and `DictationCoordinator` remain the facades existing views observe.

## Dictation

| Component | Original owner | New owner | Callers migrated |
| --- | --- | --- | --- |
| DictationSessionController | `DictationCoordinator` session generation and `mayReport` | `DictusCore/Sources/DictusCore/DictationSessionController.swift` | `DictationCoordinator` |
| TranscriptionPipeline | Post-cleanup grammar floor and sentence separator inside `DictationCoordinator` | `DictusCore/Sources/DictusCore/TranscriptionPipeline.swift` | `DictationCoordinator.stopDictation` |
| CleanupPipeline | `PolishCoordinator.shared.polish` call inside `DictationCoordinator` | `DictusApp/Dictation/CleanupPipeline.swift` | `DictationCoordinator.stopDictation` |
| DictationDeliveryStore | Five App Group writes at the ready boundary | `DictusCore/Sources/DictusCore/DictationDeliveryStore.swift` | `DictationCoordinator` |

Multilingual text still skips the sentence separator when `insertsTranscriptionAsIs` is set and there is no translation target. Spoken text is not translated by this move.

## Keyboard runtime

| Component | Original owner | New owner | Callers migrated |
| --- | --- | --- | --- |
| KeyboardSurfaceState | Emoji-category offset, selection, and expanded guards on `KeyboardState` | `DictusCore/Sources/DictusCore/KeyboardSurfaceState.swift` | `KeyboardState` setters. Published fields stay on `KeyboardState` for existing Combine subscribers. |
| KeyboardInputRouter | Controller ownership check in `KeyboardViewController` | `DictusCore/Sources/DictusCore/KeyboardInputRouter.swift` | `routeProxyCommand`, `routeProxyText` |
| KeyboardDictationBridge | Recovery URL and the 0.75s open debounce | `DictusCore/Sources/DictusCore/KeyboardDictationBridge.swift` | `openDictusForRecovery`. `openModelPreparation` still uses its own 1s interval and the same URL. |
| KeyboardLifecycleMonitor | Heartbeat reading inside `KeyboardState.dictationLiveness` | `DictusCore/Sources/DictusCore/KeyboardLifecycleMonitor.swift` | `KeyboardState`. A missing heartbeat still reports age `-1`. |

## Keyboard surfaces

| Component | Original owner | New owner | Callers migrated |
| --- | --- | --- | --- |
| LetterKeyboardSurface | `LetterKeyboardPageView` in `KeyboardRootView` | `DictusKeyboard/LetterKeyboardSurface.swift` | `KeyboardRootView.areaSurface` |
| KeyboardTouchOverlay | `AdaptiveLetterTouchRouter` in `KeyboardRootView` | `DictusKeyboard/KeyboardTouchOverlay.swift` | `LetterKeyboardSurface` |
| NumberKeyboardSurface | `LiquidNumberPadView` in `KeyboardRootView` | `DictusKeyboard/NumberKeyboardSurface.swift` | `KeyboardRootView.areaSurface` |
| SymbolKeyboardSurface | `LiquidSymbolPageView` in `KeyboardRootView` | `DictusKeyboard/SymbolKeyboardSurface.swift` | `KeyboardRootView.areaSurface` |
| KeyboardChrome | `embeddedSurface`, glass/solid material, and voice-board chrome faces | `DictusKeyboard/KeyboardChrome.swift` (`KeyboardRootView` extension) | `KeyboardRootView` body |
| VoiceBoardSurface | Dictation-board mic, space bar, and listening wave | `DictusKeyboard/VoiceBoardSurface.swift` (`KeyboardRootView` extension) | `KeyboardRootView.areaSurface` |
| EmojiKeyboardSurface | `EmojiPickerView` | Same view, named `EmojiKeyboardSurface` via typealias | `KeyboardRootView` emoji case |
| EmojiSurfaceModel | Page splitting inside `EmojiPickerView.makePages` | `DictusCore/Sources/DictusCore/EmojiSurfaceModel.swift` | `EmojiPickerView.makePages` |
| EmojiGestureCoordinator | `EmojiHoldGestureRecognizer` in `EmojiPickerView` | `DictusKeyboard/Views/EmojiGestureCoordinator.swift` | `EmojiPagerCollectionView` |
| EmojiCategoryControl | `EmojiCategoryScrubControl` in `EmojiCategoryBar.swift` | `DictusKeyboard/Views/EmojiCategoryControl.swift` | `KeyboardViewController` through `typealias EmojiCategoryScrubControl` |
| KeyVariantPopup | Already `DictusKeyboard/Views/KeyVariantPopup.swift` | Unchanged | Existing letter, symbol, and emoji popups |

The emoji collection view, cells, and buttons stayed in `EmojiPickerView.swift`. They are private to that file and own the grid geometry.

## App services

| Component | Original owner | New owner | Callers migrated |
| --- | --- | --- | --- |
| ModelPreparationCoordinator | Prewarm lock and quarantine in `ModelManager` | `DictusApp/Models/ModelPreparationCoordinator.swift` | Whisper and Parakeet download paths in `ModelManager` |
| LiveActivityStateMapper | Standby `ContentState` built with `KeyboardDictationService.isEnabled` | `DictusCore/Sources/DictusCore/LiveActivityStateMapper.swift` | Visible standby updates in `LiveActivityManager` |

Terminal `activity.end` payloads that only pass `.standby` still use the default content initializer. Those are dismissal snapshots, not the standby control.

## Tests and build

- Focused behavior tests: `DictusCore/Tests/DictusCoreTests/RestructuringOwnershipTests.swift`.
- Existing source contracts were pointed at the new files. The assertions themselves were kept.
- Final `DictusCore` suite: 1755 tests, 1 skipped, 0 failures.
- `git diff --check`: clean.
- `xcodebuild` scheme `sAiity-iOS`, generic iOS Simulator, `CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**. Log: `/tmp/saiity-restructure-build.log`.

## Device-only verification

All of the following are **pending**. The phone was not available, and a simulator build does not exercise them.

| Flow | Status |
| --- | --- |
| Emoji swipe, hold, tone popup, and category scrub | Pending |
| Letter, number, and symbol key spacing, popups, and gaps | Pending |
| Hold-to-speak, tap-to-open, and mic recovery | Pending |
| Liquid Glass and solid material hit testing | Pending |
| Haptics versus key click sound | Pending |
| Live Activity standby, recording, and cleanup | Pending |
| Multilingual dictation without silent translation | Pending |

Phrases still to record on device:

- `Schick mir bitte the updated invoice tomorrow.`
- `Can you send das Dokument an Peter?`
- `你好，can you send me die Rechnung bitte?`
