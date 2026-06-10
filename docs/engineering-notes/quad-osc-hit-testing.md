# Quad OSC Hit Testing And Dragging

Last updated: 2026-06-10 15:47 MDT
Reference commit: 11aa3148242f9743c8c48903739c604f84dd2e66
Observed host versions: macOS 26.5, Motion Studio 6.2, Final Cut Pro 12.2

This note records reusable OSC hit-test and drag lessons for four-corner FxPlug controls. It does not record product features or implementation choices. Project-specific choices live outside `engineering-notes`; in this repository they are recorded in `../quad-implementation-notes.md`.

For a reusable layer-by-layer model, start with `quad-coordinate-layer-contract.md`. This file focuses on the hit-test and drag questions that Apple leaves to the plug-in and host behavior.

## Event Interpretation

- A four-corner OSC can receive points that need different interpretation in different hosts.
- Final Cut can send raw host-canvas points.
- Motion can send surface-local points that must be mapped back to canvas.
- Initial hover/hit resolution should choose either raw canvas or mapped surface for a mouse point, not both.
- Once a drag starts, store the chosen coordinate mode and reuse it for the whole drag. A drag must not switch between raw and mapped interpretation when the cursor crosses the object frame.
- Do not decide event mode from "inside/outside the video rectangle" alone. A source-selection handle can validly live outside the visible video rectangle, object bounds, or current viewer crop after the user drags it.

## Versioned Host Observations

These observations are not Apple API guarantees. They were measured on macOS 26.5 with Motion Studio 6.2 and Final Cut Pro 12.2:

- Final Cut Pro initial hover/hit points behaved as raw canvas coordinates in the tested states. Adding mapped-surface fallback for the same point created mirrored or offset hit targets.
- Final Cut Pro handles and edges outside the visible video rectangle still needed raw-canvas hit testing if they were visibly drawn there.
- Motion Studio retained the need for mapped-surface compatibility in tested paths, so Motion and unknown hosts may still need that fallback when the mapped point lands near the visible control layer.
- Host-provided `activePart` could be stale or zero in Final Cut paths; local hit testing still needed to start a drag when the pointer was over a visible handle/edge/body.

## Hit Geometry Contract

- The shape drawn for interaction and the shape used for hit testing should be the same layer, with the same corner ordering and the same Y convention.
- Storage geometry may be used to compute writeback values, but it should not be queried as an additional hover or drag target.
- Fixed-size handles and hit tolerances should be defined in the event/drawing layer, not in render image pixels, unless the control is intentionally supposed to scale with the video.
- If the handle is visually clipped by the OSC drawable, keep the active drag state in the coordinate mode that started the drag. Do not fall back to body-only dragging just because the pointer left the drawable or object bounds.
- Body hit testing is a fallback, not a substitute for handle/edge hit testing. If body hits work while handles/edges outside the video do not, inspect clipping and event interpretation before changing polygon math.

## Hit Priority

- Handles should win over edges.
- Edges should win over the quad body.
- The whole quad body can start a drag and translate all four corners.
- Edge parts should translate their two adjacent corners.
- Corner parts should write one corner.
- If the host provides a nonzero active part, decide explicitly whether it wins. If the host passes none/zero, local hit testing may still need to start the drag to avoid losing host paths with stale or absent active-part dispatch.

## Template And Host Notes

- Seeing an OSC accessibility element is not proof that a plug-in's OSC class receives callbacks. Require callback logs or visible drag state changes.
- Final Cut templates created from Motion may need Motion's built-in `Publish OSC` parameter enabled for mouse-driven controls.
- Delete and re-add the effect after changing template/plugin registration. Existing host instances can cache old template state or old XPC service identity.
- Avoid stacking another effect instance as a validation shortcut; it can create misleading black, duplicated, or overlaid viewer states.
- If callback proof is needed, add a narrow debug flag and log callback entry, event interpretation, hit part, and converted points. Remove the flag during normal use.

## Regression Surfaces To Keep

- Raw canvas and Motion-style surface-local coordinates remain distinct.
- Raw Final Cut events inside the canvas frame do not add a mapped layer.
- Visible source-selection controls outside the object/video frame keep raw-canvas hit testing in the observed Final Cut path.
- Final Cut host paths can disable mapped-surface fallback.
- Local hit can start a drag when host active part is none.
- Drag display part stays highlighted even when hover stops.

## Previous Wrong Attempts

- Treating rendered filter-output pixels as enough for Final Cut dragging was wrong. Filter-output visuals can be visible while host mouse dispatch and interactive handles still need the FxOnScreenControl path.
- Clearing all OSC drawing avoided duplicate visuals but risked losing hover/drag affordances. Interactive controls should draw their own handle/hover layer when OSC callbacks are active.
- Hidden render parameters for hover were unreliable in Final Cut. FCP delivered hover callbacks, but transient parameter writeback and filter-output refresh lagged or failed to clear. Hover/active feedback belongs in the OSC overlay path.
- Testing an old already-open effect instance after code/template changes repeatedly produced false negatives. Fresh instance and host/XPC restart are part of the validation protocol.
- Adding `FxOnScreenControl` methods to the filter class itself, changing the OSC class to direct `NSObject`, or tweaking plist version strings did not fix OSC dispatch. A separate OSC class with supported-plugin registration is the shape to keep.
- Running both raw and mapped event candidates for one Final Cut mouse point created a hidden second hit layer above/below the visible quad.
