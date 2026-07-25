#!/usr/bin/env python3
"""Validate Upright candidate detection against HoliCity VP labels.

This is an offline research helper. It reads HoliCity tar files directly from
the external research workspace and writes compact JSON/CSV results back there.
It intentionally avoids extracting the full dataset into the repository.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import math
import random
import shutil
import subprocess
import tarfile
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import cv2
import numpy as np


DEFAULT_WORKSPACE = Path("/Volumes/4T/temp/AnyUprightResearchWorkspace")
DEFAULT_OUTPUT = DEFAULT_WORKSPACE / "outputs" / "holicity_upright_validation"
DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCALELSD_MODEL = (
    DEFAULT_WORKSPACE
    / "model_tests"
    / "scalelsd"
    / "coreml_conversion"
    / "compiled"
    / "scalelsd_neural_forward.mlmodelc"
)
DEFAULT_SCALELSD_EXPORTER = DEFAULT_WORKSPACE / "tools" / "export-scalelsd-upright-lines"
DEFAULT_SCALELSD_PROPOSAL_EXPORTER = DEFAULT_WORKSPACE / "tools" / "rank-scalelsd-upright-proposals"
DEFAULT_GEOCALIB_PRIOR_EXPORTER = DEFAULT_WORKSPACE / "tools" / "export-geocalib-camera-priors"
DEFAULT_GEOCALIB_MODEL_DIRECTORY = DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "GeoCalibCoreML"


@dataclass(frozen=True)
class TarEntry:
    tar_path: Path
    member_name: str


@dataclass(frozen=True)
class Sample:
    stem: str
    image: TarEntry
    camera: TarEntry
    vpts: TarEntry


@dataclass(frozen=True)
class LoadedSample:
    sample: Sample
    image: np.ndarray
    camera: dict[str, np.ndarray]
    vpts: np.ndarray
    confidence: np.ndarray


@dataclass(frozen=True)
class LineSegment:
    x1: float
    y1: float
    x2: float
    y2: float
    score: float

    @property
    def length(self) -> float:
        return math.hypot(self.x2 - self.x1, self.y2 - self.y1)

    @property
    def angle_radians(self) -> float:
        return normalized_line_angle(math.atan2(self.y2 - self.y1, self.x2 - self.x1))


@dataclass(frozen=True)
class EvaluatedSampleInput:
    sample: Sample
    image: np.ndarray
    camera: dict[str, np.ndarray]
    vpts: np.ndarray
    confidence: np.ndarray
    lines: list[LineSegment]
    detector_elapsed_ms: float
    proposal: dict[str, object] | None = None


def normalized_member_name(name: str) -> str:
    return name[2:] if name.startswith("./") else name


def stem_for_member(name: str, suffix: str) -> str:
    clean = normalized_member_name(name)
    if not clean.endswith(suffix):
        raise ValueError(f"unexpected suffix for {name}")
    return clean[: -len(suffix)]


def index_tar(tar_path: Path, suffix: str) -> dict[str, TarEntry]:
    result: dict[str, TarEntry] = {}
    with tarfile.open(tar_path) as tar:
        for member in tar.getmembers():
            if not member.isfile() or not member.name.endswith(suffix):
                continue
            result[stem_for_member(member.name, suffix)] = TarEntry(tar_path, member.name)
    return result


def build_samples(workspace: Path, image_set: str, limit: int, seed: int) -> list[Sample]:
    if image_set == "test-valid":
        image_tars = [workspace / "perspective" / "image-v1-test-valid.tar"]
    else:
        image_tars = [
            workspace / "perspective" / "image-v1" / "image-v1.tar-part-1-of-2",
            workspace / "perspective" / "image-v1" / "image-v1.tar-part-2-of-2",
        ]
    image_index: dict[str, TarEntry] = {}
    for image_tar in image_tars:
        image_index.update(index_tar(image_tar, "_imag.jpg"))

    camera_index = index_tar(workspace / "perspective" / "camr-v1.tar", "_camr.npz")
    vpts_index = index_tar(workspace / "perspective" / "vpts-v1.tar", "_vpts.npz")
    stems = sorted(set(image_index) & set(camera_index) & set(vpts_index))
    if limit > 0 and len(stems) > limit:
        random.Random(seed).shuffle(stems)
        stems = sorted(stems[:limit])
    return [
        Sample(
            stem=stem,
            image=image_index[stem],
            camera=camera_index[stem],
            vpts=vpts_index[stem],
        )
        for stem in stems
    ]


def read_tar_bytes(entry: TarEntry) -> bytes:
    with tarfile.open(entry.tar_path) as tar:
        extracted = tar.extractfile(entry.member_name)
        if extracted is None:
            raise FileNotFoundError(entry.member_name)
        return extracted.read()


def read_image(entry: TarEntry) -> np.ndarray:
    data = np.frombuffer(read_tar_bytes(entry), dtype=np.uint8)
    image = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"failed to decode image {entry.member_name}")
    return image


def read_npz(entry: TarEntry) -> dict[str, np.ndarray]:
    return dict(np.load(io.BytesIO(read_tar_bytes(entry))))


def normalized_line_angle(angle: float) -> float:
    while angle <= -math.pi / 2:
        angle += math.pi
    while angle > math.pi / 2:
        angle -= math.pi
    return angle


def angle_distance(lhs: float, rhs: float) -> float:
    return abs(normalized_line_angle(lhs - rhs))


def project_vpts(vpts: np.ndarray, width: int, height: int, fov_degrees: float) -> np.ndarray:
    f = (width * 0.5) / math.tan(math.radians(fov_degrees) * 0.5)
    cx = (width - 1) * 0.5
    cy = (height - 1) * 0.5
    points: list[tuple[float, float, float]] = []
    for direction in vpts:
        x, y, z = [float(value) for value in direction]
        if abs(z) < 1e-9:
            z = math.copysign(1e-9, z if z != 0 else 1.0)
        # HoliCity camera coordinates use x right, y up, and z pointing out of
        # the screen. The image plane is z = -1.
        u = cx - f * x / z
        v = cy + f * y / z
        points.append((u, v, z))
    return np.array(points, dtype=np.float64)


def detect_lines(
    image: np.ndarray,
    max_side: int,
    lsd_limit: int,
    hough_limit: int,
) -> list[LineSegment]:
    height, width = image.shape[:2]
    scale = min(1.0, max_side / float(max(width, height)))
    if scale < 1.0:
        resized = cv2.resize(
            image,
            (max(1, round(width * scale)), max(1, round(height * scale))),
            interpolation=cv2.INTER_AREA,
        )
    else:
        resized = image

    gray = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
    result: list[LineSegment] = []

    lsd = cv2.createLineSegmentDetector(cv2.LSD_REFINE_STD)
    detected = lsd.detect(gray)[0]
    if detected is not None:
        for row in detected.reshape(-1, 4):
            x1, y1, x2, y2 = [float(value) / scale for value in row]
            segment = LineSegment(x1, y1, x2, y2, 1.0)
            if segment.length >= max(24.0, min(width, height) * 0.04):
                result.append(segment)

    edges = cv2.Canny(gray, 80, 180, apertureSize=3)
    hough = cv2.HoughLinesP(
        edges,
        rho=1,
        theta=np.pi / 180.0,
        threshold=60,
        minLineLength=max(20, int(min(gray.shape[:2]) * 0.05)),
        maxLineGap=max(8, int(min(gray.shape[:2]) * 0.02)),
    )
    if hough is not None:
        for row in hough.reshape(-1, 4):
            x1, y1, x2, y2 = [float(value) / scale for value in row]
            segment = LineSegment(x1, y1, x2, y2, 0.75)
            if segment.length >= max(24.0, min(width, height) * 0.04):
                result.append(segment)

    result.sort(key=lambda line: line.length * line.score, reverse=True)
    deduped: list[LineSegment] = []
    for line in result:
        if any(lines_similar(line, existing) for existing in deduped):
            continue
        deduped.append(line)
        if len(deduped) >= lsd_limit + hough_limit:
            break
    return deduped


def load_sample(sample: Sample) -> LoadedSample:
    image = read_image(sample.image)
    camera = read_npz(sample.camera)
    vpts_npz = read_npz(sample.vpts)
    return LoadedSample(
        sample=sample,
        image=image,
        camera=camera,
        vpts=np.asarray(vpts_npz["vpts"], dtype=np.float64),
        confidence=np.asarray(vpts_npz["confidence"], dtype=np.float64),
    )


def detect_lines_opencv(loaded: LoadedSample, args: argparse.Namespace) -> EvaluatedSampleInput:
    start = time.perf_counter()
    lines = detect_lines(loaded.image, args.max_side, args.lsd_limit, args.hough_limit)
    elapsed_ms = (time.perf_counter() - start) * 1000.0
    return EvaluatedSampleInput(
        sample=loaded.sample,
        image=loaded.image,
        camera=loaded.camera,
        vpts=loaded.vpts,
        confidence=loaded.confidence,
        lines=lines,
        detector_elapsed_ms=elapsed_ms,
    )


def compile_swift_exporter(
    exporter: Path,
    sources: list[Path],
    rebuild: bool,
    defines: list[str] | None = None,
) -> Path:
    newest_source_mtime = max(source.stat().st_mtime for source in sources)
    if exporter.exists() and not rebuild and exporter.stat().st_mtime >= newest_source_mtime:
        return exporter

    exporter.parent.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    command = ["xcrun", "swiftc", "-O"]
    for define in defines or []:
        command.extend(["-D", define])
    command.extend(str(source) for source in sources)
    command.extend(["-sdk", sdk, "-o", str(exporter)])
    subprocess.run(command, cwd=DEFAULT_REPO_ROOT, check=True)
    return exporter


def compile_scalelsd_exporter(args: argparse.Namespace) -> Path:
    return compile_swift_exporter(
        exporter=args.scalelsd_exporter,
        sources=[
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightGeometry.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightScaleLSDPostprocessor.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightScaleLSDCoreML.swift",
            DEFAULT_REPO_ROOT / "tools" / "export-scalelsd-upright-lines.swift",
        ],
        rebuild=args.rebuild_scalelsd_exporter,
    )


def compile_scalelsd_proposal_exporter(args: argparse.Namespace) -> Path:
    return compile_swift_exporter(
        exporter=args.scalelsd_proposal_exporter,
        sources=[
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightGeometry.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightUprightCandidates.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightUprightProposal.swift",
            DEFAULT_REPO_ROOT / "tools" / "rank-scalelsd-upright-proposals.swift",
        ],
        rebuild=args.rebuild_scalelsd_proposal_exporter,
    )


def compile_geocalib_prior_exporter(args: argparse.Namespace) -> Path:
    return compile_swift_exporter(
        exporter=args.geocalib_prior_exporter,
        sources=[
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightGeometry.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightLineDetection.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightGeoCalibNeuralOutput.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightGeoCalibCoreML.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightGeoCalibOptimizer.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightGeoCalibPreprocessGeometry.swift",
            DEFAULT_REPO_ROOT / "AnyUpright" / "Plugin" / "AnyUprightGeoCalibHorizonDetector.swift",
            DEFAULT_REPO_ROOT / "tools" / "export-geocalib-camera-priors.swift",
        ],
        rebuild=args.rebuild_geocalib_prior_exporter,
    )


def detect_lines_scalelsd_coreml_batch(
    loaded_samples: list[LoadedSample],
    args: argparse.Namespace,
) -> dict[str, EvaluatedSampleInput]:
    work_parent = args.workspace / "work"
    work_parent.mkdir(parents=True, exist_ok=True)

    if args.keep_scalelsd_work:
        temp_context = None
        temp_root = work_parent / "holicity_scalelsd_coreml"
        if temp_root.exists():
            shutil.rmtree(temp_root)
        temp_root.mkdir(parents=True, exist_ok=True)
    else:
        temp_context = tempfile.TemporaryDirectory(prefix="holicity_scalelsd_coreml_", dir=work_parent)
        temp_root = Path(temp_context.name)

    try:
        cache_path = args.scalelsd_lines_cache
        if cache_path is not None and cache_path.exists():
            output_path = cache_path
            elapsed_ms = 0.0
        else:
            exporter = compile_scalelsd_exporter(args)
            manifest_samples: list[dict[str, object]] = []
            for loaded in loaded_samples:
                height, width = loaded.image.shape[:2]
                gray = cv2.cvtColor(loaded.image, cv2.COLOR_BGR2GRAY)
                resized = cv2.resize(gray, (512, 512))
                input_tensor = np.ascontiguousarray(resized.astype(np.float32) / 255.0)
                input_name = loaded.sample.stem.replace("/", "__").replace("\\", "__")
                input_path = temp_root / f"{input_name}.f32"
                input_tensor.tofile(input_path)
                manifest_samples.append(
                    {
                        "stem": loaded.sample.stem,
                        "width": width,
                        "height": height,
                        "input_f32_path": str(input_path),
                    }
                )

            manifest_path = temp_root / "manifest.json"
            output_path = temp_root / "scalelsd-lines.json"
            manifest_path.write_text(json.dumps({"samples": manifest_samples}, indent=2) + "\n", encoding="utf-8")
            start = time.perf_counter()
            subprocess.run(
                [
                    str(exporter),
                    "--manifest",
                    str(manifest_path),
                    "--model",
                    str(args.scalelsd_model),
                    "--compute-units",
                    args.scalelsd_compute_units,
                    "--output",
                    str(output_path),
                ],
                cwd=DEFAULT_REPO_ROOT,
                check=True,
            )
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            if cache_path is not None:
                cache_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(output_path, cache_path)
                output_path = cache_path

        payload = json.loads(output_path.read_text(encoding="utf-8"))

        loaded_by_stem = {loaded.sample.stem: loaded for loaded in loaded_samples}
        exported_by_stem = {exported["stem"]: exported for exported in payload["results"]}
        missing_stems = sorted(set(loaded_by_stem) - set(exported_by_stem))
        if missing_stems:
            raise ValueError(
                f"ScaleLSD line cache is missing {len(missing_stems)} requested stems; "
                f"first missing stem: {missing_stems[0]}"
            )
        selected_exports = [exported_by_stem[loaded.sample.stem] for loaded in loaded_samples]

        if args.geocalib_priors_cache is not None:
            priors_by_stem = load_or_export_geocalib_priors(loaded_samples, args, temp_root)
            for exported in selected_exports:
                exported["camera_prior"] = priors_by_stem[exported["stem"]]

        proposals_by_stem: dict[str, dict[str, object]] = {}
        if args.evaluate_scalelsd_proposals:
            proposal_exporter = compile_scalelsd_proposal_exporter(args)
            proposal_input_path = temp_root / "proposal-input.json"
            proposal_output_path = temp_root / "upright-proposals.json"
            proposal_input_path.write_text(
                json.dumps({"results": selected_exports}, indent=2) + "\n",
                encoding="utf-8",
            )
            subprocess.run(
                [
                    str(proposal_exporter),
                    "--input",
                    str(proposal_input_path),
                    "--mode",
                    args.mode,
                    "--output",
                    str(proposal_output_path),
                ],
                cwd=DEFAULT_REPO_ROOT,
                check=True,
            )
            proposal_payload = json.loads(proposal_output_path.read_text(encoding="utf-8"))
            proposals_by_stem = {
                proposal["stem"]: proposal
                for proposal in proposal_payload["results"]
            }

        per_sample_elapsed_ms = elapsed_ms / max(1, len(loaded_samples))
        result: dict[str, EvaluatedSampleInput] = {}
        for exported in selected_exports:
            stem = exported["stem"]
            loaded = loaded_by_stem[stem]
            lines = [
                LineSegment(
                    float(candidate["start"]["x"]),
                    float(candidate["start"]["y"]),
                    float(candidate["end"]["x"]),
                    float(candidate["end"]["y"]),
                    float(candidate["score"]),
                )
                for candidate in exported.get("candidates", [])
            ]
            result[stem] = EvaluatedSampleInput(
                sample=loaded.sample,
                image=loaded.image,
                camera=loaded.camera,
                vpts=loaded.vpts,
                confidence=loaded.confidence,
                lines=lines,
                detector_elapsed_ms=per_sample_elapsed_ms,
                proposal=proposals_by_stem.get(stem),
            )
        return result
    finally:
        if temp_context is not None:
            temp_context.cleanup()


def load_or_export_geocalib_priors(
    loaded_samples: list[LoadedSample],
    args: argparse.Namespace,
    temp_root: Path,
) -> dict[str, dict[str, object]]:
    cache_path = args.geocalib_priors_cache
    assert cache_path is not None
    if cache_path.exists():
        payload = json.loads(cache_path.read_text(encoding="utf-8"))
    else:
        exporter = compile_geocalib_prior_exporter(args)
        models = sorted(args.geocalib_model_directory.glob("*.mlmodelc"))
        if not models:
            raise FileNotFoundError(f"no GeoCalib .mlmodelc resources in {args.geocalib_model_directory}")
        manifest_samples: list[dict[str, object]] = []
        for loaded in loaded_samples:
            height, width = loaded.image.shape[:2]
            rgb = cv2.cvtColor(loaded.image, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
            input_tensor = np.ascontiguousarray(np.transpose(rgb, (2, 0, 1)))
            input_name = loaded.sample.stem.replace("/", "__").replace("\\", "__")
            input_path = temp_root / f"{input_name}.rgb.f32"
            input_tensor.tofile(input_path)
            manifest_samples.append(
                {
                    "stem": loaded.sample.stem,
                    "width": width,
                    "height": height,
                    "rgb_nchw_f32_path": str(input_path),
                }
            )
        manifest_path = temp_root / "geocalib-manifest.json"
        output_path = temp_root / "geocalib-priors.json"
        manifest_path.write_text(json.dumps({"samples": manifest_samples}, indent=2) + "\n", encoding="utf-8")
        command = [
            str(exporter),
            "--manifest",
            str(manifest_path),
            "--compute-units",
            args.geocalib_compute_units,
            "--output",
            str(output_path),
        ]
        for model in models:
            command.extend(["--model", str(model)])
        subprocess.run(command, cwd=DEFAULT_REPO_ROOT, check=True)
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(output_path, cache_path)
        payload = json.loads(cache_path.read_text(encoding="utf-8"))

    priors_by_stem = {prior["stem"]: prior for prior in payload["results"]}
    missing_stems = sorted({loaded.sample.stem for loaded in loaded_samples} - set(priors_by_stem))
    if missing_stems:
        raise ValueError(
            f"GeoCalib prior cache is missing {len(missing_stems)} requested stems; "
            f"first missing stem: {missing_stems[0]}"
        )
    return priors_by_stem


def lines_similar(lhs: LineSegment, rhs: LineSegment) -> bool:
    if angle_distance(lhs.angle_radians, rhs.angle_radians) > math.radians(3.0):
        return False
    lhs_mid = ((lhs.x1 + lhs.x2) * 0.5, (lhs.y1 + lhs.y2) * 0.5)
    rhs_mid = ((rhs.x1 + rhs.x2) * 0.5, (rhs.y1 + rhs.y2) * 0.5)
    return math.hypot(lhs_mid[0] - rhs_mid[0], lhs_mid[1] - rhs_mid[1]) < 12.0


def point_line_distance(point: np.ndarray, line: LineSegment) -> float:
    x0, y0 = float(point[0]), float(point[1])
    x1, y1, x2, y2 = line.x1, line.y1, line.x2, line.y2
    denominator = max(1e-9, math.hypot(x2 - x1, y2 - y1))
    return abs((y2 - y1) * x0 - (x2 - x1) * y0 + x2 * y1 - y2 * x1) / denominator


def classify_vp_orientation(vp: np.ndarray, width: int, height: int) -> str:
    cx = (width - 1) * 0.5
    cy = (height - 1) * 0.5
    dx = abs(float(vp[0]) - cx)
    dy = abs(float(vp[1]) - cy)
    if dy > dx * 1.25:
        return "vertical"
    if dx > dy * 1.25:
        return "horizontal"
    return "diagonal"


def ground_truth_vp_orientations(
    vpts: np.ndarray,
    camera: dict[str, np.ndarray],
) -> list[str]:
    pitch = math.radians(float(np.asarray(camera["pitch"]).item()))
    expected_gravity = np.asarray([0.0, math.cos(pitch), -math.sin(pitch)], dtype=np.float64)
    normalized = vpts / np.maximum(np.linalg.norm(vpts, axis=1, keepdims=True), 1e-12)
    vertical_index = int(np.argmax(np.abs(normalized @ expected_gravity)))
    return ["vertical" if index == vertical_index else "horizontal" for index in range(len(vpts))]


def proposal_line(line: dict[str, object]) -> LineSegment:
    start = line["start"]
    end = line["end"]
    assert isinstance(start, dict) and isinstance(end, dict)
    return LineSegment(
        float(start["x"]),
        float(start["y"]),
        float(end["x"]),
        float(end["y"]),
        float(line["score"]),
    )


def evaluate_selected_pair(
    pair: object,
    orientation: str,
    projected_vps: np.ndarray,
    vp_orientations: list[str],
    width: int,
    height: int,
    distance_ratio: float,
) -> dict[str, object]:
    if not isinstance(pair, dict):
        return {
            "selected": False,
            "correct": False,
            "gt_vp_index": None,
            "best_pair_distance_ratio": None,
        }

    first = proposal_line(pair["first_line"])
    second = proposal_line(pair["second_line"])
    diagonal = math.hypot(width, height)
    best_index: int | None = None
    best_distance: float | None = None
    for index, vp in enumerate(projected_vps):
        if vp_orientations[index] != orientation:
            continue
        distance = max(
            point_line_distance(vp, first) / diagonal,
            point_line_distance(vp, second) / diagonal,
        )
        if best_distance is None or distance < best_distance:
            best_index = index
            best_distance = distance

    return {
        "selected": True,
        "correct": best_distance is not None and best_distance <= distance_ratio,
        "gt_vp_index": best_index,
        "best_pair_distance_ratio": best_distance,
    }


def proposal_gt_axis_residual_degrees(
    matrix_values: object,
    projected_vps: np.ndarray,
    gt_vp_index: object,
    orientation: str,
    diagonal: float,
) -> float | None:
    if not isinstance(matrix_values, list) or len(matrix_values) != 9:
        return None
    if not isinstance(gt_vp_index, int) or not 0 <= gt_vp_index < len(projected_vps):
        return None
    output_to_source = np.asarray(matrix_values, dtype=np.float64).reshape(3, 3)
    try:
        source_to_output = np.linalg.inv(output_to_source)
    except np.linalg.LinAlgError:
        return None
    vp = projected_vps[gt_vp_index]
    transformed = source_to_output @ np.asarray([float(vp[0]), float(vp[1]), 1.0])
    x, y, z = [float(value) for value in transformed]
    if not all(math.isfinite(value) for value in (x, y, z)):
        return None
    finite_component = z * diagonal
    if orientation == "vertical":
        return math.degrees(math.atan2(math.hypot(x, finite_component), max(1e-12, abs(y))))
    return math.degrees(math.atan2(math.hypot(y, finite_component), max(1e-12, abs(x))))


def evaluate_sample(evaluated: EvaluatedSampleInput, args: argparse.Namespace) -> dict[str, object]:
    start = time.perf_counter()
    image = evaluated.image
    height, width = image.shape[:2]
    projected = project_vpts(evaluated.vpts, width, height, float(np.asarray(evaluated.camera["fov"]).item()))
    vp_orientations = ground_truth_vp_orientations(evaluated.vpts, evaluated.camera)
    lines = evaluated.lines
    diagonal = math.hypot(width, height)
    threshold = diagonal * args.vp_distance_ratio

    vp_summaries: list[dict[str, object]] = []
    vertical_hit_counts: list[int] = []
    horizontal_hit_counts: list[int] = []
    best_vertical: list[float] = []
    best_horizontal: list[float] = []
    for index, vp in enumerate(projected):
        orientation = vp_orientations[index]
        distances = sorted(point_line_distance(vp, line) / diagonal for line in lines)
        hit_count = sum(distance <= args.vp_distance_ratio for distance in distances)
        best = distances[0] if distances else None
        if orientation == "vertical":
            vertical_hit_counts.append(hit_count)
            if best is not None:
                best_vertical.append(best)
        elif orientation == "horizontal":
            horizontal_hit_counts.append(hit_count)
            if best is not None:
                best_horizontal.append(best)
        vp_summaries.append(
            {
                "index": index,
                "orientation": orientation,
                "confidence": float(evaluated.confidence[index]) if index < len(evaluated.confidence) else None,
                "x": float(vp[0]),
                "y": float(vp[1]),
                "z": float(vp[2]),
                "best_distance_ratio": best,
                "hit_count": hit_count,
            }
        )

    elapsed_ms = (time.perf_counter() - start) * 1000.0
    vertical_hits = max(vertical_hit_counts, default=0)
    horizontal_hits = max(horizontal_hit_counts, default=0)
    result: dict[str, object] = {
        "stem": evaluated.sample.stem,
        "detector": args.detector,
        "mode": args.mode,
        "width": width,
        "height": height,
        "line_count": len(lines),
        "vertical_vp_count": sum(1 for item in vp_summaries if item["orientation"] == "vertical"),
        "horizontal_vp_count": sum(1 for item in vp_summaries if item["orientation"] == "horizontal"),
        "vertical_hit_count": vertical_hits,
        "horizontal_hit_count": horizontal_hits,
        "vertical_pair_available": vertical_hits >= 2,
        "horizontal_pair_available": horizontal_hits >= 2,
        "full_pair_available": vertical_hits >= 2 and horizontal_hits >= 2,
        "best_vertical_distance_ratio": min(best_vertical) if best_vertical else None,
        "best_horizontal_distance_ratio": min(best_horizontal) if best_horizontal else None,
        "detector_elapsed_ms": evaluated.detector_elapsed_ms,
        "evaluation_elapsed_ms": elapsed_ms,
        "elapsed_ms": evaluated.detector_elapsed_ms + elapsed_ms,
        "vps": vp_summaries,
        "distance_threshold_pixels": threshold,
    }

    proposal = evaluated.proposal
    if proposal is not None:
        vertical_pair = evaluate_selected_pair(
            proposal.get("vertical_pair"),
            "vertical",
            projected,
            vp_orientations,
            width,
            height,
            args.vp_distance_ratio,
        )
        horizontal_pair = evaluate_selected_pair(
            proposal.get("horizontal_pair"),
            "horizontal",
            projected,
            vp_orientations,
            width,
            height,
            args.vp_distance_ratio,
        )
        if args.mode == "vertical":
            selected_mode_correct = bool(vertical_pair["correct"])
        elif args.mode == "horizontal":
            selected_mode_correct = bool(horizontal_pair["correct"])
        else:
            selected_mode_correct = bool(vertical_pair["correct"] and horizontal_pair["correct"])
        accepted = bool(proposal.get("accepted", False))
        matrix_values = proposal.get("output_to_source_matrix")
        result.update(
            {
                "proposal_accepted": accepted,
                "proposal_rejection_reason": proposal.get("rejection_reason"),
                "selected_vertical_pair_correct": vertical_pair["correct"],
                "selected_horizontal_pair_correct": horizontal_pair["correct"],
                "selected_mode_correct": selected_mode_correct,
                "proposal_correct_accept": accepted and selected_mode_correct,
                "proposal_false_accept": accepted and not selected_mode_correct,
                "selected_vertical_pair_distance_ratio": vertical_pair["best_pair_distance_ratio"],
                "selected_horizontal_pair_distance_ratio": horizontal_pair["best_pair_distance_ratio"],
                "proposal_vertical_support_count": (
                    proposal["vertical_pair"].get("support_count")
                    if isinstance(proposal.get("vertical_pair"), dict)
                    else None
                ),
                "proposal_horizontal_support_count": (
                    proposal["horizontal_pair"].get("support_count")
                    if isinstance(proposal.get("horizontal_pair"), dict)
                    else None
                ),
                "proposal_vertical_residual_degrees": proposal.get("vertical_residual_degrees"),
                "proposal_horizontal_residual_degrees": proposal.get("horizontal_residual_degrees"),
                "proposal_gt_vertical_axis_residual_degrees": proposal_gt_axis_residual_degrees(
                    matrix_values,
                    projected,
                    vertical_pair["gt_vp_index"],
                    "vertical",
                    diagonal,
                ),
                "proposal_gt_horizontal_axis_residual_degrees": proposal_gt_axis_residual_degrees(
                    matrix_values,
                    projected,
                    horizontal_pair["gt_vp_index"],
                    "horizontal",
                    diagonal,
                ),
                "proposal_auto_crop_scale": proposal.get("auto_crop_scale"),
            }
        )
    return result


def aggregate(results: list[dict[str, object]]) -> dict[str, object]:
    count = len(results)
    if count == 0:
        return {"image_count": 0}

    def count_true(key: str) -> int:
        return sum(1 for result in results if result[key])

    summary: dict[str, object] = {
        "image_count": count,
        "vertical_pair_available": count_true("vertical_pair_available"),
        "horizontal_pair_available": count_true("horizontal_pair_available"),
        "full_pair_available": count_true("full_pair_available"),
        "mean_line_count": float(np.mean([result["line_count"] for result in results])),
        "mean_detector_elapsed_ms": float(np.mean([result["detector_elapsed_ms"] for result in results])),
        "mean_elapsed_ms": float(np.mean([result["elapsed_ms"] for result in results])),
        "median_elapsed_ms": float(np.median([result["elapsed_ms"] for result in results])),
    }
    proposal_results = [result for result in results if "proposal_accepted" in result]
    if proposal_results:
        accepted = [result for result in proposal_results if result["proposal_accepted"]]
        false_accepts = [result for result in accepted if result["proposal_false_accept"]]
        rejection_reasons: dict[str, int] = {}
        for result in proposal_results:
            reason = result.get("proposal_rejection_reason")
            if isinstance(reason, str):
                rejection_reasons[reason] = rejection_reasons.get(reason, 0) + 1

        accepted_gt_residuals: list[float] = []
        for result in accepted:
            if not result["selected_mode_correct"]:
                continue
            residuals = [
                float(value)
                for key in (
                    "proposal_gt_vertical_axis_residual_degrees",
                    "proposal_gt_horizontal_axis_residual_degrees",
                )
                if (value := result.get(key)) is not None
            ]
            if residuals:
                accepted_gt_residuals.append(max(residuals))

        summary.update(
            {
                "proposal_count": len(proposal_results),
                "proposal_accepted": len(accepted),
                "proposal_rejected": len(proposal_results) - len(accepted),
                "proposal_coverage": len(accepted) / len(proposal_results),
                "proposal_selected_vertical_pair_correct": sum(
                    bool(result["selected_vertical_pair_correct"])
                    for result in proposal_results
                ),
                "proposal_selected_horizontal_pair_correct": sum(
                    bool(result["selected_horizontal_pair_correct"])
                    for result in proposal_results
                ),
                "proposal_selected_mode_correct": sum(
                    bool(result["selected_mode_correct"])
                    for result in proposal_results
                ),
                "proposal_correct_accept": sum(
                    bool(result["proposal_correct_accept"])
                    for result in proposal_results
                ),
                "proposal_false_accept": len(false_accepts),
                "proposal_false_accept_rate": len(false_accepts) / len(accepted) if accepted else None,
                "proposal_rejection_reasons": rejection_reasons,
                "proposal_gt_axis_residual_p95_degrees": (
                    float(np.percentile(accepted_gt_residuals, 95))
                    if accepted_gt_residuals
                    else None
                ),
            }
        )
    return summary


def write_outputs(output_dir: Path, results: list[dict[str, object]], summary: dict[str, object]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    (output_dir / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    with (output_dir / "results.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "stem",
                "width",
                "height",
                "detector",
                "mode",
                "line_count",
                "vertical_hit_count",
                "horizontal_hit_count",
                "vertical_pair_available",
                "horizontal_pair_available",
                "full_pair_available",
                "best_vertical_distance_ratio",
                "best_horizontal_distance_ratio",
                "detector_elapsed_ms",
                "evaluation_elapsed_ms",
                "elapsed_ms",
                "proposal_accepted",
                "proposal_rejection_reason",
                "selected_vertical_pair_correct",
                "selected_horizontal_pair_correct",
                "selected_mode_correct",
                "proposal_correct_accept",
                "proposal_false_accept",
                "selected_vertical_pair_distance_ratio",
                "selected_horizontal_pair_distance_ratio",
                "proposal_gt_vertical_axis_residual_degrees",
                "proposal_gt_horizontal_axis_residual_degrees",
                "proposal_auto_crop_scale",
            ],
        )
        writer.writeheader()
        for result in results:
            writer.writerow({field: result.get(field) for field in writer.fieldnames})


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, default=DEFAULT_WORKSPACE)
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--image-set", choices=["test-valid", "train"], default="test-valid")
    parser.add_argument("--limit", type=int, default=100)
    parser.add_argument("--seed", type=int, default=20260704)
    parser.add_argument("--detector", choices=["opencv", "scalelsd-coreml"], default="opencv")
    parser.add_argument("--mode", choices=["vertical", "horizontal", "full"], default="full")
    parser.add_argument("--max-side", type=int, default=768)
    parser.add_argument("--lsd-limit", type=int, default=80)
    parser.add_argument("--hough-limit", type=int, default=40)
    parser.add_argument("--vp-distance-ratio", type=float, default=0.02)
    parser.add_argument("--scalelsd-model", type=Path, default=DEFAULT_SCALELSD_MODEL)
    parser.add_argument("--scalelsd-exporter", type=Path, default=DEFAULT_SCALELSD_EXPORTER)
    parser.add_argument("--scalelsd-compute-units", choices=["all", "cpu", "cpuAndGPU", "cpuAndNeuralEngine"], default="all")
    parser.add_argument("--rebuild-scalelsd-exporter", action="store_true")
    parser.add_argument("--keep-scalelsd-work", action="store_true")
    parser.add_argument("--scalelsd-lines-cache", type=Path, default=None)
    parser.add_argument("--evaluate-scalelsd-proposals", action="store_true")
    parser.add_argument("--scalelsd-proposal-exporter", type=Path, default=DEFAULT_SCALELSD_PROPOSAL_EXPORTER)
    parser.add_argument("--rebuild-scalelsd-proposal-exporter", action="store_true")
    parser.add_argument("--geocalib-priors-cache", type=Path, default=None)
    parser.add_argument("--geocalib-prior-exporter", type=Path, default=DEFAULT_GEOCALIB_PRIOR_EXPORTER)
    parser.add_argument("--rebuild-geocalib-prior-exporter", action="store_true")
    parser.add_argument("--geocalib-model-directory", type=Path, default=DEFAULT_GEOCALIB_MODEL_DIRECTORY)
    parser.add_argument("--geocalib-compute-units", choices=["all", "cpu", "cpuAndGPU", "cpuAndNeuralEngine"], default="all")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.output is None:
        suffix = args.detector.replace("-", "_")
        args.output = DEFAULT_OUTPUT if args.detector == "opencv" else DEFAULT_OUTPUT.with_name(f"{DEFAULT_OUTPUT.name}_{suffix}_{args.mode}")

    samples = build_samples(args.workspace, args.image_set, args.limit, args.seed)
    if not samples:
        raise SystemExit("no matching HoliCity samples found")

    loaded_samples = [load_sample(sample) for sample in samples]
    if args.detector == "opencv":
        evaluated_inputs = {
            loaded.sample.stem: detect_lines_opencv(loaded, args)
            for loaded in loaded_samples
        }
    else:
        evaluated_inputs = detect_lines_scalelsd_coreml_batch(loaded_samples, args)

    results: list[dict[str, object]] = []
    for index, sample in enumerate(samples, start=1):
        result = evaluate_sample(evaluated_inputs[sample.stem], args)
        results.append(result)
        if index == 1 or index % 10 == 0 or index == len(samples):
            proposal_status = ""
            if "proposal_accepted" in result:
                proposal_status = (
                    f" proposal={'accepted' if result['proposal_accepted'] else result['proposal_rejection_reason']}"
                    f" correct={result['selected_mode_correct']}"
                )
            print(
                f"{index}/{len(samples)} {sample.stem} "
                f"lines={result['line_count']} "
                f"v={result['vertical_hit_count']} h={result['horizontal_hit_count']} "
                f"full={result['full_pair_available']}{proposal_status}",
                flush=True,
            )

    summary = {
        "workspace": str(args.workspace),
        "image_set": args.image_set,
        "limit": args.limit,
        "seed": args.seed,
        "detector": args.detector,
        "mode": args.mode,
        "max_side": args.max_side,
        "vp_distance_ratio": args.vp_distance_ratio,
        "scalelsd_model": str(args.scalelsd_model) if args.detector == "scalelsd-coreml" else None,
        "scalelsd_compute_units": args.scalelsd_compute_units if args.detector == "scalelsd-coreml" else None,
        "scalelsd_lines_cache": (
            str(args.scalelsd_lines_cache)
            if args.detector == "scalelsd-coreml" and args.scalelsd_lines_cache is not None
            else None
        ),
        "evaluate_scalelsd_proposals": (
            args.evaluate_scalelsd_proposals if args.detector == "scalelsd-coreml" else False
        ),
        "geocalib_priors_cache": (
            str(args.geocalib_priors_cache)
            if args.detector == "scalelsd-coreml" and args.geocalib_priors_cache is not None
            else None
        ),
        **aggregate(results),
    }
    write_outputs(args.output, results, summary)
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
