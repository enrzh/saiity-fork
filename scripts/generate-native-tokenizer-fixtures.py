"""Freeze exact Qwen token IDs with an independent development-only reference.

Requires tokenizers==0.21.4 in an isolated environment. Reads the explicitly
supplied tokenizer; performs no downloads, inference or transcript access.
"""
import hashlib
import json
import sys
import unicodedata
from pathlib import Path

import tokenizers
from tokenizers import Tokenizer

REVISION = "7ae557604adf67be50417f59c2c2f167def9a775"
TOKENIZER_SHA256 = "c0382117ea329cdf097041132f6d735924b697924d6f6fc3945713e96ce87539"

directory = Path(sys.argv[1])
source = directory / "tokenizer.json"
assert tokenizers.__version__ == "0.21.4", "Use the pinned reference version"
assert hashlib.sha256(source.read_bytes()).hexdigest() == TOKENIZER_SHA256, "Unexpected tokenizer"
reference = Tokenizer.from_file(str(source))

cases = {
    "empty": "",
    "english": "Hello, world!",
    "accents": "Café, Straße, naïve.",
    "decomposed": "Cafe\u0301, Straße, naïve.",
    "cjk": "你好，世界。日本語と한국어",
    "emoji": "🙂👩‍💻 café\r\n\t  end",
    "digits-contractions": "I'M sure he'll say: 12345.67",
    "url": "https://example.com/a?q=1&x=2",
    "code": "let value = foo(42)\n    print(value)",
    "prompt": "<|im_start|>system\nEdit.<|im_end|>\n<|im_start|>user\nhello<<NL>>world<|im_end|>\n<|im_start|>assistant\n",
    "added-nonspecial": '<tool_call>{"x":1}</tool_call>',
    "whitespace": " a  b\n\n\t \r\n   ",
    "unicode-whitespace": "a\u00a0b\u0085c\u2028d\u2029e\u2003f\u202fg",
    "marks": "a\u0301a\u0327 العربية हिन्दी ไทย",
    "null-controls": "\0\1\x1f\x7f",
    "hangul-normalization": "한글",
    "special-boundaries": "x<|im_start|><|im_end|>y<|endoftext|>z",
    "partial-special": "<|im_start| <|IM_START|> <<NL>>",
    "long-word": "a" * 1024,
    "long-word-8192": "a" * 8192,
    "overlapping-merges": "aaaaa aaaaaaa ababab",
    "merge-ranks": "bbb abcabababaaaa  \n     00000",
    "long-cjk": "中文测试" * 64,
    "all-ascii": "".join(chr(code) for code in range(128)),
}
for index, token in enumerate(reference.get_added_tokens_decoder().values()):
    cases[f"added-token-{index}"] = token.content

# Deterministic mixed Unicode cases exercise pretokenization boundaries.
alphabet = ["a", "Z", "9", "é", "中", "🙂", "\u0301", "\n", "\r", "\t", " ", "'", "-", "\u00a0"]
state = 17
for index in range(32):
    text = ""
    for _ in range(48):
        state = (state * 1664525 + 1013904223) & 0xffffffff
        text += alphabet[state % len(alphabet)]
    cases[f"mixed-{index}"] = text

fixture = {
    "repository": "Qwen/Qwen2.5-0.5B-Instruct",
    "revision": REVISION,
    "license": "Apache-2.0; Copyright 2024 Alibaba Cloud",
    "tokenizerSHA256": TOKENIZER_SHA256,
    "reference": f"Hugging Face tokenizers {tokenizers.__version__}; add_special_tokens=False",
    "cases": [],
}
for name, text in cases.items():
    ids = reference.encode(text, add_special_tokens=False).ids
    decoded = reference.decode(ids, skip_special_tokens=False)
    assert decoded == unicodedata.normalize("NFC", text), name
    fixture["cases"].append({"name": name, "text": text, "ids": ids, "decoded": decoded})

destination = directory / "golden.json"
destination.write_text(json.dumps(fixture, indent=2, ensure_ascii=False) + "\n")
print(f"Frozen {len(cases)} exact-ID cases: {destination}")
