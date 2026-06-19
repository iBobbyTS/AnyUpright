# Quad Implementation Notes

Last updated: 2026-06-18 21:38 MDT
Reference commit: 11aa3148242f9743c8c48903739c604f84dd2e66
Observed host versions: macOS 26.5, Motion Studio 6.2, Final Cut Pro 12.2

This file records AnyUpright-specific Quad implementation choices. Reusable debugging guidance and host observations that may help other FxPlug plug-ins live under `docs/engineering-notes/`.

## Product Shape

- `AnyUpright Source Quad` and `AnyUpright Outer Corners` are separate filters.
- The older combined Quad effect with a user-visible Mode or Stretch Mode selector is historical context only.
- Each filter fixes the hidden Quad mode parameter to its intended render semantics.
- Mirror modes were accidental exploratory work and are not part of current Quad behavior.
- `AnyUpright Source Quad` defaults to the central 80% source quadrilateral.
- The full-frame Source Quad case remains a regression fixture for identity/no-offset render checks, not the current product default.
- `AnyUpright Source Quad` includes an explicit `Detect Source Quad` custom inspector button. It is implemented as a non-animatable custom FxPlug parameter with `kFxParameterFlag_CUSTOM_UI`, an empty `NSData` custom value, and an AppKit `NSButton` view instead of a trigger toggle, so the user-facing control stays momentary. The Swift plug-in keeps strong references to every button view returned from `createView(forParameterID:)`; without that, host-side custom UI lifetime is fragile when Motion or Final Cut rebuilds inspectors. Clicking it starts FxAnalysis, uses Vision rectangle detection on one representative frame, writes the best detected rectangle into the same hidden Source Quad corner offsets used by manual handles, and enables `Edit Mode` so existing filter-output dimming and OSC handles mark the detected area. Motion Studio 6.2 and Final Cut Pro 12.2 were verified to show the published control as a `Detect` button after saving and reopening `Quad.moef`. FCP visibility also requires `Quad.moef` publish settings to target the custom parameter (`Detect Source Quad`, channel `./216` in the current development template); the raw FxPlug parameter can exist in Motion while remaining invisible in FCP if it is not published by the template.

## Source Quad

- `Edit Mode` is visible only in `AnyUpright Source Quad` and is enabled by default.
- While `Edit Mode` is enabled, the filter output keeps the image unwarped and dims outside the selected source quadrilateral.
- The filter-output dimming follows the clip/image and can render even when the host does not instantiate or dispatch the FxPlug OSC.
- The interactive white outline, blue handles, yellow hover/drag highlights, hit testing, and drag writeback are owned by the FxPlug OSC layer.
- Source Quad corner coordinate groups are hidden from the inspector; users position the source quadrilateral through onscreen handles.
- Automatic Source Quad detection is a proposal/writeback path, not a separate render mode or separate overlay state. False positives are corrected with the same manual handles.
- Dragging Source Quad handles writes hidden source-corner percentage offsets and clears matching pixel offsets so render-time source geometry is independent of OSC surface size.
- A previous point-parameter writeback experiment was backed out: Motion Studio 6.2 accepted `setXValue(_:yValue:)` during OSC drags, but later reads returned default points. The current path uses float-parameter writeback.

## Outer Corners

- `AnyUpright Outer Corners` fixes the shared Quad path to output-corner warp semantics.
- Its visible output corners expose `X %`, `Y %`, `X px`, and `Y px` offsets in the inspector.
- Final offset is `percentage * current frame dimension + pixels`.
- Positive `X` moves right. Positive `Y` moves up.
- Outer Corners writes output-corner pixel offsets while preserving existing percentage offsets.

## OSC Classes And Geometry Helpers

- Source Quad uses `AnyUprightQuadManualOSCPlugIn`.
- Outer Corners subclasses it through `AnyUprightQuadOutputCornersOSCPlugIn` and fixes `fixedQuadMode` to `.outputCorners`.
- `drawingCoordinates()` returns `kFxDrawingCoordinates_CANVAS`.
- Object/canvas conversion goes through `FxOnScreenControlAPI_v4.convertPoint(...)`.
- Source Quad uses preview-aligned raw-canvas geometry for visible OSC drawing and hit testing. The unflipped object/canvas quad is kept only for storage, writeback, and diagnostics.
- The explicit Source Quad storage-to-preview crossing uses `verticallyFlippedObjectQuad` before object-to-canvas conversion.
- `AnyUprightGeometry.quadObjectPoints`, `sourceQuadObjectPoints`, `sourceCornerPercentOffset`, and `cornerPixelOffset` own the testable corner naming and parameter/object conversion semantics.

## Render And Overlay Choices

- Source Quad edit-preview render sampling uses identity preview tile selection: `sourceTileBounds(... usesIdentityPreview: true)` requests the same source tile as the destination tile.
- Render state carries `inputImageOriginInTexture` and `inputTextureSize`; shader texture lookup computes `texturePixel = sourcePixel + inputImageOriginInTexture` before dividing by `inputTextureSize`.
- Source Quad edit preview does not apply `destinationImage.pixelTransform` or `sourceImage.inversePixelTransform` in shader.
- Source Quad OSC points use `.canvasFramePixels`; `oscSurfacePixel(fromHostCanvasPixel:)` currently returns direct X/Y.
- The overlay renderer converts local surface pixels to centered Metal vertices with one Y flip at the viewport boundary.
- Persistent OSC overlay vertices are uploaded through an `MTLBuffer`; only small constants such as viewport size use inline `setVertexBytes`.

## Final Cut And Motion Template Notes

- Final Cut templates that need onscreen dragging must include Motion's built-in `Publish OSC` setting for the FxPlug filter.
- In local `.moef` XML, the built-in setting appears as parameter `id="10005"` with `name="Publish OSC"` and `value="1"`.
- Publishing only user-facing parameters such as `Edit Mode` can still allow filter-output dimming to render, but may not instantiate or dispatch events to the OSC layer.
- After changing template publication, plugin registration, OSC class shape, or parameter surface, restart Motion/Final Cut or delete and re-add the effect.
- If PlugInKit identity looks stale, quit host apps, kill AnyUpright wrapper/XPC processes, rebuild/register the intended wrapper, and re-add the effect.
- Debug logging is enabled by creating `/tmp/AnyUprightQuadOSC.debug`; logs are written to `/tmp/AnyUprightQuadOSC.log`. Remove the flag during normal use.

## Relevant Engineering Notes

- `docs/engineering-notes/quad-coordinate-layer-contract.md`: transferable coordinate-layer contract and Apple API gaps.
- `docs/engineering-notes/y-axis-coordinate-conventions.md`: Y-axis boundaries for four-corner FxPlug controls.
- `docs/engineering-notes/quad-osc-hit-testing.md`: hit-test and drag pitfalls.
- `docs/engineering-notes/quad-osc-rendering.md`: OSC overlay rendering pitfalls.
- `docs/engineering-notes/quad-render-tile-sampling.md`: render tile/source sampling pitfalls.
- `docs/engineering-notes/quad-host-validation.md`: host-state validation pitfalls.
