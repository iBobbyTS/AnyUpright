# Quad OSC And Overlay Rendering

Last updated: 2026-06-10 15:47 MDT
Reference commit: 11aa3148242f9743c8c48903739c604f84dd2e66
Observed host versions: macOS 26.5, Motion Studio 6.2, Final Cut Pro 12.2

This note records reusable OSC overlay rendering lessons for four-corner FxPlug controls. It does not record product features or implementation choices. Project-specific choices live outside `engineering-notes`; in this repository they are recorded in `../quad-implementation-notes.md`.

For a host-neutral coordinate inventory, start with `quad-coordinate-layer-contract.md`. This file focuses on drawing interactive OSC geometry once the canvas points have already been chosen.

## Coordinate Rules

- An edit control may have two visual paths: filter output for image-relative preview/dimming, and OSC overlay for interactive handles, hover, active highlights, and hit feedback.
- Do not use `drawOSC` width/height as the actual drawable viewport without checking `destinationImage`. In Motion, width/height can describe the object/source, while the Metal drawable surface is represented by `destinationImage`/IOSurface.
- For host-canvas overlay points, do not clamp to the video frame, refit through output-image aspect fit, subtract frame center, apply backing-scale compensation, or mirror Y in the canvas-to-surface step unless logs prove that conversion is needed.
- The line/handle primitive origin and axis must use the same local-surface-to-Metal-centered conversion as vertex positions. Otherwise fragment distance fields and drawn geometry diverge.
- Treat `backingScaleFactor` as evidence for CPU-prepared assets or screen-dependent resources, not as an automatic coordinate displacement factor. Apple notes vertex coordinates already scale properly in the common case.
- Choose one unit for fixed-size UI affordances. If handles and hit radii are meant to feel screen-fixed, keep that contract in the OSC drawing/event layer and verify zoom behavior manually.

## Drawable Versus Viewer

- The Final Cut or Motion viewer is the host UI panel. The OSC drawable is the IOSurface/texture passed for drawing. The visible video rectangle is where the filtered object appears inside the viewer. These are related but not interchangeable.
- A four-corner source-selection control often needs to draw and hit outside the video rectangle. Clamping overlay points to the visible video rectangle will break that workflow.
- If callback `width`/`height`, `destinationImage.imagePixelBounds`, `destinationImage.tilePixelBounds`, and IOSurface texture size disagree, log all of them and choose the field that matches the actual drawable target for vertex conversion.
- Viewer Fit/zoom/pan symptoms should be checked against raw host canvas points before adding overlay compensation. A correct canvas-space overlay should usually move with the canvas/object mapping the host already provides.

## Versioned Host Observations

These observations are not Apple API guarantees. They were measured on macOS 26.5 with Motion Studio 6.2 and Final Cut Pro 12.2:

- In Motion Studio OSC drawing, `drawOSC` callback width/height could describe the object/source size while `destinationImage` represented the actual drawable IOSurface/Metal target.
- In Final Cut Pro zoom/pan testing, direct host canvas X/Y drawing tracked the visible controls. Frame-center compensation, backing-scale compensation, output-image Fit refitting, and renderer-level vertical mirroring all caused drift or inversion.
- `backingScaleFactor` did not explain the persistent control displacement in the tested Final Cut Pro states. It should not be used as a displacement factor unless a new log proves a screen-resource sizing issue.
- Persistent OSC drawing with more vertices needed an `MTLBuffer`; using inline `setVertexBytes` for the larger overlay caused an AGX driver abort in the tested environment.

## Crash Fix Pattern

- Persistent OSC drawing can create far more vertices than a hover-only overlay.
- Uploading a larger vertex array through inline `setVertexBytes` can exceed what is safe for the driver path.
- Allocate an `MTLBuffer` for overlay vertices and bind it with `setVertexBuffer`; keep only small constants such as viewport size inline.

## Logging

Useful draw diagnostics include:

- host callback dimensions, surface, object bounds, frame, and quad;
- canvas, direct, center-relative, and frame-fit point mappings;
- IOSurface/texture/image/tile target state;
- local, direct, frame-local, centered, and clip mappings;
- line/handle primitive construction;
- final centered Metal vertex bounds and representative vertex samples.

If these markers are absent after a rebuild, the host is probably running an old XPC service or has not invoked the new draw path.

## Previous Wrong Attempts

- Drawing source-selection controls only in the filter output made them visible in Final Cut but did not by itself make them draggable.
- Drawing two visible layers, one filter-output layer and one host OSC layer, caused confusing duplicate quads. The fix was to make the OSC layer use the same preview-aligned geometry as hit testing and dragging.
- Full frame-center compensation, backing-scale residual formulas, and canvas-frame aspect-fit remapping all overfit the Final Cut pan symptom and broke other viewer states.
- Leaving overlay vertices on an `(x - width / 2, y - height / 2)` conversion misplaced Y in Metal when the intended centered vertex space was Y-up. The correct boundary conversion in that setup is `(x - width / 2, height / 2 - y)`.
- Treating `setVertexBytes` as safe for all overlay sizes was wrong. Larger persistent OSC controls need `MTLBuffer`.
