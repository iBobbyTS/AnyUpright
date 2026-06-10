# Quad Coordinate Layer Contract

Last updated: 2026-06-10 15:40 MDT
Reference commit: 11aa3148242f9743c8c48903739c604f84dd2e66
Observed host versions: macOS 26.5, Motion Studio 6.2, Final Cut Pro 12.2

This note is a transferable debugging contract for four-corner FxPlug controls. It is not a product feature description. Use it when implementing a similar source-quad/corner-pin control, or when a visible handle, hover target, render preview, or final warp appears shifted, mirrored, or fixed to the viewer instead of the image. Names such as "source quad" are examples of a source-selection control, not a requirement that another plug-in use the same product shape.

Apple's FxPlug documentation names the host coordinate spaces and says Y increases upward in `CANVAS`, `DOCUMENT`, and `OBJECT`. It does not fully define how Final Cut Pro's viewer, the visible video rectangle, pan/zoom, the OSC drawable IOSurface, render tiles, and plug-in parameter storage relate to each other. Treat those host-specific relationships as empirical until logging proves them.

## Official API Baseline

Use Apple documentation and SDK headers to establish only the baseline the host API actually promises:

- `FxDrawingCoordinates` names `CANVAS`, `DOCUMENT`, and `OBJECT`, and documents those spaces as Y-up.
- `FxOnScreenControl` event callbacks pass mouse positions in the space returned by `drawingCoordinates()`.
- `FxOnScreenControlAPI.convertPoint(...)` converts among the named OSC spaces; use it instead of reconstructing object-to-canvas math.
- `FxOnScreenControlAPI_v2` exposes canvas zoom, canvas pixel aspect ratio, object/input bounds, object/input dimensions, pixel aspect ratio, and object-to-screen transform. These are evidence sources, not automatic correction factors.
- `FxOnScreenControlAPI_v3.backingScaleFactor` is useful for screen-dependent resources such as CPU-prepared textures; Apple notes vertex coordinates normally scale properly already.
- `drawOSC(width,height,activePart,destinationImage,...)` supplies callback dimensions and an `FxImageTile` destination image. Validate which one matches the actual drawable surface before building Metal vertices.
- `FxImageTile` exposes tile bounds, image bounds, pixel transforms, image origin, IOSurface, and Metal texture retrieval. It does not define a plug-in's sampling or clamping policy.
- `FxTileableEffect` separates destination image bounds, source tile requests, and render tile execution. A plug-in must make tile/source sampling identity-preserving if an edit preview claims to be identity.

Everything beyond that baseline is a project convention or host observation and should be logged before it becomes a formula.

## Observed Host Behavior

The following behavior was measured on macOS 26.5 with Motion Studio 6.2 and Final Cut Pro 12.2. Apple documentation did not promise these details, and future host versions may differ. Treat these as starting hypotheses, then confirm with logs in the target environment.

- Final Cut Pro 12.2 delivered source-selection initial hover/hit points that behaved as raw host-canvas coordinates in the tested viewer states. Running the same point through the Motion-style mapped-surface fallback created a second, hidden hit layer above or below the visible controls.
- In Final Cut Pro 12.2, visible source-selection handles and edges could live outside the visible video/object rectangle after dragging and still needed raw-canvas hit testing. Being outside the video frame was not evidence that the event point was surface-local.
- In the tested Final Cut Pro zoom/pan states, direct host canvas X and direct host canvas Y moved symmetrically for persistent OSC drawing. Frame-center compensation, backing-scale residual formulas, Fit/aspect refitting, and Y-only displacement formulas made the control drift or stick to the preview window.
- In Motion Studio 6.2, some OSC paths behaved as if event points were surface-local and needed mapping back to canvas. This compatibility path is kept for Motion and unknown hosts, but Final Cut Pro 12.2 initial hover/hit disables it.
- In Motion Studio 6.2 OSC drawing, callback `drawOSC` width/height could describe the object/source dimensions while the actual drawable target was represented by `destinationImage` and its IOSurface/Metal texture. Building overlay vertices from width/height alone could choose the wrong viewport.
- In the tested hosts, a filter-output source-selection edit preview should not apply `destinationImage.pixelTransform` or `sourceImage.inversePixelTransform`. The host applies object/view transforms after the plug-in renders the filter output, so applying those transforms in the shader double-moved the preview.
- With padded render tiles in the tested Motion/FCP render path, source texture sampling needed the input image origin inside the texture. Treating `sourcePixel / imageSize` as the texture coordinate produced a verified 2 px vertical identity-preview shift.
- Motion Studio 6.2 accepted point-parameter writes during an OSC drag in one experiment, but subsequent reads returned default points. Float-parameter writeback persisted reliably in the tested path.
- Final Cut Pro templates created from Motion needed the built-in Motion `Publish OSC` setting enabled for the FxPlug filter. Publishing only custom user-facing parameters allowed filter-output visuals to render, but did not guarantee Final Cut would instantiate or dispatch mouse events to the OSC.
- Accessibility showing `OZFxPlugOnscreenControl` in Final Cut Pro 12.2 proved only that the host exposed an OSC accessibility element. It did not prove the plug-in's own OSC callbacks were firing.

## Layer Inventory

| Layer | Owner | Unit | Origin And Y | Use In A Four-Corner Control | What Apple Defines | What You Must Validate |
| --- | --- | --- | --- | --- | --- | --- |
| Source clip image | host/render input | image pixels | Project convention should be explicit; in this project visual top has smaller Y | Texture content being sampled | `FxImageTile.imagePixelBounds`, `tilePixelBounds`, `pixelTransform`, `imageOrigin` exist | Whether tile origin/padding means `sourcePixel / imageSize` is wrong |
| Filter output image | plug-in render output | image pixels | Same image-pixel convention as the renderer | Final warped frame or identity edit preview | `destinationImageRect`, `destinationImage`, and output tiles | Whether host later applies object/view transforms after plug-in render |
| Valid image rect | plug-in math | image pixels | Same as filter output image | Clamp only coordinates outside real image content | Apple gives image bounds but not your clamping policy | Distinguish real image bounds from padded tile bounds |
| Render tile texture | host/Metal | texture pixels | Metal texture layout, not necessarily image-space origin | Efficient partial render/sampling | `FxImageTile.tilePixelBounds`, IOSurface/Metal texture | Input texture origin inside a padded tile; texture size versus image size |
| Parameter storage | plug-in | percent and/or pixels | Define per parameter; do not inherit host meaning implicitly | Persistent, keyframeable corner positions | FxPlug persists parameters; point/float behavior is host/API-specific | Whether writeback reads persist at the same time and keyframe context |
| FxPlug object space | host OSC API plus plug-in helpers | normalized object coordinates | Apple documents Y increasing upward; object is 0-1 width/height | Stable handles relative to the filtered object | `OBJECT`; `objectBounds`; `objectToScreenTransform`; conversion API | Which object bounds host uses for filters, templates, and transformed clips |
| FxPlug canvas space | host OSC API | canvas pixels or host canvas units | Apple documents Y increasing upward | Mouse event space when `drawingCoordinates()` returns `CANVAS`; persistent OSC points after object conversion | `CANVAS`; event positions are in `drawingCoordinates` space | Whether Final Cut gives raw canvas points while Motion gives surface-local-looking points in a specific path |
| FxPlug document space | host OSC API | movie canvas units | Apple documents Y increasing upward | Optional intermediate; avoid unless you have a reason | `DOCUMENT` is named as movie canvas coordinates | Whether using it changes pan/zoom or pixel-aspect behavior in your host |
| Host viewer / preview window | host UI | screen/UI pixels | Host-specific | The Final Cut/Motion panel the user sees | Not fully specified by FxPlug OSC docs | Relationship among viewer pan/zoom, visible video rectangle, and canvas points |
| Visible video rectangle in viewer | host UI/object transform | host canvas or screen pixels depending on callback | Host-specific | Where the video appears after Fit/zoom/pan/spatial conform | Not fully specified | Whether controls should be clamped to it; for source selection, they often must not be |
| OSC drawable surface | host OSC render target | IOSurface/texture pixels | Metal texture coordinates; define your shader boundary | Where you draw interactive handles/lines | `drawOSC` supplies `destinationImage`; width/height are callback values | Whether callback width/height equal texture size; often validate against `destinationImage` |
| Local OSC surface pixels | plug-in overlay math | pixels in OSC drawable | Choose one convention; here local X/Y are host-canvas X/Y for raw-canvas controls | Input to overlay primitive construction | Not separately defined by Apple | Whether you need any canvas-to-surface mapping at all |
| Metal centered vertices | plug-in shader | centered pixels | Usually X right, Y up after explicit conversion | Vertex positions and primitive distance fields | Metal itself; not FxPlug-specific | Exactly one surface-to-Metal Y flip, and primitive origins/axes use the same conversion |

## Boundary Rules

- Every conversion must name its source layer and destination layer. A naked `height - y`, frame-center subtraction, or backing-scale adjustment is a bug until the two layers are identified.
- Do not use a viewer symptom to infer a renderer fix. If filter output export aligns but OSC hover is mirrored, inspect canvas/event interpretation and overlay drawing first.
- Do not use a renderer symptom to infer an OSC fix. If the no-plugin export and edit-preview export differ by a constant row/column shift, inspect render tile origin and source texture addressing first.
- Apple documents that `CANVAS`, `DOCUMENT`, and `OBJECT` Y increase upward, but it does not define how the Final Cut viewer panel, visible video rectangle, and OSC drawable map to that canvas in every state. Log before compensating.
- Treat X and Y symmetrically unless logs prove the host sends them in different spaces. If horizontal pan is correct with direct canvas X, a vertical-only formula is suspect.
- Keep visible geometry, hit geometry, and drag writeback geometry separate. They may share points, but they do not necessarily share coordinate semantics.

## Implementation Recipe

1. Define image/output pixel semantics first. Pick top-left/Y-down or bottom-left/Y-up and write it down before adding parameters.
2. Define persistent parameter semantics separately. User-facing `Y` may mean "up" even if image pixels grow down.
3. Convert parameters to render image pixels in one place. This is where user-facing positive-up offsets become image-pixel subtraction if the renderer uses visual top as smaller Y.
4. Convert parameter storage to object-space OSC handles in one place. For FxPlug object space, visual top should use larger normalized Y because Apple documents OSC coordinate Y as upward.
5. Convert object handles to host canvas through `FxOnScreenControlAPI.convertPoint(...)`. Do not manually reimplement object-to-canvas transforms while debugging pan/zoom.
6. Decide the event interpretation for each host. For Final Cut, verify whether the event point is raw canvas; for Motion, verify whether a surface-local mapper is needed. Choose one interpretation for a mouse point.
7. Draw OSC controls in the same visible layer used by hit testing. A hidden storage layer must not also be hit-testable.
8. Convert local OSC surface pixels to Metal vertices at the final overlay-rendering boundary. Flip Y once there if your Metal vertex space is centered with Y up.
9. During drag writeback, cross from visible canvas/object geometry back to persistent storage explicitly. This is independent from hit testing.
10. In edit-preview render mode, keep identity video sampling identity. Request/source the matching tile and account for input tile origin inside the texture.

## Diagnostic Questions

When the control is visibly displaced:

- Does an exported frame without host viewer UI show the same displacement? If yes, inspect render tile/source sampling.
- Does the visible line move correctly but hover fires on a mirrored line? If yes, inspect duplicate hit layers or raw-versus-mapped event candidates.
- Does the whole control stay fixed in the preview window while the video pans underneath it? If yes, inspect accidental viewer/frame compensation.
- Does only Y fail while X tracks perfectly? If yes, prove why host X and Y are in different spaces before adding a Y-only correction.
- Does the bug appear only after reusing an existing host instance? If yes, rebuild/re-register/re-add before changing math.

When the handle is outside the video rectangle:

- Decide whether "outside video" means outside source image, outside object bounds, outside host canvas frame, outside OSC drawable, or outside the currently visible viewer panel.
- For source-selection controls, outside the video rectangle can still be valid interaction if the visible handle is drawn there.
- If a point is outside the OSC drawable texture, the renderer may not show it, but drag state should not reinterpret the coordinate mode mid-drag.
- Do not use "outside object frame" alone as proof that an event needs Motion-style surface mapping; Final Cut source handles can intentionally live outside the object/video frame.

## Logging Checklist

A useful coordinate log should include all values needed to disprove a bad conversion:

- host bundle identifier and host app name;
- `drawingCoordinates()` result;
- callback `width`/`height`;
- `destinationImage.tilePixelBounds`, `imagePixelBounds`, IOSurface/texture size, and image origin if available;
- `objectBounds`, `inputBounds`, object width/height, canvas zoom, backing scale, and pixel aspect ratio;
- raw mouse position from the callback;
- object-space handle points before and after any intentional Y flip;
- host-canvas points after `convertPoint`;
- mapped-surface candidate if one is used, and why it was accepted or rejected;
- selected event interpretation stored for an active drag;
- final visible hit quad, storage/writeback quad, and active part;
- overlay local surface points and final Metal-centered vertices.

Do not log only the final point. Most repeated fixes failed because the final point looked plausible while one upstream layer had already crossed a Y boundary.

## Gaps To Cover Yourself

Apple's headers are necessary but not enough for a robust four-corner OSC:

- They state that FxPlug drawing coordinate spaces have Y increasing upward, but not how Final Cut's visible preview panel maps to raw canvas callbacks.
- They provide `convertPoint` between named spaces, but not a product-level rule for source-selection handles that intentionally leave the video rectangle.
- They provide `canvasZoom`, pixel aspect APIs, object bounds, and backing scale, but not whether a given OSC should compensate those values. Decide from logged host behavior.
- They provide `drawOSC(width,height,destinationImage,...)`, but not a guarantee that callback width/height are the actual Metal drawable size in every host path.
- They define image/tile bounds and pixel transforms, but not how your edit-preview identity mode should request source tiles or clamp padded output coordinates.

When a bug sits in one of those gaps, prefer a log-backed project convention over an inferred formula.

## Previous Wrong Attempts

- Treating Final Cut viewer pan as a signal to subtract canvas-frame center kept the control attached to the preview window instead of the video/canvas geometry.
- Treating `drawOSC` callback width/height as the drawable viewport hid the real IOSurface/texture dimensions in Motion-style paths.
- Treating backing scale as a displacement factor made a symptom look closer while preserving the wrong coordinate boundary.
- Treating storage object geometry as another visible hit candidate created two hit layers: the visible one and a mirrored hidden one.
- Treating a render identity shift as template placement led to dead ends; padded render tile sampling was the layer that had actually moved.
