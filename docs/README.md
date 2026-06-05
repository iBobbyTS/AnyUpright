# AnyUpright

AnyUpright is a suite of FxPlug effects for single-frame-assisted perspective and upright correction. The effects target fixed-camera or mostly static correction workflows where analysis and manual setup happen on one representative frame, while the resulting transform persists across the whole clip and supports host keyframes through published parameters.

## Current State

- The repository is initialized as an Xcode FxPlug 4 project.
- The template brightness filter has been replaced with three separate FxPlug filters under the `AnyUpright` group.
- No Motion template files are tracked here yet; the current product is the registered FxPlug filters.
- There is no package manager, Docker runtime, or CI workflow yet.
- Geometry tests live in `AnyUprightTests/` and can be run as a lightweight Swift executable.
- The shared geometry layer now includes line candidate filtering, horizon correction estimation, and centered perspective parameter estimation from reference lines.
- Quad and Upright expose FxPlug onscreen controls in addition to inspector parameters.
- `tools/render-warp-previews.swift` generates CPU-rendered preview PNGs from the same geometry matrices used by the Metal renderer, so matrix semantics can be checked without launching a host app.

## Effects

### AnyUpright Horizon

Automatically detects a horizontal reference line in the current frame and applies a rotation correction across the clip.

Current implementation:

- `AnyUpright Horizon Manual` is registered as a separate FxPlug filter.
- `Rotation` is a manual angle slider.
- `Fill Frame` controls whether the rotated image is zoomed enough to avoid black edges.
- `Analyze Horizon` starts FxAnalysis near the current parameter time when the host provides one, runs Vision horizon detection, and writes the detected correction back to `Rotation`.
- If Vision does not return a horizon observation, the implementation falls back to the shared Sobel/Hough horizontal-line detector and estimates rotation from the best near-horizontal references.
- Horizon analysis writeback debugging notes live in `docs/debug/2026-06-05-horizon-analysis-writeback.md`.

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

Provides manual four-point perspective transforms.

Current implementation:

- `AnyUpright Quad Manual` is registered as a separate FxPlug filter.
- `Mode` selects `Output Corners` or `Source Quad`.
- `Apply Source Quad` is shown only in `Source Quad` mode. It controls whether source-quad edits are rendered: leave it off while positioning handles, then enable it to map the selected source quadrilateral to the full output frame.
- In `Output Corners` mode, each visible output corner exposes `X %`, `Y %`, `X px`, and `Y px` offsets in the inspector.
- In `Source Quad` mode, the corner coordinate groups are hidden from the inspector; users position the source quadrilateral with onscreen handles.
- Final offset is `percentage * current frame dimension + pixels`.
- Positive `X` moves right. Positive `Y` moves up.
- In `Output Corners` mode, the four offsets are a destination/output quadrilateral and map back to the full source frame, matching the direction a user sees in the Motion canvas.
- In `Source Quad` mode, the four offsets describe a source quadrilateral that maps to the full output frame, matching a document-scanner or Microsoft Lens style correction.
- The current onscreen control draws the active quadrilateral and four handles in object space. Dragging a handle writes the corresponding pixel offset while preserving any existing percentage offset.

Two intended modes:

1. Source quad to full frame: user drags four points around an object such as a phone screen; editing can display handles without moving the image, and applying maps that quadrilateral to the original frame size.
2. Frame-corner warp: user drags the four output corners and sees the warped image in realtime; the stretched result is the actual output.

Primary risks:

- Coordinate consistency across canvas space, source pixels, proxy resolution, and Final Cut project settings.
- Onscreen control usability.
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

Use one repository and one product suite, but expose three separate Final Cut effects. Shared implementation should live behind small common modules:

- Geometry: normalized points, lines, homography, affine transforms, vanishing-point helpers, and coordinate conversion.
- Detection: frame downsampling, edge/line detection, candidate scoring, and analysis result serialization.
- Rendering: shared Metal pipeline for affine and projective texture warps.
- UI/controls: reusable Metal onscreen overlay drawing, object-space hit testing, and parameter writeback where FxPlug APIs permit it.
- Quad object-space conversion: `AnyUprightGeometry.quadObjectPoints` and `cornerPixelOffset` own the Motion/FxPlug handle coordinate semantics so corner names, X direction, and Y direction stay testable outside the host app.
- Upright candidate slots: fixed inspector slot IDs, object/image coordinate conversion, selection limits, and onscreen hit testing live in `AnyUprightUprightCandidates.swift`; FxPlug parameter read/write remains in the effect class.

Playback rendering should use precomputed parameters only. Detection should be explicit, cached, or analysis-driven instead of happening on every frame.

The current traditional line detector is a CPU reference implementation based on Sobel edges, gradient-constrained Hough voting, and simple non-maximum suppression. It is intended to provide candidate lines for automatic and semi-automatic workflows; exact transform parameters are still solved by the shared geometry layer from the selected reference lines.

### Research Notes

- Apple Vision has [`VNDetectHorizonRequest`](https://developer.apple.com/documentation/vision/vndetecthorizonrequest), whose result is a `VNHorizonObservation`; this is the preferred first implementation path for automatic horizon correction before falling back to custom line voting.
- Apple Vision also has [`VNDetectRectanglesRequest`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest) and [`VNDetectDocumentSegmentationRequest`](https://developer.apple.com/documentation/vision/vndetectdocumentsegmentationrequest), both of which can return rectangle corner observations. These are useful for proposing a Lens-style source quadrilateral, but manual handles remain required because screens, signs, and documents may be partially occluded or visually ambiguous.
- Core Image's [`CIFilter.perspectiveCorrection()`](https://developer.apple.com/documentation/coreimage/cifilter/3228380-perspectivecorrection) is the platform reference for source-quadrilateral-to-rectangular-output semantics: four input image corners map to the output image corners. AnyUpright uses its own Metal renderer for FxPlug playback, but the Quad `Source Quad` mode follows the same conceptual direction.
- Lightroom's [Upright](https://helpx.adobe.com/lightroom-classic/help/guided-upright-perspective-correction.html) modes include Level, Vertical, Auto, Full, and Guided workflows. Guided Upright lets users draw guides that should become horizontal or vertical, which matches the planned manual reference-line model.
- OpenCV's [`HoughLines` / `HoughLinesP`](https://docs.opencv.org/4.x/d9/db0/tutorial_hough_lines.html) and [`LineSegmentDetector`](https://docs.opencv.org/master/db/d73/classcv_1_1LineSegmentDetector.html) are the practical reference algorithms for candidate line extraction. The repo should keep the public data model independent from OpenCV so a future implementation can choose Vision, traditional CPU code, Metal kernels, or a small pre-trained model without changing render semantics.
- FxPlug 4 provides [`FxAnalysis`](https://developer.apple.com/documentation/professional_video_applications/fxanalysisapi) for explicit frame analysis and [`FxOnScreenControl`](https://developer.apple.com/documentation/professional_video_applications/fxonscreencontrolapi_v4) for canvas drawing, hit testing, and mouse events. Automatic and semi-automatic modes should analyze a representative frame, write keyframeable parameters, and let the existing Metal warp renderer handle playback.
- FxPlug angle parameters are handled as radians in the current Motion validation path: `getFloatValue` returns angle slider values in radians, and `setFloatValue` writes angle parameter values that Motion displays after radians-to-degrees conversion. This differs from the FxPlug SDK header comment that says angle writes use degrees, so Horizon and Upright keep internal analysis rotation values in radians and write radians back to angle parameters. See `docs/debug/2026-06-05-horizon-analysis-writeback.md` for the validation notes that led to this convention.

## Validation Expectations

For meaningful functionality changes, validate at the lowest level that proves the behavior:

- Geometry math: deterministic unit tests or sample vectors.
- Metal warp: visual test frames or known point mapping checks.
- FxPlug integration: build the wrapper app target and verify the plugin loads in Motion or Final Cut Pro.
- Final Cut behavior: verify published parameters, keyframes, proxy resolution, and clip trim/retime behavior when possible.

Current command-line checks:

```sh
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift AnyUpright/Plugin/AnyUprightUprightCandidates.swift AnyUprightTests/AnyUprightGeometryTests.swift -o /tmp/AnyUprightGeometryTests && /tmp/AnyUprightGeometryTests
xcrun swiftc tools/validate-fxplug-manifest.swift -o /tmp/AnyUprightValidateManifest && /tmp/AnyUprightValidateManifest .
xcrun swiftc tools/audit-feature-surface.swift -o /tmp/AnyUprightAuditFeatureSurface && /tmp/AnyUprightAuditFeatureSurface .
xcrun swift tools/generate-test-assets.swift .agent-work/test-assets
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift tools/analyze-test-assets.swift -o /tmp/AnyUprightAnalyzeAssets && /tmp/AnyUprightAnalyzeAssets .agent-work/test-assets
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift tools/render-warp-previews.swift -o /tmp/AnyUprightRenderWarpPreviews && /tmp/AnyUprightRenderWarpPreviews .agent-work/test-assets .agent-work/warp-previews
xcrun swiftc tools/validate-warp-previews.swift -o /tmp/AnyUprightValidateWarpPreviews && /tmp/AnyUprightValidateWarpPreviews .agent-work/warp-previews
SDK=$(xcrun --sdk macosx --show-sdk-path) && xcrun swiftc -typecheck AnyUpright/Plugin/*.swift -sdk "$SDK" -F /Library/Developer/SDKs/FxPlug.sdk/Library/Frameworks -F /Library/Developer/Frameworks -I AnyUpright/Plugin -import-objc-header "AnyUpright/Plugin/XPC Service-Bridging-Header.h"
xcodebuild -project AnyUpright.xcodeproj -scheme "Wrapper Application" -configuration Debug -derivedDataPath /tmp/AnyUprightDerivedData build
```

If Xcode reports a missing Metal Toolchain during build, install it with Xcode's suggested `xcodebuild -downloadComponent MetalToolchain` before repeating the full build.

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
- `quad-source-apply-preview.png`: maps the known phone-screen source quadrilateral to the full output frame.
- `quad-output-corners-preview.png`: applies output-corner dragging semantics.
- `upright-centered-preview.png`: applies centered vertical/horizontal perspective plus rotation.

The preview renderer is CPU-only and exists to prove mapping semantics. Playback in Motion and Final Cut still uses the shared Metal warp.

### Motion Validation Checklist

After building the wrapper app, Motion should see three independent FxPlug filters under the AnyUpright group. Use a 1920 x 1080 project and import the generated PNGs as still images.

Horizon:

- Apply `AnyUpright Horizon Manual` to `horizon-tilted-8deg.png`.
- Click `Analyze Horizon`; `Rotation` should move near the opposite of the visible tilt and the horizon should level out.
- Enable `Fill Frame`; the render should zoom enough to hide rotation black edges.

Quad:

- Apply `AnyUpright Quad Manual` to `quad-phone-screen.png`.
- In `Output Corners` mode, drag the four onscreen handles; the image should warp in realtime.
- In `Output Corners` mode, `Apply Source Quad` should be hidden and the four corner coordinate groups should be visible.
- In `Source Quad` mode with `Apply Source Quad` off, drag the four handles around the phone-screen quadrilateral; the image should not warp while editing.
- In `Source Quad` mode, the four corner coordinate groups should be hidden because positioning happens through onscreen handles.
- Turn `Apply Source Quad` on; the selected screen quadrilateral should map to the full output frame.

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

This repository currently ships the three effects as FxPlug filters registered by the wrapper app. Motion or Final Cut template files are not tracked yet. If a template-based distribution is required later, run the wrapper app once so macOS registers the plug-in, apply each FxPlug filter in Motion, publish the intended parameters, and save three separate Final Cut Effect templates.
