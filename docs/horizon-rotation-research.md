# Horizon Rotation Research Notes

This note records research for the `AnyUpright Horizon` effect only. It is intentionally scoped to roll estimation and centered affine rotation. Plane rectification, four-corner correction, keystone, source quadrilateral selection, camera pitch correction, FoV recovery, and homography validation belong to the Quad or Upright workstreams.

## Product Boundary

| User goal | Product path | Parameters written | Current research scope |
| --- | --- | --- | --- |
| The camera was rolled a little; make the image level. | `AnyUpright Horizon` | `Rotation`, optionally `Fill Frame` | In scope. Estimate roll angle and render a centered affine rotation. |
| Vertical or horizontal perspective needs correction. | `AnyUpright Upright` | `Vertical Perspective`, `Horizontal Perspective`, optionally `Rotation` | Out of scope for this note. Use separate guide-line and perspective validation. |
| A screen, sign, page, or facade should be mapped to a rectangle. | `AnyUpright Source Quad` | Source quadrilateral hidden corner offsets | Out of scope for this note. Validate with corner and homography metrics. |
| The output frame corners should be warped manually. | `AnyUpright Outer Corners` | Output-corner offsets | Out of scope for this note. Validate with destination quad mapping. |

For the Horizon effect, a detector may internally estimate a horizon line, gravity/up direction, pitch, or FoV if that helps obtain a better roll estimate. The effect should consume only the roll correction and discard the other degrees of freedom.

## Datasets

| Dataset | Labels | Use for Horizon | Caveats |
| --- | --- | --- | --- |
| [Horizon Lines in the Wild](https://mvrl.cse.wustl.edu/datasets/hlw/) / [paper](https://www.bmva-archive.org.uk/bmvc/2016/papers/paper020/paper020.pdf) | Annotated horizon line. The paper reports about 100k images and 2,018 evaluation images. | Convert horizon line slope to roll angle and evaluate horizon-line error. Good broad natural-image source. | The benchmark is horizon-line accuracy, not a pure roll benchmark. Horizon vertical offset is useful for calibration research but should be ignored for rotation-only validation. |
| GSV and SUN360 calibration benchmarks used by [CTRL-C](https://openaccess.thecvf.com/content/ICCV2021/papers/Lee_CTRL-C_Camera_Calibration_TRansformer_With_Line-Classification_ICCV_2021_paper.pdf) | Synthetic crops with sampled FoV, pitch, and roll. | Use roll and up-direction accuracy. Ignore FoV and pitch for the current milestone. | Generated from panoramas; useful for controlled roll labels, but not a substitute for user footage. |
| Stanford2D3D, TartanAir, MegaDepth, and LaMAR as evaluated by [GeoCalib](https://arxiv.org/html/2409.06704v1) | Camera calibration / gravity labels. | Strong validation set for single-image roll estimation across indoor, synthetic, outdoor, and localization imagery. | More setup work than HLW. These datasets evaluate broader calibration, so report only roll-related metrics for Horizon. |
| [MU-SID sea image dataset](https://www.mdpi.com/2077-1312/10/2/193) and the [Moroccan Maritime Dataset](https://arxiv.org/html/2110.13694v4) | Sea horizon lines. | Useful targeted stress tests for visible sea horizons and weak horizon edges. | Domain-specific. Accuracy here does not prove indoor, city, handheld, product, or event footage behavior. |
| Project-local synthetic rotation set | Known input roll produced by rotating generated or sampled frames. | Fast regression fixture for sign convention, radians writeback, fill-frame rendering, and edge cases near zero roll. | Synthetic images can overstate accuracy. Keep real-frame manual spot checks in the loop. |

## Candidate Algorithms

| Approach | Cost profile | Rotation signal | Fit for current milestone |
| --- | --- | --- | --- |
| Apple Vision `VNDetectHorizonRequest` | Platform API; explicit single-frame analysis. | Horizon observation converted to roll correction. | Preferred first production path because it avoids bundling a model and already matches the current plugin integration. |
| Sobel/Canny/LSD plus Hough or RANSAC | Lightweight CPU path, especially on downsampled frames. | Dominant near-horizontal line slope. | Good fallback and deterministic test baseline. Needs confidence checks to avoid locking onto non-horizon lines. |
| Vanishing-point / Manhattan-world geometry | Moderate CPU cost; depends on enough reliable straight lines. | Gravity/up direction, then roll. | Useful for architecture and interiors where true horizon may be invisible. Weak on natural images and shallow-depth footage with few lines. |
| DeepHorizon-style direct horizon CNN | CNN inference; legacy public implementation exists in [`scottworkman/deephorizon`](https://github.com/scottworkman/deephorizon). | Horizon line, then slope as roll. | Good research benchmark. Shipping it directly would need separate licensing and model-format review. |
| CTRL-C / GPNet-style camera calibration | Deep model plus line/image cues. | Roll, pitch, FoV, horizon; consume roll only. | Strong accuracy reference. Too broad for the first native implementation unless packaged as an optional offline prototype. |
| Perspective Fields / GeoCalib-style dense camera calibration | Deep model plus geometric fitting; still compatible with the 10-second single-analysis budget. | Gravity/up direction and roll; consume roll only. | Best research direction for robust future roll detection, especially when a visible horizon is absent. Heavier dependency surface than Vision/Hough. |

Representative published rotation-related numbers:

| Method | Benchmark | Reported metric relevant to roll |
| --- | --- | --- |
| DeepHorizon, as compared in CTRL-C | GSV / SUN360 | Mean roll error 1.78 deg / 1.16 deg. |
| CTRL-C | GSV / SUN360 | Mean roll error 0.66 deg / 0.96 deg; horizon error AUC 87.29% / 85.45%. |
| UVP baseline, as compared in GeoCalib | Stanford2D3D / TartanAir / MegaDepth / LaMAR | Median roll error 0.52 deg / 0.89 deg / 0.51 deg / 0.38 deg. |
| GeoCalib | Stanford2D3D / TartanAir / MegaDepth / LaMAR | Median roll error 0.40 deg / 0.43 deg / 0.36 deg / 0.28 deg. |

These numbers are not directly interchangeable because the datasets, camera assumptions, and metrics differ. Use them to choose prototypes, not as a single leaderboard.

## Current Research Selection

The current offline prototype selection for automatic Horizon rotation is:

1. Use GeoCalib as the primary roll estimator.
2. Reject writeback unless GeoCalib `roll_uncertainty <= 3 deg`.
3. Run lightweight verifier estimates and reject when two or more verifiers disagree with GeoCalib by more than 10 degrees.
4. Keep Horizon writeback rotation-only. If the requested correction exceeds the product's practical rotation range, such as Lightroom-style +/-45 degrees, reject or require manual confirmation rather than switching to perspective correction.

The tested verifier set is `axis_hough`, `axis_lsd`, and `gradient_axis`. These verifiers are not accurate enough to replace GeoCalib as the primary estimator, but they are useful for catching rare confident-wrong model outputs.

## LaMAR2k Rotation Results

Local experiment workspace: `/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory`.

GeoCalib on all 2,000 LaMAR2k images:

| Method | Count | MAE | Median AE | RMSE | P90 AE | <=1 deg | <=2 deg | <=5 deg | Mean time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `geocalib_pinhole_mps` | 2000 | 0.941 deg | 0.278 deg | 3.589 deg | 1.338 deg | 86.45% | 93.10% | 96.30% | 202 ms |

Selected gate policy on the same 2,000 images:

| Policy | Accepted | Median AE | P90 AE | <=2 deg | Accepted >5 deg | Accepted >10 deg |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `roll_uncertainty <= 3 deg` and fewer than two verifier disagreements above 10 deg | 1631 / 2000 (81.55%) | 0.238 deg | 0.746 deg | 99.08% | 2 | 0 |

Classical verifier baselines remain much weaker as standalone estimators:

| Verifier | Coverage | Median AE | P90 AE | <=2 deg | Mean time |
| --- | ---: | ---: | ---: | ---: | ---: |
| `gradient_axis` | 99.95% | 2.570 deg | 12.583 deg | 42.0% | 8.52 ms |
| `axis_hough` | 93.95% | 2.342 deg | 11.551 deg | 45.0% | 3.59 ms |
| `axis_lsd` | 98.90% | 2.209 deg | 11.101 deg | 47.3% | 13.04 ms |

## Swift/Metal Migration Status

The selected pipeline was migrated in verified slices before moving into the FxPlug project.

Completed temporary prototypes:

| Slice | Verification result |
| --- | --- |
| Gate policy CPU + Metal | Matches Python for `unc<=3 && no_2_verifier_diff>10`; accepted `1631/2000`, median AE `0.238 deg`, p90 AE `0.746 deg`, accepted >10 deg `0`. |
| `gradient_axis` from blurred-gray fixture | `2000/2000` passed; max angle difference `0.000010 deg`, max confidence relative difference `0.00000766`. |
| `gradient_axis` direct image path | ImageIO JPEG + Metal area resize/grayscale/Gaussian/Sobel vs Python/OpenCV CSV: median angle diff `0.002710 deg`, p90 `0.010172 deg`, max `0.276839 deg`; `16/2000` above `0.05 deg`. |
| GeoCalib `patch_embed1.proj` stem | `20/20` passed through conv, BatchNorm affine, GELU, conv, BatchNorm affine; max abs diff `0.00000763`, max RMSE `0.000000311`. |
| GeoCalib first MSCAN depthwise conv | `20/20` passed for `backbone.block1[0].attn.spatial_gating_unit.conv0` grouped 5x5 conv; max abs diff `0.000000954`, max RMSE `0.00000000995`. |
| GeoCalib first full MSCAN block | `5/5` passed for `backbone.block1[0]` across BatchNorm, 1x1 projections, GELU, multi-branch depthwise attention, residual channel scaling, and MLP; final NCHW max abs diff `0.00000429`, max RMSE `0.000000255`. |
| GeoCalib full MSCAN stage 1 | `5/5` passed through all three `block1` blocks plus stage-end `LayerNorm(64)` over flattened spatial tokens; final NCHW max abs diff `0.00000572`, max RMSE `0.000000371`. |
| GeoCalib full MSCAN stage 2 | `5/5` passed through `patch_embed2`, all three `block2` blocks, and stage-end `LayerNorm(128)`; final NCHW max abs diff `0.00000274`, max RMSE `0.000000198`. |
| GeoCalib full MSCAN stage 3 | `1/1` passed through `patch_embed3`, all twelve `block3` blocks, and stage-end `LayerNorm(320)`; final NCHW max abs diff `0.00000143`, max RMSE `0.000000138`. Deep intermediate block max abs reached `0.00119`, with relative diff `0.0000162`, due to long float accumulation order differences in the naive Metal verifier. |
| GeoCalib full MSCAN stage 4 | `1/1` passed through `patch_embed4`, all three `block4` blocks, and stage-end `LayerNorm(512)`; final NCHW max abs diff `0.000000954`, max RMSE `0.000000125`. |
| GeoCalib LightHamHead pre-NMF decoder slice | `1/1` passed for `up_head` bilinear resize with `align_corners=false`, four-level channel concat, and `decoder.squeeze` 1x1 ConvModule + ReLU; squeeze max abs diff `0.000000715`, max RMSE `0.0000000288`. |
| GeoCalib LightHamHead Hamburger/NMF slice | `1/1` passed for fixed-basis `up_head` Hamburger through `ham_in`, 7-step NMF, `ham_out`, and residual ReLU; NMF output max abs diff `0.00000238`, final max abs diff `0.000000954`. |
| GeoCalib `up_head` decoder output path | `1/1` passed through align, low-level feature fusion, uncertainty head, up logits, and normalized `up_field`; log-uncertainty max abs diff `0.0000191`, normalized `up_field` max abs diff `0.000000238`. |
| GeoCalib low-level encoder | `5/5` passed from processed RGB input through both full-resolution ConvModule layers; `ll` feature max abs diff `0`. |
| GeoCalib `latitude_head` decoder path | `1/1` passed through pre-NMF, fixed-basis Hamburger/NMF, low-level feature fusion, confidence, logits, and `latitude_field`; NMF output max abs diff `0.00000191`, log-uncertainty max abs diff `0.00000763`, latitude field max abs diff `0.000000298`. |
| GeoCalib full fixed-NMF neural forward | `3/3` passed from processed RGB tensor through MSCAN, low-level encoder, and both dense decoder heads; `up_field` max abs diff `0.000000834`, `latitude_field` max abs diff `0.000000715`, max confidence diff `0.00000188`. |
| GeoCalib LM optimizer | `3/3` passed for the default pinhole optimizer path from dense `up_field`/`latitude_field` inputs through final `camera_data`, `gravity_data`, costs, stop step, covariance, and roll/pitch/vFoV uncertainties; camera max abs diff `0.0000916`, gravity max abs diff `0.0000000596`, uncertainty diffs about `1e-8` radians. Covariance max abs diff `0.001953` is only `8.8e-7` relative on focal covariance entries around `2e3`. The optimizer has also been moved into `AnyUpright/Plugin/AnyUprightGeoCalibOptimizer.swift` with a fixture-backed standalone test. |
| GeoCalib project-owned neural prototype | `3/3` neural-forward fixture-backed test passed from the AnyUpright repo using `AnyUpright/Plugin/AnyUprightGeoCalibNeuralPrototype.swift` and `AnyUpright/Plugin/AnyUprightGeoCalib.metal`; `Wrapper Application` Debug build also compiles the Swift and Metal files into the XPC target. |
| GeoCalib runtime resource bundle | `AnyUpright/Plugin/GeoCalibRuntime/` contains a flat runtime bundle with `754` `.f32` tensors plus `manifest.json`, `115,965,716` tensor bytes. The `Wrapper Application` Debug build copies these into the XPC plug-in `Contents/Resources`; `AnyUprightGeoCalibRuntimeBundleTests` passed against both the source bundle and the built plug-in resources. |
| GeoCalib preprocessing | `AnyUprightGeoCalibPreprocessorTests` passed against synthetic Python `ImagePreprocessor` fixtures covering Kornia bilinear resize, Gaussian antialiasing, 32-multiple center crop, and `scales`. Max tolerated output difference is `5e-5` absolute / `5e-6` RMSE for Float32 accumulation order. |
| GeoCalib Horizon detector integration | `AnyUprightGeoCalibHorizonDetectorTests` passed from runtime bundle + Metal neural forward + Swift LM optimizer + roll gate. The test matches Python optimizer fixture roll and uncertainty, verifies `correction = -roll`, checks `roll_uncertainty <= 3 deg`, `+/-45 deg`, and two-verifier rejection logic, and also runs the first fixture through the built plug-in `default.metallib`. A single fixture through built resources + `default.metallib` measured `9.57s` wall time on this machine. |

Project integration and host validation:

- `Analyze Horizon` now runs the project-owned GeoCalib detector first, writes only accepted roll corrections, and falls back to Vision/Hough only if the GeoCalib runtime cannot run. A GeoCalib rejection does not write fallback parameters.
- Runtime resources deliberately exclude the 234MB test fixture bundle: the neural-forward fixture contains about 110.6MB of weight files and about 121.5MB of test input/expected tensors. `tools/build-geocalib-runtime-bundle.py` builds the slim flat runtime bundle and was verified to output 754 runtime tensors plus a manifest, about 112MB total, with no fixture `entries`.
- Host analysis caps the RGB analysis image at 1920 pixels on the long edge before the GeoCalib preprocessing step. This keeps high-resolution stills inside the 10-second explicit-analysis budget without changing the downstream model, LM optimizer, uncertainty gate, verifier gate, or rotation-only writeback semantics.
- Motion validation on `/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/data/lamar2k/images/257834199224.jpg` wrote `Rotation = -13.9 deg`, matching the Python expected correction near `-13.8846 deg` after rounding in the UI.
- Final Cut Pro 12.2 validation required a local `Horizon.moef` template under `~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/Horizon/`. After restarting FCP, the Effects Browser showed `Horizon`, the inspector exposed `Analyze Horizon`, `Rotation`, and `Fill Frame`, and a 5712 x 4284 still was analyzed through a 1920 x 1440 RGB image in about 6.65 seconds. The accepted result had `roll=3.073 deg`, `uncertainty=1.076 deg`, verifier differences `4.39 deg` and `4.19 deg`, and wrote `Rotation=-3.1 deg` in the FCP inspector.
- Creating `/tmp/AnyUprightGeoCalib.debug` enables temporary host analysis logs at `/tmp/anyupright-geocalib-debug.log`; keep the flag absent during normal use.

## Validation Criteria

- Primary metric: absolute roll error in degrees. For horizon-line datasets, compute roll from the line angle and compare it with the predicted correction angle.
- Secondary metric: failure handling. Count low-confidence or no-result frames separately from wrong high-confidence corrections.
- Rendering metric: after writing `Rotation`, the rendered frame should be a centered affine rotation. `Fill Frame` may zoom to hide black edges, but it must not introduce a perspective warp.
- Regression fixtures: include small known rotations around zero, mild user-like corrections such as +/-0.5, +/-1, +/-2, and +/-5 degrees, plus a few larger stress rotations.
- Current out-of-scope metrics: corner error, quadrilateral IoU, homography reprojection error, vertical convergence correction, pitch error, and FoV error.

## Implementation Notes For AnyUpright

- Keep analysis explicit and single-frame-assisted. Playback should use only the saved angle and the existing Metal affine rotation path.
- The plugin currently stores angle parameter values in radians in the Motion validation path. Any detector output in degrees must be converted before writeback.
- Use a conservative confidence model. When the best detected line is ambiguous, near-vertical, too short, or semantically unlikely to represent level, prefer no writeback over a confident wrong rotation.
- If a future prototype uses a broad camera-calibration model, treat pitch/FoV/gravity details as internal evidence. Do not expand the Horizon effect into perspective correction.
