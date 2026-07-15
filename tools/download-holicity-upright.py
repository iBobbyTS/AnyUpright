#!/usr/bin/env python3
"""Download HoliCity assets for AnyUpright Upright validation.

The default preset downloads the smallest practical set for image-space Upright
validation: perspective images, camera metadata, vanishing points, splits, and
semantic labels. Larger geometry assets can be requested explicitly.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote


BASE_URL = "https://huggingface.co/yichaozhou/holicity/resolve/main"
TERMS_URL = "https://raw.githubusercontent.com/zhou13/holicity/master/LICENSE"
DEFAULT_TARGET = Path("/Volumes/4T/temp/AnyUprightResearchWorkspace")


@dataclass(frozen=True)
class Asset:
    path: str
    size: int
    groups: tuple[str, ...]
    reason: str


ASSETS: tuple[Asset, ...] = (
    Asset(
        "perspective/image-v1/image-v1.tar-part-1-of-2",
        3_180_940_976,
        ("images",),
        "Perspective RGB images for line detection and visual validation.",
    ),
    Asset(
        "perspective/image-v1/image-v1.tar-part-2-of-2",
        3_180_464_063,
        ("images",),
        "Perspective RGB images for line detection and visual validation.",
    ),
    Asset(
        "perspective/image-v1-test-valid.tar",
        633_436_160,
        ("images",),
        "Validation/test perspective RGB images.",
    ),
    Asset(
        "perspective/camr-v1.tar",
        153_681_920,
        ("camera",),
        "Camera metadata for geometry checks.",
    ),
    Asset(
        "perspective/vpts-v1.tar",
        76_840_960,
        ("vpts",),
        "Vanishing-point labels for direction-family validation.",
    ),
    Asset(
        "split/split-all-v1-bugfix.zip",
        598_658,
        ("split",),
        "Official all-view split metadata.",
    ),
    Asset(
        "split/split-middle-v1-bugfix.zip",
        480_507,
        ("split",),
        "Official middle-view split metadata.",
    ),
    Asset(
        "perspective/segmentation-v1.tar",
        164_413_440,
        ("semantic",),
        "Small semantic labels useful for filtering sky/road/building cases.",
    ),
    Asset(
        "perspective/plane-v1.tar",
        524_441_600,
        ("planes",),
        "Optional plane labels for deeper geometry diagnostics.",
    ),
    Asset(
        "perspective/planes-v1-test-valid.tar",
        52_592_640,
        ("planes",),
        "Optional validation/test plane labels.",
    ),
    Asset(
        "perspective/depth-v1/depth-v1.tar-part-1-of-6",
        4_379_509_018,
        ("depth",),
        "Optional depth maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/depth-v1/depth-v1.tar-part-2-of-6",
        4_376_513_394,
        ("depth",),
        "Optional depth maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/depth-v1/depth-v1.tar-part-3-of-6",
        4_380_407_683,
        ("depth",),
        "Optional depth maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/depth-v1/depth-v1.tar-part-4-of-6",
        4_381_039_430,
        ("depth",),
        "Optional depth maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/depth-v1/depth-v1.tar-part-5-of-6",
        4_381_501_296,
        ("depth",),
        "Optional depth maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/depth-v1/depth-v1.tar-part-6-of-6",
        4_377_317_891,
        ("depth",),
        "Optional depth maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/normal-v1/normal-v1.tar-part-1-of-9",
        4_542_271_290,
        ("normal",),
        "Optional normal maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/normal-v1/normal-v1.tar-part-2-of-9",
        4_540_099_637,
        ("normal",),
        "Optional normal maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/normal-v1/normal-v1.tar-part-3-of-9",
        4_537_879_263,
        ("normal",),
        "Optional normal maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/normal-v1/normal-v1.tar-part-4-of-9",
        4_541_723_642,
        ("normal",),
        "Optional normal maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/normal-v1/normal-v1.tar-part-5-of-9",
        4_534_012_151,
        ("normal",),
        "Optional normal maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/normal-v1/normal-v1.tar-part-6-of-9",
        4_543_261_015,
        ("normal",),
        "Optional normal maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/normal-v1/normal-v1.tar-part-7-of-9",
        4_543_134_972,
        ("normal",),
        "Optional normal maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/normal-v1/normal-v1.tar-part-8-of-9",
        4_542_043_916,
        ("normal",),
        "Optional normal maps for deriving extra 3D checks.",
    ),
    Asset(
        "perspective/normal-v1/normal-v1.tar-part-9-of-9",
        4_530_314_628,
        ("normal",),
        "Optional normal maps for deriving extra 3D checks.",
    ),
    Asset(
        "panorama/panorama-camera.tar.xz",
        530_000,
        ("panorama-camera",),
        "Optional panorama camera metadata; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-01-of-22",
        4_206_875_308,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-02-of-22",
        4_319_523_159,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-03-of-22",
        4_265_464_791,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-04-of-22",
        4_239_398_805,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-05-of-22",
        4_181_260_686,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-06-of-22",
        4_166_502_394,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-07-of-22",
        4_169_037_388,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-08-of-22",
        4_193_218_987,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-09-of-22",
        4_236_237_536,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-10-of-22",
        4_200_140_051,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-11-of-22",
        4_191_372_257,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-12-of-22",
        4_202_604_492,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-13-of-22",
        4_191_465_496,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-14-of-22",
        4_202_403_267,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-15-of-22",
        4_209_353_948,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-16-of-22",
        4_195_706_159,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-17-of-22",
        4_174_842_300,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-18-of-22",
        4_195_263_358,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-19-of-22",
        4_179_038_122,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-20-of-22",
        4_182_308_510,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-21-of-22",
        4_196_102_137,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-image/panorama.tar-part-22-of-22",
        4_000_189_048,
        ("panorama-images",),
        "Optional source panoramas; not needed for first Upright validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-01-of-28",
        3_759_479_371,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-02-of-28",
        3_807_893_107,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-03-of-28",
        3_779_998_404,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-04-of-28",
        3_873_925_935,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-05-of-28",
        3_833_442_639,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-06-of-28",
        3_823_745_704,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-07-of-28",
        3_781_403_024,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-08-of-28",
        3_589_968_189,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-09-of-28",
        3_808_752_052,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-10-of-28",
        3_615_326_597,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-11-of-28",
        4_122_478_112,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-12-of-28",
        4_108_440_878,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-13-of-28",
        4_032_481_199,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-14-of-28",
        4_019_754_390,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-15-of-28",
        4_037_596_397,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-16-of-28",
        4_300_787_795,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-17-of-28",
        3_849_759_314,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-18-of-28",
        3_812_214_822,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-19-of-28",
        3_890_084_707,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-20-of-28",
        3_867_951_884,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-21-of-28",
        3_907_484_266,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-22-of-28",
        3_888_361_197,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-23-of-28",
        3_934_845_330,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-24-of-28",
        4_033_055_443,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-25-of-28",
        4_078_134_982,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-26-of-28",
        4_191_745_587,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-27-of-28",
        4_170_621_461,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
    Asset(
        "panorama/panorama-depth/panorama-depth.tar.xz-part-28-of-28",
        3_598_298_489,
        ("panorama-depth",),
        "Optional panorama depth; not needed for perspective validation.",
    ),
)

PRESETS: dict[str, tuple[str, ...]] = {
    "upright-minimal": ("images", "camera", "vpts", "split"),
    "upright-core": ("images", "camera", "vpts", "split", "semantic"),
    "perspective-geometry": (
        "images",
        "camera",
        "vpts",
        "split",
        "semantic",
        "planes",
        "depth",
        "normal",
    ),
    "all-public": (
        "images",
        "camera",
        "vpts",
        "split",
        "semantic",
        "planes",
        "depth",
        "normal",
        "panorama-camera",
        "panorama-images",
        "panorama-depth",
    ),
}

GROUP_DESCRIPTIONS: dict[str, str] = {
    "images": "Required. Perspective RGB images for the detector.",
    "camera": "Required. Perspective camera metadata.",
    "vpts": "Required. Vanishing-point labels.",
    "split": "Required. Official split metadata.",
    "semantic": "Recommended. Small labels for filtering scene classes.",
    "planes": "Optional. Plane labels for deeper geometry diagnostics.",
    "depth": "Optional. Perspective depth maps, large.",
    "normal": "Optional. Perspective normal maps, large.",
    "panorama-camera": "Optional. Panorama camera metadata.",
    "panorama-images": "Optional. Source panoramas, very large.",
    "panorama-depth": "Optional. Panorama depth, very large.",
}


def human_size(size: int) -> str:
    return f"{size / 1_000_000_000:.3f} GB / {size / (1024**3):.3f} GiB"


def asset_url(path: str) -> str:
    return f"{BASE_URL}/{quote(path, safe='/')}?download=true"


def selected_assets(preset: str, includes: list[str]) -> tuple[list[Asset], tuple[str, ...]]:
    groups = tuple(dict.fromkeys((*PRESETS[preset], *includes)))
    selected = [
        asset for asset in ASSETS if any(group in groups for group in asset.groups)
    ]
    return selected, groups


def print_plan(assets: list[Asset], groups: tuple[str, ...], target: Path) -> None:
    total = sum(asset.size for asset in assets)
    print(f"target: {target}")
    print(f"groups: {', '.join(groups)}")
    print(f"files: {len(assets)}")
    print(f"download size: {total:,} bytes ({human_size(total)})")
    print()
    for asset in assets:
        print(f"{asset.size:>13,}  {human_size(asset.size):>21}  {asset.path}")


def write_manifest(target: Path, args: argparse.Namespace, assets: list[Asset]) -> None:
    target.mkdir(parents=True, exist_ok=True)
    manifest = {
        "generated_at_unix": int(time.time()),
        "source": "https://huggingface.co/yichaozhou/holicity",
        "terms_url": TERMS_URL,
        "preset": args.preset,
        "include": args.include,
        "target": str(target),
        "total_bytes": sum(asset.size for asset in assets),
        "files": [
            {
                "path": asset.path,
                "size": asset.size,
                "groups": list(asset.groups),
                "reason": asset.reason,
                "url": asset_url(asset.path),
            }
            for asset in assets
        ],
    }
    (target / "holicity_download_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n",
        encoding="utf-8",
    )


def run_curl(curl: str, token: str | None, url: str, output: Path) -> None:
    command = [
        curl,
        "--location",
        "--fail",
        "--retry",
        "5",
        "--retry-delay",
        "5",
        "--continue-at",
        "-",
        "--output",
        str(output),
        url,
    ]
    if token:
        command[1:1] = ["--header", f"Authorization: Bearer {token}"]
    subprocess.run(command, check=True)


def download_asset(args: argparse.Namespace, target: Path, asset: Asset) -> None:
    output = target / asset.path
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        current_size = output.stat().st_size
        if current_size == asset.size and not args.force:
            print(f"skip complete: {asset.path}")
            return
        if current_size > asset.size and not args.force:
            raise SystemExit(
                f"{output} is larger than expected; remove it or pass --force"
            )
        if args.force:
            output.unlink()

    print(f"download: {asset.path} ({human_size(asset.size)})")
    run_curl(args.curl, args.hf_token or os.environ.get("HF_TOKEN"), asset_url(asset.path), output)
    actual_size = output.stat().st_size
    if actual_size != asset.size:
        raise SystemExit(
            f"size mismatch for {output}: got {actual_size}, expected {asset.size}"
        )


def parse_args() -> argparse.Namespace:
    all_groups = sorted(GROUP_DESCRIPTIONS)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--target",
        type=Path,
        default=DEFAULT_TARGET,
        help=f"download root, default: {DEFAULT_TARGET}",
    )
    parser.add_argument(
        "--preset",
        choices=sorted(PRESETS),
        default="upright-core",
        help="asset preset to download",
    )
    parser.add_argument(
        "--include",
        choices=all_groups,
        action="append",
        default=[],
        help="add a group on top of the selected preset; may be repeated",
    )
    parser.add_argument("--dry-run", action="store_true", help="print plan only")
    parser.add_argument("--list-groups", action="store_true", help="list groups and exit")
    parser.add_argument(
        "--accept-terms",
        action="store_true",
        help=f"confirm you have reviewed and accept the HoliCity terms: {TERMS_URL}",
    )
    parser.add_argument("--force", action="store_true", help="redownload existing files")
    parser.add_argument("--curl", default="curl", help="curl executable")
    parser.add_argument("--hf-token", default=None, help="optional Hugging Face token")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.list_groups:
        for name in sorted(GROUP_DESCRIPTIONS):
            size = sum(asset.size for asset in ASSETS if name in asset.groups)
            print(f"{name:16} {human_size(size):>21}  {GROUP_DESCRIPTIONS[name]}")
        return 0

    assets, groups = selected_assets(args.preset, args.include)
    print_plan(assets, groups, args.target)

    if args.dry_run:
        return 0

    if not args.accept_terms:
        print(
            f"Refusing to download until --accept-terms is passed. Terms: {TERMS_URL}",
            file=sys.stderr,
        )
        return 2

    write_manifest(args.target, args, assets)
    for asset in assets:
        download_asset(args, args.target, asset)
    write_manifest(args.target, args, assets)
    print(f"done: {args.target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
