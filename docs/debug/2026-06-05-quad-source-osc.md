# Quad Source OSC Debug

Date: 2026-06-05

## Context

`AnyUpright Quad Manual` Source Quad is intended to work like a reverse corner-pin editor:

- `Show Corner Adjuster = on`: keep the rendered image unchanged, dim the area outside the source quad, draw four draggable handles, and persist their positions.
- `Show Corner Adjuster = off`: hide the handles and map the saved source quadrilateral to the full output frame.

Original Motion symptom: a visible overlay could appear, but it did not follow the selected object/image correctly and was not usable as draggable source-corner controls. The 2026-06-06 validation passes below supersede that initial symptom.

## Current Evidence

- Motion accessibility shows host OSC elements such as `OZFxPlugOnscreenControl` and `OZSelectedOSC`, but that alone does not prove the AnyUpright OSC class is being called.
- `/tmp/AnyUprightQuadOSC.log` previously showed filter render-path logging but no `quad-osc-init`, `draw-enter`, `hit-enter`, or drag callbacks after enabling the relevant Motion controls in one validation pass. Treat any earlier claim that OSC callbacks were proven working as stale unless reproduced again.
- Runtime `Info.plist` and the built binary include the `AnyUprightQuadManualOSCPlugIn` class and separate `FxOnScreenControl` registration linked to the Quad filter UUID. This makes manifest shape less likely to be the only issue.
- The installed Pixel Film Studios `PFSMaskV2` binary confirms a production FxPlug can use the same general shape: one `FxFilter` entry plus a separate `FxOnScreenControl` entry whose `supportedPlugins` points to the controlled filter UUID.
- 2026-06-05 21:24 local retest: after rebuilding and relaunching the wrapper, toggling `Show Corner Adjuster` in Motion only produced `filter-state` log lines. No `quad-osc-init`, `drawing-coordinates`, `draw-enter`, `hit-enter`, or drag lines appeared.
- The built AnyUpright binary exposes the expected Objective-C selectors and type encodings for `AnyUprightQuadManualOSCPlugIn`: `initWithAPIManager:`, `drawingCoordinates`, `drawOSCWithWidth:height:activePart:destinationImage:atTime:`, `hitTestOSCAtMousePositionX:mousePositionY:activePart:atTime:`, `mouseDown...`, `mouseDragged...`, `mouseUp...`, `keyDown...`, and `keyUp...`.
- System log during the Motion-triggered XPC relaunch included `invalid plugin object used for launch; launched plugin UUID differs from the UUID in the plugin object used for the request (most likely due to path-based fallback)`. Treat stale PlugInKit/LaunchServices identity as an active suspicion until a fresh-document/fresh-registration test disproves it.
- 2026-06-06 follow-up check: the temporary direct-`NSObject` Quad OSC experiment still only produced `filter-state` rows in `/tmp/AnyUprightQuadOSC.log`; no `quad-osc-init`, `drawing-coordinates`, `draw-enter`, `hit-enter`, or drag callbacks were observed. `tools/validate-fxplug-manifest.swift` still passes, while `tools/audit-feature-surface.swift` fails because it intentionally expects the original `AnyUprightOSCPlugIn` base-class shape. This result says the direct inheritance experiment is not evidence that host OSC dispatch is fixed.
- 2026-06-06 fresh-instance check: adding a new Quad filter instance eventually produced `quad-osc-init`, `drawing-coordinates canvas`, `draw-enter`, `hit-enter`, and renderer logs, so the separate OSC class can be instantiated by Motion when the filter instance is fresh enough.
- The OSC `drawOSC` callback reports `width=3840 height=2160`, while the `destinationImage` IOSurface/logged surface is `1670 x 844`. Mouse events also arrive in the surface-local coordinate system, not in raw object or full canvas pixels. Hit-testing must therefore map event surface coordinates back through the object canvas frame before comparing against canvas-space handles.
- The pre-fix renderer logged the default top-left handle as canvas `(659.1,719.2)` mapping to surface pixel `(167.0,84.4)`, while the matching Motion mouse event near that visible handle was around `(167.4,760.5)`. That was a Y-axis mismatch in the renderer's canvas-pixel path, not in the source-quad object geometry.
- 2026-06-06 01:17 local fix: `AnyUprightOSCOverlayRenderer.localPixel` no longer flips Y for `.pixels` coordinates. The expected default top-left handle now maps consistently with `AUCanvasSurfaceMapper.eventPoint(fromCanvasPoint:)`, around `(167.0,759.6)` for the captured `1670 x 844` surface.
- After rebuilding and relaunching the wrapper, automation attempts with `osascript`, `CGEvent`, and Computer Use did not successfully select a fresh Motion filter instance or trigger new `draw-enter` logs. `osascript` was blocked by auxiliary access (`-25211`), and Computer Use repeatedly reported an inactive app state before click/drag. Do not treat the absence of new logs in that pass as proof that the Y fix failed; it only means Motion did not run the fresh OSC callback path during that automated check.

## Similar Code And References Checked

### Apple FxPlug OSC Documentation

- Source: https://developer.apple.com/documentation/professional-video-applications/adding-onscreen-controls-to-plug-ins
- Archived guide source: https://developer.apple.com/library/archive/documentation/AppleApplications/Conceptual/FXPlug_overview/OnScreenControls/OnScreenControls.html
- Relevance: primary reference for Motion/FCP OSC lifecycle.
- Useful findings:
  - OSC is a separate plug-in class bundled with the effect.
  - The host sends `initWithAPIManager:` to the OSC class.
  - Draw effect-aligned geometry in object space, but draw handles in canvas space so handle size and orientation remain stable with viewer zoom.
  - Use `FxOnScreenControlAPI.convertPointFromSpace(...)` to convert between object and canvas.
  - Apple explicitly points to `FxShapeOSC.m` in the `FxShape` sample for coordinate conversion examples.
  - The archived guide includes the closest public conceptual example for this feature: a rectangular/quad selection control with four corner handles, four edge handles, an inside drag area, named active parts, canvas/object conversion, parameter readback/writeback during `mouseDragged`, and `forceUpdate = YES`.
  - The guide states that mouse coordinates arrive in the space returned by `drawingCoordinates()`. If Quad Source returns canvas coordinates, hit-test and drag positions are canvas-space and should be converted to object space before writing source-corner parameters.
- Limitation: the installed local FxPlug SDK only contains headers; `FxShapeOSC.m` sample source was not present under `/Library/Developer/SDKs/FxPlug.sdk`. The archived guide uses older OpenGL selection examples, so it informs event/coordinate semantics rather than the Metal `destinationImage` drawing implementation.

### FCP Cafe FxPlug Notes

- Source: https://fcp.cafe/developers/fxplug/
- Relevance: current FxPlug release-note aggregation and practical caveats.
- Useful findings:
  - Notes that OSC controls still need to provide a valid texture, even if nothing visible is drawn, otherwise a red overlay can appear in Final Cut Pro.
  - Notes recent FxPlug fixes around OSC dragging jitter and object-bounds caching.
- Limitation: not an implementation sample.

### SpliceKit / FCPBridge FxPlug Guide

- Source: https://github.com/elliotttate/SpliceKit/blob/main/docs/FXPLUG_PLUGIN_GUIDE.md
- Relevance: community FxPlug 4 implementation guide.
- Useful findings:
  - Recommends `drawingCoordinates = kFxDrawingCoordinates_CANVAS` for best UX.
  - Repeats the same object-to-canvas conversion pattern for drawing aligned controls with stable canvas-space handles.
  - Mentions Motion's host-provided `Publish OSC` toggle for effects with onscreen controls.
- Limitation: guide-level code snippets, not a four-corner corner-pin OSC implementation.

### Gyroflow Toolbox

- Source: https://github.com/latenitefilms/GyroflowToolbox
- Local inspection: downloaded source archive and searched `Source/Gyroflow/Plugin`.
- Result: real Objective-C FxPlug project, useful for parameter/custom inspector patterns and wrapper/XPC layout, but no `FxOnScreenControl` implementation was found.
- Related note: its custom inspector views mention being hosted in an overlay window, but that is not Motion canvas OSC behavior.

### FxKit

- Source: https://github.com/jslinker/FxKit
- Local inspection: downloaded source archive and searched Swift plug-in code.
- Result: useful Swift FxPlug wrapper/example project, but no canvas OSC or draggable overlay implementation was found.

### FxBrightness

- Source: https://github.com/FidelityFuze/FxBrightness
- Local inspection: downloaded source archive and checked project contents.
- Result: useful Swift/Metal FxPlug rendering example, but no OSC implementation was found.

### Spectra

- Source: https://github.com/elliotttate/Spectra
- Local inspection: downloaded source archive and checked project contents.
- Result: useful FxPlug4 LUT/Metal example, but no OSC implementation was found.

### CommandPost Viewer Overlays

- Source: https://github.com/CommandPost/CommandPost
- User-facing feature docs: https://commandpost.fcp.cafe/final-cut-pro/viewer-overlay/
- Local inspection: downloaded the `develop` archive and checked:
  - `src/plugins/finalcutpro/viewer/overlays.lua`
  - `src/extensions/cp/apple/finalcutpro/viewer/Viewer.lua`
  - `src/plugins/finalcutpro/tangent/overlay.lua`
- Relevance: real, open-source Final Cut Pro viewer overlay implementation.
- Useful findings:
  - This is not an FxPlug implementation. It runs as an external automation app and uses Accessibility plus Hammerspoon-style `hs.canvas`.
  - It locates the FCP viewer via AX tree matching, reads the viewer content frame from `AXFrame`, creates a separate overlay canvas over that frame, and redraws when viewer/window state changes.
  - It supports viewer grids, crosshairs, letterbox overlays, still-frame overlays, and draggable guide state, so it is a useful product/UX reference for overlay persistence and frame tracking.
  - Draggable guides are implemented by adding canvas elements with `trackMouseDown`, `trackMouseUp`, and `trackMouseMove`; on drag, the code computes mouse position relative to the overlay canvas, moves the visible center and guide lines, then persists guide position in config.
- Limitation: it does not exercise Motion/FCP `FxOnScreenControl`, `Publish OSC`, `supportedPlugins`, `drawOSCWithWidth`, `hitTestOSC`, parameter writeback, or object/canvas conversion inside a plug-in. Do not use it as evidence that FxPlug OSC callbacks are working.

### GLSL2FxPlug Point Parameter

- Source: https://github.com/9elements/GLSL2FxPlug
- Local inspection: downloaded source archive and checked `README.markdown` and `src/processor.py`.
- Relevance: older FxPlug generator that documents `$POINT` as a two-slider parameter with a pointer control inside the canvas.
- Useful findings:
  - It is evidence that simple point-style controls have existed in FxPlug-style plug-ins.
  - The generated path appears to use standard point parameters rather than a custom four-handle `FxOnScreenControl`.
- Limitation: not an FxPlug 4 Metal OSC implementation and not a four-corner drag overlay. It does not explain the current Motion dispatch issue.

### Keyframeless

- Source: https://github.com/overpolish/keyframeless
- Local inspection: downloaded the `main` archive and checked the FxPlug sources under:
  - `KeyframelessKit/KeyframelessKit/OSC/Base/`
  - `KeyframelessKit/KeyframelessKit/OSC/Controls/`
  - `Canvas/Canvas/Plugin/OSC/`
  - `Glow/Glow/Plugin/OSC.m`
  - `MagicMove/MagicMove/Plugin/OSC.m`
- Relevance: this is the strongest public source-code reference found so far. It is a current Objective-C FxPlug suite with real viewer OSC drawing, hit-testing, dragging, cursor changes, and parameter writeback.
- Useful findings:
  - `Info.plist` uses the same general manifest shape as AnyUpright and PFSMaskV2: one `FxFilter` entry plus a separate `FxOnScreenControl` entry with `supportedPlugins` pointing at the filter UUID.
  - `KKOnScreenControl` returns `kFxDrawingCoordinates_CANVAS`, so mouse positions, hit tests, and draggable handles are in canvas coordinates.
  - `KKOnScreenControl+CoordinateSpace` centralizes object-to-canvas and canvas-to-object conversions through `FxOnScreenControlAPI_v4.convertPointFromSpace(...)`.
  - `KKCropOSC` is the closest source-level analogue for Quad Source: it converts the full object frame to canvas coordinates, computes corner/edge handle positions in canvas space, hit-tests handles with a pixel radius, converts dragged canvas points back to object space, writes normal FxPlug parameters with `FxParameterSettingAPI_v5`, then sets `forceUpdate = YES`.
  - `GlowOSC` and `MagicMoveOSC` confirm the same pattern for point/ring controls: draw in canvas space, convert only when writing object-space parameters, and update hover/drag cursors through `FxOnScreenControlAPI_v4.setCursor(...)`.
  - Canvas' own OSC code shows a more complex multi-point/path editor using explicit active-part IDs, hover state, drag state, and `setCursor`, which is useful if Quad Source later grows edge dragging or whole-quad dragging.
- Limitation:
  - Keyframeless source is PolyForm Noncommercial 1.0.0. Use it only as an implementation reference for FxPlug host behavior and coordinate strategy; do not copy source into AnyUpright.
  - `KKCropOSC` is axis-aligned crop, not arbitrary four-point perspective selection. For AnyUpright, the transferable part is the OSC lifecycle and coordinate/writeback pattern, not the crop parameter math itself.

### Pixel Film Studios PFSMaskV2

- Source: installed local closed-source app at `/Applications/Pixel Film Studios/Plugins/PFSMaskV2.app`.
- Local inspection:
  - `Info.plist` contains an `FxOnScreenControl` entry linked to the filter.
  - It was the only installed Pixel Film Studios plug-in found in this scan with an `FxOnScreenControl`/`supportedPlugins` registration.
  - `otool -ov` shows `PFSMaskV2OSC` methods including `initWithAPIManager:`, `drawingCoordinates`, `drawOSCWithWidth:height:activePart:destinationImage:atTime:`, `hitTestOSCAtMousePositionX:mousePositionY:activePart:atTime:`, `mouseDraggedAtPositionX:positionY:activePart:modifiers:forceUpdate:atTime:`.
  - Binary metadata includes ivars such as `_canvasSize`, `_selectionBoxRect`, `_currentPointCount`, `_mouseDownPart`, `_cacheTransform`, `_cachePoints`, `_lastObjectPosition`, cursors, and point lists, which matches a canvas/object drag-control implementation with cached geometry and drag state.
  - Strings show use of `convertPointFromSpace:fromX:fromY:toSpace:toX:toY:`, `setCursor:`, parameter retrieval calls, mouse entered/moved/exited handlers, and helper names for selection-box/shape/handle/scale/rotate drag paths.
- Limitation: binary-only reference; no source code to copy or verify exact coordinate math.

## Dead Ends

- Public GitHub code search through the unauthenticated API returned `Requires authentication`.
- The local `gh` token is expired, so authenticated GitHub code search was not available in this pass.
- Search-engine checks, local FxPlug SDK checks, and downloaded source-archive checks did not find a public arbitrary four-corner perspective `FxOnScreenControl` implementation. Keyframeless `KKCropOSC` is a close crop/rectangle handle reference, not a source-quad homography editor.
- GitHub repository search for `FxPlug` found a small number of repositories, but the relevant public Final Cut/Motion plug-ins inspected so far were render/filter examples or guides, not draggable canvas OSC implementations.
- Unauthenticated GitHub code search still blocks exact queries such as `FxOnScreenControl_v4 drawOSCWithWidth` with `Requires authentication`; broad repository search did not surface a direct corner-pin OSC sample.
- A local scan of installed `/Applications/Pixel Film Studios`, `/Applications/Coremelt`, and `/Applications/FxFactory.app` plug-in plists found only `PFSMaskV2` exposing an `FxOnScreenControl` entry with `supportedPlugins`.
- `grep.app` API requests were blocked by a Vercel security checkpoint in this environment.
- OBS/OpenFX corner-pin or transform examples can help with homography/render math, but they do not exercise Motion/FCP `FxOnScreenControl`, `Publish OSC`, object/canvas conversion, or parameter writeback.
- CommandPost-style external viewer overlays can help as a fallback product architecture or UX reference, but they are outside the FxPlug host callback path and would be a separate helper-app strategy.
- Seeing `OZFxPlugOnscreenControl` in Motion is insufficient evidence by itself; callback logs or visible drag behavior are required.
- Changing the Quad and Upright OSC plist `version` values from `1.0` to `1` aligned them with PFSMaskV2, but did not make Motion call `AnyUprightQuadManualOSCPlugIn`. Keep `version=1` only because it matches the known-good binary, not because it fixed callback dispatch.
- Temporary experiment: adding `FxOnScreenControl` to the Quad filter plist entry and making `AnyUprightQuadManualPlugIn` itself implement minimal OSC methods still produced only `filter-state` logs. Motion did not call the filter-level `drawingCoordinates`, `drawOSC`, or hit-test methods. This path was reverted and should not be retried without new evidence.
- Temporary experiment: changing `AnyUprightQuadManualOSCPlugIn` to inherit directly from `NSObject` instead of `AnyUprightOSCPlugIn` did not make Motion instantiate/call the OSC class. The audit script failing after this change is expected because the script is checking the pre-experiment class declaration, not because manifest validation failed.
- Attempting `pluginkit -r` on the built pluginkit returned `remove: Connection invalid` in this environment. Use wrapper relaunch, XPC process restart, and system log evidence instead of assuming `pluginkit -r` is available.

## Current Root-Cause Hypothesis

The current implementation direction is to make the Quad Source OSC a canvas-space control:

1. Return `kFxDrawingCoordinates_CANVAS` from `drawingCoordinates()`.
2. Store source-corner state in normal FxPlug parameters, not transient OSC-only state.
3. For draw and hit-test, convert saved object-space source corners to canvas space through `FxOnScreenControlAPI_v4.convertPointFromSpace`.
4. Draw the dimmed quad and connecting edges aligned to converted canvas positions, with handles sized in surface pixels through the object canvas frame.
5. For hit-test and drags, map the Motion event surface point back into canvas space through `AUCanvasSurfaceMapper`, then convert canvas to object space before writing the underlying source-corner parameter values.
6. Set `forceUpdate = true` after state changes so Motion redraws and the filter re-renders when needed.

This matches Apple guidance and the available production binary evidence better than drawing the overlay as if it were just part of the filtered image.
The stale-instance risk remains: when the existing `.motn` filter instance does not emit `quad-osc-init`/`draw-enter`, add a fresh Quad filter instance after rebuilding and relaunching the wrapper/XPC.

## Repeatable Verification Notes

1. Rebuild the wrapper app and kill stale AnyUpright wrapper/XPC processes before retesting in Motion.
2. Prefer a fresh `AnyUpright Quad Manual` instance after changing the `Info.plist` or OSC class shape; old `.motn` instances can cache stale plug-in identity or parameter surfaces.
3. In Motion, verify `Mode = Source Quad`, `Show Corner Adjuster = on`, and the host `Publish OSC` checkbox is on.
4. With the adjuster visible, drag a visible corner handle and confirm the hidden matching `Top/Bottom Left/Right X/Y px` parameter changes. Runtime file logging is intentionally not kept in production code.
5. Toggle `Show Corner Adjuster` off and confirm the overlay disappears while the saved source quad is applied to the output.

## 2026-06-06 Validation Result

- Rebuilt `Wrapper Application`, relaunched the AnyUpright wrapper/XPC service, selected a fresh enough `AnyUpright Quad Manual 1` instance in Motion, and confirmed:
  - `Mode = Source Quad`
  - `Show Corner Adjuster = on`
  - Motion host `Publish OSC = on`
- Motion instantiated `AnyUprightQuadManualOSCPlugIn`, called `drawingCoordinates`, `hitTestOSC`, and `drawOSC`.
- The renderer Y-axis fix was confirmed in runtime logs: the default top-left handle mapped from canvas `(659.1,719.2)` to surface pixel near `(167.0,759.6)`, matching the visible top-left handle location. Before the fix, the same point rendered near `(167.0,84.4)`.
- Dragging the visible top-left handle in Motion produced the expected callback chain:
  - hit-test matched `part=1`
  - `mouseDown` and `mouseDragged` fired
  - `Top Left X/Y px` parameters changed to non-zero values
  - subsequent draws moved the same handle to the dragged surface coordinate
- One remaining edge case was found and fixed during cleanup: Motion can call `hitTestOSC` before the first `drawOSC`, while `lastSurfaceSize` is still the initial `1x1` fallback. That caused one early hit-test to map event coordinates to extremely large canvas coordinates. `eventMapper` now returns `nil` until a real surface size has been cached, so pre-draw hit-tests fall back to host-provided canvas coordinates instead of applying the invalid `1x1` scale.
- Temporary `/tmp/AnyUprightQuadOSC.log` file logging and noisy `NSLog` statements were removed after validation. Re-add targeted logging only if another host-level OSC issue appears.

Current status: the Source Quad OSC overlay is no longer just a static visual overlay; it follows the Motion canvas coordinate frame, hit-tests the visible handles, and writes persistent source-corner parameters during drag.

## 2026-06-06 Follow-Up Validation

- Public FxFactory Reverse Corner Pin page was rechecked as a product UX reference. The page describes the effect as removing perspective by stretching a four-pin perspective area into a rectangle; pins can be keyframed. This matches the current `Source Quad` direction, excluding Reverse Corner Pin's extra flip/mirror stretch mode for now.
- Rebuilt `Wrapper Application` with the default DerivedData path, relaunched the AnyUpright wrapper/XPC service, and checked Motion's current `AnyUpright.motn` document.
- Motion state for the selected fresh instance:
  - `AnyUpright Quad Manual 1`
  - `Mode = Source Quad`
  - `Show Corner Adjuster = on`
  - `Publish OSC = on`
- With `Show Corner Adjuster = on`, the central 80% source quad overlay was visible: outside area dimmed, selected quad stayed brighter, and the image was not newly warped by the current instance.
- Temporarily disabling the older stacked `AnyUpright Quad Manual` instance avoided confusion from two Source Quad filters in the same document.
- Toggling `Show Corner Adjuster` off on `AnyUpright Quad Manual 1` hid the overlay and applied the selected source quad to the output frame, confirming the source-quad-to-full-frame homography direction in Motion.
- The Motion document was not saved during this validation; inspector toggles were used only as a runtime check.

## 2026-06-06 Reverse Corner Pin Mirror Increment

- FxFactory's public Reverse Corner Pin page says the pinned area can also be flipped or mirrored while preserving perspective, which is a distinct product capability beyond the existing `Stretch to Frame` flow.
- Chosen implementation path: keep the existing Source Quad handles and hidden source-corner float parameters, add a `Stretch Mode` popup, and implement mirror modes in the shared Metal warp renderer. This avoids reworking OSC, because the same four pins define both stretch and mirror behavior.
- `Stretch to Frame` remains the default and preserves the current behavior: when `Show Corner Adjuster` is off, the selected source quad maps to the full output frame.
- `Mirror Horizontal` / `Mirror Vertical` are Source Quad-only render modes. The shader tests whether the output pixel is inside the selected source quadrilateral projected into output space; inside pixels sample the mirrored source quad, while outside pixels sample the original image through the identity output-to-source matrix.
- Dead end avoided: do not implement mirror by swapping full-output-frame corners in the existing source-quad homography. That mirrors the entire output mapping and does not preserve the original image outside the pinned area. The correct path is `selected quad -> rectangular coordinates -> mirror -> selected quad`, with a shader-side inside-quad mask/fallback.
- Metal shared headers must not include `<stdint.h>`; the Metal compiler rejects the SDK's `stdint.h` include chain. Use plain `int` fields in shared shader structs when a 32-bit mode flag is enough.
- `tools/render-warp-previews.swift` uses `@main` and depends on geometry symbols, so run it with `xcrun swiftc -parse-as-library tools/render-warp-previews.swift AnyUpright/Plugin/AnyUprightGeometry.swift -o /tmp/AnyUprightRenderWarpPreviews && /tmp/AnyUprightRenderWarpPreviews ...`. Running it with `swift tools/render-warp-previews.swift AnyUpright/Plugin/AnyUprightGeometry.swift ...` treats the geometry file as a program argument, not as a compiled source file.
- Current automated coverage verifies the matrix semantics for horizontal and vertical mirror modes and generates a CPU mirror-patch preview at `.agent-work/warp-previews/quad-source-mirror-horizontal-preview.png`, but host-app visual validation in Motion/FCP is still needed after rebuilding.

## 2026-06-06 Cleanup Validation

- Temporary `/tmp/AnyUprightQuadOSC.log` logging, filter-state logging, callback logging, and high-contrast OSC debug styling were removed from the source after the callback/drag path had been validated.
- The production Quad Source OSC style now uses the normal blue handles, white outline, and black outside dim at alpha `0.30`, matching the intended 70% outside brightness.
- Automated checks passed after cleanup:
  - `swift tools/audit-feature-surface.swift`
  - `swift tools/validate-fxplug-manifest.swift`
  - `xcrun swiftc AnyUprightTests/AnyUprightGeometryTests.swift AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightUprightCandidates.swift AnyUpright/Plugin/AnyUprightLineDetection.swift -o /tmp/AnyUprightGeometryTests && /tmp/AnyUprightGeometryTests`
  - `xcrun swiftc -parse-as-library tools/render-warp-previews.swift AnyUpright/Plugin/AnyUprightGeometry.swift -o /tmp/AnyUprightRenderWarpPreviews && /tmp/AnyUprightRenderWarpPreviews .agent-work/test-assets .agent-work/warp-previews`
  - `git diff --check`
  - `xcodebuild -project AnyUpright.xcodeproj -scheme "Wrapper Application" -configuration Debug -derivedDataPath /Users/ibobby/Library/Developer/Xcode/DerivedData/AnyUpright-fmxlkbxylbewbfgffirfqheenyke build`
- Motion screenshot validation after the cleanup build showed the selected `AnyUpright Quad Manual 3` Source Quad overlay following the Motion canvas/object frame, with outside dimming and four blue corner handles visible. The selected instance had `Mode = Source Quad`, `Stretch Mode = Mirror Horizontal`, `Show Corner Adjuster = on`, and `Publish OSC = on`.
- Computer Use could read the renamed Motion app (`Motion Creator Studio.app`) but did not keep an active interaction session for key or drag actions, so the cleanup pass did not re-run a live drag. The live drag/writeback evidence remains the earlier 2026-06-06 Motion validation where `hitTestOSC`, `mouseDown`, and `mouseDragged` fired and the hidden corner pixel offsets changed.

## 2026-06-06 CGEvent Drag Probe

- Computer Use still could not hold an active interaction session for `Motion Creator Studio.app`, but AppleScript/System Events could activate Motion and send `Escape`, which closed the stuck inspector parameter menu.
- `screencapture` plus a small image scan was enough to locate the four blue OSC handles in the current screenshot. Before the probe, the selected handle components were near:
  - top-left `(1474, 329)-(1503, 358)`
  - top-right `(2810, 329)-(2839, 358)`
  - bottom-left `(1474, 1005)-(1503, 1034)`
  - bottom-right `(2810, 1005)-(2839, 1031)`
- A short CoreGraphics mouse-event probe dragged the visible top-right handle from approximately screenshot pixel `(2824,344)` to `(2776,388)` by posting a left mouse down, a sequence of left-drag events, and a left mouse up.
- Result: Motion accepted the drag. With `Show Corner Adjuster = on`, the room image was not stretched into the full frame; instead, the source quadrilateral boundary moved in the canvas. That proves the edit-mode behavior is currently wired to move the source quad rather than applying the render warp live.
- After the probe, a `Cmd-Z` was sent through System Events to avoid intentionally leaving the Motion document modified. The Motion document was not saved during this validation.
- Limitation: this low-level probe proves visible drag behavior but is less precise than the earlier `/tmp/AnyUprightQuadOSC.log` callback validation. It does not directly expose the hidden float parameter values after cleanup, because the source-corner groups are intentionally hidden in `Source Quad` mode. If parameter-level evidence is needed again, temporarily re-add narrowly scoped logging or expose a debug-only inspector readout, then remove it before finishing.

## 2026-06-06 Motion Mirror Apply Probe

- With `AnyUpright Quad Manual 3` selected, `Mode = Source Quad`, `Stretch Mode = Mirror Horizontal`, `Show Corner Adjuster = on`, and `Publish OSC = on`, a low-level click probe toggled `Show Corner Adjuster` off.
- Result: the onscreen adjuster disappeared and the renderer applied the selected source quad as a mirrored patch over the original frame. The grid and source image outside the selected quadrilateral stayed visible/unchanged, which confirms the shader-side `WarpSelectionOverOriginal` path rather than a full-frame mirror.
- The same checkbox was clicked again after the screenshot probe to restore edit mode. The Motion document was not saved.
- This is the current strongest host-app evidence for the Reverse Corner Pin mirror behavior: edit mode moves/stores pins without warping; apply mode hides the handles and composites the mirrored selected quadrilateral over the original shot.

## 2026-06-06 Motion Mirror Vertical Probe

- Restored Motion selection from `IMG_0850` to `AnyUpright Quad Manual 3` by selecting the expanded layer-list row with keyboard navigation. Direct Computer Use click calls continued to report an inactive session even immediately after `get_app_state`, so low-level CGEvent clicks plus accessibility readback were used instead.
- Changed `Stretch Mode` from `Mirror Horizontal` to `Mirror Vertical` after calibrating the popup menu with `screencapture` and image analysis. The successful state was confirmed through Motion accessibility: `Mode = Source Quad`, `Stretch Mode = Mirror Vertical`, `Show Corner Adjuster = on`, and `Publish OSC = on`.
- Toggled `Show Corner Adjuster` off and captured `/tmp/anyupright-mirror-vertical-applied.png`. In that applied state, the blue OSC handles disappeared and the selected area rendered as the vertically mirrored patch over the original shot/grid, matching the same shader-side `WarpSelectionOverOriginal` path as horizontal mirror.
- Toggled `Show Corner Adjuster` back on after the probe and confirmed Motion accessibility again reported `Show Corner Adjuster = 1`. The Motion document was not saved.
- Tooling note: do not trust rough inspector coordinates for this Motion layout. The successful `Stretch Mode` popup hit was around logical `(260, 348)`, and the successful `Mirror Vertical` menu item was around logical `(255, 372)` on a `2992 x 1934` screenshot. The successful `Show Corner Adjuster` checkbox hit was around logical `(283, 371)`.
