# AnyUpright

AnyUpright is a suite of FxPlug effects for single-frame-assisted perspective and upright correction. The effects target fixed-camera or mostly static correction workflows where analysis and manual setup happen on one representative frame, while the resulting transform persists across the whole clip and supports host keyframes through published parameters.

## Current State

- The repository is initialized as an Xcode FxPlug 4 project.
- The template brightness filter has been replaced with four separate FxPlug filters under the `AnyUpright` group.
- No Motion template files are tracked here yet; the current product is the registered FxPlug filters.
- There is no package manager, Docker runtime, or CI workflow yet.
- Geometry tests live in `AnyUprightTests/` and can be run as a lightweight Swift executable.
- The shared geometry layer now includes line candidate filtering, horizon correction estimation, and centered perspective parameter estimation from reference lines.
- Quad and Upright expose FxPlug onscreen controls through separate `FxOnScreenControl` plug-in entries linked to their filter UUIDs with `supportedPlugins`.
- Inner Stretch edit-mode dimming is rendered into the filter output itself, so the selected source area follows the video image even when host OSC drawing is unavailable. The interactive outline, handles, hover highlights, hit testing, and drag writeback are owned by the FxPlug OSC layer.
- `tools/render-warp-previews.swift` generates CPU-rendered preview PNGs from the same geometry matrices used by the Metal renderer, so matrix semantics can be checked without launching a host app.

## Engineering Notes

If you are a person or agent debugging FxPlug coordinate flips, Final Cut/Motion OSC hit testing, viewer-vs-video drift, `drawOSC` drawable sizing, tiled render sampling shifts, or fixed-shape Core ML model routing, start with `docs/engineering-notes/`.

## Effects

### AnyUpright Horizon

Automatically detects a horizontal reference line in the current frame and applies a rotation correction across the clip.

Product scope:

- Horizon is the rotation-only leveling effect. It is for shots where the camera was rolled slightly and a centered affine rotation is the most natural correction.
- Horizon analysis may use a detected horizon, line slope, vanishing/up direction, or learned camera-calibration cue to estimate roll, but it should write only `Rotation` for this effect. It should not write perspective, keystone, Inner Stretch, Outer Stretch, pitch, FoV, or homography parameters.
- Research notes, dataset options, and roll-only validation criteria are recorded in `docs/horizon-rotation-research.md`.

Current implementation:

- `AnyUpright Horizon` is registered as a separate FxPlug filter.
- `Rotation` is a manual angle slider.
- `Fill Frame` controls whether the rotated image is zoomed enough to avoid black edges.
- `Analyze Horizon` starts FxAnalysis near the current parameter time when the host provides one, runs the project-owned Core ML-only GeoCalib roll detector with direct Metal GeoCalib preprocessing, verifier gate, and optimizer glue, and writes only the accepted centered rotation correction back to `Rotation`.
- GeoCalib writeback is accepted only when `roll_uncertainty <= 3 deg`, the absolute correction is within the Horizon `+/-45 deg` product range, and fewer than two available verifiers disagree with GeoCalib by more than 10 degrees. The current in-plugin verifiers are project Hough-axis and gradient-axis estimates; rejected GeoCalib results produce no writeback.
- The in-plugin Core ML path uses an XPC-process shared cache keyed by fixed input shape. Adding the effect asks `FxOnScreenControlAPI_v4` for the current input/object size, selects the nearest production shape, and prewarms that model when the host exposes dimensions; it no longer hardcodes a 4:3 prewarm. Cached Core ML sessions expire independently per shape after 15 seconds without analysis, extend that shape to 30 seconds from the next analysis start, and extend only that shape to 60 seconds when two analyses happen inside its 30-second window.
- `AnyUpright/Plugin/GeoCalibCoreML/` currently contains fixed-shape `.mlmodelc` graphs because the flexible-shape ML Program paths, while runnable after experimental `torch.export` conversion patches, measured about 12-13x slower than fixed-shape Core ML for the current 4:3 inputs. This held for both `RangeDim` and `EnumeratedShapes`. The fixed production shapes are 4:3 `[1, 3, 320, 416]`, 3:4 `[1, 3, 416, 320]`, 16:9 `[1, 3, 320, 544]`, 9:16 `[1, 3, 544, 320]`, 1:1 `[1, 3, 320, 320]`, 3:2 `[1, 3, 320, 480]`, 2:3 `[1, 3, 480, 320]`, and 2.35:1 `[1, 3, 320, 736]`. Images whose aspect ratio is not one of these labels use the nearest model ratio, then aspect-fill resize and center crop to that model's static input shape. The compiled models have identical `weights/weight.bin` blobs, so local plugin resources should dedupe every non-canonical weight with `tools/dedupe-geocalib-coreml-weights.sh`; this keeps Core ML behavior unchanged while keeping the eight-shape Core ML resource directory around 116MB instead of storing eight full weight copies. For reusable routing diagnostics, see `docs/engineering-notes/coreml-fixed-shape-routing.md`.
- Verifiers run only after the primary GeoCalib result passes the uncertainty and `+/-45 deg` product gate; this keeps rejected frames from paying verifier cost while preserving the two-verifier rejection rule for candidate writebacks.
- There is no Swift/Metal GeoCalib neural fallback runtime in the plug-in path. If Core ML GeoCalib resources or model execution are unavailable, the existing non-GeoCalib Vision/Hough fallback detectors may still try to produce a rotation; a GeoCalib confidence/verifier rejection does not fall through to those fallback detectors.
- Horizon analysis writeback history is archived under `.agent-work/debug/`; stable engineering conventions should live in `docs/engineering-notes/`.

Workflow:

1. User applies the effect to a clip.
2. User analyzes the current frame or selects a candidate line.
3. Plugin writes the resulting correction into keyframeable parameters.
4. Playback and export use only the saved transform.

Primary risks:

- False positives when strong lines are not true horizon references.
- Low-confidence frames with no reliable horizontal line.
- Need for manual override and visible candidate feedback.
- Analysis requests target a tiny time range around the button's current parameter time when that time falls inside the input range; host behavior still needs Motion/FCP validation on trimmed and retimed clips.

### AnyUpright Quad Transform

Provides manual four-point perspective transforms through two separate FxPlug filters.

Current implementation:

- Quad-specific implementation choices and historical product-shape decisions are recorded in `docs/quad-implementation-notes.md`. Reusable coordinate/debugging lessons remain under `docs/engineering-notes/`.
- `AnyUpright Inner Stretch` is registered as a separate FxPlug filter. It fixes the shared Quad render path to `Inner Stretch` semantics.
- `AnyUpright Outer Stretch` is registered as a separate FxPlug filter. It fixes the shared Quad render path to output/outer-corner warp semantics.
- The old inspector `Mode` popup is now a hidden fixed parameter so each filter keeps stable render state without asking the user to switch modes inside one effect.
- `Detect Edge and Corner` is exposed as a native FxPlug push button registered with `addPushButton` on Inner Stretch parameter channel `./216`. Clicking it starts FxAnalysis near the current parameter time and runs independent edge/corner detection, but it no longer moves the current Inner Stretch. Instead it writes hidden edge and corner primitive slots with normalized 0...1 scores, enables `Edit Mode`, and enables `Choose from detections`. `Choose from detections` controls both OSC display and hit testing for detected primitives: when enabled, detected edges/corners above `Score Threshold` are drawn above the existing manual handles, and hit testing changes from the manual quad to detected primitives. Selecting four detected corners or four detected lines writes the Inner Stretch to that proposed quadrilateral, then automatically exits detection-choice mode. Final Cut Pro only shows the button, choice toggle, and threshold when the Motion template publish settings include the push-button target (channel `./216`), choice target (channel `./218`), and threshold target (channel `./217` in the current `Inner Stretch.moef`); if FCP shows only `Edit Mode`, publish/save those parameters in Motion or add the matching publish targets, then restart FCP.
- `Edit Mode` is shown only in `AnyUpright Inner Stretch`. It is enabled by default: when enabled, the filter output keeps the image unwarped and dims the area outside the current input quadrilateral, while the draggable outline and handles are drawn in the OSC overlay. Disable it to hide the adjuster and stretch the selected input quadrilateral to the full output frame.
- In `AnyUpright Inner Stretch`, the default input quadrilateral is the central 80% of the frame. The 100% full-frame selection is still covered as an identity/no-offset geometry case for validation. The edit preview dims the outside area to 70% brightness and leaves the selected quadrilateral at original brightness. The OSC overlay connects the four handles with a white outline and draws blue fixed-size circular handles, with yellow hover/drag highlights. Detected candidate edges are drawn as green lines and detected candidate corners are drawn as green crosses only while `Edit Mode` and `Choose from detections` are enabled; hovered or selected detection primitives use the same yellow highlight color as manual quad dragging.
- In `AnyUpright Outer Stretch`, each visible output corner exposes `X %`, `Y %`, `X px`, and `Y px` offsets in the inspector.
- In `AnyUpright Inner Stretch`, the corner coordinate groups are hidden from the inspector; users position the input quadrilateral with onscreen handles.
- Final offset is `percentage * current frame dimension + pixels`.
- Positive `X` moves right. Positive `Y` moves up.
- In `AnyUpright Outer Stretch`, the four offsets are a destination/output quadrilateral and map back to the full source frame, matching the direction a user sees in the Motion canvas.
- In `AnyUpright Inner Stretch`, the same corner offset parameters describe an input quadrilateral that maps to the full output frame, matching a document-scanner or Microsoft Lens style correction. Those parameter groups are hidden in the inspector while this filter is active.
- The visible `Inner Stretch` edit UI is split across two layers. The filter output layer keeps an identity preview and dims outside the selected input quadrilateral, so users can tell `Edit Mode` is still active. The Inner Stretch `FxOnScreenControl` draws the white outline, blue handles, and yellow hover/drag highlights in host canvas space, so handles can remain visible and draggable outside the video frame. For Final Cut raw-canvas events, the OSC outline and hit layer use the same source-preview geometry as the filter output; the unflipped object/canvas quad is kept for storage/writeback diagnostics. Final Cut host connections disable Motion-style mapped-surface fallback during initial Inner Stretch hover/hit tests so raw canvas points above or outside the video frame cannot fold into an invisible hit layer. Motion-style surface-local event points are mapped back to canvas coordinates for Motion and unknown hosts when needed, but visible Final Cut raw-canvas controls outside the object frame keep raw hit testing. OSC control points are drawn from host canvas-frame points instead of output-image aspect-fit space: X and Y both stay in host canvas pixels, with no frame-center compensation, surface-scale compensation, clamping, Fit renormalization, or renderer-level vertical mirroring. Inner Stretch dragging crosses the preview/object Y boundary explicitly, writes hidden source-corner percentage offsets, and clears matching pixel offsets so the render-time inner stretch is independent of OSC surface resolution. Outer Stretch uses its own OSC entry and writes output-corner pixel offsets while preserving any existing percentage offset. See `docs/engineering-notes/y-axis-coordinate-conventions.md`, `docs/engineering-notes/quad-osc-hit-testing.md`, and `docs/engineering-notes/quad-osc-rendering.md` before changing this path.
- A hidden point-parameter experiment was intentionally backed out: Motion accepted `setXValue(_:yValue:)` during OSC drags but subsequent reads still returned the default points. Inner Stretch now uses the float-parameter path because Motion was verified to persist those writes.

Two intended filters:

1. Source quad to full frame: user drags four points around an object such as a phone screen or sign; editing can display handles without moving the image, and applying maps that quadrilateral to the original frame size.
2. Frame-corner warp: user drags the four output corners and sees the warped image in realtime; the stretched result is the actual output.

Primary risks:

- Coordinate consistency across canvas space, source pixels, proxy resolution, and Final Cut project settings.
- Onscreen control usability.
- Rectangle detection false positives, especially when the strongest rectangle is not the object the user intended; manual handles remain the correction path.
- Keyframing corner positions without creating confusing interpolation.

### AnyUpright Upright

Provides Lightroom-style upright correction controls.

Current implementation:

- `AnyUpright Upright` is registered as a separate FxPlug filter.
- The visible parameter surface is `Direction`, `Analyze`, `Mode`, `Auto Crop`, and `Edit Mode`. The implementation no longer exposes separate chosen-detection, threshold, guide, candidate, vertical-perspective, horizontal-perspective, or rotation controls in the inspector.
- `Direction` chooses the correction family: `Vertical`, `Horizontal`, or `Full`. Hidden vertical perspective, horizontal perspective, and rotation result parameters are still stored for older non-direct correction paths, but axes excluded by the current direction are ignored at render time.
- `Mode` chooses `Manual`, `Semi Auto`, or `Full Auto`. `Analyze` applies the current manual guide state in manual mode, or starts candidate-line analysis in semi/full-auto modes.
- `Edit Mode` shows the original unwarped frame and displays Upright OSC lines. Turning `Edit Mode` off applies the stored correction and hides all Upright OSC lines. `Auto Crop` zooms the rendered correction just enough to keep output-frame corners inside the source frame when possible.
- Manual Vertical with two contributing guide lines solves a direct output-to-source matrix from those source-image guide lines so the referenced lines become vertical after correction; it does not infer a visible rotation angle and then rebuild a matrix from that angle. Older non-direct vertical perspective paths use a centered keystone transform around the horizontal centerline. Positive values move the top inward and bottom outward; negative values move the top outward and bottom inward.
- Horizontal perspective uses a centered keystone transform around the vertical centerline. Positive values move the right side inward and left side outward; negative values move the right side outward and left side inward.
- Upright perspective parameters are normalized by their acting axis so guide-line correction keeps the same meaning across aspect ratios: vertical perspective is normalized by image height, and horizontal perspective is normalized by image width.
- Rotation is stored internally for older correction paths and applies only in `Full` direction. Manual Vertical direct-matrix rendering does not consume rotation.
- Internally this implementation treats upright perspective as a destination/output quadrilateral and maps it back to the full source frame.
- The centered keystone math is tested at the homography level: vertical, horizontal, and combined perspective transforms keep the frame center anchored instead of acting like edge-pivot shears.
- Manual mode displays only the guide lines relevant to the current direction. The first two guides default to vertical references and the last two default to horizontal references, so an unanalyzed clip starts from usable guide positions. Dragging endpoints updates correction immediately. Clicking a guide line toggles whether it contributes to correction; disabled guide endpoints draw gray. Switching back from semi/full-auto to manual preserves guide positions and does not show detected lines.
- Manual and semi-auto vertical/horizontal modes support 0, 1, or 2 contributing lines. Manual and semi-auto full mode supports 0, 1, 2, 3, or 4 contributing lines. Zero contributing lines means no upright correction for the included axis.
- Semi-auto mode displays only analyzed candidate lines that match the current direction. Candidate lines are the only hittable OSC primitives in this mode. Clicking a candidate toggles selection and writes correction while preventing more than two selected lines per orientation.
- Full-auto mode analyzes matching candidate lines, selects the two highest-scoring included candidates overall, writes correction, and displays only those selected lines while `Edit Mode` is on.
- Candidate detection first tries the local M-LSD large Core ML model and Swift decode/ranking path, then falls back to the shared Sobel/Hough detector when the ignored local model resource is missing or inference fails.

Implemented controls:

- Direction dropdown for vertical, horizontal, or full correction.
- Analyze push button.
- Mode dropdown for manual, semi-auto, or full-auto control.
- Auto Crop checkbox.
- Edit Mode checkbox.

Automation levels:

- Full auto: detect candidate lines and choose the two highest-scoring included references automatically.
- Semi auto: detect candidate lines matching the current direction and allow the user to choose references by clicking lines in the canvas.
- Manual: user adjusts the default guide lines directly in the canvas.
- The semi-auto implementation uses hidden fixed candidate slots rather than dynamic inspector UI rows, and it does not yet draw text labels.

Primary risks:

- Automatic scoring quality. The M-LSD path produces model-confidence-filtered line segments, then uses angle fit, line length, center proximity, and pair promotion as the candidate score. The Sobel/Hough fallback still uses a simpler angle-plus-length compatibility score.
- UX complexity from combining manual axes, drawn lines, detected candidates, and keyframes.
- Avoiding realtime playback cost from frame analysis.

## Architecture Direction

Use one repository and one product suite, but expose four separate Final Cut effects. Shared implementation should live behind small common modules:

- Geometry: normalized points, lines, homography, affine transforms, vanishing-point helpers, and coordinate conversion.
- Detection: frame downsampling, edge/line detection, candidate scoring, and analysis result serialization.
- Rendering: shared Metal pipeline for affine and projective texture warps.
- UI/controls: image-space edit dimming in the filter render output, reusable Metal onscreen overlay drawing for OSC visuals, canvas-space hit testing, object/canvas conversion through `FxOnScreenControlAPI_v4`, and parameter writeback where FxPlug APIs permit it.
- FxPlug OSC registration: Inner Stretch, Outer Stretch, and Upright use separate OSC classes linked with `supportedPlugins`. Apple documentation describes this as the expected shape for onscreen controls, and an installed Pixel Film Studios FxPlug (`PFSMaskV2`) uses the same `supportedPlugins` key in its plist. If Motion does not call OSC methods, first suspect stale PlugInKit registration or host instance caching before changing coordinate math. In Motion's Metal OSC path, the `drawOSC` width/height values can describe the source object, while the drawable tile is represented by `destinationImage`; host OSC surfaces should map canvas coordinates to the destination texture/tile dimensions instead of treating `width` and `height` as the viewport. In Final Cut's zoomed viewer path, Inner Stretch OSC drawing keeps host canvas X and Y direct; the reusable overlay renderer flips Y only when converting those surface pixels into centered Metal vertex coordinates. If vertical pan drift appears, compare the host callback canvas points and X/Y symmetry before adding Y-specific math. Inner Stretch edit-mode dimming is rendered by the filter output so it follows the clip/image, while Inner Stretch OSC owns the interactive outline, handles, hover highlights, hit testing, and drag writeback. Creating `/tmp/AnyUprightQuadOSC.debug` enables temporary OSC coordinate logging to `/tmp/AnyUprightQuadOSC.log`; creating `/tmp/AnyUprightGeoCalib.debug` enables Horizon GeoCalib analysis logging to `/tmp/anyupright-geocalib-debug.log`. Leave both flags absent during normal use.
- Quad object-space conversion: `AnyUprightGeometry.quadObjectPoints`, `innerStretchObjectPoints`, `sourceCornerPercentOffset`, and `cornerPixelOffset` own the Motion/FxPlug handle coordinate semantics so corner names, X direction, and Y direction stay testable outside the host app. `Inner Stretch` stores the four handles as hidden percent offsets during OSC drags; `Outer Stretch` exposes the same offset parameters in the inspector.
- Upright candidate slots: fixed inspector slot IDs, score gating, object/image coordinate conversion, selection limits, and onscreen hit testing live in `AnyUprightUprightCandidates.swift`; FxPlug parameter read/write remains in the effect class.
- Coordinate-system notes: Y-axis semantics differ across image/output pixels, FxPlug object space, host canvas events, Metal overlay drawing, viewer/video rectangles, render tile sampling, guided reference-line solving, and Metal texture-boundary matrices. Start with `docs/engineering-notes/quad-coordinate-layer-contract.md`, then read the focused notes under `docs/engineering-notes/` before changing Y-axis conversion, hit testing, OSC drawing, parameter writeback, edit-preview sampling, Upright guide geometry, or render matrix boundaries.

Playback rendering should use precomputed parameters only. Detection should be explicit, cached, or analysis-driven instead of happening on every frame.

The current traditional line detector is a CPU reference implementation based on Sobel edges, gradient-constrained Hough voting, and simple non-maximum suppression. It is used as the fallback for Upright candidate detection when the local ignored M-LSD Core ML model resource is not installed. Exact transform parameters are still solved by the shared geometry layer from the selected reference lines.

### Research Notes

- Apple Vision has [`VNDetectHorizonRequest`](https://developer.apple.com/documentation/vision/vndetecthorizonrequest), whose result is a `VNHorizonObservation`; this remains the lightweight fallback if the Core ML GeoCalib path cannot run.
- Roll-only horizon leveling research is tracked in `docs/horizon-rotation-research.md`. Keep this separate from Inner Stretch, Outer Stretch, and centered perspective correction research: the current Horizon milestone validates only rotation angle accuracy and affine rotation render behavior.
- Current Horizon implementation uses GeoCalib primary roll estimation gated by `roll_uncertainty <= 3 deg` plus rejection when two or more lightweight verifiers disagree by more than 10 degrees. The Swift/Core ML migration was verified against the Python fixed-NMF baseline on the 2,000-image LaMAR2k rotation set before project integration. Project-owned pieces now include GeoCalib preprocessing/gate/verifier glue in `AnyUprightGeoCalibHorizonDetector.swift`, the LM optimizer in `AnyUprightGeoCalibOptimizer.swift`, the Core ML neural-forward runtime and per-shape shared plugin cache in `AnyUprightGeoCalibCoreML.swift`, and the ignored local Core ML model bundle under `AnyUpright/Plugin/GeoCalibCoreML/`. Motion and Final Cut Pro 12.2 have both been verified to run `Analyze Horizon`, accept GeoCalib results, and write only `Rotation`.
- Horizon host analysis now prefers `AUGeoCalibDirectImagePreprocessor`, a shared Metal compute path that samples the analysis `FxImageTile` directly into the selected fixed-shape GeoCalib tensor with bilinear+antialias semantics, aspect-fill resize, and center crop. The previous Core Image RGB render plus Swift CPU `AUGeoCalibImagePreprocessor` remains as a compatibility fallback if direct Metal preprocessing cannot run.
- Performance validation should use the `Wrapper Application` Release build; Debug uses Swift `-Onone` and Metal debug info. Creating `/tmp/AnyUprightGeoCalib.debug` enables Horizon GeoCalib host logs in both Debug and Release at `/tmp/anyupright-geocalib-debug.log`, including click-to-cleanup, RGB render, preprocessing, Core ML cache/load/predict, optimizer gate, verifier, and writeback timings.
- `tools/build-geocalib-runtime-bundle.py` is retained only for historical Swift/Metal GeoCalib prototype reproduction; the plug-in no longer ships or calls the runtime bundle.
- `tools/build-geocalib-coreml-fixed-shapes.py` builds fixed-shape GeoCalib ML Program graphs for 4:3, 3:4, 16:9, 9:16, 1:1, 3:2, 2:3, and 2.35:1 from the verified algorithm workspace, compiles them with `xcrun coremlcompiler`, and copies the resulting `.mlmodelc` directories into the ignored local `AnyUpright/Plugin/GeoCalibCoreML/` resource folder.
- Upright M-LSD candidate detection expects the ignored local model resource at `AnyUpright/Plugin/MLSDCoreML/mlsd_large_512_fp32.mlmodelc`. The current local resource was compiled from `/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/outputs/mlsd_coreml/mlsd_large_512_fp32.mlpackage`; the Swift/Core ML prototype in that work directory previously verified candidate-level endpoint drift below 2% and layer-boundary drift below 1% against the Python baseline.
- `tools/dedupe-geocalib-coreml-weights.sh` validates that every non-canonical Core ML `weight.bin` is byte-identical to `neural_forward_320x416.mlmodelc/weights/weight.bin`, then replaces it with a relative symlink. The script is safe to rerun and refuses to modify weights that do not hash-match.
- Flexible-shape Core ML was validated as an experiment, not as the production path. `torch.export` + `RangeDim` and `torch.export` + `EnumeratedShapes` neural-forward packages both matched the fixed-shape Core ML outputs within `8e-6` max tensor diff on tested 4:3 images, but warm prediction stayed around `353-366 ms` for 4:3 inputs instead of `27-29 ms`; synthetic 16:9-style shapes stayed around `436-457 ms`.
- Motion 6.2 Release validation of the current 4:3 `Horizon.moef` test image measured the fixed-shape Core ML path at about `503 ms` from `Analyze Horizon` click/start to parameter writeback after the 15-second model-unload window, and about `279 ms` with an in-memory cached Core ML session. The detector body measured `276.7 ms` cold and `142.0 ms` cached; Core ML itself measured `178.2 ms` cold (`67.1 ms` session load, `110.9 ms` predict) and `37.5 ms` cached. Motion's FxAnalysis tile did not expose a Metal texture for this run, so direct Metal preprocessing fell back to the CI/CPU compatibility path.
- Apple Vision also has [`VNDetectRectanglesRequest`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest) and [`VNDetectDocumentSegmentationRequest`](https://developer.apple.com/documentation/vision/vndetectdocumentsegmentationrequest), both of which can return rectangle corner observations. These are useful for proposing a Lens-style input quadrilateral, but the current Inner Stretch detection overlay intentionally uses independent line/corner primitives so it can show multiple plausible edges and intersections without forcing them into closed rectangles.
- Core Image's [`CIFilter.perspectiveCorrection()`](https://developer.apple.com/documentation/coreimage/cifilter/3228380-perspectivecorrection) is the platform reference for input-quadrilateral-to-rectangular-output semantics: four input image corners map to the output image corners. AnyUpright uses its own Metal renderer for FxPlug playback, but the Quad `Inner Stretch` mode follows the same conceptual direction.
- Lightroom's [Upright](https://helpx.adobe.com/lightroom-classic/help/guided-upright-perspective-correction.html) modes include Level, Vertical, Auto, Full, and Guided workflows. Guided Upright lets users draw guides that should become horizontal or vertical, which matches the planned manual reference-line model.
- OpenCV's [`HoughLines` / `HoughLinesP`](https://docs.opencv.org/4.x/d9/db0/tutorial_hough_lines.html) and [`LineSegmentDetector`](https://docs.opencv.org/master/db/d73/classcv_1_1LineSegmentDetector.html) are the practical reference algorithms for candidate line extraction. The repo should keep the public data model independent from OpenCV so a future implementation can choose Vision, traditional CPU code, Metal kernels, or a small pre-trained model without changing render semantics.
- FxPlug 4 provides [`FxAnalysis`](https://developer.apple.com/documentation/professional_video_applications/fxanalysisapi) for explicit frame analysis and [`FxOnScreenControl`](https://developer.apple.com/documentation/professional_video_applications/fxonscreencontrolapi_v4) for canvas drawing, hit testing, and mouse events. Automatic and semi-automatic modes should analyze a representative frame, write keyframeable parameters, and let the existing Metal warp renderer handle playback.
- Open-source search did not turn up a usable FxPlug corner-pin onscreen-control implementation. Checked public FxPlug examples and plug-ins include FxKit, Spectra, GyroflowToolbox, pravMotion, FxBrightness, and SpliceKit; they do not provide a working four-corner `FxOnScreenControl` reference. FxFactory Reverse Corner Pin is the closest product UX reference, but it is closed source. Its public product page describes the target behavior as stretching a perspective area defined by four pins into a rectangle, with keyframeable pins for static shots or camera motion.
- For Reverse Corner Pin-style behavior, the closest open implementation references found so far are OBS/StreamFX corner-pin or 3D-transform effects. They are useful for render/math semantics but not for FxPlug OSC interaction because they do not exercise Motion/FCP's object-space to canvas-space conversion, hit testing, or parameter writeback APIs.
- FxPlug angle parameters are handled as radians in the current Motion validation path: `getFloatValue` returns angle slider values in radians, and `setFloatValue` writes angle parameter values that Motion displays after radians-to-degrees conversion. This differs from the FxPlug SDK header comment that says angle writes use degrees, so Horizon and Upright keep internal analysis rotation values in radians and write radians back to angle parameters. The validation history is archived under `.agent-work/debug/`.

## Validation Expectations

For meaningful functionality changes, validate at the lowest level that proves the behavior:

- Geometry math: deterministic unit tests or sample vectors.
- Metal warp: visual test frames or known point mapping checks.
- FxPlug integration: build the wrapper app target and verify the plugin loads in Motion or Final Cut Pro.
- Final Cut behavior: verify published parameters, keyframes, proxy resolution, and clip trim/retime behavior when possible.

Current command-line checks:

```sh
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift AnyUpright/Plugin/AnyUprightUprightCandidates.swift AnyUprightTests/AnyUprightGeometryTests.swift -o /tmp/AnyUprightGeometryTests && /tmp/AnyUprightGeometryTests
xcrun swiftc AnyUpright/Plugin/AnyUprightGeoCalibPreprocessGeometry.swift AnyUprightTests/AnyUprightGeoCalibPreprocessGeometryTests.swift -o /tmp/AnyUprightGeoCalibPreprocessGeometryTests && /tmp/AnyUprightGeoCalibPreprocessGeometryTests
xcrun swiftc AnyUpright/Plugin/AnyUprightGeoCalibOptimizer.swift AnyUprightTests/AnyUprightGeoCalibOptimizerTests.swift -o /tmp/AnyUprightGeoCalibOptimizerTests && /tmp/AnyUprightGeoCalibOptimizerTests /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_optimizer_3
xcrun swiftc AnyUpright/Plugin/AnyUprightGeoCalibNeuralOutput.swift AnyUpright/Plugin/AnyUprightGeoCalibCoreML.swift AnyUprightTests/AnyUprightGeoCalibCoreMLCacheTests.swift -o /tmp/AnyUprightGeoCalibCoreMLCacheTests && /tmp/AnyUprightGeoCalibCoreMLCacheTests /Users/ibobby/Projects/AnyUpright
xcrun swiftc -O AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift AnyUpright/Plugin/AnyUprightGeoCalibNeuralOutput.swift AnyUpright/Plugin/AnyUprightGeoCalibCoreML.swift AnyUpright/Plugin/AnyUprightGeoCalibOptimizer.swift AnyUpright/Plugin/AnyUprightGeoCalibPreprocessGeometry.swift AnyUpright/Plugin/AnyUprightGeoCalibHorizonDetector.swift tools/evaluate-swift-geocalib-rotation.swift -o /tmp/AnyUprightSwiftGeoCalibFullValidationCompileCheck
xcrun swiftc AnyUpright/Plugin/CommandQueuePool.swift AnyUprightTests/AnyUprightMetalDeviceCacheTests.swift -o /tmp/AnyUprightMetalDeviceCacheTests && /tmp/AnyUprightMetalDeviceCacheTests
xcrun swiftc AnyUpright/Plugin/CommandQueuePool.swift tools/stress-metal-device-cache.swift -o /tmp/AnyUprightStressMetalDeviceCache && /tmp/AnyUprightStressMetalDeviceCache
xcrun swiftc tools/validate-fxplug-manifest.swift -o /tmp/AnyUprightValidateManifest && /tmp/AnyUprightValidateManifest .
xcrun swiftc tools/audit-feature-surface.swift -o /tmp/AnyUprightAuditFeatureSurface && /tmp/AnyUprightAuditFeatureSurface .
xcrun swift tools/generate-test-assets.swift .agent-work/test-assets
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift tools/analyze-test-assets.swift -o /tmp/AnyUprightAnalyzeAssets && /tmp/AnyUprightAnalyzeAssets .agent-work/test-assets
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift tools/render-warp-previews.swift -o /tmp/AnyUprightRenderWarpPreviews && /tmp/AnyUprightRenderWarpPreviews .agent-work/test-assets .agent-work/warp-previews
xcrun swiftc tools/validate-warp-previews.swift -o /tmp/AnyUprightValidateWarpPreviews && /tmp/AnyUprightValidateWarpPreviews .agent-work/warp-previews
SDK=$(xcrun --sdk macosx --show-sdk-path) && xcrun swiftc -typecheck AnyUpright/Plugin/*.swift -sdk "$SDK" -F /Library/Developer/SDKs/FxPlug.sdk/Library/Frameworks -F /Library/Developer/Frameworks -I AnyUpright/Plugin -import-objc-header "AnyUpright/Plugin/XPC Service-Bridging-Header.h"
xcodebuild -project AnyUpright.xcodeproj -scheme "Wrapper Application" -configuration Release -derivedDataPath /tmp/AnyUprightDerivedDataRelease build
```

Full 2,000-image GeoCalib validation uses `tools/run-swift-geocalib-full-validation.sh` with the LaMAR2k dataset in `/Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/data/lamar2k`.

If Xcode reports a missing Metal Toolchain during build, install it with Xcode's suggested `xcodebuild -downloadComponent MetalToolchain` before repeating the full build.

When debugging Motion integration, avoid registering multiple builds with the same wrapper bundle ID at the same time. In particular, mixing a `/tmp/AnyUprightDerivedData` build with Xcode's default `~/Library/Developer/Xcode/DerivedData/.../AnyUpright.app` can leave Motion using a stale path-based PlugInKit object; OSC entries may then fail to attach even when the plist is correct. If this happens, quit or kill the stale wrapper/XPC process, unregister the stale wrapper with `lsregister -u /path/to/AnyUpright.app`, rebuild/register the intended wrapper, and then restart Motion or re-add the effect instance.

### Local Test Assets

The repository includes a deterministic Swift generator for host-app validation images:

```sh
xcrun swift tools/generate-test-assets.swift .agent-work/test-assets
```

It writes ignored PNG files under `.agent-work/test-assets/`:

- `horizon-tilted-8deg.png`: a strong 8-degree tilted horizon for `Analyze Horizon`.
- `quad-phone-screen.png`: a skewed phone-screen grid for both Quad modes.
- `upright-facade-perspective.png`: a perspective facade grid for Upright auto, semi-auto, and guided workflows.

`tools/analyze-test-assets.swift` compiles with the shared geometry and line-detection files. It verifies that the generated images produce enough candidate lines, that Horizon's fallback detector preserves Hough vote order for the dominant tilted line, and that Upright can solve bounded parameters from the detected candidates. This is algorithm validation only; it does not replace Motion/FCP onscreen-control testing.

`tools/render-warp-previews.swift` compiles with the shared geometry file and writes preview PNGs under `.agent-work/warp-previews/`:

- `horizon-fill-preview.png`: applies the horizon rotation with fill enabled.
- `quad-inner-stretch-adjuster-preview.png`: keeps the original image still while rendering a CPU reference overlay for Inner Stretch mapping semantics. In the live plug-in, filter output owns the dimming path and OSC owns the interactive outline/handles.
- `quad-inner-stretch-apply-preview.png`: maps the known phone-screen input quadrilateral to the full output frame.
- `quad-output-corners-preview.png`: applies output-corner dragging semantics.
- `upright-centered-preview.png`: applies centered vertical/horizontal perspective plus rotation.

The preview renderer is CPU-only and exists to prove mapping semantics. Playback in Motion and Final Cut still uses the shared Metal warp.

### Motion Validation Checklist

After building the wrapper app, Motion should see four independent FxPlug filters under the AnyUpright group. Use a 1920 x 1080 project and import the generated PNGs as still images.

Horizon:

- Apply `AnyUpright Horizon` to a photo-like tilted frame first. The GeoCalib path is conservative and may reject synthetic line art; use `horizon-tilted-8deg.png` mainly for affine render/fill checks or fallback-path debugging.
- Click `Analyze Horizon`; when GeoCalib accepts the frame, `Rotation` should move near the opposite of the visible tilt and the horizon should level out. When GeoCalib rejects the frame, `Rotation` should remain unchanged.
- Enable `Fill Frame`; the render should zoom enough to hide rotation black edges.

Quad:

- Apply `AnyUpright Inner Stretch` to `quad-phone-screen.png`.
- With `Edit Mode` on, the outside area should be dimmed to 70% brightness while the image itself remains unwarped. The dimming path is filter output and should still appear even if Motion's `Publish OSC` checkbox is off.
- Click `Detect Edge and Corner`; `Edit Mode` and `Choose from detections` should be enabled, the manual inner stretch should not move, and detected independent edges/corners above `Score Threshold` should appear as green lines and green crosses.
- Disable `Choose from detections`; detected green lines/crosses should hide and the manual quad should become hittable again. Re-enable it; hovering detected points or lines should turn them yellow. Selecting four points or four lines should write the Inner Stretch to that proposed quadrilateral and automatically disable `Choose from detections`.
- In Final Cut Pro, verify the `Inner Stretch` effect inspector shows `Edit Mode`, `Choose from detections`, `Score Threshold`, and a `Detect Edge and Corner` button after restarting FCP. If only `Edit Mode` appears, the Motion template is missing the published push-button, choice, and threshold targets.
- Enable `Publish OSC` when testing the interactive outline and handles. The four handles should start at the central 80% of the frame, and dragging them around the phone-screen quadrilateral should not warp the image while editing.
- The four corner coordinate groups should be hidden in Inner Stretch because positioning happens through onscreen handles.
- Turn `Edit Mode` off; the selected screen quadrilateral should map to the full output frame and the handles should be hidden.
- Apply `AnyUpright Outer Stretch` to `quad-phone-screen.png`.
- Drag the four onscreen handles; the image should warp in realtime.
- `Edit Mode` should be hidden and the four corner coordinate groups should be visible in Outer Stretch.

Upright:

- Apply `AnyUpright Upright` to `upright-facade-perspective.png`.
- The inspector should expose only `Direction`, `Analyze`, `Mode`, `Auto Crop`, and `Edit Mode`.
- With `Edit Mode` on, the image should remain unwarped and Upright OSC should appear inside the actual video frame, not at absolute preview-window coordinates.
- In `Manual` mode, switch `Direction` between `Vertical`, `Horizontal`, and `Full`; only the matching default guide lines should appear. Drag endpoints to update correction, then click a guide line to disable it and verify its endpoints become gray.
- Turn `Edit Mode` off; the stored correction should render through the shared Metal warp and all Upright OSC should disappear. Toggle `Auto Crop` and verify it zooms the rendered correction to avoid exposed source edges when possible.
- In `Semi Auto` mode, click `Analyze`; only analyzed candidate lines matching `Direction` should be drawn and hittable. Clicking candidates should toggle correction selection without allowing more than two selected lines per orientation.
- In `Full Auto` mode, click `Analyze`; the plug-in should select and apply the two highest-scoring included candidate lines automatically.

## Open Decisions

- Whether Motion template files should be tracked in the repository or generated/copied from a documented local template location.
- Minimum supported macOS, Final Cut Pro, Motion, Xcode, and FxPlug SDK versions.
- Code signing, notarization, and distribution model.
- Multi-locale policy beyond the current `en.lproj` template resources.
- Xcode Test Navigator integration for the current lightweight geometry tests.
- Automated Metal shader validation.

## Motion And Final Cut Templates

This repository currently ships the four effects as FxPlug filters registered by the wrapper app. Motion or Final Cut template files are not tracked yet. If a template-based distribution is required later, run the wrapper app once so macOS registers the plug-in, apply each FxPlug filter in Motion, publish the intended parameters, and save four separate Final Cut Effect templates.

For Final Cut templates that need onscreen dragging, the Motion template must include the host `Publish OSC` setting for the FxPlug filter. In the local `.moef` XML this appears as the built-in filter parameter `id="10005"` with `name="Publish OSC"` and `value="1"`. Publishing only user-facing parameters such as `Edit Mode` is not enough: Final Cut can still render Inner Stretch's filter-output dimming, but it may not instantiate or dispatch mouse events to the `FxOnScreenControl` that draws and hits the interactive handles.

The current local development Final Cut templates live under `~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/`. `Inner Stretch/Inner Stretch.moef` publishes Inner Stretch controls; `Horizon/Horizon.moef` publishes only `Analyze Horizon` (`./102`), `Rotation` (`./100`), and `Fill Frame` (`./101`). `Upright/Upright.moef` should publish the five visible controls `Direction`, `Analyze`, `Mode`, `Auto Crop`, and `Edit Mode`, plus the built-in `Publish OSC` setting. After adding or changing a local template, restart Final Cut Pro before judging Effects Browser visibility.
