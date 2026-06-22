#!/usr/bin/env python3
"""Build fixed-shape GeoCalib neural-forward Core ML packages.

This script intentionally reuses the verified experiment conversion code in
the AnyUpright algorithm work directory. It creates one fixed ML Program per
GeoCalib preprocessing output shape, compiles each package to .mlmodelc, and
copies the compiled models into the plugin resource directory.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import numpy as np
import torch


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WORKDIR = Path("/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory")
OUTPUT_NAMES = ["up_field", "up_confidence", "latitude_field", "latitude_confidence"]
SHAPE_SPECS = [
    ("4x3", (1, 3, 320, 416)),
    ("3x4", (1, 3, 416, 320)),
    ("16x9", (1, 3, 320, 544)),
    ("9x16", (1, 3, 544, 320)),
    ("1x1", (1, 3, 320, 320)),
    ("3x2", (1, 3, 320, 480)),
    ("2x3", (1, 3, 480, 320)),
    ("235x100", (1, 3, 320, 736)),
]


def model_name(shape: tuple[int, int, int, int]) -> str:
    return f"neural_forward_{shape[2]}x{shape[3]}.mlmodelc"


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def load_conversion_helpers(workdir: Path) -> dict[str, Any]:
    scripts_dir = workdir / "scripts"
    geocalib_dir = workdir / "external" / "GeoCalib"
    if not scripts_dir.is_dir() or not geocalib_dir.is_dir():
        raise SystemExit(f"invalid GeoCalib work directory: {workdir}")

    sys.path.insert(0, str(geocalib_dir))
    sys.path.insert(0, str(scripts_dir))

    import coremltools as ct  # noqa: WPS433
    from geocalib import GeoCalib  # noqa: WPS433
    from evaluate_geocalib_coreml_conversion import (  # noqa: WPS433
        NeuralForwardWrapper,
        convert_mlprogram,
        patch_static_nmf_forward,
        patch_trace_shape_asserts,
        trace_model,
    )
    from export_fixed_nmf_reference import patch_fixed_nmf_bases  # noqa: WPS433

    return {
        "ct": ct,
        "GeoCalib": GeoCalib,
        "NeuralForwardWrapper": NeuralForwardWrapper,
        "convert_mlprogram": convert_mlprogram,
        "patch_static_nmf_forward": patch_static_nmf_forward,
        "patch_trace_shape_asserts": patch_trace_shape_asserts,
        "trace_model": trace_model,
        "patch_fixed_nmf_bases": patch_fixed_nmf_bases,
    }


def convert_shape(
    helpers: dict[str, Any],
    shape: tuple[int, int, int, int],
    shape_dir: Path,
    fixed_nmf_seed: int,
) -> dict[str, Any]:
    ct = helpers["ct"]
    GeoCalib = helpers["GeoCalib"]
    NeuralForwardWrapper = helpers["NeuralForwardWrapper"]
    convert_mlprogram = helpers["convert_mlprogram"]
    patch_static_nmf_forward = helpers["patch_static_nmf_forward"]
    trace_model = helpers["trace_model"]
    patch_fixed_nmf_bases = helpers["patch_fixed_nmf_bases"]

    shape_dir.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(12345 + shape[2] * 10_000 + shape[3])
    example = torch.rand(shape, dtype=torch.float32)
    conversion_model = GeoCalib().cpu().eval()
    patch_fixed_nmf_bases(conversion_model, fixed_nmf_seed, "cpu")
    static_nmf_patches = patch_static_nmf_forward(conversion_model, example)
    wrapper = NeuralForwardWrapper(conversion_model).cpu().eval()

    start = time.perf_counter()
    traced = trace_model(wrapper, (example.cpu(),), shape_dir, "neural_forward")
    mlmodel = convert_mlprogram(
        traced,
        inputs=[ct.TensorType(name="image", shape=shape, dtype=np.float32)],
        outputs=[ct.TensorType(name=name) for name in OUTPUT_NAMES],
        out_dir=shape_dir,
        name="neural_forward",
    )
    return {
        "input_shape": list(shape),
        "shape_name": "x".join(str(dim) for dim in shape),
        "static_nmf_patches": static_nmf_patches,
        "package_dir": str(shape_dir / "neural_forward.mlpackage"),
        "specification_version": int(mlmodel.get_spec().specificationVersion),
        "elapsed_ms": (time.perf_counter() - start) * 1000.0,
    }


def compile_package(package_dir: Path, compile_root: Path) -> Path:
    if compile_root.exists():
        shutil.rmtree(compile_root)
    compile_root.mkdir(parents=True)
    run(["xcrun", "coremlcompiler", "compile", str(package_dir), str(compile_root)])
    compiled = compile_root / "neural_forward.mlmodelc"
    if not compiled.is_dir():
        raise SystemExit(f"coremlcompiler did not create {compiled}")
    return compiled


def copy_model(compiled: Path, destination: Path, force: bool) -> str:
    if destination.exists():
        if not force:
            return "kept_existing"
        shutil.rmtree(destination)
    shutil.copytree(compiled, destination, symlinks=True)
    return "copied"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workdir", type=Path, default=DEFAULT_WORKDIR)
    parser.add_argument("--out", type=Path, default=DEFAULT_WORKDIR / "outputs" / "geocalib_coreml_fixed_shapes")
    parser.add_argument(
        "--coreml-root",
        type=Path,
        default=REPO_ROOT / "AnyUpright" / "Plugin" / "GeoCalibCoreML",
    )
    parser.add_argument("--fixed-nmf-seed", type=int, default=1234)
    parser.add_argument("--force", action="store_true", help="replace existing .mlmodelc directories")
    parser.add_argument(
        "--shapes",
        default=",".join(label for label, _ in SHAPE_SPECS),
        help="comma-separated shape labels: 4x3,3x4,16x9,9x16,1x1,3x2,2x3,235x100",
    )
    args = parser.parse_args()

    requested = {item.strip() for item in args.shapes.split(",") if item.strip()}
    by_label = dict(SHAPE_SPECS)
    unknown = sorted(requested - set(by_label))
    if unknown:
        raise SystemExit(f"unknown shape labels: {', '.join(unknown)}")

    helpers = load_conversion_helpers(args.workdir)
    helpers["patch_trace_shape_asserts"]()
    args.out.mkdir(parents=True, exist_ok=True)
    args.coreml_root.mkdir(parents=True, exist_ok=True)

    rows: list[dict[str, Any]] = []
    for label, shape in SHAPE_SPECS:
        if label not in requested:
            continue
        destination = args.coreml_root / model_name(shape)
        shape_dir = args.out / f"{label}_{shape[2]}x{shape[3]}"
        if destination.exists() and not args.force:
            rows.append(
                {
                    "label": label,
                    "input_shape": list(shape),
                    "model_dir": str(destination),
                    "status": "kept_existing",
                }
            )
            continue

        print(f"==> converting {label} shape={shape}")
        result = convert_shape(helpers, shape, shape_dir, args.fixed_nmf_seed)
        compiled = compile_package(shape_dir / "neural_forward.mlpackage", shape_dir / "compiled")
        status = copy_model(compiled, destination, force=args.force)
        result |= {
            "label": label,
            "model_dir": str(destination),
            "status": status,
        }
        rows.append(result)

    summary = {
        "coreml_root": str(args.coreml_root),
        "out": str(args.out),
        "fixed_nmf_seed": args.fixed_nmf_seed,
        "force": args.force,
        "models": rows,
    }
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
