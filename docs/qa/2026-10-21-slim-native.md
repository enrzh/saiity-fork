# Slimmer, more native app and keyboard (21–22 Oct 2026)

Branch `claude/slim-native`, nine commits on top of 6fc3b8ab (59e130bc to 4d39fcd2). Build number unchanged (243). On 22 Oct 2026, at the owner's request, 2770e1d7 and later bcd3f912 were installed on their iPhone Air as a Release development build (signed with the team's development certificate). No TestFlight, push or release.

## Size

Unsigned Release device builds, measured with `du -sk`:

| Part | 6fc3b8ab | After 5b0b85bd | Now (4d39fcd2) |
| --- | ---: | ---: | ---: |
| Whole app | 67,968 KiB | 58,000 KiB | 36,716 KiB |
| Keyboard extension | 31,272 KiB | 25,220 KiB | 24,952 KiB |
| Widget extension | 2,784 KiB | 1,664 KiB | 1,472 KiB |

Where it came from:

- Next-word dictionaries use the NGRM v2 layout (`tools/ngram_pack.py`): 25.7 MB to 20.6 MB. Each prediction is one 32-bit word/score index; keys and entry starts are tables read straight from the mapped file, so loading builds no index and a loaded language no longer holds 1,280 KiB of heap.
- The MLX engine (Qwen3-ASR and local cleanup), Parakeet (FluidAudio) and custom/Ollama models are gone; the app binary fell from about 22 MB to 5,240 KiB. Dictation is Whisper; cleanup is Apple Intelligence or none. Downloaded files of the removed engines are deleted on launch.
- The hidden paywall and subscription code, sound feedback and its sounds, the brand PNG every target copied, the setup video and about 1,900 lines of unreachable keyboard code are gone.

## What changed for the user

- The app is one native list: readiness, Keyboard Dictation, recent dictations, then Dictation, Keyboard, Models, Help and About. Models has one Voice Model picker (Automatic or a specific model).
- Keyboard settings are Layout, Default Keyboard, Autocorrection, Show Top Bar, Key Popups, Haptics and Vocabulary. Material, Background, Key Containers, Hold Speed, Adaptive Touch and the per-key Tap and Hold editor are gone; everyone gets key plates, every accent and skin tone, the default hold timing and adaptive key targets. Key Popups (Off, Popup, Popout, Key flash) came back on 22 Oct at the owner's request.
- There is no glass inset behind the keys any more (22 Oct, owner's request): keys sit directly on the system keyboard backdrop on every page.
- Key popups and the accent row are opaque like the keys. As glass they rendered light grey, so a dark-mode popup showed a white letter on near-white.
- The keyboard expands the text replacements from iPhone Settings › General › Keyboard › Text Replacement. Syllivra no longer has its own editor; snippets saved earlier still expand, win over iOS's for the same shortcut, and can be deleted under Keyboard › Syllivra Replacements, which appears only while any exist.
- Autocorrect fixes swapped letters ("hte", "goign", "wrok", "taht", and in German "nciht", "acuh", "eigentlcih") and common English web typos ("teh", "adn", "becuase", "recieve", "definately", "seperate"). See "Autocorrect" below.
- Replay, the "usable without editing?" buttons and the separate Cleanup Diagnostics screen are gone; cleanup events are under Help › Diagnostics.

## More (•••) on the dictation board

Owner report on 22 Oct: More works but is not very responsive. On the simulator, before the fix, taps a few points off the dots never reached the keyboard: the input view logged no touch at all. A remote keyboard only receives touches over painted pixels (also found on the phone earlier, see `docs/keyboard-ui-unification-plan.md`). The old glass inset started below the board's 32 pt top lane, so More and power sat on clear pixels and only taps on their glyphs arrived. `KeyboardInputView` now paints a 2% `secondarySystemBackground` canvas over the whole keyboard. Afterwards, six taps around the More square opened the menu every time in two fresh runs, where the same sequence had failed three of four times before. The canvas is not visible in light or dark mode. Whether this was the whole problem on the phone needs the owner's check.

Tapping the app above the keyboard does not close a keyboard menu: those touches go to the app. A tap anywhere on the keyboard closes it.

## Autocorrect

Two faults, both older than this branch:

1. The trie search tried a swap only when both letters sat in the same compressed node. They usually sit on either side of a branch, so swaps were scored as two key substitutions ("goign" → "gough"). The search now carries the second half of a swap into the next node.
2. `en_spellcheck.dict` is built from Norvig's web counts, which contain web typos; a listed word counts as correct. `tools/typo_finder.swift` lists words macOS's US and British dictionaries reject (capitalized too, so names stay) and would autocorrect to a word of the list at least five times as frequent and at most two edits away. `tools/dict_builder.py --exclude tools/typos/en.tsv` leaves those 2,496 entries out (37,504 remain). British spellings ("tyres", "practise", "colour") and chat words ("gonna", "lol", "okay") stay. German, French and Spanish are unchanged: their candidate lists held colloquial words ("ähm", "kämst", "roller").

Checks: the multilingual harness (`scripts/test-multilingual-autocorrect.swift`) gained these cases and passes; `scripts/test-aosp-trie-concurrency.mm` passes under ASan/UBSan and TSan; the builder still reproduces the German, French and Spanish dictionaries byte for byte. In Messages on the simulator, "i am goign home becuase teh weather is nice adn warm" now types as "i am going home because the weather is nice and warm" (before: unchanged).

## Dictionary equivalence (NGRM v2)

- `tools/ngram_pack.py` decodes every v2 entry and compares it with the v1 entry before writing.
- Old and new readers were given the same 38 million queries across de/en/es/fr with zero differences. 3,000 truncated or corrupted files loaded under ASan without a crash.

## Tests

- 1,811 kernel tests pass.
- `scripts/test-key-grid-typing.swift` passes end to end. Two of its checks had gone stale before this branch (the emoji grid stops before Delete; Delete uses the narrowed command face) and failed the same way on the pre-branch build; they now check the current layout.
- `scripts/test-autocorrect-overrides.swift` and `scripts/render-native-keyboard.swift --compile-only` pass.

## Seen on screen (simulator "sAiity Product QA", iOS 26.5, light and dark)

- More with the top bar off and on, Output language, emoji (categories, insert, Delete, skin-tone hold-slide), letters, press popup and accent row in light and dark.
- The app: home, Dictation, Keyboard, Models, Help, About, Diagnostics, history, setup steps, dark mode and the largest text size.
- iOS's "vlg" replacement expanded to "Viele liebe Grüße!"; a saved Syllivra snippet for the same shortcut won; deleting it hid the row.

## Observations, not changed

- Faster tapping (about 0.35 s apart) occasionally dropped the first letter after a space in the simulator. It did not happen at one tap per second.
- A lowercase "i" is not capitalized to "I".

## Still needs a phone

Haptics and typing feel, real dictation from the keyboard and in the app, Live Activity, autocorrect and text replacements in other apps, and memory with a large model loaded. See `build-244-phone-check.md`.
