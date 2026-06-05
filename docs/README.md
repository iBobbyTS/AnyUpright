# AnyUpright

AnyUpright is planned as a suite of Final Cut Pro effects for single-frame-assisted perspective and upright correction. The effects target fixed-camera or mostly static correction workflows where analysis and manual setup happen on one representative frame, while the resulting transform can persist across the whole clip and support keyframes.

## Current State

- The repository is initialized as an Xcode FxPlug 4 template project.
- The template brightness filter has been replaced with three manual prototype FxPlug filters.
- No Motion templates for the final effects are tracked here yet.
- There is no package manager, Docker runtime, or CI workflow yet.
- Geometry tests live in `AnyUprightTests/` and can be run as a lightweight Swift executable.
- The shared geometry layer now includes line candidate filtering, horizon correction estimation, and centered perspective parameter estimation from reference lines.
- Quad and Upright now expose first-pass FxPlug onscreen controls in addition to inspector parameters.

## Planned Effects

### AnyUpright Horizon

Automatically detects a horizontal reference line in the current frame and applies a rotation correction across the clip.

Current prototype:

- `AnyUpright Horizon Manual` is registered as a separate FxPlug filter.
- `Rotation` is a manual angle slider.
- `Fill Frame` controls whether the rotated image is zoomed enough to avoid black edges.
- `Analyze Horizon` starts FxAnalysis on a representative frame, runs Vision horizon detection, and writes the detected correction back to `Rotation`.

Expected workflow:

1. User applies the effect to a clip.
2. User analyzes the current frame or selects a candidate line.
3. Plugin writes the resulting correction into keyframeable parameters.
4. Playback and export use only the saved transform.

Primary risks:

- False positives when strong lines are not true horizon references.
- Low-confidence frames with no reliable horizontal line.
- Need for manual override and visible candidate feedback.
- The first automatic implementation analyzes a tiny time range at the start of the input range; current-frame targeting still needs host-behavior validation and likely a dedicated analysis-frame control.

### AnyUpright Quad Transform

Provides manual four-point perspective transforms.

Current prototype:

- `AnyUpright Quad Manual` is registered as a separate FxPlug filter.
- `Mode` selects `Output Corners` or `Source Quad`.
- `Apply Source Quad` controls whether source-quad edits are rendered. Leave it off while positioning handles, then enable it to map the selected source quadrilateral to the full output frame.
- Each visible output corner exposes `X %`, `Y %`, `X px`, and `Y px` offsets.
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

Current prototype:

- `AnyUpright Upright Manual` is registered as a separate FxPlug filter.
- `Vertical Perspective` uses a centered keystone transform around the horizontal centerline. Positive values move the top inward and bottom outward; negative values move the top outward and bottom inward.
- `Horizontal Perspective` uses a centered keystone transform around the vertical centerline. Positive values move the right side inward and left side outward; negative values move the right side outward and left side inward.
- `Rotation` applies a manual rotation around the frame center.
- Internally this prototype treats upright perspective as a destination/output quadrilateral and maps it back to the full source frame. Fill, crop, and position are intentionally separate future steps.
- `Auto Vertical`, `Auto Horizontal`, and `Auto Full` start FxAnalysis on a representative frame, downsample it, run the shared Sobel/Hough candidate-line detector, choose up to two near-axis references, and write estimated perspective values back to the existing sliders.
- Four editable guide lines are exposed as point parameters and onscreen line handles. The first two default to vertical references; the last two default to horizontal references.
- `Apply Guided Vertical`, `Apply Guided Horizontal`, and `Apply Guided Full` convert enabled guide lines into the existing keyframeable `Vertical Perspective`, `Horizontal Perspective`, and, for full mode, `Rotation` parameters.

Planned controls:

- Manual vertical, horizontal, and rotation axes.
- Four manually drawn reference lines.
- Vertical transform from detected or selected near-vertical lines.
- Horizontal transform from detected or selected near-horizontal lines.
- Full transform combining vertical and horizontal references.

Automation levels:

- Full auto: detect candidate lines and choose references automatically.
- Semi auto: display candidates and allow the user to choose one or two references.
- Manual: user draws or adjusts references directly.
- Semi-auto candidate display and selection is not implemented yet; detected lines are currently consumed only by the full-auto buttons.

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

Playback rendering should use precomputed parameters only. Detection should be explicit, cached, or analysis-driven instead of happening on every frame.

The current traditional line detector is a CPU reference implementation based on Sobel edges, gradient-constrained Hough voting, and simple non-maximum suppression. It is intended to provide candidate lines for automatic and semi-automatic workflows; exact transform parameters are still solved by the shared geometry layer from the selected reference lines.

### Research Notes

- Apple Vision has [`VNDetectHorizonRequest`](https://developer.apple.com/documentation/vision/vndetecthorizonrequest), whose result is a `VNHorizonObservation`; this is the preferred first implementation path for automatic horizon correction before falling back to custom line voting.
- Apple Vision also has [`VNDetectRectanglesRequest`](https://developer.apple.com/documentation/vision/vndetectrectanglesrequest) and [`VNDetectDocumentSegmentationRequest`](https://developer.apple.com/documentation/vision/vndetectdocumentsegmentationrequest), both of which can return rectangle corner observations. These are useful for proposing a Lens-style source quadrilateral, but manual handles remain required because screens, signs, and documents may be partially occluded or visually ambiguous.
- Lightroom's [Upright](https://helpx.adobe.com/lightroom-classic/help/guided-upright-perspective-correction.html) modes include Level, Vertical, Auto, Full, and Guided workflows. Guided Upright lets users draw guides that should become horizontal or vertical, which matches the planned manual reference-line model.
- OpenCV's [`HoughLines` / `HoughLinesP`](https://docs.opencv.org/4.x/d9/db0/tutorial_hough_lines.html) and [`LineSegmentDetector`](https://docs.opencv.org/master/db/d73/classcv_1_1LineSegmentDetector.html) are the practical reference algorithms for candidate line extraction. The repo should keep the public data model independent from OpenCV so a future implementation can choose Vision, traditional CPU code, Metal kernels, or a small pre-trained model without changing render semantics.
- FxPlug 4 provides [`FxAnalysis`](https://developer.apple.com/documentation/professional_video_applications/fxanalysisapi) for explicit frame analysis and [`FxOnScreenControl`](https://developer.apple.com/documentation/professional_video_applications/fxonscreencontrolapi_v4) for canvas drawing, hit testing, and mouse events. Automatic and semi-automatic modes should analyze a representative frame, write keyframeable parameters, and let the existing Metal warp renderer handle playback.

## Validation Expectations

For meaningful functionality changes, validate at the lowest level that proves the behavior:

- Geometry math: deterministic unit tests or sample vectors.
- Metal warp: visual test frames or known point mapping checks.
- FxPlug integration: build the wrapper app target and verify the plugin loads in Motion or Final Cut Pro.
- Final Cut behavior: verify published parameters, keyframes, proxy resolution, and clip trim/retime behavior when possible.

Current command-line checks:

```sh
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift AnyUprightTests/AnyUprightGeometryTests.swift -o /tmp/AnyUprightGeometryTests && /tmp/AnyUprightGeometryTests
SDK=$(xcrun --sdk macosx --show-sdk-path) && xcrun swiftc -typecheck AnyUpright/Plugin/*.swift -sdk "$SDK" -F /Library/Developer/SDKs/FxPlug.sdk/Library/Frameworks -F /Library/Developer/Frameworks -I AnyUpright/Plugin -import-objc-header "AnyUpright/Plugin/XPC Service-Bridging-Header.h"
xcodebuild -project AnyUpright.xcodeproj -scheme "Wrapper Application" -configuration Debug -derivedDataPath /tmp/AnyUprightDerivedData build
```

If Xcode reports a missing Metal Toolchain during build, install it with Xcode's suggested `xcodebuild -downloadComponent MetalToolchain` before repeating the full build.

## Open Decisions

- Whether the suite should use one FxPlug XPC service with multiple plugin classes or separate plugin targets.
- Whether Motion template files should be tracked in the repository or generated/copied from a documented local template location.
- Minimum supported macOS, Final Cut Pro, Motion, Xcode, and FxPlug SDK versions.
- Code signing, notarization, and distribution model.
- Multi-locale policy beyond the current `en.lproj` template resources.
- Xcode Test Navigator integration for the current lightweight geometry tests.
- Automated Metal shader validation.

## Motion And Final Cut Templates

This prototype registers three FxPlug filters in the wrapper app, but it does not include Motion or Final Cut template files yet. The next integration step is to run the wrapper app once so macOS registers the plug-in, apply each FxPlug filter in Motion, publish the intended parameters, and save three separate Final Cut Effect templates.
