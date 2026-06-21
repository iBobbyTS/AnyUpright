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
