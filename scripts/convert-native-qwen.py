"""Development-only Qwen 2.5 graph export. Never downloads model files."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import tempfile

import numpy as np
import torch
from transformers import Qwen2Config, Qwen2ForCausalLM

REVISION = "7ae557604adf67be50417f59c2c2f167def9a775"
WEIGHTS_SHA256 = "fdf756fa7fcbe7404d5c60e26bff1a0c8b8aa1f72ced49e7dd0210fe288fb7fe"
TOKENIZER_SHA256 = "c0382117ea329cdf097041132f6d735924b697924d6f6fc3945713e96ce87539"
CONFIG_SHA256 = "18e18afcaccafade98daf13a54092927904649e1dd4eba8299ab717d5d94ff45"


class QwenStep(torch.nn.Module):
    def __init__(self, reference, context):
        super().__init__()
        self.reference = reference
        self.context = context
        config = reference.config
        self.head_dim = config.hidden_size // config.num_attention_heads
        self.groups = config.num_attention_heads // config.num_key_value_heads
        if (context <= 0 or context > config.max_position_embeddings or config.use_sliding_window
                or config.rope_scaling is not None or self.head_dim % 2
                or config.hidden_size % config.num_attention_heads
                or config.num_attention_heads % config.num_key_value_heads):
            raise ValueError("Unsupported Qwen attention/context configuration")
        self.register_buffer("inv_freq", 1.0 / (config.rope_theta ** (
            torch.arange(0, self.head_dim, 2, dtype=torch.float32) / self.head_dim)))
        self.register_buffer("cache_positions", torch.arange(context))
        self.cache_names = []
        for index in range(config.num_hidden_layers):
            for kind in ["key", "value"]:
                name = f"{kind}_cache_{index}"
                self.register_buffer(name, torch.zeros((1, config.num_key_value_heads, context, self.head_dim),
                                                        dtype=torch.float16))
                self.cache_names.append(name)

    def reset_cache(self):
        for name in self.cache_names:
            self.get_buffer(name).zero_()

    def rotate(self, tensor):
        half = self.head_dim // 2
        return torch.cat((-tensor[..., half:], tensor[..., :half]), dim=-1)

    def forward(self, input_ids, position, causal_mask):
        config = self.reference.config
        hidden = self.reference.model.embed_tokens(input_ids.to(torch.int64))
        angles = position.to(torch.float32).reshape(1, 1, 1) * self.inv_freq.reshape(1, 1, -1)
        angles = torch.cat((angles, angles), dim=-1).unsqueeze(1)
        cosine, sine = angles.cos(), angles.sin()
        write_mask = (self.cache_positions == position[0]).to(torch.float16).reshape(1, 1, -1, 1)
        for index, layer in enumerate(self.reference.model.layers):
            normalized = layer.input_layernorm(hidden)
            query = layer.self_attn.q_proj(normalized).reshape(1, 1, config.num_attention_heads,
                                                              self.head_dim).transpose(1, 2)
            key = layer.self_attn.k_proj(normalized).reshape(1, 1, config.num_key_value_heads,
                                                            self.head_dim).transpose(1, 2)
            value = layer.self_attn.v_proj(normalized).reshape(1, 1, config.num_key_value_heads,
                                                              self.head_dim).transpose(1, 2)
            query = query * cosine + self.rotate(query) * sine
            key = key * cosine + self.rotate(key) * sine
            key_cache = self.get_buffer(f"key_cache_{index}")
            value_cache = self.get_buffer(f"value_cache_{index}")
            key_cache[:] = key_cache * (1 - write_mask) + key.to(torch.float16) * write_mask
            value_cache[:] = value_cache * (1 - write_mask) + value.to(torch.float16) * write_mask
            keys = key_cache.float().repeat_interleave(self.groups, dim=1)
            values = value_cache.float().repeat_interleave(self.groups, dim=1)
            scores = torch.matmul(query, keys.transpose(-1, -2)) / math.sqrt(self.head_dim)
            attention = torch.softmax(scores + causal_mask, dim=-1)
            attended = torch.matmul(attention, values).transpose(1, 2).reshape(1, 1, config.hidden_size)
            hidden = hidden + layer.self_attn.o_proj(attended)
            hidden = hidden + layer.mlp(layer.post_attention_layernorm(hidden))
        return self.reference.lm_head(self.reference.model.norm(hidden))[:, -1, :]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_checkpoint(source):
    for name, expected in [("config.json", CONFIG_SHA256), ("tokenizer.json", TOKENIZER_SHA256),
                           ("model.safetensors", WEIGHTS_SHA256)]:
        path = source / name
        if path.is_symlink() or not path.is_file():
            raise FileNotFoundError(f"Required local checkpoint file is missing or unsafe: {name}")
        if sha256(path) != expected:
            raise ValueError(f"Checkpoint does not match the pinned Qwen revision: {name}")
    license_path = source / "LICENSE"
    if license_path.is_symlink() or not license_path.is_file() or license_path.stat().st_size == 0:
        raise FileNotFoundError("Keep the upstream LICENSE with the local checkpoint")
    return json.loads((source / "config.json").read_text())


def export(step, destination, model_identifier, revision, architecture, license_record, source=None):
    import coremltools as ct

    if destination.exists():
        raise FileExistsError("Use a new export directory; existing artifacts are never overwritten")
    step.reset_cache()
    example = (torch.tensor([[3]], dtype=torch.int32), torch.tensor([0], dtype=torch.int32),
               torch.zeros((1, 1, 1, step.context)))
    with torch.no_grad():
        traced = torch.jit.trace(step, example, check_trace=False)
    step.reset_cache()
    states = [ct.StateType(wrapped_type=ct.TensorType(shape=tuple(step.get_buffer(name).shape),
                                                      dtype=np.float16), name=name) for name in step.cache_names]
    model = ct.convert(traced, convert_to="mlprogram", minimum_deployment_target=ct.target.iOS18,
                       compute_precision=ct.precision.FLOAT32, compute_units=ct.ComputeUnit.CPU_ONLY,
                       inputs=[ct.TensorType(name="input_ids", shape=(1, 1), dtype=np.int32),
                               ct.TensorType(name="position", shape=(1,), dtype=np.int32),
                               ct.TensorType(name="causal_mask", shape=(1, 1, 1, step.context), dtype=np.float32)],
                       outputs=[ct.TensorType(name="logits", dtype=np.float32)], states=states)
    destination.mkdir(parents=True)
    model.save(str(destination / "decoder.mlpackage"))
    if source is not None:
        import shutil
        for name in ["tokenizer.json", "config.json", "LICENSE"]:
            shutil.copyfile(source / name, destination / name)
    provenance = {"recipe": "qwen-step-v1", "coremltools": ct.__version__, "torch": torch.__version__,
                  "transformers": __import__("transformers").__version__, "context": step.context,
                  "weightsAndActivations": "float32", "kvCache": "float16",
                  "sourceWeightSHA256": WEIGHTS_SHA256 if source is not None else None,
                  "pretrained": source is not None}
    (destination / "conversion.json").write_text(json.dumps(provenance, indent=2) + "\n")
    tensor = lambda name, dtype, shape: {"name": name, "dataType": dtype, "shape": list(shape)}
    manifest = {
        "schemaVersion": 1, "modelIdentifier": model_identifier, "upstreamRevision": revision,
        "architecture": architecture, "minimumIOSMajor": 18, "license": license_record,
        "contextWindowTokens": step.context, "vocabularySize": step.reference.config.vocab_size,
        "graphs": [{"name": "decoder", "path": "decoder.mlpackage",
                    "inputs": [tensor("input_ids", "int32", (1, 1)), tensor("position", "int32", (1,)),
                               tensor("causal_mask", "float32", (1, 1, 1, step.context))],
                    "outputs": [tensor("logits", "float32", (1, step.reference.config.vocab_size))],
                    "states": [dict(tensor(name, "float16", step.get_buffer(name).shape), contextAxis=2)
                               for name in step.cache_names]}],
    }
    if source is not None:
        manifest["tokenizer"] = {"path": "tokenizer.json", "kind": "bpe",
                                 "endTokenIDs": [step.reference.config.eos_token_id]}
    return model, manifest


def verify_cache(step, model, tokens, destination):
    step.reset_cache()
    state = model.make_state()
    golden, actuals = [], []
    with torch.no_grad():
        for index, token in enumerate(tokens):
            mask = np.full((1, 1, 1, step.context), -10000.0, dtype=np.float32)
            mask[..., :index + 1] = 0
            inputs = {"input_ids": np.array([[token]], dtype=np.int32),
                      "position": np.array([index], dtype=np.int32), "causal_mask": mask}
            cached = step(torch.from_numpy(inputs["input_ids"]), torch.from_numpy(inputs["position"]),
                          torch.from_numpy(mask)).numpy()
            full = step.reference(torch.tensor([tokens[:index + 1]]), use_cache=False).logits[:, -1, :].numpy()
            # FP16 cache error is checked separately from Core ML conversion error.
            np.testing.assert_allclose(cached, full, atol=0.02, rtol=0.01)
            actual = model.predict(inputs, state=state)["logits"]
            np.testing.assert_allclose(actual, cached, atol=0.001, rtol=0.01)
            assert np.argmax(actual) == np.argmax(full), "Greedy token differs from the full-prefix reference"
            golden.append(cached.tolist())
            actuals.append(actual.tolist())
    fresh_mask = np.full((1, 1, 1, step.context), -10000.0, dtype=np.float32)
    fresh_mask[..., 0] = 0
    fresh = model.predict({"input_ids": np.array([[tokens[0]]], dtype=np.int32),
                           "position": np.array([0], dtype=np.int32), "causal_mask": fresh_mask},
                          state=model.make_state())["logits"]
    np.testing.assert_allclose(fresh, golden[0], atol=0.001, rtol=0.01)
    (destination / "cache-golden.json").write_text(json.dumps({"tokens": tokens, "logits": golden,
                                                             "nativeLogits": actuals,
                                                             "absoluteTolerance": 0.001}, indent=2) + "\n")


def write_manifest(destination, manifest):
    # An export cannot be admitted by the native loader until numerical checks finish.
    manifest["files"] = {str(path.relative_to(destination)): sha256(path)
                         for path in destination.rglob("*") if path.is_file()}
    (destination / "native-runtime.json").write_text(json.dumps(manifest, indent=2) + "\n")


def convert_checkpoint(source, destination):
    if destination.exists():
        raise FileExistsError("Use a new export directory; existing artifacts are never overwritten")
    validate_checkpoint(source)
    # Reference/conversion tools stay outside all production targets. No network or remote code is allowed.
    reference = Qwen2ForCausalLM.from_pretrained(str(source), local_files_only=True, trust_remote_code=False,
                                               torch_dtype=torch.float32, attn_implementation="eager").eval()
    step = QwenStep(reference, 2048).eval()
    model, manifest = export(step, destination, "qwen2_5_0_5b", REVISION, "qwen2_5",
                   {"identifier": "Apache-2.0", "source": f"https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct/blob/{REVISION}/LICENSE"},
                   source=source)
    from tokenizers import Tokenizer
    tokens = Tokenizer.from_file(str(source / "tokenizer.json")).encode("Hello, world!", add_special_tokens=False).ids
    verify_cache(step, model, tokens, destination)
    write_manifest(destination, manifest)
    print(f"Exported pinned Qwen Core ML step graph to {destination}")
    print("Context 2048; FP32 weights/activations and FP16 KV state; iOS 18+; not enabled in the app")
    return model


def self_test(destination):
    with tempfile.TemporaryDirectory() as temporary:
        source = Path(temporary)
        try:
            validate_checkpoint(source)
        except (FileNotFoundError, ValueError):
            pass
        else:
            raise AssertionError("An incomplete checkpoint must fail before model loading")
        (source / "config.json").write_text("{}")
        try:
            validate_checkpoint(source)
        except ValueError:
            pass
        else:
            raise AssertionError("A modified checkpoint must fail before model loading")
    torch.manual_seed(20261012)
    config = Qwen2Config(vocab_size=32, hidden_size=32, intermediate_size=64,
                         num_hidden_layers=2, num_attention_heads=4, num_key_value_heads=2,
                         max_position_embeddings=16, rope_theta=1000000.0,
                         rms_norm_eps=1e-6, tie_word_embeddings=True, use_sliding_window=False, sliding_window=None)
    config._attn_implementation = "eager"
    reference = Qwen2ForCausalLM(config).eval()
    step = QwenStep(reference, 16).eval()
    prefix = [3, 7, 11, 5]
    golden = []
    with torch.no_grad():
        for index, token in enumerate(prefix):
            mask = torch.full((1, 1, 1, 16), -10000.0)
            mask[..., :index + 1] = 0
            actual = step(torch.tensor([[token]], dtype=torch.int32), torch.tensor([index], dtype=torch.int32), mask)
            expected = reference(torch.tensor([prefix[:index + 1]]), use_cache=False).logits[:, -1, :]
            torch.testing.assert_close(actual, expected, atol=0.005, rtol=0.01)
            golden.append(actual.numpy().tolist())
        step.reset_cache()
        mask = torch.full((1, 1, 1, 16), -10000.0)
        mask[..., 0] = 0
        reset = step(torch.tensor([[prefix[0]]], dtype=torch.int32), torch.tensor([0], dtype=torch.int32), mask)
        torch.testing.assert_close(reset, torch.tensor(golden[0]), atol=0.0001, rtol=0.001)
    model, manifest = export(step, destination, "native-qwen-cache-probe", "owned-qwen-cache-v1", "coreml-probe",
                   {"identifier": "MIT", "source": "scripts/convert-native-qwen.py; repository LICENSE; synthetic weights"})
    verify_cache(step, model, prefix, destination)
    write_manifest(destination, manifest)
    print("Synthetic Qwen cache, full-prefix reference, native Core ML and state-reset checks passed")
    print("This is an untrained two-layer fixture, not pretrained Qwen model parity")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--output", type=Path)
    arguments = parser.parse_args()
    if arguments.self_test is not None:
        if arguments.source is not None or arguments.output is not None:
            parser.error("Use --self-test alone, or --source and --output together")
        self_test(arguments.self_test)
    elif arguments.source is not None and arguments.output is not None:
        convert_checkpoint(arguments.source, arguments.output)
    else:
        parser.error("Provide --self-test <new-directory> or --source <local-checkpoint> --output <new-directory>")
