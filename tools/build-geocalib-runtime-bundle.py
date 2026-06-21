#!/usr/bin/env python3
"""Build a slim GeoCalib runtime bundle from a verified neural-forward fixture.

The neural-forward fixture contains both runtime weights and test-only tensors.
This tool copies only tensors referenced by the top-level `neural_forward`
manifest section, then writes a slim manifest with no fixture entries.

Xcode's synchronized folder build flattens loose resource files into
`Contents/Resources`, so this tool also flattens runtime tensor names and
rewrites manifest paths to their basenames.
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from typing import Any


def referenced_runtime_files(value: Any) -> set[str]:
    paths: set[str] = set()
    if isinstance(value, dict):
        for child in value.values():
            paths.update(referenced_runtime_files(child))
    elif isinstance(value, list):
        for child in value:
            paths.update(referenced_runtime_files(child))
    elif isinstance(value, str) and value.endswith(".f32"):
        paths.add(value)
    return paths


def flatten_runtime_paths(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: flatten_runtime_paths(child) for key, child in value.items()}
    if isinstance(value, list):
        return [flatten_runtime_paths(child) for child in value]
    if isinstance(value, str) and value.endswith(".f32"):
        return Path(value).name
    return value


def build_bundle(source: Path, output: Path) -> None:
    manifest_path = source / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    if "neural_forward" not in manifest:
        raise SystemExit(f"{manifest_path} does not contain a neural_forward section")

    runtime_files = referenced_runtime_files(manifest["neural_forward"])
    if not runtime_files:
        raise SystemExit("no runtime .f32 files found in neural_forward manifest")

    output.mkdir(parents=True, exist_ok=True)
    for relative in sorted(runtime_files):
        src = source / relative
        dst = output / Path(relative).name
        if not src.exists():
            raise SystemExit(f"missing runtime tensor {src}")
        shutil.copy2(src, dst)

    flattened_neural_forward = flatten_runtime_paths(manifest["neural_forward"])
    slim_manifest = {
        "description": "AnyUpright GeoCalib fixed-NMF runtime model bundle.",
        "source_fixture": str(source),
        "runtime_file_count": len(runtime_files),
        "neural_forward": flattened_neural_forward,
    }
    (output / "manifest.json").write_text(json.dumps(slim_manifest, indent=2, sort_keys=True) + "\n")

    total_bytes = sum((output / Path(relative).name).stat().st_size for relative in runtime_files)
    print(f"wrote {len(runtime_files)} runtime tensors")
    print(f"runtime bytes: {total_bytes}")
    print(f"output: {output}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        default="/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_neural_forward_3",
        type=Path,
        help="Verified GeoCalib neural-forward fixture directory.",
    )
    parser.add_argument("--out", required=True, type=Path, help="Output runtime bundle directory.")
    args = parser.parse_args()

    build_bundle(args.source, args.out)


if __name__ == "__main__":
    main()
