# Stretch Implementation Notes

Last updated: 2026-07-25 20:35 MDT
Reference commit: 660ee0736c22d6dc430f3887a07eb219259b41c4
Observed host versions: macOS 26.5.1 (25F80), Motion Creator Studio 6.2 and 6.3 (450156), Final Cut Pro 12.2 and 12.3 (450152), FxPlug framework 4.3.4 (18567.3)

This file records AnyUpright-specific Stretch implementation choices. Reusable debugging guidance and host observations that may help other FxPlug plug-ins live under `docs/engineering-notes/`.

## Product Shape

- `AnyUpright Inner Stretch` and `AnyUpright Outer Stretch` are separate filters.
- The older combined Stretch effect with a user-visible Mode or Stretch Mode selector is historical context only.
- Each filter fixes the hidden Stretch mode parameter to its intended render semantics.
- Mirror modes were accidental exploratory work and are not part of current Stretch behavior.
- `AnyUpright Inner Stretch` defaults to the central 80% input selection.
- The full-frame Inner Stretch case remains a regression fixture for identity/no-offset render checks, not the current product default.
- `AnyUpright Inner Stretch` is manual-only. It does not implement `FxAnalyzer` or expose detector, score-threshold, or candidate-selection parameters. Former parameter IDs `216...218`, groups `384...385`, and hidden detection-slot ranges starting at `400` and `600` are retired and must not be reused.

## Inner Stretch

- `Edit Mode` is visible only in `AnyUpright Inner Stretch` and is enabled by default.
- While `Edit Mode` is enabled, the filter output keeps the image unwarped and dims outside the selected input selection.
- The filter-output dimming follows the clip/image and can render even when the host does not instantiate or dispatch the FxPlug OSC.
- The interactive white outline, blue handles, yellow hover/drag highlights, hit testing, and drag writeback are owned by the FxPlug OSC layer.
- Inner Stretch corner coordinate groups are hidden from the inspector; users position the input selection through onscreen handles.
- Dragging Inner Stretch handles writes hidden source-corner percentage offsets and clears matching pixel offsets so render-time source geometry is independent of OSC surface size.
- A previous point-parameter writeback experiment was backed out: Motion Studio 6.2 accepted `setXValue(_:yValue:)` during OSC drags, but later reads returned default points. The current path uses float-parameter writeback.

## Outer Stretch

- `AnyUpright Outer Stretch` fixes the shared Stretch path to output-corner warp semantics.
- Its visible output corners expose `X %`, `Y %`, `X px`, and `Y px` offsets in the inspector.
- Final offset is `percentage * current frame dimension + pixels`.
- Positive `X` moves right. Positive `Y` moves up.
- Outer Stretch writes output-corner pixel offsets while preserving existing percentage offsets.

## OSC Classes And Geometry Helpers

- Inner Stretch uses `AnyUprightInnerStretchOSCPlugIn`.
- Outer Stretch subclasses it through `AnyUprightOuterStretchOSCPlugIn` and fixes `fixedStretchMode` to `.outputCorners`.
- `drawingCoordinates()` returns `kFxDrawingCoordinates_CANVAS`.
- Object/canvas conversion goes through `FxOnScreenControlAPI_v4.convertPoint(...)`.
- Inner Stretch visible OSC drawing, hit testing, hover, and drag routing all use the same unflipped FxPlug Y-up object/canvas geometry. The custom overlay renderer and Motion's IOSurface composition own the display-space crossing.
- `StretchOSCEventCoordinateMode` selects the accepted host-event interpretation for hit testing and dragging. After `convertPoint(...)` returns the FxPlug Y-up object coordinate, writeback stores it directly for both `.rawCanvas` and `.mappedSurface`.
- Corner identity remains unchanged across this boundary. A visible `topLeft` is drawn and hit as `topLeft`, then writes only the `topLeft` parameter group.
- `AnyUprightGeometry.stretchObjectPoints`, `innerStretchObjectPoints`, `sourceCornerPercentOffset`, and `cornerPixelOffset` own the testable corner naming and parameter/object conversion semantics.

## Render And Overlay Choices

- Both Stretch mode filters currently declare full-buffer rendering. Inner Stretch edit preview and both applied Stretch modes are treated as full-frame render surfaces for Motion/FCP preview stability.
- Stretch parameter state populates stable input/output sizes before rendering. Applied Stretch matrices are solved in that stable correction frame, then adapted to the current render request's source/output size.
- Inner Stretch edit-preview render sampling uses identity preview tile selection: `sourceTileBounds(... usesIdentityPreview: true)` requests the same source tile as the destination tile.
- Inner Stretch edit preview keeps its project matrix as the current-request identity path even when stable correction sizes are present; stable-size adaptation is for applied Stretch transforms.
- Render state carries `inputImageOriginInTexture` and `inputTextureSize`; shader texture lookup computes `texturePixel = sourcePixel + inputImageOriginInTexture` before dividing by `inputTextureSize`.
- Inner Stretch edit preview does not apply `destinationImage.pixelTransform` or `sourceImage.inversePixelTransform` in shader.
- Inner Stretch OSC points use `.canvasFramePixels`; `oscSurfacePixel(fromHostCanvasPixel:)` currently returns direct X/Y.
- The overlay renderer converts these direct Y-up Canvas pixels to centered Metal vertices. Motion's composition of the returned IOSurface completes the observed display mapping; callers must not preflip points to match IOSurface memory layout.
- Inner Stretch uses the same boundary-adjusted render matrices as the other Warp paths. The matrix converts physical output-IOSurface Y to logical output-image Y, applies the projective transform, then converts logical source-image Y to the physical input texture and adds the tile origin. Edit Mode applies the matching physical-output Y conversion before its selection-to-rect matrix.
- Persistent OSC overlay vertices are uploaded through an `MTLBuffer`; only small constants such as viewport size use inline `setVertexBytes`.

## Final Cut And Motion Template Notes

- Final Cut templates that need onscreen dragging must include Motion's built-in `Publish OSC` setting for the FxPlug filter.
- In local `.moef` XML, the built-in setting appears as parameter `id="10005"` with `name="Publish OSC"` and `value="1"`.
- Publishing only user-facing parameters such as `Edit Mode` can still allow filter-output dimming to render, but may not instantiate or dispatch events to the OSC layer.
- After changing template publication, plugin registration, OSC class shape, or parameter surface, restart Motion/Final Cut or delete and re-add the effect.
- If PlugInKit identity looks stale, quit host apps, kill AnyUpright wrapper/XPC processes, rebuild/register the intended wrapper, and re-add the effect.
- Debug logging is enabled by creating `/tmp/AnyUprightStretchOSC.debug`; logs are written to `/tmp/AnyUprightStretchOSC.log`. Remove the flag during normal use.
- Temporary Stretch render diagnostics use `/tmp/AnyUprightStretchRender.debug` and `/tmp/AnyUprightStretchRender.log`. They are intended for local debugging only and should remain flag-gated.

## Relevant Engineering Notes

- `docs/engineering-notes/stretch-coordinate-layer-contract.md`: transferable coordinate-layer contract and Apple API gaps.
- `docs/engineering-notes/y-axis-coordinate-conventions.md`: Y-axis boundaries for four-corner FxPlug controls.
- `docs/engineering-notes/stretch-osc-hit-testing.md`: hit-test and drag pitfalls.
- `docs/engineering-notes/stretch-osc-rendering.md`: OSC overlay rendering pitfalls.
- `docs/engineering-notes/stretch-render-tile-sampling.md`: render tile/source sampling pitfalls.
- `docs/engineering-notes/stretch-host-validation.md`: host-state validation pitfalls.
