# Owned Qwen cache conversion probe

This is an untrained, seeded two-layer Qwen-shaped test graph. It is not the
pretrained Qwen 2.5 0.5B checkpoint and cannot establish language quality or
phone performance. It is a test resource only; no graph or Python tool is
bundled into the app, keyboard, widget or inference library.

Generated with `scripts/convert-native-qwen.py --self-test <new-directory>` using
seed `20261012`, vocabulary 32, hidden size 32, four attention heads, two KV
heads and context 16. `conversion.json` records the development tool versions.
Weights/activations use FP32 and the four KV states use FP16. It requires the
iOS 18/macOS 15 state API; the app's iOS 17 deployment target is unchanged.

`cache-golden.json` records cached PyTorch logits and independently executed
Core ML logits for numeric tokens `[3, 7, 11, 5]`. The generator also compares
cached output against the full-prefix reference and checks greedy-token
agreement and fresh Core ML state. The Swift test loads the same graph through
`NativeModelArtifacts`, checks every logit with absolute tolerance `0.001`, and
starts again with fresh state. This verifies these inputs and this export.

The exporter writes `native-runtime.json` only after its numerical checks pass;
the manifest hashes every generated data/model file. `README.md` is explanatory
documentation added afterward and is not part of the graph bundle.

The seeded weights and exporter are first-party test material under the
repository's MIT license. Torch, Transformers and coremltools are isolated
development/reference tools and are not production dependencies.
