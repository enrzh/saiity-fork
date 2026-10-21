# Slimmer, more native app and keyboard (21 Oct 2026)

Branch `claude/slim-native`, commits 59e130bc, ee38b5fd and 5b0b85bd on top of 6fc3b8ab. Build number unchanged (243). No phone install, TestFlight, push or release.

## Size

Unsigned Release device builds of the same tree before and after, measured with `du -sk`:

| Part | Before | After |
| --- | ---: | ---: |
| Whole app | 67,968 KiB | 58,000 KiB |
| Keyboard extension | 31,272 KiB | 25,220 KiB |
| Widget extension | 2,784 KiB | 1,664 KiB |
| Sounds | 1,216 KiB | 100 KiB |

Where it came from:

- Next-word dictionaries use the NGRM v2 layout (`tools/ngram_pack.py`): 25.7 MB to 20.6 MB. Each prediction is one 32-bit word/score index; keys and entry starts are tables read straight from the mapped file, so loading builds no index and a loaded language no longer holds 1,280 KiB of heap.
- The brand PNG only the hidden paywall used was copied into the app, keyboard and widget bundles (about 1.1 MB each). It, the paywall and the kernel's resource bundle are gone; the logo is the existing vector everywhere.
- Sound feedback is off by default and nothing in the app could turn it on or pick a sound. The three default sounds remain; a different saved name falls back to its default.
- The keyboard setup video (old "sAiity" branding, picture in picture) is replaced by written steps.

## Dictionary equivalence

- `tools/ngram_pack.py` decodes every v2 entry and compares it with the v1 entry before writing.
- The old reader (from 6fc3b8ab) and the new reader were compiled side by side and given the same queries: every word in each language's string table and frequency list as a bigram key (results capped at 3 and 16), bigram scores, every predicted follower as a trigram pair, trigram scores and capitalized variants. 38 million queries across de/en/es/fr, zero differences.
- `scripts/test-aosp-trie-concurrency.mm` passes under ASan/UBSan and under TSan. 3,000 truncated or corrupted files loaded under ASan without a crash.
- On the simulator, an identical 52-character typing run produced the same text and the same 27 autocorrect log decisions with the old build (v1 file, 6,154,536 bytes loaded) and the new build (v2, 4,802,112 bytes).

## Seen on screen (simulator "sAiity Product QA", iOS 26.5, light and dark)

Taps reach the keyboard extension on this simulator, so these were exercised, not inferred:

- More with the top bar off and on opens the native menu; Output language opens its submenu.
- Emoji: categories switch, a tap inserts the emoji, Delete removes one whole emoji, the grid stops before Delete, and hold-then-slide inserts exactly one skin-tone variant.
- Letters type correctly at about one tap per second.
- The app: home, Dictation, Keyboard, Models, Help, About, history, setup steps, dark mode and the largest accessibility text size.

## Observations, not changed

- Space did not correct "teh", "adn" or "goign" in either build. The English trie contains "becuase" (frequency 36,213), so it is treated as a word.
- Faster tapping (about 0.35 s apart) occasionally dropped the first letter after a space. It did not happen at one tap per second; whether a phone shows it is unknown.

## Still needs a phone

Haptics and typing feel, real dictation from the keyboard and in the app, Live Activity, autocorrect in other apps, and memory with a large model loaded. See `build-244-phone-check.md`.
