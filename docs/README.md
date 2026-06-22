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
- Quad Source edit-mode dimming is rendered into the filter output itself, so the selected source area follows the video image even when host OSC drawing is unavailable. The interactive outline, handles, hover highlights, hit testing, and drag writeback are owned by the FxPlug OSC layer.
- `tools/render-warp-previews.swift` generates CPU-rendered preview PNGs from the same geometry matrices used by the Metal renderer, so matrix semantics can be checked without launching a host app.

## Engineering Notes

If you are a person or agent debugging FxPlug coordinate flips, Final Cut/Motion OSC hit testing, viewer-vs-video drift, `drawOSC` drawable sizing, or tiled render sampling shifts, start with `docs/engineering-notes/`.

## Effects

### AnyUpright Horizon

Automatically detects a horizontal reference line in the current frame and applies a rotation correction across the clip.

Product scope:

- Horizon is the rotation-only leveling effect. It is for shots where the camera was rolled slightly and a centered affine rotation is the most natural correction.
- Horizon analysis may use a detected horizon, line slope, vanishing/up direction, or learned camera-calibration cue to estimate roll, but it should write only `Rotation` for this effect. It should not write perspective, keystone, Source Quad, Outer Corners, pitch, FoV, or homography parameters.
- Research notes, dataset options, and roll-only validation criteria are recorded in `docs/horizon-rotation-research.md`.

Current implementation:

- `AnyUpright Horizon Manual` is registered as a separate FxPlug filter.
- `Rotation` is a manual angle slider.
- `Fill Frame` controls whether the rotated image is zoomed enough to avoid black edges.
- `Analyze Horizon` starts FxAnalysis near the current parameter time when the host provides one, runs the project-owned GeoCalib Core ML roll detector with Swift preprocessing, verifier gate, and optimizer glue, and writes only the accepted centered rotation correction back to `Rotation`.
- GeoCalib writeback is accepted only when `roll_uncertainty <= 3 deg`, the absolute correction is within the Horizon `+/-45 deg` product range, and fewer than two available verifiers disagree with GeoCalib by more than 10 degrees. The current in-plugin verifiers are project Hough-axis and gradient-axis estimates; rejected GeoCalib results produce no writeback.
- The in-plugin Core ML path uses an XPC-process shared cache keyed by fixed input shape. Adding the effect configures both model resources and prewarms the common `[1, 3, 320, 416]` landscape model; the `[1, 3, 416, 320]` portrait model is loaded only if analysis needs it. Cached Core ML sessions expire after 15 seconds without analysis, extend to 30 seconds from the next analysis start, and extend to 60 seconds when two analyses happen inside that 30-second window.
- Verifiers run only after the primary GeoCalib result passes the uncertainty and `+/-45 deg` product gate; this keeps rejected frames from paying verifier cost while preserving the two-verifier rejection rule for candidate writebacks.
- If the Core ML GeoCalib resources or model execution are unavailable, the implementation falls back to the previous project-owned Swift/Metal GeoCalib runtime, then to Vision horizon detection, and then to the shared Sobel/Hough horizontal-line detector.
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
- `AnyUpright Source Quad` is registered as a separate FxPlug filter. It fixes the shared Quad render path to `Source Quad` semantics.
- `AnyUpright Outer Corners` is registered as a separate FxPlug filter. It fixes the shared Quad render path to output/outer-corner warp semantics.
- The old inspector `Mode` popup is now a hidden fixed parameter so each filter keeps stable render state without asking the user to switch modes inside one effect.
- `Detect Source Quad` is exposed as a custom FxPlug inspector button, backed by a non-animatable custom parameter with `kFxParameterFlag_CUSTOM_UI`. The custom parameter uses an empty `NSData` value and the Swift plug-in keeps strong references to every AppKit `NSButton` view returned from `createView(forParameterID:)` for the XPC process lifetime so host-side custom UI rebuilds or plug-in teardown cannot release a Swift view prematurely. Clicking it starts FxAnalysis near the current parameter time and runs independent edge/corner detection, but it no longer moves the current Source Quad. Instead it writes hidden edge and corner primitive slots with normalized 0...1 scores, enables `Edit Mode`, and enables `Choose from detections`. `Choose from detections` controls both OSC display and hit testing for detected primitives: when enabled, detected edges/corners above `Score Threshold` are drawn above the existing manual handles, and hit testing changes from the manual quad to detected primitives. Selecting four detected corners or four detected lines writes the Source Quad to that proposed quadrilateral, then automatically exits detection-choice mode. Final Cut Pro only shows the button, choice toggle, and threshold when the Motion template publish settings include the custom parameter target (channel `./216`), choice target (channel `./218`), and threshold target (channel `./217` in the current `Quad.moef`); if FCP shows only `Edit Mode`, publish/save those parameters in Motion or add the matching publish targets, then restart FCP. The current template gives the button's published target a blank display name so FCP visually shows only the momentary `Detect Edge and Corner` button, not an extra `Detect Source Quad` label.
- `Edit Mode` is shown only in `AnyUpright Source Quad`. It is enabled by default: when enabled, the filter output keeps the image unwarped and dims the area outside the current source quadrilateral, while the draggable outline and handles are drawn in the OSC overlay. Disable it to hide the adjuster and stretch the selected source quadrilateral to the full output frame.
- In `AnyUpright Source Quad`, the default source quadrilateral is the central 80% of the frame. The 100% full-frame selection is still covered as an identity/no-offset geometry case for validation. The edit preview dims the outside area to 70% brightness and leaves the selected quadrilateral at original brightness. The OSC overlay connects the four handles with a white outline and draws blue fixed-size circular handles, with yellow hover/drag highlights. Detected candidate edges are drawn as green lines and detected candidate corners are drawn as green crosses only while `Edit Mode` and `Choose from detections` are enabled; hovered or selected detection primitives use the same yellow highlight color as manual quad dragging.
- In `AnyUpright Outer Corners`, each visible output corner exposes `X %`, `Y %`, `X px`, and `Y px` offsets in the inspector.
- In `AnyUpright Source Quad`, the corner coordinate groups are hidden from the inspector; users position the source quadrilateral with onscreen handles.
- Final offset is `percentage * current frame dimension + pixels`.
- Positive `X` moves right. Positive `Y` moves up.
- In `AnyUpright Outer Corners`, the four offsets are a destination/output quadrilateral and map back to the full source frame, matching the direction a user sees in the Motion canvas.
- In `AnyUpright Source Quad`, the same corner offset parameters describe a source quadrilateral that maps to the full output frame, matching a document-scanner or Microsoft Lens style correction. Those parameter groups are hidden in the inspector while this filter is active.
- The visible `Source Quad` edit UI is split across two layers. The filter output layer keeps an identity preview and dims outside the selected source quadrilateral, so users can tell `Edit Mode` is still active. The Source Quad `FxOnScreenControl` draws the white outline, blue handles, and yellow hover/drag highlights in host canvas space, so handles can remain visible and draggable outside the video frame. For Final Cut raw-canvas events, the OSC outline and hit layer use the same source-preview geometry as the filter output; the unflipped object/canvas quad is kept for storage/writeback diagnostics. Final Cut host connections disable Motion-style mapped-surface fallback during initial Source Quad hover/hit tests so raw canvas points above or outside the video frame cannot fold into an invisible hit layer. Motion-style surface-local event points are mapped back to canvas coordinates for Motion and unknown hosts when needed, but visible Final Cut raw-canvas controls outside the object frame keep raw hit testing. OSC control points are drawn from host canvas-frame points instead of output-image aspect-fit space: X and Y both stay in host canvas pixels, with no frame-center compensation, surface-scale compensation, clamping, Fit renormalization, or renderer-level vertical mirroring. Source Quad dragging crosses the preview/object Y boundary explicitly, writes hidden source-corner percentage offsets, and clears matching pixel offsets so the render-time source quad is independent of OSC surface resolution. Outer Corners uses its own OSC entry and writes output-corner pixel offsets while preserving any existing percentage offset. See `docs/engineering-notes/y-axis-coordinate-conventions.md`, `docs/engineering-notes/quad-osc-hit-testing.md`, and `docs/engineering-notes/quad-osc-rendering.md` before changing this path.
- A hidden point-parameter experiment was intentionally backed out: Motion accepted `setXValue(_:yValue:)` during OSC drags but subsequent reads still returned the default points. Source Quad now uses the float-parameter path because Motion was verified to persist those writes.

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

- `AnyUpright Upright Manual` is registered as a separate FxPlug filter.
- `Vertical Perspective` uses a centered keystone transform around the horizontal centerline. Positive values move the top inward and bottom outward; negative values move the top outward and bottom inward.
- `Horizontal Perspective` uses a centered keystone transform around the vertical centerline. Positive values move the right side inward and left side outward; negative values move the right side outward and left side inward.
- `Rotation` applies a manual rotation around the frame center.
- Internally this implementation treats upright perspective as a destination/output quadrilateral and maps it back to the full source frame. Fill, crop, and position are intentionally separate future steps.
- The centered keystone math is tested at the homography level: vertical, horizontal, and combined perspective transforms keep the frame center anchored instead of acting like edge-pivot shears.
- `Auto Vertical`, `Auto Horizontal`, and `Auto Full` start FxAnalysis near the current parameter time, downsample it, run the shared Sobel/Hough candidate-line detector, choose up to two references whose deviation from the requested axis is strictly less than 30 degrees, and write estimated values back to the existing sliders. Full mode also writes `Rotation` from the selected horizontal references, or vertical references when no horizontal references are available.
- Four editable guide lines are exposed as point parameters and onscreen line handles. The first two default to vertical references; the last two default to horizontal references.
- `Apply Guided Vertical`, `Apply Guided Horizontal`, and `Apply Guided Full` convert enabled guide lines into the existing keyframeable `Vertical Perspective`, `Horizontal Perspective`, and, for full mode, `Rotation` parameters.
- `Detect Vertical Candidates`, `Detect Horizontal Candidates`, and `Detect Full Candidates` fill up to 40 static candidate slots with detected lines whose deviation from the requested axis is strictly less than 30 degrees. Full mode reserves half the slots for vertical candidates and half for horizontal candidates.
- Candidate lines are drawn in the onscreen overlay. Blue means visible but not selected; green means selected; yellow means the active hit-tested line. Clicking a candidate line toggles the same `Selected` checkbox exposed in the inspector, but onscreen clicks will not add a third selected line for the same orientation.
- `Apply Selected Vertical`, `Apply Selected Horizontal`, and `Apply Selected Full` use the selected candidate lines, capped at two per orientation, and write the same keyframeable transform parameters used by manual and full-auto modes. This cap is also enforced during apply if the inspector is edited directly.

Implemented controls:

- Manual vertical, horizontal, and rotation axes.
- Four manually drawn reference lines.
- Vertical transform from detected or selected near-vertical lines.
- Horizontal transform from detected or selected near-horizontal lines.
- Full transform combining vertical and horizontal references.

Automation levels:

- Full auto: detect candidate lines and choose references automatically.
- Semi auto: display candidates and allow the user to choose one or two references.
- Manual: user draws or adjusts references directly.
- The semi-auto implementation uses fixed candidate slots rather than dynamic UI rows, and it does not yet draw text labels or expose line-strength scoring.

Primary risks:

- Automatic scoring quality. Angle alone is not enough; line length, strength, spatial separation, and geometric consistency should be part of candidate ranking.
- UX complexity from combining manual axes, drawn lines, detected candidates, and keyframes.
- Avoiding realtime playback cost from frame analysis.

## Architecture Direction

Use one repository and one product suite, but expose four separate Final Cut effects. Shared implementation should live behind small common modules:

- Geometry: normalized points, lines, homography, affine transforms, vanishing-point helpers, and coordinate conversion.
- Detection: frame downsampling, edge/line detection, candidate scoring, and analysis result serialization.
- Rendering: shared Metal pipeline for affine and projective texture warps.
- UI/controls: image-space edit dimming in the filter render output, reusable Metal onscreen overlay drawing for OSC visuals, canvas-space hit testing, object/canvas conversion through `FxOnScreenControlAPI_v4`, and parameter writeback where FxPlug APIs permit it.
- FxPlug OSC registration: Source Quad, Outer Corners, and Upright use separate OSC classes linked with `supportedPlugins`. Apple documentation describes this as the expected shape for onscreen controls, and an installed Pixel Film Studios FxPlug (`PFSMaskV2`) uses the same `supportedPlugins` key in its plist. If Motion does not call OSC methods, first suspect stale PlugInKit registration or host instance caching before changing coordinate math. In Motion's Metal OSC path, the `drawOSC` width/height values can describe the source object, while the drawable tile is represented by `destinationImage`; host OSC surfaces should map canvas coordinates to the destination texture/tile dimensions instead of treating `width` and `height` as the viewport. In Final Cut's zoomed viewer path, Source Quad OSC drawing keeps host canvas X and Y direct; the reusable overlay renderer flips Y only when converting those surface pixels into centered Metal vertex coordinates. If vertical pan drift appears, compare the host callback canvas points and X/Y symmetry before adding Y-specific math. Source Quad edit-mode dimming is rendered by the filter output so it follows the clip/image, while Source Quad OSC owns the interactive outline, handles, hover highlights, hit testing, and drag writeback. Creating `/tmp/AnyUprightQuadOSC.debug` enables temporary OSC coordinate logging to `/tmp/AnyUprightQuadOSC.log`; creating `/tmp/AnyUprightGeoCalib.debug` enables Horizon GeoCalib analysis logging to `/tmp/anyupright-geocalib-debug.log`. Leave both flags absent during normal use.
- Quad object-space conversion: `AnyUprightGeometry.quadObjectPoints`, `sourceQuadObjectPoints`, `sourceCornerPercentOffset`, and `cornerPixelOffset` own the Motion/FxPlug handle coordinate semantics so corner names, X direction, and Y direction stay testable outside the host app. `Source Quad` stores the four handles as hidden percent offsets during OSC drags; `Outer Corners` exposes the same offset parameters in the inspector.
- Upright candidate slots: fixed inspector slot IDs, object/image coordinate conversion, selection limits, and onscreen hit testing live in `AnyUprightUprightCandidates.swift`; FxPlug parameter read/write remains in the effect class.
- Coordinate-system notes: Y-axis semantics differ across image/output pixels, FxPlug object space, host canvas events, Metal overlay drawing, viewer/video rectangles, and render tile sampling. Start with `docs/engineering-notes/quad-coordinate-layer-contract.md`, then read the focused Quad notes under `docs/engineering-notes/` before changing Y-axis conversion, hit testing, OSC drawing, parameter writeback, or Source Quad edit-preview sampling.

Playback rendering should use precomputed parameters only. Detection should be explicit, cached, or analysis-driven instead of happening on every frame.

The current traditional line detector is a CPU reference implementation based on Sobel edges, gradient-constrained Hough voting, and simple non-maximum suppression. It is intended to provide candidate lines for automatic and semi-automatic workflows; exact transform parameters are still solved by the shared geometry layer from the selected reference lines.

### Research Notes

- Apple Vision has [`VNDetectHorizonRequest`](https://developer.apple.com/documentation/vision/vndetecthorizonrequest), whose result is a `VNHorizonObservation`; this remains the lightweight fallback if the GeoCalib runtime cannot run.
- Roll-only horizon leveling research is tracked in `docs/horizon-rotation-research.md`. Keep this separate from Source Quad, Outer Corners, and centered perspective correction research: the current Horizon milestone validates only rotation angle accuracy and affine rotation render behavior.
- Current Horizon implementation uses GeoCalib primary roll estimation gated by `roll_uncertainty <= 3 deg` plus rejection when two or more lightweight verifiers disagree by more than 10 degrees. The Swift/Core ML migration was verified against the Python fixed-NMF baseline on the 2,000-image LaMAR2k rotation set before project integration. Project-owned pieces now include GeoCalib preprocessing/gate/verifier glue in `AnyUprightGeoCalibHorizonDetector.swift`, the LM optimizer in `AnyUprightGeoCalibOptimizer.swift`, the Core ML neural-forward runtime and shared plugin cache in `AnyUprightGeoCalibCoreML.swift`, the ignored local Core ML model bundle under `AnyUpright/Plugin/GeoCalibCoreML/`, and the previous Swift/Metal runtime bundle under `AnyUpright/Plugin/GeoCalibRuntime/` as fallback. Motion and Final Cut Pro 12.2 have both been verified to run `Analyze Horizon`, accept GeoCalib results, and write only `Rotation`.
- Horizon host analysis renders the source frame to an RGB analysis image capped at 1920 pixels on the long edge before the project-owned GeoCalib preprocessing step. This avoids multi-minute work on very high resolution stills while preserving the same model, optimizer, uncertainty, verifier, and writeback semantics.
- Performance validation should use the `Wrapper Application` Release build; Debug uses Swift `-Onone` and Metal debug info. Creating `/tmp/AnyUprightGeoCalib.debug` enables Horizon GeoCalib host logs in both Debug and Release at `/tmp/anyupright-geocalib-debug.log`, including click-to-cleanup, RGB render, preprocessing, Core ML cache/load/predict, optimizer gate, verifier, and writeback timings.
- `tools/build-geocalib-runtime-bundle.py` creates a slim GeoCalib runtime bundle from the verified neural-forward fixture. It copies only the 754 runtime weight tensors and writes a manifest without fixture `entries`; it intentionally excludes test input and expected-output tensors. The generated bundle is flat because Xcode synchronized folders copy loose resources into `Contents/Resources`.
- Apple Vision also has [`VNDetectRectanglesRequest`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest) and [`VNDetectDocumentSegmentationRequest`](https://developer.apple.com/documentation/vision/vndetectdocumentsegmentationrequest), both of which can return rectangle corner observations. These are useful for proposing a Lens-style source quadrilateral, but the current Source Quad detection overlay intentionally uses independent line/corner primitives so it can show multiple plausible edges and intersections without forcing them into closed rectangles.
- Core Image's [`CIFilter.perspectiveCorrection()`](https://developer.apple.com/documentation/coreimage/cifilter/3228380-perspectivecorrection) is the platform reference for source-quadrilateral-to-rectangular-output semantics: four input image corners map to the output image corners. AnyUpright uses its own Metal renderer for FxPlug playback, but the Quad `Source Quad` mode follows the same conceptual direction.
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
xcrun swiftc AnyUpright/Plugin/AnyUprightGeoCalibNeuralPrototype.swift AnyUpright/Plugin/AnyUprightGeoCalibRuntimeBundle.swift AnyUprightTests/AnyUprightGeoCalibRuntimeBundleTests.swift -o /tmp/AnyUprightGeoCalibRuntimeBundleTests && /tmp/AnyUprightGeoCalibRuntimeBundleTests AnyUpright/Plugin/GeoCalibRuntime
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift AnyUpright/Plugin/AnyUprightGeoCalibNeuralPrototype.swift AnyUpright/Plugin/AnyUprightGeoCalibRuntimeBundle.swift AnyUpright/Plugin/AnyUprightGeoCalibOptimizer.swift AnyUpright/Plugin/AnyUprightGeoCalibHorizonDetector.swift AnyUprightTests/AnyUprightGeoCalibPreprocessorTests.swift -o /tmp/AnyUprightGeoCalibPreprocessorTests && /tmp/AnyUprightGeoCalibPreprocessorTests
xcrun swiftc AnyUpright/Plugin/AnyUprightGeoCalibOptimizer.swift AnyUprightTests/AnyUprightGeoCalibOptimizerTests.swift -o /tmp/AnyUprightGeoCalibOptimizerTests && /tmp/AnyUprightGeoCalibOptimizerTests /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_optimizer_3
xcrun swiftc AnyUpright/Plugin/AnyUprightGeoCalibNeuralPrototype.swift AnyUprightTests/AnyUprightGeoCalibNeuralForwardTests.swift -o /tmp/AnyUprightGeoCalibNeuralForwardTests && /tmp/AnyUprightGeoCalibNeuralForwardTests /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_neural_forward_3 AnyUpright/Plugin/AnyUprightGeoCalib.metal /tmp/AnyUprightGeoCalibNeuralForwardSummary.json
xcrun swiftc AnyUpright/Plugin/AnyUprightGeoCalibNeuralPrototype.swift AnyUpright/Plugin/AnyUprightGeoCalibRuntimeBundle.swift AnyUpright/Plugin/AnyUprightGeoCalibCoreML.swift AnyUprightTests/AnyUprightGeoCalibCoreMLCacheTests.swift -o /tmp/AnyUprightGeoCalibCoreMLCacheTests && /tmp/AnyUprightGeoCalibCoreMLCacheTests
xcrun swiftc AnyUpright/Plugin/AnyUprightGeoCalibNeuralPrototype.swift AnyUpright/Plugin/AnyUprightGeoCalibRuntimeBundle.swift AnyUpright/Plugin/AnyUprightGeoCalibOptimizer.swift AnyUprightTests/AnyUprightGeoCalibEndToEndTests.swift -o /tmp/AnyUprightGeoCalibEndToEndTests && /tmp/AnyUprightGeoCalibEndToEndTests /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_neural_forward_3 /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_optimizer_3 AnyUpright/Plugin/GeoCalibRuntime AnyUpright/Plugin/AnyUprightGeoCalib.metal
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift AnyUpright/Plugin/AnyUprightGeoCalibNeuralPrototype.swift AnyUpright/Plugin/AnyUprightGeoCalibRuntimeBundle.swift AnyUpright/Plugin/AnyUprightGeoCalibOptimizer.swift AnyUpright/Plugin/AnyUprightGeoCalibHorizonDetector.swift AnyUprightTests/AnyUprightGeoCalibHorizonDetectorTests.swift -o /tmp/AnyUprightGeoCalibHorizonDetectorTests && /tmp/AnyUprightGeoCalibHorizonDetectorTests /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_neural_forward_3 /Users/ibobby/Temp/AnyUprightAlgorithmWorkDirectory/fixtures/geocalib_optimizer_3 AnyUpright/Plugin/GeoCalibRuntime AnyUpright/Plugin/AnyUprightGeoCalib.metal
xcrun swiftc AnyUpright/Plugin/CommandQueuePool.swift AnyUprightTests/AnyUprightMetalDeviceCacheTests.swift -o /tmp/AnyUprightMetalDeviceCacheTests && /tmp/AnyUprightMetalDeviceCacheTests
xcrun swiftc AnyUpright/Plugin/CommandQueuePool.swift tools/stress-metal-device-cache.swift -o /tmp/AnyUprightStressMetalDeviceCache && /tmp/AnyUprightStressMetalDeviceCache
xcrun swiftc tools/validate-fxplug-manifest.swift -o /tmp/AnyUprightValidateManifest && /tmp/AnyUprightValidateManifest .
xcrun swiftc tools/audit-feature-surface.swift -o /tmp/AnyUprightAuditFeatureSurface && /tmp/AnyUprightAuditFeatureSurface .
xcrun swift tools/generate-test-assets.swift .agent-work/test-assets
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift tools/analyze-test-assets.swift -o /tmp/AnyUprightAnalyzeAssets && /tmp/AnyUprightAnalyzeAssets .agent-work/test-assets
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift tools/render-warp-previews.swift -o /tmp/AnyUprightRenderWarpPreviews && /tmp/AnyUprightRenderWarpPreviews .agent-work/test-assets .agent-work/warp-previews
xcrun swiftc tools/validate-warp-previews.swift -o /tmp/AnyUprightValidateWarpPreviews && /tmp/AnyUprightValidateWarpPreviews .agent-work/warp-previews
python3 tools/build-geocalib-runtime-bundle.py --out /tmp/AnyUprightGeoCalibRuntimeBundle
SDK=$(xcrun --sdk macosx --show-sdk-path) && xcrun swiftc -typecheck AnyUpright/Plugin/*.swift -sdk "$SDK" -F /Library/Developer/SDKs/FxPlug.sdk/Library/Frameworks -F /Library/Developer/Frameworks -I AnyUpright/Plugin -import-objc-header "AnyUpright/Plugin/XPC Service-Bridging-Header.h"
xcodebuild -project AnyUpright.xcodeproj -scheme "Wrapper Application" -configuration Debug -derivedDataPath /tmp/AnyUprightDerivedData build
```

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
- `quad-source-adjuster-preview.png`: keeps the original image still while rendering a CPU reference overlay for Source Quad mapping semantics. In the live plug-in, filter output owns the dimming path and OSC owns the interactive outline/handles.
- `quad-source-apply-preview.png`: maps the known phone-screen source quadrilateral to the full output frame.
- `quad-output-corners-preview.png`: applies output-corner dragging semantics.
- `upright-centered-preview.png`: applies centered vertical/horizontal perspective plus rotation.

The preview renderer is CPU-only and exists to prove mapping semantics. Playback in Motion and Final Cut still uses the shared Metal warp.

### Motion Validation Checklist

After building the wrapper app, Motion should see four independent FxPlug filters under the AnyUpright group. Use a 1920 x 1080 project and import the generated PNGs as still images.

Horizon:

- Apply `AnyUpright Horizon Manual` to a photo-like tilted frame first. The GeoCalib path is conservative and may reject synthetic line art; use `horizon-tilted-8deg.png` mainly for affine render/fill checks or fallback-path debugging.
- Click `Analyze Horizon`; when GeoCalib accepts the frame, `Rotation` should move near the opposite of the visible tilt and the horizon should level out. When GeoCalib rejects the frame, `Rotation` should remain unchanged.
- Enable `Fill Frame`; the render should zoom enough to hide rotation black edges.

Quad:

- Apply `AnyUpright Source Quad` to `quad-phone-screen.png`.
- With `Edit Mode` on, the outside area should be dimmed to 70% brightness while the image itself remains unwarped. The dimming path is filter output and should still appear even if Motion's `Publish OSC` checkbox is off.
- Click `Detect Edge and Corner`; `Edit Mode` and `Choose from detections` should be enabled, the manual source quad should not move, and detected independent edges/corners above `Score Threshold` should appear as green lines and green crosses.
- Disable `Choose from detections`; detected green lines/crosses should hide and the manual quad should become hittable again. Re-enable it; hovering detected points or lines should turn them yellow. Selecting four points or four lines should write the Source Quad to that proposed quadrilateral and automatically disable `Choose from detections`.
- In Final Cut Pro, verify the `Quad` effect inspector shows `Edit Mode`, `Choose from detections`, `Score Threshold`, and a `Detect Edge and Corner` button after restarting FCP. If only `Edit Mode` appears, the Motion template is missing the published custom-parameter, choice, and threshold targets.
- Enable `Publish OSC` when testing the interactive outline and handles. The four handles should start at the central 80% of the frame, and dragging them around the phone-screen quadrilateral should not warp the image while editing.
- The four corner coordinate groups should be hidden in Source Quad because positioning happens through onscreen handles.
- Turn `Edit Mode` off; the selected screen quadrilateral should map to the full output frame and the handles should be hidden.
- Apply `AnyUpright Outer Corners` to `quad-phone-screen.png`.
- Drag the four onscreen handles; the image should warp in realtime.
- `Edit Mode` should be hidden and the four corner coordinate groups should be visible in Outer Corners.

Upright:

- Apply `AnyUpright Upright Manual` to `upright-facade-perspective.png`.
- Manual `Vertical Perspective`, `Horizontal Perspective`, and `Rotation` should be keyframeable and should all render through the shared Metal warp.
- Drag the four guide-line endpoints and click `Apply Guided Vertical`, `Apply Guided Horizontal`, or `Apply Guided Full`; the matching sliders should update.
- Click `Auto Vertical`, `Auto Horizontal`, or `Auto Full`; the plugin should analyze near the current parameter time and write the matching transform parameters.
- Click `Detect Vertical Candidates`, `Detect Horizontal Candidates`, or `Detect Full Candidates`; detected lines should appear in the onscreen overlay and inspector candidate slots. Blue lines are visible but unselected, green lines are selected, and clicking a line toggles its selected state without allowing more than two selected lines per orientation.
- Click `Apply Selected Vertical`, `Apply Selected Horizontal`, or `Apply Selected Full`; the selected candidate lines, capped at two per orientation, should update the same transform parameters used by manual and auto modes.

## Open Decisions

- Whether Motion template files should be tracked in the repository or generated/copied from a documented local template location.
- Minimum supported macOS, Final Cut Pro, Motion, Xcode, and FxPlug SDK versions.
- Code signing, notarization, and distribution model.
- Multi-locale policy beyond the current `en.lproj` template resources.
- Xcode Test Navigator integration for the current lightweight geometry tests.
- Automated Metal shader validation.

## Motion And Final Cut Templates

This repository currently ships the four effects as FxPlug filters registered by the wrapper app. Motion or Final Cut template files are not tracked yet. If a template-based distribution is required later, run the wrapper app once so macOS registers the plug-in, apply each FxPlug filter in Motion, publish the intended parameters, and save four separate Final Cut Effect templates.

For Final Cut templates that need onscreen dragging, the Motion template must include the host `Publish OSC` setting for the FxPlug filter. In the local `.moef` XML this appears as the built-in filter parameter `id="10005"` with `name="Publish OSC"` and `value="1"`. Publishing only user-facing parameters such as `Edit Mode` is not enough: Final Cut can still render Source Quad's filter-output dimming, but it may not instantiate or dispatch mouse events to the `FxOnScreenControl` that draws and hits the interactive handles.

The current local development Final Cut templates live under `~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/`. `Quad/Quad.moef` publishes Source Quad controls; `Horizon/Horizon.moef` publishes only `Analyze Horizon` (`./102`), `Rotation` (`./100`), and `Fill Frame` (`./101`). After adding or changing a local template, restart Final Cut Pro before judging Effects Browser visibility.
