#!/usr/bin/env python3
"""Convert the official fixed-shape ScaleLSD neural forward to Core ML.

The official Python post-processing remains outside the graph. The converted
model accepts a normalized grayscale tensor shaped [1, 1, 512, 512] and emits
the raw dense logits shaped [1, 9, 256, 256].
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn


DEFAULT_WORKSPACE = Path("/Volumes/4T/temp/AnyUprightResearchWorkspace")
DEFAULT_SCALELSD_ROOT = DEFAULT_WORKSPACE / "model_tests" / "scalelsd"
DEFAULT_OFFICIAL_REPO = DEFAULT_SCALELSD_ROOT / "official"
DEFAULT_CHECKPOINT = DEFAULT_SCALELSD_ROOT / "models" / "scalelsd-vitbase-v2-train-sa1b.pt"
DEFAULT_OUTPUT = DEFAULT_SCALELSD_ROOT / "coreml_conversion"
INPUT_SHAPE = (1, 1, 512, 512)
OUTPUT_SHAPE = (1, 9, 256, 256)


class NeuralForwardWrapper(nn.Module):
    def __init__(self, model: nn.Module):
        super().__init__()
        self.backbone = model.backbone

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        output, _ = self.backbone(image)
        if isinstance(output, list):
            return output[0]
        return output


def install_fixed_shape_forward_vit() -> None:
    """Replace trace-hostile dynamic Unflatten with a fixed 32x32 reshape."""
    import scalelsd.ssl.backbones.dpt.models as models
    import scalelsd.ssl.backbones.dpt.vit as vit

    def fixed_forward_vit(pretrained: nn.Module, image: torch.Tensor):
        pretrained.model.forward_flex(image)
        layers = [pretrained.activations[str(index)] for index in range(1, 5)]
        postprocess = [
            pretrained.act_postprocess1,
            pretrained.act_postprocess2,
            pretrained.act_postprocess3,
            pretrained.act_postprocess4,
        ]
        result = []
        for layer, post in zip(layers, postprocess):
            layer = post[0:2](layer)
            if layer.ndim == 3:
                layer = layer.reshape(layer.shape[0], layer.shape[1], 32, 32)
            result.append(post[3:](layer))
        return tuple(result)

    vit.forward_vit = fixed_forward_vit
    models.forward_vit = fixed_forward_vit


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def compile_package(package: Path, output: Path) -> Path:
    compile_root = output / "compiled"
    if compile_root.exists():
        shutil.rmtree(compile_root)
    compile_root.mkdir(parents=True)
    run(["xcrun", "coremlcompiler", "compile", str(package), str(compile_root)])
    compiled = compile_root / f"{package.stem}.mlmodelc"
    if not compiled.is_dir():
        raise RuntimeError(f"coremlcompiler did not create {compiled}")
    return compiled


def tensor_stats(reference: np.ndarray, candidate: np.ndarray) -> dict[str, float]:
    difference = np.abs(reference.astype(np.float64) - candidate.astype(np.float64))
    return {
        "max_abs": float(difference.max()),
        "mean_abs": float(difference.mean()),
        "p99_abs": float(np.quantile(difference, 0.99)),
    }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def export_postprocess_fixture(model: nn.Module, example: torch.Tensor, dense_logits: np.ndarray, output: Path) -> Path:
    from scalelsd.base import WireframeGraph
    from scalelsd.ssl.models.detector import ScaleLSD

    ScaleLSD.num_junctions_inference = 512
    ScaleLSD.junction_threshold_hm = 0.008
    annotations = {
        "width": 512,
        "height": 512,
        "filename": "deterministic-random-input",
        "use_lsd": False,
        "use_nms": False,
    }
    with torch.no_grad():
        output_list, _ = model(example, annotations)
    official = output_list[0]
    indices = WireframeGraph.xyxy2indices(official["juncs_pred"], official["lines_pred"])
    graph = WireframeGraph(
        official["juncs_pred"],
        official["juncs_score"],
        indices,
        official["lines_score"],
        official["width"],
        official["height"],
    )
    lines = graph.line_segments(threshold=10.0, to_np=True)

    dense_path = output / "dense_logits.f32"
    dense_logits.astype("<f4", copy=False).tofile(dense_path)
    fixture = {
        "dense_tensor": dense_path.name,
        "dense_shape": list(dense_logits.shape),
        "image_width": 512,
        "image_height": 512,
        "configuration": {
            "distance_threshold": 5.0,
            "junction_to_line_squared_distance_threshold": 10.0,
            "junction_heatmap_threshold": 0.008,
            "maximum_junctions": 512,
            "line_support_threshold": 10.0,
            "use_nms": False,
        },
        "junction_count": int(official["juncs_pred"].shape[0]),
        "graph_edge_count": int(official["lines_pred"].shape[0]),
        "lines": [
            {
                "x1": float(line[0]),
                "y1": float(line[1]),
                "x2": float(line[2]),
                "y2": float(line[3]),
                "score": float(line[4]),
            }
            for line in lines
        ],
    }
    fixture_path = output / "postprocess_fixture.json"
    fixture_path.write_text(json.dumps(fixture, indent=2) + "\n", encoding="utf-8")
    return fixture_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--official-repo", type=Path, default=DEFAULT_OFFICIAL_REPO)
    parser.add_argument("--checkpoint", type=Path, default=DEFAULT_CHECKPOINT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--precision", choices=["float32", "float16"], default="float32")
    parser.add_argument("--skip-convert", action="store_true")
    args = parser.parse_args()

    if not args.official_repo.is_dir():
        raise SystemExit(f"missing official ScaleLSD checkout: {args.official_repo}")
    if not args.checkpoint.is_file():
        raise SystemExit(f"missing ScaleLSD checkpoint: {args.checkpoint}")

    sys.path.insert(0, str(args.official_repo))
    import coremltools as ct
    from scalelsd.ssl.misc.train_utils import load_scalelsd_model

    install_fixed_shape_forward_vit()
    args.output.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(20260710)
    example = torch.rand(INPUT_SHAPE, dtype=torch.float32)
    model = load_scalelsd_model(str(args.checkpoint), device="cpu")
    wrapper = NeuralForwardWrapper(model).cpu().eval()

    with torch.no_grad():
        pytorch_output = wrapper(example).cpu().numpy()
    if pytorch_output.shape != OUTPUT_SHAPE:
        raise RuntimeError(f"expected output {OUTPUT_SHAPE}, got {pytorch_output.shape}")

    trace_start = time.perf_counter()
    traced = torch.jit.trace(wrapper, example, strict=False, check_trace=False)
    traced_path = args.output / "scalelsd_neural_forward.pt"
    traced.save(str(traced_path))
    with torch.no_grad():
        traced_output = traced(example).cpu().numpy()
    trace_stats = tensor_stats(pytorch_output, traced_output)
    trace_seconds = time.perf_counter() - trace_start

    fixture_path = args.output / "raw_tensor_fixture.npz"
    input_fixture_path = args.output / "input_tensor.f32"
    example.cpu().numpy().astype("<f4", copy=False).tofile(input_fixture_path)
    np.savez_compressed(
        fixture_path,
        input=example.cpu().numpy(),
        pytorch_output=pytorch_output,
        traced_output=traced_output,
    )
    postprocess_fixture_path = export_postprocess_fixture(model, example, pytorch_output, args.output)

    package_path = args.output / "scalelsd_neural_forward.mlpackage"
    compiled_path: Path | None = None
    coreml_stats: dict[str, float] | None = None
    convert_seconds: float | None = None
    if not args.skip_convert:
        if package_path.exists():
            shutil.rmtree(package_path)
        precision = ct.precision.FLOAT32 if args.precision == "float32" else ct.precision.FLOAT16
        convert_start = time.perf_counter()
        mlmodel = ct.convert(
            traced,
            convert_to="mlprogram",
            inputs=[ct.TensorType(name="image", shape=INPUT_SHAPE, dtype=np.float32)],
            outputs=[ct.TensorType(name="dense_logits", dtype=np.float32)],
            compute_precision=precision,
            minimum_deployment_target=ct.target.macOS14,
        )
        mlmodel.short_description = "ScaleLSD fixed 512x512 neural forward"
        mlmodel.input_description["image"] = "Normalized grayscale NCHW tensor [1,1,512,512]"
        mlmodel.output_description["dense_logits"] = "Raw ScaleLSD logits [1,9,256,256]"
        mlmodel.save(str(package_path))
        convert_seconds = time.perf_counter() - convert_start
        compiled_path = compile_package(package_path, args.output)
        prediction = mlmodel.predict({"image": example.cpu().numpy()})["dense_logits"]
        coreml_stats = tensor_stats(pytorch_output, prediction)
        np.savez_compressed(
            fixture_path,
            input=example.cpu().numpy(),
            pytorch_output=pytorch_output,
            traced_output=traced_output,
            coreml_output=prediction,
        )

    summary = {
        "official_repo": str(args.official_repo),
        "checkpoint": str(args.checkpoint),
        "checkpoint_sha256": sha256_file(args.checkpoint),
        "input_shape": list(INPUT_SHAPE),
        "output_shape": list(OUTPUT_SHAPE),
        "precision": args.precision,
        "torch_version": torch.__version__,
        "coremltools_version": ct.__version__,
        "trace_seconds": trace_seconds,
        "trace_parity": trace_stats,
        "convert_seconds": convert_seconds,
        "coreml_parity": coreml_stats,
        "traced_model": str(traced_path),
        "package": str(package_path) if not args.skip_convert and package_path.exists() else None,
        "compiled_model": str(compiled_path) if compiled_path else None,
        "fixture": str(fixture_path),
        "input_fixture": str(input_fixture_path),
        "postprocess_fixture": str(postprocess_fixture_path),
    }
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
