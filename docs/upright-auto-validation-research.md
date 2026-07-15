# Upright Auto Validation Research Notes

This note records the current validation status for automatic `AnyUpright Upright`
candidate selection and the near-term external datasets worth using for broader
validation. It is separate from `docs/horizon-rotation-research.md`, which is
scoped to roll-only Horizon behavior.

Research snapshot date: 2026-07-03.

Local experiment workspace:
`/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory`.

Primary local evidence file:
`/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/VALID_RESULTS.json`.

## Current Algorithm Sufficiency

The current M-LSD large Core ML path plus clipping and the `pair` ranker is good
enough for semi-auto guide proposal. It is not yet enough to treat Vertical,
Horizontal, or Full as production-ready true auto writeback without additional
geometry validation and rejection policy.

Key local results from `VALID_RESULTS.json`:

| Check | Result |
| --- | ---: |
| M-LSD large Core ML candidate-level endpoint drift within 2 percent | 217 / 217 |
| M-LSD large Core ML mean total time | 70.94 ms |
| M-LSD large Core ML max total time | 80.75 ms |
| M-LSD module-boundary layers within 1 percent Linf | 336 / 336 |
| M-LSD leaf layers within 1 percent Linf | 477 / 477 |
| Upright vertical images with a guide pair | 216 / 217 |
| Upright horizontal images with a guide pair | 216 / 217 |
| Upright full images with guide pairs | 215 / 217 |
| Upright full images with at least two candidates in each orientation | 217 / 217 |
| Vertical images with two matched GT lines | 178 / 217 |
| Horizontal images with two matched GT lines | 202 / 217 |

Practical read:

- Vertical auto is close to an experimental mode, but it still needs final
  transform validation, confidence gating, and host/manual spot checks before
  automatic writeback is safe.
- Horizontal auto is also close, but the evidence is slightly weaker than the
  raw guide-pair rate suggests because correct-line matching is not perfect.
- Full auto is not ready. It needs robust direction-family selection,
  vanishing-point or Manhattan-family solving, transform sanity checks, and a
  conservative reject/no-writeback path.
- Semi-auto can use the current detector/ranker now because user selection is
  still the final disambiguation step.

## Recommended External Datasets

The four most useful next validation datasets are listed below. Download status
and size are based on public pages and public repository APIs checked on
2026-07-03. Treat these as planning numbers, not a guarantee that future hosting
or access terms remain unchanged.

| Dataset | Public direct download? | Public size for complete usable data | Why it is useful here | Notes |
| --- | --- | ---: | --- | --- |
| NYU-VP + NYU Depth V2 labeled | Yes for VP labels and NYU Depth V2 labeled MAT file | NYU Depth V2 labeled MAT: 2,972,037,809 bytes, 2.972 GB, 2.768 GiB. NYU-VP GitHub API repo size: about 52.5 MB; a local shallow clone measured 167 MB with 116 MB under `data/`. | Best quick real indoor vanishing-point validation for Vertical, Horizontal, and Full candidate selection. | NYU-VP labels require the NYU Depth V2 labeled MAT file to load original RGB images. The full raw NYU Depth V2 video dataset is separately listed by NYU as about 428 GB and is not needed for the first VP validation pass. |
| Horizon Lines in the Wild (HLW) | No direct public file link found; official page asks users to submit an access request. | Not publicly listed. | Useful for roll/horizon-line validation and reject-policy checks, not sufficient proof for Upright Vertical/Horizontal/Full perspective auto. | The official page describes a large horizon-line dataset; the paper reports 100,553 images and 2,018 evaluation images. No official compressed size was found on the public page or paper. |
| Structured3D | Not direct public download from official page; access is provided after submitting the agreement form. | Official complete package size was not found on the public page. A restricted Hugging Face package `Gen3DF/Structured3D` exposes 14,978,703,021 bytes, 14.979 GB, 13.950 GiB for its visible `pcd`/`layout` package, but this should not be treated as the official full rendered Structured3D size. | Strong synthetic indoor validation source for clean geometry, layout, lines, and Full-mode rectification behavior. | Use after NYU-VP when clean ground truth matters more than real-image distribution. Verify the exact downloadable package after agreement access is granted. |
| HoliCity | Yes, for the public Hugging Face files linked from the project website, subject to terms of use. | Hugging Face downloadable files counted by subdirectory: 276,915,789,624 bytes, 276.916 GB, 257.898 GiB, excluding external CAD licensing/downloads. | Best real outdoor/city validation source among the four, especially for line families, vanishing points, and hard Full-mode cases. | The project site links scene downloads for panorama/split and perspective downloads for image, camera, depth, normal, plane, semantic, and vanishing points. CAD data is linked externally through AccuCities and should be handled as a separate access/licensing item. |

HoliCity public Hugging Face size breakdown:

| Component | Bytes | Decimal GB | Binary GiB |
| --- | ---: | ---: | ---: |
| `panorama/panorama-image` | 92,298,308,199 | 92.298 | 85.959 |
| `panorama/panorama-depth` | 109,518,031,275 | 109.518 | 101.997 |
| `panorama/panorama-camera.tar.xz` | 530,000 | 0.001 | 0.000 |
| `perspective` | 75,097,840,985 | 75.098 | 69.940 |
| `split` | 1,079,165 | 0.001 | 0.001 |
| Total | 276,915,789,624 | 276.916 | 257.898 |

HoliCity perspective sub-breakdown:

| Component | Bytes | Decimal GB |
| --- | ---: | ---: |
| `perspective/image-v1` | 6,361,405,039 | 6.361 |
| `perspective/image-v1-test-valid.tar` | 633,436,160 | 0.633 |
| `perspective/camr-v1.tar` | 153,681,920 | 0.154 |
| `perspective/depth-v1` | 26,276,288,712 | 26.276 |
| `perspective/normal-v1` | 40,854,740,514 | 40.855 |
| `perspective/plane-v1.tar` | 524,441,600 | 0.524 |
| `perspective/planes-v1-test-valid.tar` | 52,592,640 | 0.053 |
| `perspective/segmentation-v1.tar` | 164,413,440 | 0.164 |
| `perspective/vpts-v1.tar` | 76,840,960 | 0.077 |

Recommended HoliCity download plan for AnyUpright:

| Asset group | Download? | Size | Reason |
| --- | --- | ---: | --- |
| `perspective/image-v1/*` and `perspective/image-v1-test-valid.tar` | Yes, default | 6.995 GB | Required input RGB images for M-LSD detection and visual inspection. |
| `perspective/camr-v1.tar` | Yes, default | 0.154 GB | Camera metadata for geometry sanity checks. |
| `perspective/vpts-v1.tar` | Yes, default | 0.077 GB | Direct vanishing-point labels for direction-family and Full-mode validation. |
| `split/*.zip` | Yes, default | 0.001 GB | Official split metadata. |
| `perspective/segmentation-v1.tar` | Yes, default | 0.164 GB | Small enough to include; useful for filtering sky, road, and building cases. |
| `perspective/plane-v1.tar` and `perspective/planes-v1-test-valid.tar` | Optional | 0.577 GB | Useful only when validating against fitted planes or diagnosing geometry misses. |
| `perspective/depth-v1/*` | Optional | 26.276 GB | Not needed when camera and VP labels are enough; use only to derive additional 3D checks. |
| `perspective/normal-v1/*` | Optional | 40.855 GB | Not needed for the first VP/line validation pass; use only for normal-derived geometry checks. |
| `panorama/*` | No for the first pass | 201.817 GB | Source panoramas are not needed for validating the provided perspective renderings. |
| External CAD data | No for the first pass | not counted | Separate AccuCities access/licensing item; not needed for image-space Upright validation. |

The repo helper `tools/download-holicity-upright.py` downloads to
`/Volumes/4T/temp/AnyUprightResearchWorkspace` by default. Its default
`upright-core` preset downloads the first five rows above, about
7,390,856,684 bytes / 7.391 GB / 6.884 GiB. Larger data is opt-in:

```bash
python3 tools/download-holicity-upright.py --dry-run
python3 tools/download-holicity-upright.py --accept-terms
python3 tools/download-holicity-upright.py --accept-terms --include planes
python3 tools/download-holicity-upright.py --accept-terms --preset perspective-geometry
```

## HoliCity Validation Runs

The HoliCity validation helper is `tools/validate-holicity-upright.py`.
It reads HoliCity tar files directly from
`/Volumes/4T/temp/AnyUprightResearchWorkspace`, projects the provided 3D
vanishing-point directions into the image, detects line segments, and measures
whether at least two detected segments pass near the vertical and horizontal VP
families. It supports three detector backends:

- `--detector opencv` runs the original OpenCV LSD/Hough reference path.
- `--detector mlsd-coreml` decodes the HoliCity images in Python, writes a
  temporary RGBA manifest, compiles and calls
  `tools/export-mlsd-upright-candidates.swift`, and evaluates the Swift/Core ML
  M-LSD candidate output in the same VP-family metric.
- `--detector scalelsd-coreml` runs the fixed-512 ScaleLSD Core ML neural
  forward plus the official-equivalent Swift postprocessor. Raw lines can be
  persisted with `--scalelsd-lines-cache` so selector iterations do not rerun
  inference.

Initial 2026-07-04 smoke outputs:

| Output | Images | VP distance threshold | Vertical pair | Horizontal pair | Full pair | Mean time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `/Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_upright_validation_sample10` | 10 | 2% diagonal | 7 / 10 | 10 / 10 | 7 / 10 | 1028.6 ms |
| `/Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_upright_validation_sample100_thr001` | 100 | 1% diagonal | 63 / 100 | 82 / 100 | 50 / 100 | 1067.9 ms |
| `/Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_upright_validation_sample100` | 100 | 2% diagonal | 72 / 100 | 84 / 100 | 61 / 100 | 1049.4 ms |
| `/Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_upright_validation_sample100_thr003` | 100 | 3% diagonal | 75 / 100 | 87 / 100 | 65 / 100 | 1081.6 ms |

Swift/Core ML M-LSD outputs from the same 2026-07-04 harness:

| Output | Images | Mode | VP distance threshold | Vertical pair | Horizontal pair | Full pair | Mean line count | Mean detector time |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `/Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_upright_validation_mlsd_coreml_full_sample1` | 1 | full | 2% diagonal | 1 / 1 | 1 / 1 | 1 / 1 | 38.0 | 1960.6 ms |
| `/Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_upright_validation_mlsd_coreml_full_sample10` | 10 | full | 2% diagonal | 6 / 10 | 9 / 10 | 6 / 10 | 31.0 | 20.2 ms |
| `/Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_upright_validation_mlsd_coreml_full_sample100` | 100 | full | 2% diagonal | 82 / 100 | 76 / 100 | 62 / 100 | 33.49 | 10.6 ms |
| `/Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_upright_validation_mlsd_coreml_vertical_sample10` | 10 | vertical | 2% diagonal | 6 / 10 | 1 / 10 | 0 / 10 | 21.5 | 20.7 ms |
| `/Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_upright_validation_mlsd_coreml_horizontal_sample10` | 10 | horizontal | 2% diagonal | 2 / 10 | 9 / 10 | 2 / 10 | 24.4 | 91.7 ms |

ScaleLSD quality validation and Swift/Core ML migration snapshot from
2026-07-10:

| Backend | Images | Vertical pair | Horizontal pair | Full pair |
| --- | ---: | ---: | ---: | ---: |
| Official ScaleLSD Python, FP32 checkpoint | 100 | 96 / 100 | 98 / 100 | 94 / 100 |
| Official ScaleLSD Python, FP32 checkpoint | 2500 | 2386 / 2500 | 2415 / 2500 | 2301 / 2500 |
| ScaleLSD FP32 Core ML + Swift postprocess | 100 | 96 / 100 | 98 / 100 | 94 / 100 |
| ScaleLSD FP16 Core ML + Swift postprocess | 100 | 96 / 100 | 98 / 100 | 94 / 100 |

The fixed-shape migration uses a normalized grayscale `[1, 1, 512, 512]`
input and exports raw `[1, 9, 256, 256]` dense logits. The Core ML graph owns
only neural inference; Swift owns junction extraction, HAFM line decoding, and
wireframe support counting. On the deterministic postprocess fixture, Swift
decoded the same 119 official Python lines with zero coordinate drift from the
same PyTorch dense tensor. Using Core ML output, all 119 lines and support
scores still matched, with a maximum coordinate drift of about `3.05e-5`
pixels. FP32 Core ML raw-logit maximum absolute drift was about `2.86e-4`;
FP16 was about `7.37e-2`, but both precisions preserved every sample100
vertical/horizontal/full availability decision.

Current migration files:

- `tools/build-scalelsd-coreml.py` traces and converts the official fixed-shape
  neural forward, compiles the package, and emits PyTorch/Core ML fixtures.
- `AnyUprightScaleLSDPostprocessor.swift` implements official Python
  postprocessing in Swift.
- `AnyUprightScaleLSDCoreML.swift` loads the fixed Core ML graph and returns raw
  dense logits.
- `tools/export-scalelsd-upright-lines.swift` is the offline Swift/Core ML
  exporter used by the HoliCity harness.
- `tools/validate-holicity-upright.py --detector scalelsd-coreml` runs the same
  VP-family quality metric.
- `AnyUprightUprightProposal.swift` owns the detector-independent offline
  direction/VP grouping, same-VP pair ranking, mode selection, existing guided
  transform construction, crop validation, and structured rejection reasons.
- `tools/rank-scalelsd-upright-proposals.swift` exports that Swift ranker for
  the HoliCity harness.
- `tools/export-geocalib-camera-priors.swift` exports the existing fixed-shape
  GeoCalib gravity/FOV estimates used as an optional camera prior.

### ScaleLSD Proposal-Selection Baseline

The proposal stage was evaluated on the deterministic 100-image HoliCity
sample (`seed=20260704`, `2%` image-diagonal VP distance). The corrected raw
availability metric assigns the one gravity VP from camera pitch, treats the
other VPs as horizontal, and requires both lines to hit the same VP. This fixes
the earlier harness behavior that classified VPs from their 2D position and
summed hits across different VPs.

Corrected raw availability is `96/100` Vertical, `99/100` Horizontal, and
`95/100` Full. The current GeoCalib-prior selector baseline is:

| Mode | Selected pair(s) correct | Accepted | Correct accept | False accept | False-accept rate |
| --- | ---: | ---: | ---: | ---: | ---: |
| Vertical | 56 / 100 | 95 / 100 | 56 | 39 | 41.1% |
| Horizontal | 31 / 100 | 24 / 100 | 12 | 12 | 50.0% |
| Full | 7 / 100 | 86 / 100 | 5 | 81 | 94.2% |

Horizontal and Full require a second approximately orthogonal horizontal VP
cluster when a camera prior is present. This improves Horizontal selection but
does not make Full reliable: high-support wrong Manhattan-like clusters remain
common. GeoCalib uncertainty, line support, and crop scale did not isolate a
high-precision Full subset on this sample. The implemented path is therefore a
reproducible offline experiment only; it must not write production plug-in
parameters.

The completed 4,984-image FP16 Core ML run reported `4807/4984` Vertical,
`4803/4984` Horizontal, and `4626/4984` Full under the legacy availability
metric. Keep those numbers only as detector-run history; they are not directly
comparable to the corrected same-VP metric. A full corrected rerun can reuse a
persisted raw-line cache, but the original full run did not retain one.

This is still an offline migration path. The production Upright detector order
has not changed, and the plugin does not yet ship or load the ScaleLSD model.
Remaining production work includes plugin-side grayscale preprocessing,
resource/session ownership, candidate reduction/ranking, final-transform
validation, and conservative reject behavior.

Representative commands:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate-holicity-upright.py --detector opencv --limit 100 --vp-distance-ratio 0.02
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate-holicity-upright.py --detector mlsd-coreml --mode full --limit 100 --vp-distance-ratio 0.02
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate-holicity-upright.py --detector mlsd-coreml --mode vertical --limit 10 --vp-distance-ratio 0.02
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate-holicity-upright.py --detector mlsd-coreml --mode horizontal --limit 10 --vp-distance-ratio 0.02
PYTHONDONTWRITEBYTECODE=1 python3 tools/build-scalelsd-coreml.py --precision float16 --output /Volumes/4T/temp/AnyUprightResearchWorkspace/model_tests/scalelsd/coreml_conversion_fp16
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate-holicity-upright.py --detector scalelsd-coreml --mode full --limit 100 --vp-distance-ratio 0.02 --scalelsd-model /Volumes/4T/temp/AnyUprightResearchWorkspace/model_tests/scalelsd/coreml_conversion_fp16/compiled/scalelsd_neural_forward.mlmodelc
PYTHONDONTWRITEBYTECODE=1 python3 tools/validate-holicity-upright.py --detector scalelsd-coreml --mode full --limit 100 --seed 20260704 --vp-distance-ratio 0.02 --scalelsd-lines-cache /Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_scalelsd_coreml_fp16_testvalid_sample100_lines.json --geocalib-priors-cache /Volumes/4T/temp/AnyUprightResearchWorkspace/outputs/holicity_geocalib_testvalid_sample100_priors.json --evaluate-scalelsd-proposals
```

Interpretation:

- The downloaded HoliCity `upright-core` set is usable: image, camera, and VP
  stems align cleanly, and the VP projection/metric path produces stable
  per-image results.
- The OpenCV LSD/Hough reference path is much weaker than the current local
  M-LSD large evidence. Its 100-image Full pair result stays only `61/100` at
  the default 2% diagonal threshold, while threshold relaxation to 3% reaches
  only `65/100`.
- The Swift/Core ML M-LSD backend is now connected to the same HoliCity harness.
  At the default 2% diagonal threshold, the 100-image Full pair result is
  `62/100`, close to the OpenCV `61/100` Full-pair score, but with stronger
  individual vertical-pair availability (`82/100` vs. `72/100`) and weaker
  horizontal-pair availability (`76/100` vs. `84/100`) on this sample.
- The current VP-family metric is a candidate-availability smoke test. It does
  not validate the final transform, reject policy, or whether selected candidate
  pairs produce visually acceptable Upright writeback.
- The vertical/horizontal mode runs are mainly backend smoke tests. The summary
  still reports all VP-family fields from the shared metric, so non-target
  family counts can be nonzero when a line geometrically passes near another VP.
- ScaleLSD is substantially stronger on this candidate-availability metric,
  and the current FP32/FP16 Swift/Core ML sample100 results preserve the official
  Python quality decisions exactly. This does not yet prove production auto
  writeback because the metric does not score the selected transform.
- Next validation step: replace the current heuristic VP selector with a
  stronger calibrated Manhattan/VP solver, then validate its reject precision
  on a held-out HoliCity split and NYU-VP before considering plug-in writeback.

## Validation Order

Recommended order:

1. NYU-VP with NYU Depth V2 labeled images.
   Use this first because it is small enough to fit local iteration and has real
   indoor vanishing-point labels.
2. HLW only for roll/horizon rejection checks.
   Do not count HLW as evidence that Upright Full auto is correct.
3. Structured3D after access is granted.
   Use it for clean synthetic indoor geometry and stress cases where ground
   truth is easier to derive.
4. HoliCity once the pipeline can process a larger dataset.
   Use it as the outdoor/city stress test for direction-family selection,
   vanishing-point behavior, and false-positive rejection.

Datasets not in the first four:

- ScanNet can be useful for large real indoor stress testing, but deriving
  usable VP or upright labels from camera pose/surface normals adds more setup
  work than NYU-VP or Structured3D.
- SU3 / SceneCity-style synthetic city datasets may still be useful for clean
  outdoor geometry, but Structured3D and HoliCity currently have clearer access
  and size signals for this project.

## Source Pointers

- NYU Depth V2 official page:
  `https://cs.nyu.edu/~fergus/datasets/nyu_depth_v2.html`
- NYU Depth V2 labeled MAT file:
  `http://horatio.cs.nyu.edu/mit/silberman/nyu_depth_v2/nyu_depth_v2_labeled.mat`
- NYU-VP repository:
  `https://github.com/fkluger/nyu_vp`
- HLW official page:
  `https://mvrl.cse.wustl.edu/datasets/hlw/`
- HLW paper:
  `https://arxiv.org/abs/1604.02129`
- Structured3D official page:
  `https://structured3d-dataset.org/`
- Structured3D code repository:
  `https://github.com/bertjiazheng/Structured3D`
- HoliCity official page:
  `https://holicity.io/`
- HoliCity code repository:
  `https://github.com/zhou13/holicity`
- HoliCity Hugging Face repository:
  `https://huggingface.co/yichaozhou/holicity`
