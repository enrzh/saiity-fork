"""Generate an owned, analytic Core ML test graph; no trained weights or network.

Development tool only. Run with coremltools 8.3.0 and numpy in an isolated venv:
python scripts/generate-native-model-fixture.py SyllivraKernel/Tests/SyllivraInferenceTests/Fixtures/linear
"""
import hashlib
import json
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder

destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
builder = NeuralNetworkBuilder([("input", datatypes.Array(2))], [("logits", datatypes.Array(3))],
                               disable_rank5_shape_mapping=True)
builder.add_inner_product("linear", W=np.array([[2, 0], [0, 3], [-1, -1]], dtype=np.float32),
                          b=np.array([0.5, -1, 2], dtype=np.float32), input_channels=2,
                          output_channels=3, has_bias=True, input_name="input", output_name="logits")
for feature in list(builder.spec.description.input) + list(builder.spec.description.output):
    feature.type.multiArrayType.dataType = ct.proto.FeatureTypes_pb2.ArrayFeatureType.FLOAT32
model_path = destination / "linear.mlmodel"
ct.models.utils.save_spec(builder.spec, str(model_path))
manifest = {
    "schemaVersion": 1, "modelIdentifier": "native-linear-probe", "upstreamRevision": "owned-linear-v1",
    "architecture": "coreml-probe", "minimumIOSMajor": 17,
    "license": {"identifier": "Apache-2.0", "source": "scripts/generate-native-model-fixture.py; repository LICENSE"},
    "files": {model_path.name: hashlib.sha256(model_path.read_bytes()).hexdigest()},
    "graphs": [{"name": "decoder", "path": model_path.name,
                "inputs": [{"name": "input", "dataType": "float32", "shape": [2]}],
                "outputs": [{"name": "logits", "dataType": "float32", "shape": [3]}], "states": []}]
}
(destination / "native-runtime.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Generated analytic linear graph: {model_path}")
