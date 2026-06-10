# Y-Axis Coordinate Conventions

AnyUpright crosses several coordinate systems whose Y axes are not interchangeable. Before changing geometry, hit testing, OSC drawing, Metal vertices, candidate-line conversion, or parameter writeback, identify the source coordinate space, the destination coordinate space, and whether the conversion crosses a Y-axis boundary.

This note records the current project convention. It is intentionally about semantics and ownership, not a replacement for tests.

## Coordinate Spaces

### Image And Output Pixels

- Image-space and output-space geometry use pixel coordinates where `top` means smaller Y and `bottom` means larger Y.
- `AUQuad.fullFrame(_:)`, `sourceQuad(from:size:)`, homography input/output points, and rendered source selections follow this convention.
- User-facing Quad offsets are expressed as positive `X` right and positive `Y` up. Applying those offsets to image/output pixels subtracts the Y component because image/output pixel Y grows downward.

### FxPlug Object Space

- FxPlug object coordinates are normalized over the object.
- Current Quad object-space helpers treat visual top as larger Y and visual bottom as smaller Y. The full-frame object base is top-left `(0, 1)`, top-right `(1, 1)`, bottom-right `(1, 0)`, bottom-left `(0, 0)`.
- Source Quad object-space storage uses the same visual direction: top source handles have larger Y than bottom source handles.
- Converting object-space points to source image pixels crosses a Y-axis boundary. Do not assume an object-space point's Y has the same visual meaning as an image-space pixel's Y.

### FxPlug Canvas And OSC Events

- Source Quad OSC hit testing primarily works in host canvas coordinates returned by FxPlug conversions.
- Final Cut can provide raw canvas-position events, while Motion may provide surface-local events. The current code keeps candidate paths for both and maps Motion-style surface-local events back to canvas coordinates before hit testing. Initial hover/hit tests must choose one event interpretation for a given mouse point: raw-canvas events inside the host canvas frame should not also compete against mapped-surface candidates, because that creates a second mirrored hit layer.
- Host canvas points used for Source Quad's persistent OSC outline, handles, hover highlights, and active highlights already have the correct Y direction for OSC drawing. Do not flip their Y again when drawing those controls.
- Source Quad's persistent OSC drawing treats host canvas X and Y symmetrically: control points are drawn directly in host canvas pixels. Do not add frame-center, surface-scale, backing-scale, aspect-fit, or Y-only compensation unless host callback data proves X and Y are arriving in different coordinate spaces.

### Metal Render Vertices

- The warp renderer builds tile-local Metal vertices from FxPlug tile bounds and pairs them with image/output coordinates.
- The source/output geometry used by the shader remains image/output pixel geometry. Keep Y-axis conversion at the boundary where tile vertices are paired with output coordinates.
- The OSC overlay renderer receives local pixel positions for the overlay surface. For Source Quad host-canvas control points, local X and local Y should remain the host canvas X and Y. They should not be clamped, re-normalized through output-image aspect fit, offset by viewer-frame centers, scaled by backing scale, or vertically mirrored.
- The OSC overlay renderer flips Y only when converting local surface pixels into the centered Metal vertex space: `metalX = surfaceX - surfaceWidth / 2`, `metalY = surfaceHeight / 2 - surfaceY`. Apply the same conversion to overlay primitive origins and axes so fragment distance fields stay aligned with the drawn vertices.

## Practical Rules

- Never fix a vertical mismatch by adding a local `height - y` until the two coordinate spaces on either side of the line are named.
- Positive user-facing Quad Y moves up, but image/output pixel Y grows down. That sign difference belongs in the parameter-to-image conversion layer.
- FxPlug object-space visual top uses larger normalized Y. Image/output pixel visual top uses smaller Y. That conversion should be explicit and covered by geometry tests.
- OSC outline, handles, and hover highlights for Source Quad are a display-only path. Keep their Y handling separate from drag writeback and persistent parameter conversion.
- If a handle drags correctly but the yellow hover highlight appears on the opposite edge, suspect only the hover/overlay drawing path before changing geometry or parameter writeback.
- If a visible source quad moves correctly but the hit target is mirrored, inspect the raw canvas versus mapped surface event path before changing the render preview.
- Any change that crosses one of these boundaries should add or update a deterministic geometry test that names the two coordinate spaces involved.

## Current Regression Checks

The lightweight geometry test executable includes coverage for:

- Source Quad image-space selection and object-space handle positions.
- Raw canvas event handling versus Motion-style surface-local event mapping.
- Source Quad OSC overlay drawing keeping host canvas X and Y direct, including points outside the visible surface.
- OSC surface-pixel to Metal centered-pixel conversion, including the single viewport-height Y flip at that boundary.
- Positive Quad Y offset semantics.

Run the documented geometry command in `docs/README.md` after changing any Y-axis conversion.
