# Y-Axis Coordinate Conventions

Last updated: 2026-06-10 15:47 MDT
Reference commit: 11aa3148242f9743c8c48903739c604f84dd2e66
Observed host versions: macOS 26.5, Motion Studio 6.2, Final Cut Pro 12.2

This note records reusable Y-axis guidance for four-corner FxPlug controls. It does not record product features or implementation choices. Project-specific choices live outside `engineering-notes`; in this repository they are recorded in `../quad-implementation-notes.md`.

For the cross-layer contract and debugging method, read `quad-coordinate-layer-contract.md` first. Host-specific statements in this note are versioned observations from macOS 26.5, Motion Studio 6.2, and Final Cut Pro 12.2 unless Apple API behavior is explicitly named.

## Coordinate Boundaries

### Image And Output Pixels

- A plug-in must define its own image/output pixel convention. A common renderer convention is visual top as smaller Y and visual bottom as larger Y.
- User-facing offsets may still define positive `Y` as up. If image pixels grow downward, the parameter-to-image conversion must subtract Y:

```swift
x = base.x + percent.x * width + pixels.x
y = base.y - percent.y * height - pixels.y
```

- Keep homography input/output points, source selections, output-corner geometry, and render sampling in one explicit image/output convention.

### FxPlug Object Space

- Apple documents `OBJECT`, `DOCUMENT`, and `CANVAS` drawing coordinates as Y-up spaces.
- For normalized object-space handles, visual top should therefore have larger normalized Y than visual bottom.
- Converting object-space storage to image/output preview geometry crosses a Y-axis boundary. Do not assume an object-space point's Y has the same visual meaning as an image/output pixel's Y.

### Preview-Aligned Interaction Layer

- A source-selection edit preview is often image/output-space geometry, while persistent handle storage may be object-space geometry.
- The visible outline, handles, hit layer, hover highlights, and active highlights should use one preview-aligned layer.
- A storage/writeback layer may be logged for diagnostics, but it must not compete as a second visible hit layer.

### FxPlug Canvas And OSC Events

- OSC interaction should work in the coordinate space declared by `drawingCoordinates()` after any explicit `FxOnScreenControlAPI.convertPoint(...)` conversion.
- Final Cut raw-canvas events and Motion-style surface-local events are host observations, not interchangeable coordinate facts.
- Initial hover/hit tests should choose one event interpretation for a mouse point. Running raw and mapped interpretations for the same point can create a hidden mirrored hit layer.
- Drag writeback may need to cross from preview-aligned canvas/object geometry back to persistent storage. Keep that conversion explicit and separate from hit testing.
- Treat host canvas X and Y symmetrically unless callback logs prove they arrive in different spaces.

### Metal Render Vertices

- A warp renderer may build tile-local Metal vertices while pairing them with image/output coordinates.
- Keep shader source/output geometry in the renderer's image/output pixel convention.
- For OSC overlay rendering, define a local surface-pixel layer before converting to Metal vertices.
- If Metal vertex space is centered with Y up, perform the single Y flip at the local-surface-to-Metal boundary:

```text
metalX = surfaceX - surfaceWidth / 2
metalY = surfaceHeight / 2 - surfaceY
```

- Apply the same boundary conversion to overlay primitive origins and axes so fragment distance fields align with drawn vertices.

## Practical Rules

- Name both coordinate spaces before adding any `height - y` style fix.
- Apple documents FxPlug `CANVAS`, `DOCUMENT`, and `OBJECT` coordinates as Y-up spaces. Image/render pixel conventions are still a plug-in decision and must be bridged explicitly.
- If user-facing positive Y means up but image/output pixel Y grows down, put that sign difference in the parameter-to-image conversion layer.
- If a handle drags correctly but hover appears on the opposite edge, inspect hover/overlay drawing and event interpretation before changing render geometry.
- If the visible source-selection quad moves correctly but hit targets are mirrored, inspect raw canvas versus mapped surface event resolution before changing render preview or homography.
- If the visible video/export is shifted while OSC controls are correct, inspect render tile/source texture origin before changing OSC or object-space math.

## Regression Surfaces To Keep

A robust four-corner control should have deterministic checks for:

- Positive user-facing Y offset semantics.
- Image-space selection and object-space handle positions.
- Raw-canvas drag writeback crossing back to object/parameter storage.
- Raw-canvas hit geometry matching the visible preview layer.
- Raw-canvas event handling versus Motion-style surface-local event mapping.
- Host gating of any mapped-surface fallback.
- Host canvas X/Y staying direct for overlay points, including points outside the visible surface.
- OSC surface-pixel to Metal-centered-pixel conversion, including the single viewport-height Y flip.

## Previous Wrong Attempts

- Full center-offset compensation for Final Cut vertical pan made the control frame stay fixed in the preview area instead of following the video/canvas geometry.
- Backing-scale residual compensation made the displacement magnitude look closer but inverted or over-amplified Y. The decisive observation was that horizontal pan was already correct with direct host canvas X, so vertical pan should not receive a one-off formula without evidence that host X and Y are different spaces.
- Re-fitting canvas points through the video frame or output-image aspect fit made pan behavior look stable in one state but wrong at zoom/pan states. OSC drawing should keep host canvas X/Y direct unless logs prove otherwise.
- Globally changing event candidate order or adding a new Y-flipped event candidate broke drag dispatch. Event interpretation should stay separate from writeback semantics.
- Letting storage object/canvas geometry compete with preview-aligned raw-canvas geometry created mirrored hit layers. The visible layer and hit layer must agree.
- Applying `FxImageTile.pixelTransform` to a base edit preview was incorrect in the observed host path. The preview was rendered into filter output, and Motion/Final Cut applied object/view transforms after plug-in rendering, so applying the host transform in shader double-moved the overlay.
