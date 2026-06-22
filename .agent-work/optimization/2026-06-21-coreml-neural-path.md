# Swift Core ML Neural Path

## Goal

Migrate GeoCalib neural forward from the current correctness-oriented Swift/Metal runner to Swift Core ML or MPSGraph, while keeping Swift glue, verifier gate, and LM optimizer. Do not use lossy speed optimizations such as Float16 conversion, quantization, palettization, pruning, or lower-resolution model inputs as a substitute for performance.

## Success Criteria

- First target: 20 LaMAR2k images, per-run mean under 500 ms, no accuracy regression against the Python fixed-NMF baseline.
- Second target: 20 LaMAR2k images, per-run mean under 300 ms, no accuracy regression against the Python fixed-NMF baseline.
- Precision comparison must use Python as the authority. Swift/Core ML should be changed to match Python, not the reverse.

## Current Evidence

- Python fixed-NMF MPS full 2,000-image baseline: mean GeoCalib about 190 ms, mean total about 211 ms.
- Existing project-owned Swift/Metal full 2,000-image migration run: mean GeoCalib about 1130 ms, mean total about 1185 ms.
- Existing Python Core ML conversion experiment produced a neural-forward ML Program at `/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/geocalib_coreml_mlprogram_probe_8_v4/neural_forward/neural_forward.mlpackage`.
- That converted neural-forward model matched Python neural outputs on 8 same-shape images with max field differences around `1e-6`, and hybrid Swift/Python optimizer roll differences below `0.00004 deg`.

## Candidate Direction

Use the existing fixed-NMF neural-forward ML Program for the dense field prediction, then keep the existing Swift preprocessing, verifier estimates, gate policy, and `AUGeoCalibOptimizer` path. Start with a static-shape model for one common preprocessed shape, validate 20 images from that shape group, and only then decide whether to add grouped models or dynamic-shape conversion.

## Experiment Log

### 2026-06-21 Initial Direction

Status: active.

Planned test:

1. Inspect the ML Program input/output names and runtime precision.
2. Add a Swift Core ML neural session that returns `AUGeoCalibNeuralOutput`.
3. Extend the standalone 20-image validation tool with a Core ML neural mode.
4. Compare against Python fixed-NMF predictions for the same 20 filenames.

Result so far:

- Added a Swift Core ML neural session for the FP32 neural-forward ML Program.
- Added a detector entry point that accepts already-computed neural outputs and reuses the existing Swift optimizer/gate.
- One-image smoke with `95419735117.jpg` succeeded:
  - accepted
  - abs error: `0.198 deg`
  - detect time: `203.660 ms`
  - GeoCalib time: `297.122 ms`
  - total time: `370.067 ms`

### 2026-06-21 20-Image Core ML Target-500 Validation

Status: effective for the first target.

Command:

```sh
cd /Users/ibobby/Projects/AnyUpright
tools/run-swift-geocalib-full-validation.sh \
  --dataset /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/data/lamar2k \
  --out /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/swift_coreml_geocalib_20_target500_v1 \
  --coreml-model /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/geocalib_coreml_mlprogram_probe_8_v4/neural_forward/neural_forward.mlpackage \
  --image-list /Users/ibobby/Projects/AnyUpright/.agent-work/optimization/lamar2k-shape416x320-20.txt \
  --max-analysis-dimension 1920 \
  --verifier-max-dimension 640 \
  --progress-every 1
```

Result:

- Count: `20`
- Accepted: `16`
- All-image mean total: `186.948 ms`
- All-image p90 total: `189.819 ms`
- All-image max total: `327.419 ms`
- All-image mean GeoCalib: `138.718 ms`
- All-image max GeoCalib: `258.144 ms`
- All-image mean detect: `58.993 ms`
- All-image max detect: `167.294 ms`
- Swift/Core ML all-image MAE: `2.738985 deg`
- Python fixed-NMF subset MAE: `2.741177 deg`
- Swift/Core ML p90 AE: `6.036426 deg`
- Python fixed-NMF subset p90 AE: `6.336685 deg`
- Swift/Core ML within 2 deg: `80.0%`
- Python fixed-NMF subset within 2 deg: `80.0%`

Migration comparison:

```sh
/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/.conda/bin/python \
  /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/scripts/compare_geocalib_migration.py \
  --python /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/python_geocalib_lamar2k_2000_fixed_nmf_migration/geocalib/predictions.csv \
  --migrated /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/swift_coreml_geocalib_20_target500_v1/predictions.csv \
  --migrated-label swift_coreml \
  --out /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/swift_coreml_vs_python_geocalib_20_target500_v1
```

- Mean roll diff vs Python: `0.043770 deg`
- Median roll diff vs Python: `0.005941 deg`
- P90 roll diff vs Python: `0.061009 deg`
- Max roll diff vs Python: `0.371669 deg`
- Mean abs-error delta vs Python: `-0.002191 deg`
- P90 abs-error delta vs Python: `0.015362 deg`

Interpretation:

The Swift Core ML neural path meets the first target on this 20-image validation slice. It keeps the same FP32 model outputs exposed as MultiArrays, preserves the Swift optimizer/gate path, and does not show a material accuracy regression against Python fixed-NMF. The largest roll deltas are on already-rejected or high-error images, and aggregate subset accuracy is not worse than Python.

### 2026-06-21 Compute Units And Warm-Up

Status: mixed; warm-up effective, alternate compute-unit placement ineffective.

I tested three approaches after the first target:

| direction | result |
| --- | --- |
| `--coreml-compute-units cpuAndGPU` with `.mlpackage` | Ineffective. First image total rose to `418.423 ms`; all-image mean total `194.387 ms`. |
| `--coreml-compute-units cpuAndNeuralEngine` with `.mlpackage` | Ineffective. Stable frames moved near/above 300 ms; all-image mean total `301.781 ms`, p90 total `314.721 ms`. |
| Precompiled `.mlmodelc` without warm-up | Partially effective. First image total dropped from `327.419 ms` to `310.472 ms`, still above the 300 ms per-run target. |
| Precompiled `.mlmodelc` plus `--warmup-neural` | Effective. All 20 measured runs stayed below 300 ms; max total `203.247 ms`. |

The warm-up uses one untimed FP32 zero-input neural prediction to force Core ML's first prediction setup before timed image analysis. It does not change model precision, image preprocessing, model input shape, model outputs, Swift optimizer math, or gate policy.

Command:

```sh
cd /Users/ibobby/Projects/AnyUpright
xcrun coremlcompiler compile \
  /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/geocalib_coreml_mlprogram_probe_8_v4/neural_forward/neural_forward.mlpackage \
  /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/coreml_compiled_neural_forward_416x320

tools/run-swift-geocalib-full-validation.sh \
  --dataset /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/data/lamar2k \
  --out /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/swift_coreml_geocalib_20_warmup_target300_v1 \
  --coreml-model /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/coreml_compiled_neural_forward_416x320/neural_forward.mlmodelc \
  --warmup-neural \
  --image-list /Users/ibobby/Projects/AnyUpright/.agent-work/optimization/lamar2k-shape416x320-20.txt \
  --max-analysis-dimension 1920 \
  --verifier-max-dimension 640 \
  --progress-every 1
```

Result:

- Count: `20`
- Accepted: `16`
- All-image mean total: `176.740 ms`
- All-image p90 total: `185.804 ms`
- All-image max total: `203.247 ms`
- All-image mean GeoCalib: `129.460 ms`
- All-image max GeoCalib: `141.367 ms`
- All-image mean detect: `53.139 ms`
- All-image max detect: `60.657 ms`
- Swift/Core ML all-image MAE: `2.738985 deg`
- Swift/Core ML within 2 deg: `80.0%`

Migration comparison against Python fixed-NMF:

- Mean roll diff vs Python: `0.043770 deg`
- Median roll diff vs Python: `0.005941 deg`
- P90 roll diff vs Python: `0.061009 deg`
- Max roll diff vs Python: `0.371669 deg`
- Mean abs-error delta vs Python: `-0.002191 deg`
- P90 abs-error delta vs Python: `0.015362 deg`
- Python fixed-NMF subset MAE: `2.741177 deg`
- Python fixed-NMF subset p90 AE: `6.336685 deg`
- Python fixed-NMF subset within 2 deg: `80.0%`

Interpretation:

The second target is achieved for this 20-image validation slice when using the compiled FP32 ML Program and an explicit untimed neural warm-up. The useful optimization is avoiding first-prediction runtime setup in the measured analysis path, not changing precision or model behavior. For product integration, the warm-up should be tied to model/session initialization rather than to user-visible analysis timing.

### 2026-06-21 Shared Intersection Lossless Optimization

Status: effective for shared preprocessing; Core ML input reuse is correct but only a small contributor.

Scope:

This pass intentionally optimized only the intersection of the test harness and the intended plugin analysis path:

- Included: `AUGeoCalibImagePreprocessor.preprocessRGB`, Core ML neural input staging, neural output consumption by the existing Swift optimizer/gate, and the same verifier policy.
- Excluded: JPEG/disk dataset loading, CSV writing, Python comparison scripts, Final Cut/FxAnalysis scheduling, parameter writeback, and plugin-only frame acquisition overhead.

Changes:

| direction | result |
| --- | --- |
| Fuse resize and center-crop in `AUGeoCalibImagePreprocessor` | Correct and small by itself. It removes the intermediate full resized RGB tensor and the crop copy. |
| Reuse one Core ML input `MLMultiArray` per `AUGeoCalibCoreMLNeuralInferenceSession` | Correct and small by itself. It avoids per-image input tensor/provider allocation while keeping FP32 values unchanged. A lock protects the shared input buffer. |
| Parallelize the three independent RGB channels in preprocessing blur/resize | Effective. The pixel math is unchanged; independent channel work is distributed across CPU cores. |

Validation command:

```sh
cd /Users/ibobby/Projects/AnyUpright
tools/run-swift-geocalib-full-validation.sh \
  --dataset /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/data/lamar2k \
  --out /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/swift_coreml_geocalib_20_intersection_lossless_parallel_v1 \
  --coreml-model /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/coreml_compiled_neural_forward_416x320/neural_forward.mlmodelc \
  --warmup-neural \
  --image-list /Users/ibobby/Projects/AnyUpright/.agent-work/optimization/lamar2k-shape416x320-20.txt \
  --max-analysis-dimension 1920 \
  --verifier-max-dimension 640 \
  --progress-every 1
```

Result:

- Count: `20`
- Accepted: `16`
- All-image mean total: `129.770 ms`
- All-image median total: `128.689 ms`
- All-image p90 total: `136.913 ms`
- All-image mean GeoCalib: `82.807 ms`
- All-image p90 GeoCalib: `87.602 ms`
- All-image mean preprocess: `30.289 ms`
- All-image mean detect: `52.518 ms`
- Swift/Core ML all-image MAE: `2.738985 deg`
- Swift/Core ML within 2 deg: `80.0%`

Comparison against the previous warm-up baseline:

- Changed prediction/decision records: `0`
- Max roll diff vs previous Swift/Core ML: `0.0 deg`
- Mean abs-error delta vs previous Swift/Core ML: `0.0 deg`
- Mean total delta: `-46.970 ms`
- Mean preprocess delta: `-46.032 ms`
- Mean GeoCalib delta: `-46.653 ms`

Migration comparison against Python fixed-NMF:

- Mean roll diff vs Python: `0.043770 deg`
- Median roll diff vs Python: `0.005941 deg`
- P90 roll diff vs Python: `0.061009 deg`
- Max roll diff vs Python: `0.371669 deg`
- Mean abs-error delta vs Python: `-0.002191 deg`
- P90 abs-error delta vs Python: `0.015362 deg`

Interpretation:

This is a real shared-path optimization: it does not depend on removing test-only dataset work and does not use lossy precision, quantization, lower-resolution inputs, altered verifier thresholds, or model changes. The remaining shared-path cost on this 20-image slice is mostly Core ML neural plus optimizer/detect at about `52.5 ms`, verifier at about `35.8 ms`, and preprocessing at about `30.3 ms`. The next lossless candidates are verifier scheduling/parallelism and internal detect profiling before changing optimizer implementation.

### 2026-06-22 Plugin Integration And Host Validation

Status: integrated into the Horizon FxPlug analysis path and verified in both Final Cut Pro 12.2 and Motion Studio 6.2.

Integration:

- Added ignored local Core ML runtime resources under `AnyUpright/Plugin/GeoCalibCoreML/`.
- The XPC service bundle now includes two compiled FP32 ML Program models:
  - `neural_forward_416x320.mlmodelc`
  - `neural_forward_320x416.mlmodelc`
- `AnyUprightHorizonPlugIn` now tries Core ML first, selecting the model by preprocessed input shape.
- If Core ML resources or model execution fail, the plugin falls back to the previous project-owned Swift/Metal GeoCalib runtime, then to the older Vision/Hough fallback chain.

Final Cut Pro validation:

- Library: `/Users/ibobby/Movies/Develop.fcpbundle`
- Clip/project: existing `2026-06-09 | Untitled Compound Clip` with `IMG_1118`
- Host frame bounds: `5712x4284`
- Analysis RGB cap: `1920x1440`
- Core ML shape: `[1, 3, 320, 416]`
- Result: `accepted=true`, `rollDeg=3.044743`, `correctionDeg=-3.044743`, `uncDeg=1.060720`
- Verifier diffs: `axis_hough=6.381240 deg`, `gradient_axis=4.174846 deg`
- UI writeback: `Rotation=-3.0 deg`
- First click total from `start` to `cleanup`: about `9.40 s`, including Core ML model load and warm-up.
- Second click total from `start` to `cleanup`: about `3.17 s`. The Core ML run plus detector segment was about `244 ms`; the larger host-path time was before `geocalib coreml shape`, covering plugin-side frame preprocessing and verifier work on the host frame.

Motion validation:

- Template opened: `~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/Horizon/Horizon.moef`
- Important test detail: importing a still into the template as a separate ordinary layer does not replace the template's `Effect Source`; that path triggers the button selector but may not produce analysis frames for the actual image. Applying `AnyUpright Horizon` directly to the imported image layer does exercise the Motion analysis path.
- Test image: `/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/data/lamar2k/images/257834199224.jpg`
- Host frame bounds: `1920x1440`
- Core ML shape: `[1, 3, 320, 416]`
- Result: `accepted=true`, `rollDeg=13.878209`, `correctionDeg=-13.878209`, `uncDeg=0.454973`
- Verifier diffs: `axis_hough=0.077320 deg`, `gradient_axis=3.911218 deg`
- UI writeback: `Rotation=-13.9 deg`

Interpretation:

The plugin migration preserves the verified Swift/Core ML result path and works in both target hosts. The standalone validation timing remains the best measure of algorithm migration cost because it excludes host frame acquisition and FxAnalysis scheduling; host timing is still within the current 10-second single-detection product budget on the tested stills.
