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
