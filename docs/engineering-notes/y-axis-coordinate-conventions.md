# Y-Axis Coordinate Conventions

Last updated: 2026-07-25 17:14 MDT
Reference commit: a1e6085b1fca63e703f1970635b68fe875052047
Observed host versions: macOS 26.5.1 (25F80), Motion Creator Studio 6.2 (447036) and 6.3 (450156), Final Cut Pro 12.2 and 12.3 (450152), Xcode 26.5 (17F42), FxPlug framework 4.3.4 (18567.3)

This note records reusable Y-axis guidance for four-corner FxPlug controls. It does not record product features or implementation choices. Project-specific choices live outside `engineering-notes`; in this repository they are recorded in `../stretch-implementation-notes.md`.

For the cross-layer contract and debugging method, read `stretch-coordinate-layer-contract.md` first. Host-specific statements in this note are versioned observations from the host versions named with each finding; they are not universal FxPlug guarantees unless Apple API behavior is explicitly named.

## Official API Baseline

- FxPlug framework 4.3.4 `FxOnScreenControl.h` states that Y increases upward in CANVAS, DOCUMENT, and OBJECT drawing coordinates.
- `drawingCoordinates()` defines the coordinate space used for OSC events.
- `FxOnScreenControlAPI.convertPoint(...)` converts between named drawing spaces, but the API does not define a product-independent rule for converting a preview-aligned source-selection point into a plug-in's persistent parameter convention.

## Coordinate Boundaries

### Image And Output Pixels

- A plug-in must define its own image/output pixel convention. A common renderer convention is visual top as smaller Y and visual bottom as larger Y.
- User-facing offsets may still define positive `Y` as up. If image pixels grow downward, the parameter-to-image conversion must subtract Y:

```swift
x = base.x + percent.x * width + pixels.x
y = base.y - percent.y * height - pixels.y
```

- Keep homography input/output points, source selections, output-corner geometry, reference-line solving, and render sampling in one explicit image/output convention.

### FxPlug Object Space

- Apple documents `OBJECT`, `DOCUMENT`, and `CANVAS` drawing coordinates as Y-up spaces.
- For normalized object-space handles, visual top should therefore have larger normalized Y than visual bottom.
- Converting object-space storage to image/output preview geometry crosses a Y-axis boundary. Do not assume an object-space point's Y has the same visual meaning as an image/output pixel's Y.
- Reference-line controls stored as normalized object-space points need the same boundary as point handles before line solving. A line can look correct in an OSC overlay while its persisted endpoints still need `1.0 - y` before becoming image-space geometry.

### Preview-Aligned Interaction Layer

- A source-selection edit preview is often image/output-space geometry, while persistent handle storage may be object-space geometry.
- For the observed Motion 6.3 OSC path, keep the points supplied to both hit testing and custom overlay drawing in the same FxPlug Y-up CANVAS layer. The overlay renderer and Motion's IOSurface composition together own the display-space crossing.
- Do not preflip CANVAS points merely because the backing IOSurface has top-down pixel memory. In the observed host path, doing so draws the named corner at its vertically opposite screen position.
- The source selection consumed by the Warp renderer is separate top-down image geometry. Preserve named-corner identity across that boundary instead of sharing numeric Y values between OSC and Warp layers.

### FxPlug Canvas And OSC Events

- OSC interaction should work in the coordinate space declared by `drawingCoordinates()` after any explicit `FxOnScreenControlAPI.convertPoint(...)` conversion.
- Final Cut raw-canvas events and Motion-style surface-local events are host observations, not interchangeable coordinate facts.
- Initial hover/hit tests should choose one event interpretation for a mouse point. Running raw and mapped interpretations for the same point can create ambiguous hit targets.
- Drag writeback must use the object coordinate returned by the FxPlug canvas conversion directly. The overlay renderer and image Warp each own later coordinate boundaries; neither transform is part of parameter writeback.
- Treat host canvas X and Y symmetrically unless callback logs prove they arrive in different spaces.

### Event Interpretation And Persistent Writeback

- Event interpretation and persistent writeback are separate concerns. Raw-canvas and mapped-surface candidates choose how to resolve the host event, but both accepted canvas points are converted through FxPlug into Y-up object coordinates before parameter writeback.
- Preserve the accepted event interpretation for the entire drag, then write the converted object point directly. Do not reuse the preview drawing layer's `y = 1 - y` transform for persistent parameters.
- Observed on Motion Creator Studio 6.3: the Inner Stretch path resolves as `.rawCanvas`. Applying an additional preview-to-storage flip changed an upper object Y near `0.663` into `0.337`; the OSC drag feedback could still look locally coherent while the persisted edit mask and final render moved to the vertically mirrored location.
- This failure signature separates the layers: a correct live overlay with a mirrored mask and final render means the visible/hit layer is likely correct and the persisted Y value is wrong. When both the mask and applied render agree on the wrong position, inspect their shared parameter source before changing either renderer.

### Metal Render Vertices

- A warp renderer may build tile-local Metal vertices while pairing them with image/output coordinates.
- Keep shader source/output geometry in the renderer's image/output pixel convention.
- Keep project geometry and texture addressing separate. A projective output-to-source matrix should map output image pixels to source image pixels; a separate render boundary should map source image pixels into the current input texture.
- For OSC overlay rendering, name the coordinate convention accepted by the renderer before converting to Metal vertices. In the current renderer, the input remains the FxPlug Y-up CANVAS pixel layer.
- The current overlay renderer converts those pixels to centered Metal vertices with:

```text
metalX = surfaceX - surfaceWidth / 2
metalY = surfaceHeight / 2 - surfaceY
```

- Apply the same conversion to overlay primitive origins and axes so fragment distance fields align with drawn vertices. Motion's composition of the returned IOSurface is part of the observed final orientation, so do not infer that the renderer input must be top-down from IOSurface memory layout alone.
- Observed for Inner Stretch Warp in Motion 6.3: the Metal interpolant carries physical output-IOSurface coordinates, while projective geometry is defined in logical image coordinates and the input texture uses physical texture coordinates. Compose both boundaries into the render matrix: flip output Y before the projective transform, then flip source Y into the input texture. The two flips cancel for identity, so identity alone cannot validate this path.

## Practical Rules

- Name both coordinate spaces before adding any `height - y` style fix.
- Apple documents FxPlug `CANVAS`, `DOCUMENT`, and `OBJECT` coordinates as Y-up spaces. Image/render pixel conventions are still a plug-in decision and must be bridged explicitly.
- If user-facing positive Y means up but image/output pixel Y grows down, put that sign difference in the parameter-to-image conversion layer.
- Do not apply a preview drawing Y flip during parameter writeback. FxPlug canvas conversion already provides the Y-up object coordinate used by persistent point parameters.
- If a handle drags correctly but hover appears on the opposite edge, inspect hover/overlay drawing and event interpretation before changing render geometry.
- If the visible source-selection stretch moves correctly but hit targets are mirrored, inspect raw canvas versus mapped surface event resolution before changing render preview or homography.
- If the visible video/export is shifted while OSC controls are correct, inspect render tile/source texture origin before changing OSC or object-space math.
- If an offline CPU render and the live Metal render disagree while using the same project geometry matrix, inspect the source-image-to-input-texture boundary and the fragment output-coordinate boundary before changing the solver.
- If a reference line should become vertical or horizontal after correction, verify the transformed source line in image/output coordinates. Do not infer correctness from the stored endpoint signs alone.

## Regression Surfaces To Keep

A robust four-corner control should have deterministic checks for:

- Positive user-facing Y offset semantics.
- Image-space selection and object-space handle positions.
- Raw-canvas and mapped-surface drag writeback both preserving the converted FxPlug object Y directly.
- FxPlug Y-up hit geometry and OSC drawing input sharing the same named-corner identity and numeric CANVAS coordinates.
- OSC Canvas-to-Metal/host composition preserving visual corner identity without preflipping the Canvas input.
- Raw-canvas event handling versus Motion-style surface-local event mapping.
- Host gating of any mapped-surface fallback.
- Host canvas X/Y staying direct for overlay points, including points outside the visible surface.
- OSC Canvas-pixel to Metal-centered-pixel conversion plus host composition.
- Object-space reference lines converting to image-space lines before perspective estimation.
- Inner Stretch render matrices mapping displayed output TL/TR/BR/BL to displayed source TL/TR/BR/BL after both host render-boundary conversions, including non-zero texture origins.
- Legacy boundary-adjusted render matrices matching their explicit output-image and source-texture Y conversions.

## Previous Wrong Attempts

- Full center-offset compensation for Final Cut vertical pan made the control frame stay fixed in the preview area instead of following the video/canvas geometry.
- Backing-scale residual compensation made the displacement magnitude look closer but inverted or over-amplified Y. The decisive observation was that horizontal pan was already correct with direct host canvas X, so vertical pan should not receive a one-off formula without evidence that host X and Y are different spaces.
- Re-fitting canvas points through the video frame or output-image aspect fit made pan behavior look stable in one state but wrong at zoom/pan states. OSC drawing should keep host canvas X/Y direct unless logs prove otherwise.
- Globally changing event candidate order or adding a new Y-flipped event candidate broke drag dispatch. Event interpretation should stay separate from writeback semantics.
- Applying the source-selection preview drawing `1 - y` conversion during parameter writeback mirrored the persisted Y. Motion 6.3 runtime logs showed the affected path was `.rawCanvas`, disproving the earlier mapped-surface hypothesis.
- Preflipping Y-up FxPlug CANVAS points before custom OSC drawing made a visual top-left handle appear at the bottom while hit callbacks still used the host Canvas layer. Hit testing and overlay drawing input must share the same Canvas points; the renderer/host composition owns the visual crossing.
- Adding only a source-texture Y flip to Inner Stretch Warp inverted the default identity image, but the inverse conclusion was also wrong: removing both flips keeps identity upright while mirroring asymmetric projective geometry. Validate with a non-symmetric four-corner fixture and model both physical output and physical input boundaries.
- Applying `FxImageTile.pixelTransform` to a base edit preview was incorrect in the observed host path. The preview was rendered into filter output, and Motion/Final Cut applied object/view transforms after plug-in rendering, so applying the host transform in shader double-moved the overlay.
- Treating visually correct guide overlays as proof that stored guide endpoints were already in image-space Y-down coordinates was wrong. Object-space storage can draw correctly through host conversion and still require a Y flip before image-space line solving.
- Leaving one output-coordinate Y flip and one input-texture Y flip inside the shader made render orientation hard to reason about. The production model should name both boundaries and preferably compose them into a testable render matrix.
