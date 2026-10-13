# Qwen 2.5 tokenizer reference

Test data only. This directory is copied into `SyllivraInferenceTests` resources;
it is not a resource of the app, keyboard, widget or inference library.

- Upstream: `Qwen/Qwen2.5-0.5B-Instruct`.
- Revision: `7ae557604adf67be50417f59c2c2f167def9a775`.
- Source: <https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/tree/7ae557604adf67be50417f59c2c2f167def9a775>.
- `tokenizer.json` is the unmodified public artifact downloaded through Chrome
  on October 12, 2026. SHA-256:
  `c0382117ea329cdf097041132f6d735924b697924d6f6fc3945713e96ce87539`.
- License: Apache-2.0, Copyright 2024 Alibaba Cloud. The accompanying `LICENSE`
  preserves the license text and attribution read from the pinned source view;
  whitespace was normalized when transcribing it.
- `golden.json` contains 78 synthetic public text cases, exact token IDs and
  decoded text generated with Hugging Face `tokenizers==0.21.4`, with
  `add_special_tokens=False` and `skip_special_tokens=False`.

Regenerate only in an isolated development environment with that reference
version installed:

```sh
python scripts/generate-native-tokenizer-fixtures.py \
  SyllivraKernel/Tests/SyllivraInferenceTests/Fixtures/qwen2.5
```

The script checks the exact tokenizer hash and performs no downloads, model
inference or transcript access. Its Python dependency is not a production
runtime dependency. No trained model weights or speech recordings are included.

These cases cover NFC normalization, composed/decomposed accents, CJK, Arabic,
Indic scripts, emoji, all ASCII bytes, Unicode whitespace, prompt roles, every
added token, URLs, code, line-break markers, overlapping merges and long words.
They establish parity for these cases and this artifact, not for every possible
Unicode input, other tokenizer families or any model's semantic accuracy.
