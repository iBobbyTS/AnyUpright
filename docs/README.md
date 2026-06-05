# AnyUpright

AnyUpright is planned as a suite of Final Cut Pro effects for single-frame-assisted perspective and upright correction. The effects target fixed-camera or mostly static correction workflows where analysis and manual setup happen on one representative frame, while the resulting transform can persist across the whole clip and support keyframes.

## Current State

- The repository is initialized as an Xcode FxPlug 4 template project.
- The template brightness filter has been replaced with three manual prototype FxPlug filters.
- No Motion templates for the final effects are tracked here yet.
- There is no package manager, Docker runtime, or CI workflow yet.
- Geometry tests live in `AnyUprightTests/` and can be run as a lightweight Swift executable.

## Planned Effects

### AnyUpright Horizon

Automatically detects a horizontal reference line in the current frame and applies a rotation correction across the clip.

Current prototype:

- `AnyUpright Horizon Manual` is registered as a separate FxPlug filter.
- `Rotation` is a manual angle slider.
- `Fill Frame` controls whether the rotated image is zoomed enough to avoid black edges.

Expected workflow:

1. User applies the effect to a clip.
2. User analyzes the current frame or selects a candidate line.
3. Plugin writes the resulting correction into keyframeable parameters.
4. Playback and export use only the saved transform.

Primary risks:

- False positives when strong lines are not true horizon references.
- Low-confidence frames with no reliable horizontal line.
- Need for manual override and visible candidate feedback.

### AnyUpright Quad Transform

Provides manual four-point perspective transforms.

Current prototype:

- `AnyUpright Quad Manual` is registered as a separate FxPlug filter.
- Each visible output corner exposes `X %`, `Y %`, `X px`, and `Y px` offsets.
- Final offset is `percentage * current frame dimension + pixels`.
- Positive `X` moves right. Positive `Y` moves up.
- Internally this prototype treats the four offsets as a destination/output quadrilateral and maps it back to the full source frame, matching the direction a user sees in the Motion canvas.

Two intended modes:

1. Source quad to full frame: user drags four points around an object such as a phone screen; editing displays handles without moving the image, and applying maps that quadrilateral to the original frame size.
2. Frame-corner warp: user drags the four output corners and sees the warped image in realtime; the stretched result is the actual output.

Primary risks:

- Coordinate consistency across canvas space, source pixels, proxy resolution, and Final Cut project settings.
- Onscreen control usability.
- Keyframing corner positions without creating confusing interpolation.

### AnyUpright Upright

Provides Lightroom-style upright correction controls.

Current prototype:

- `AnyUpright Upright Manual` is registered as a separate FxPlug filter.
- `Vertical Perspective` uses keystone-style perspective correction for top-far/bottom-far cases.
- `Horizontal Perspective` uses keystone-style perspective correction for left-far/right-far cases.
- `Rotation` applies a manual rotation around the frame center.

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

Primary risks:

- Automatic scoring quality. Angle alone is not enough; line length, strength, spatial separation, and geometric consistency should be part of candidate ranking.
- UX complexity from combining manual axes, drawn lines, detected candidates, and keyframes.
- Avoiding realtime playback cost from frame analysis.

## Architecture Direction

Use one repository and one product suite, but expose three separate Final Cut effects. Shared implementation should live behind small common modules:

- Geometry: normalized points, lines, homography, affine transforms, vanishing-point helpers, and coordinate conversion.
- Detection: frame downsampling, edge/line detection, candidate scoring, and analysis result serialization.
- Rendering: shared Metal pipeline for affine and projective texture warps.
- UI/controls: reusable onscreen handle drawing and hit-testing where FxPlug APIs permit it.

Playback rendering should use precomputed parameters only. Detection should be explicit, cached, or analysis-driven instead of happening on every frame.

## Validation Expectations

For meaningful functionality changes, validate at the lowest level that proves the behavior:

- Geometry math: deterministic unit tests or sample vectors.
- Metal warp: visual test frames or known point mapping checks.
- FxPlug integration: build the wrapper app target and verify the plugin loads in Motion or Final Cut Pro.
- Final Cut behavior: verify published parameters, keyframes, proxy resolution, and clip trim/retime behavior when possible.

Current command-line checks:

```sh
xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUprightTests/AnyUprightGeometryTests.swift -o /tmp/AnyUprightGeometryTests && /tmp/AnyUprightGeometryTests
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
