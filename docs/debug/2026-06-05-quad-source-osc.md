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
- 2026-06-06 01:17 local fix: `AnyUprightOSCOverlayRenderer.localPixel` no longer flips Y for `.pixels` coordinates. In the Metal overlay path, the expected default top-left handle maps to bottom-origin render-target pixel coordinates around `(167.0,759.6)` for the captured `1670 x 844` surface. Do not reuse that value as a Motion mouse-event coordinate; later 2026-06-06 testing showed OSC mouse events are top-origin surface-local coordinates.
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

## 2026-06-06 Source Quad Event Y-Axis Fix

- User report: the visible Source Quad handles and the final `Stretch to Frame` result did not correspond, and dragging was vertically inverted. Putting the mouse on the visible top-left handle dragged the bottom-left handle; whole-quad drags also moved vertically opposite to the pointer.
- Root cause: the overlay renderer and the mouse-event mapper were using different implicit Y origins, but `AUCanvasSurfaceMapper` treated them as the same. The Metal overlay path uses bottom-origin local pixels after converting canvas coordinates into the render target. Motion mouse events delivered to the OSC callbacks are surface-local/top-origin. Mapping event Y with `minY + y / height` therefore turned a visual top event into the bottom canvas/object point.
- Fix: keep the existing overlay renderer coordinate path unchanged, and invert only `AUCanvasSurfaceMapper`'s event conversion:
  - `eventPoint(fromCanvasPoint:)` now maps visual/canvas top to small event Y.
  - `canvasPoint(fromEventPoint:)` now maps small event Y back to the canvas top (`maxY` side).
- Regression coverage:
  - `testCanvasSurfaceMapperConvertsFxPlugOSCEvents` now asserts that the visual top-left handle converts to event Y `84.4`, while bottom-left converts to `759.6` for the known Motion surface/frame sample.
  - `testQuadSourceObjectSpacePixelsMatchFxPlugOSCEvents` now also asserts that a visible Source Quad object-space drag maps to the Y-flipped source-image sample point used by the final homography.
- Automated checks passed after the fix:
  - `swift tools/audit-feature-surface.swift`
  - `swift tools/validate-fxplug-manifest.swift`
  - `xcrun swiftc AnyUprightTests/AnyUprightGeometryTests.swift AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightUprightCandidates.swift AnyUpright/Plugin/AnyUprightLineDetection.swift -o /tmp/AnyUprightGeometryTests && /tmp/AnyUprightGeometryTests`
  - `xcrun swiftc -parse-as-library tools/render-warp-previews.swift AnyUpright/Plugin/AnyUprightGeometry.swift -o /tmp/AnyUprightRenderWarpPreviews && /tmp/AnyUprightRenderWarpPreviews .agent-work/test-assets .agent-work/warp-previews`
  - `git diff --check`
  - `xcodebuild -project AnyUpright.xcodeproj -scheme "Wrapper Application" -configuration Debug -derivedDataPath /Users/ibobby/Library/Developer/Xcode/DerivedData/AnyUpright-fmxlkbxylbewbfgffirfqheenyke build`
- Host-app validation status: Motion loaded the rebuilt `AnyUpright XPC Service` from the expected DerivedData path, and the selected filter had `Mode = Source Quad`, `Stretch Mode = Stretch to Frame`, `Show Corner Adjuster = on`, and `Publish OSC = on`. The active Motion viewer then showed a black frame, so this pass did not perform a reliable live drag screenshot comparison. Re-test in Motion with a visible source frame before treating the manual drag symptom as host-verified.

## 2026-06-06 Source Quad Stretch Mismatch Follow-Up

- User report after the Y-axis fix: dragging was closer, but the applied `Stretch to Frame` image still did not exactly match the selected four-handle region.
- Additional evidence from the Motion screenshot: the project had two visible `IMG_0850` rows. When validating `Stretch to Frame`, hide or disable duplicate underlying media layers; otherwise the stretched result can visually blend with the original layer underneath and look like a wrong warp.
- Code-level risk found: Source Quad handles were persisted primarily as pixel offsets derived from the current OSC object size. FxPlug render-time `sourceSize` can differ from the OSC object size because of proxy/render scale, still-image/video metadata, or host surface sizing. That makes the visible handle region and render-time source quadrilateral diverge even when the corner order is correct.
- Fix: Source Quad OSC drags now persist corner movement as hidden percentage offsets relative to the normalized source-quad base, and clear the matching pixel offsets. Whole-quad Source Quad drags also write percentage deltas and clear pixel offsets. `Output Corners` continues to use pixel offsets because that mode is explicitly output-frame pixel manipulation.
- Regression coverage: `testQuadSourceObjectDragPreservesCentralBase` and `testQuadSourceObjectSpacePixelsMatchFxPlugOSCEvents` now verify percent-offset Source Quad writes and that the final source quad samples the Y-flipped image point matching the visible handle.
- Automated checks passed:
  - `swift tools/audit-feature-surface.swift`
  - `swift tools/validate-fxplug-manifest.swift`
  - `xcrun swiftc AnyUprightTests/AnyUprightGeometryTests.swift AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightUprightCandidates.swift AnyUpright/Plugin/AnyUprightLineDetection.swift -o /tmp/AnyUprightGeometryTests && /tmp/AnyUprightGeometryTests`
  - `xcrun swiftc -parse-as-library tools/render-warp-previews.swift AnyUpright/Plugin/AnyUprightGeometry.swift -o /tmp/AnyUprightRenderWarpPreviews && /tmp/AnyUprightRenderWarpPreviews .agent-work/test-assets .agent-work/warp-previews`
  - `git diff --check`
  - `xcodebuild -project AnyUpright.xcodeproj -scheme "Wrapper Application" -configuration Debug -derivedDataPath /Users/ibobby/Library/Developer/Xcode/DerivedData/AnyUpright-fmxlkbxylbewbfgffirfqheenyke build`

## 2026-06-06 Product Definition Correction

- User report: the drag/edit area should follow the video image, not the Motion/FCP canvas; the current canvas OSC overlay can detach from the video image and is not visible in Final Cut.
- Product decision: Source Quad edit-mode visuals now belong to the filter render output. `Show Corner Adjuster = on` renders the original image unchanged, dims pixels outside the selected source quadrilateral to 70% brightness, draws the selected quadrilateral outline, and draws four handle markers directly into the output frame.
- The Quad `FxOnScreenControl` remains the interactive input path where the host supports OSC, but it clears its own host overlay surface instead of drawing a second visible canvas-space overlay. This prevents Motion from showing two visual layers with different coordinate owners.
- The same `quadSelectionToOutputRectMatrix` is used by the edit preview to identify the selected source quadrilateral and by mirror modes to identify the selected patch. Turning `Show Corner Adjuster` off still uses `quadOutputToSourceMatrix(..., showCornerAdjuster: false)` to map the saved source quad to the full output frame.
- Consequence for FCP: the visual adjuster should be visible because it is now part of the effect output. Mouse dragging still depends on host OSC support; if FCP does not dispatch OSC interactions, the visible layer can still be used as a preview but interaction will need a future FCP-compatible input strategy.
- Automated checks passed after the render-output overlay change:
  - `xcrun swiftc AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift AnyUpright/Plugin/AnyUprightUprightCandidates.swift AnyUprightTests/AnyUprightGeometryTests.swift -o /tmp/AnyUprightGeometryTests && /tmp/AnyUprightGeometryTests`
  - `xcrun swiftc tools/validate-fxplug-manifest.swift -o /tmp/AnyUprightValidateManifest && /tmp/AnyUprightValidateManifest .`
  - `xcrun swiftc tools/audit-feature-surface.swift -o /tmp/AnyUprightAuditFeatureSurface && /tmp/AnyUprightAuditFeatureSurface .`
  - `xcrun swiftc -parse-as-library tools/render-warp-previews.swift AnyUpright/Plugin/AnyUprightGeometry.swift -o /tmp/AnyUprightRenderWarpPreviews && /tmp/AnyUprightRenderWarpPreviews .agent-work/test-assets .agent-work/warp-previews`
  - `xcrun swiftc tools/validate-warp-previews.swift -o /tmp/AnyUprightValidateWarpPreviews && /tmp/AnyUprightValidateWarpPreviews .agent-work/warp-previews`
  - `SDK=$(xcrun --sdk macosx --show-sdk-path) && xcrun swiftc -typecheck AnyUpright/Plugin/*.swift -sdk "$SDK" -F /Library/Developer/SDKs/FxPlug.sdk/Library/Frameworks -F /Library/Developer/Frameworks -I AnyUpright/Plugin -import-objc-header "AnyUpright/Plugin/XPC Service-Bridging-Header.h"`
  - `git diff --check`
  - `xcodebuild -project AnyUpright.xcodeproj -scheme "Wrapper Application" -configuration Debug -derivedDataPath /Users/ibobby/Library/Developer/Xcode/DerivedData/AnyUpright-fmxlkbxylbewbfgffirfqheenyke build`
- Motion validation: `Quad.moef` showed the Source Quad dimming, outline, and blue handles with `Show Corner Adjuster = on` and Motion's host `Publish OSC = off`. This confirms the visible edit layer no longer depends on the host OSC overlay surface.

## 2026-06-07 FCP Drag Follow-Up

- User report: Final Cut still showed the Source Quad handles but the points could not be dragged.
- Open-source comparison: `overpolish/keyframeless` remains the closest public FxPlug reference for real Final Cut drag behavior. Its OSC classes register through a separate `FxOnScreenControl` plist entry with `supportedPlugins`, draw real host OSC controls, treat incoming mouse positions as canvas coordinates, and write parameters from `mouseDragged...` with `forceUpdate = YES`.
- Root-cause hypothesis from the comparison: AnyUpright had moved all visible Source Quad handles into the filter output and cleared the Quad OSC surface. That satisfied the product requirement that the overlay follow the video image, but it also removed the visible host OSC geometry that Final Cut may require for reliable hit testing. Additionally, the Motion-specific surface-local event mapper was applied whenever an OSC surface size existed; Final Cut may deliver raw canvas coordinates instead, matching Keyframeless and Apple examples.
- Code change: Quad Source now restores a low-alpha host OSC hit layer while keeping the primary visible edit overlay in the filter output. The host OSC layer is only for interaction and should visually sit under the output-rendered handles.
- Code change: Quad OSC hit testing now considers both raw canvas coordinates and Motion-style surface-local coordinates. `mouseDown` stores the coordinate mode for that drag, and `mouseDragged` uses the stored mode so the drag path cannot jump between coordinate systems.
- Code change: `mouseDown` now uses the host-provided nonzero `activePart` when available, otherwise falls back to the plug-in's duplicate hit-test result. This avoids rejecting a valid Final Cut drag if its `activePart` dispatch is zero or differs slightly from the plug-in's local hit-test calculation.
- Regression coverage: `testCanvasSurfaceMapperKeepsRawCanvasCandidatesDistinct` documents that Final Cut-style raw canvas events and Motion-style surface-local events are distinct and should both remain supported. `testOSCDragPartFallsBackToLocalHitWhenHostPartIsNone` covers the Final Cut risk case where the host passes no active part but the plug-in locally hit-tests the quad body.
- Validation completed in code:
  - `xcrun swiftc -module-cache-path /tmp/AnyUprightModuleCache AnyUpright/Plugin/AnyUprightGeometry.swift AnyUpright/Plugin/AnyUprightLineDetection.swift AnyUpright/Plugin/AnyUprightUprightCandidates.swift AnyUprightTests/AnyUprightGeometryTests.swift -o /tmp/AnyUprightGeometryTests`
  - `/tmp/AnyUprightGeometryTests`
  - `SDK=$(xcrun --sdk macosx --show-sdk-path) && xcrun swiftc -module-cache-path /tmp/AnyUprightModuleCache -typecheck AnyUpright/Plugin/*.swift -sdk "$SDK" -F /Library/Developer/SDKs/FxPlug.sdk/Library/Frameworks -F /Library/Developer/Frameworks -I AnyUpright/Plugin -import-objc-header "AnyUpright/Plugin/XPC Service-Bridging-Header.h"`
  - `/tmp/AnyUprightValidateManifest .`
  - `/tmp/AnyUprightAuditFeatureSurface .`
  - `xcodebuild -project AnyUpright.xcodeproj -scheme "Wrapper Application" -configuration Debug -derivedDataPath /Users/ibobby/Library/Developer/Xcode/DerivedData/AnyUpright-fmxlkbxylbewbfgffirfqheenyke build`
- Final Cut validation status: Final Cut was already open with an existing `Quad` effect instance. The viewer showed `Mode = Source Quad`, `Show Corner Adjuster = on`, and four output-rendered handles. Computer Use could read the visible window but direct click/drag actions against `com.apple.FinalCutApp` returned `noWindowsAvailable`; `screencapture` also failed in this sandbox with `could not create image from display`. A temporary `/tmp/AnyUprightQuadOSC.log` diagnostic build produced no log for the already-open Final Cut instance, which means that instance had not called the newly built OSC code. Re-test after restarting Final Cut or adding a fresh Quad effect instance from the newly registered wrapper.

## 2026-06-07 Template Publish OSC Finding

- Apple Motion template documentation says that, for an FxPlug filter with onscreen controls, Final Cut users can use the filter's onscreen controls only if Motion's Filters inspector has `Publish OSC` enabled. The Publishing pane does not show this setting.
- Local template comparison found a concrete mismatch:
  - `~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/Quad/Quad.moef` contains only published targets for `Mode` (`198`) and `Show Corner Adjuster` (`199`).
  - The same file does not contain the current `Stretch Mode` parameter (`197`) and does not contain the built-in FxPlug `Publish OSC` parameter (`10005`).
  - Local Color Finale `.moef` templates contain `Input Points` (`10003`) followed by `Publish OSC` (`10005`) with `value="1"`.
- Updated hypothesis: the Final Cut effect template can render AnyUpright's filter output overlay, but cannot dispatch mouse drags to `AnyUprightQuadManualOSCPlugIn` until the template includes/enables `Publish OSC`. This is a template publication issue, not a homography issue.
- Code-side guard added during this pass: Final Cut-style raw canvas events and Motion-style surface-local events are both supported, and a drag keeps its chosen coordinate mode. In particular, raw canvas drags can move outside the object frame and must not switch to surface-local mapping mid-drag.
- Repo-local condensed notes for this pass live at `.agent-work/debug/2026-06-07-fcp-source-quad-drag.md`.

## 2026-06-07 Single Visible Source Quad Handles

- User validation after deleting and re-adding the Final Cut effect: Source Quad dragging and final transform are nearly correct. The remaining UX issue is visual duplication: Final Cut shows the image-space source quad and a second host OSC quad, and dragging the outside host handles controls the inner image-space quad.
- Cleanup: Quad OSC `drawOSC` now updates the host surface-size cache and clears the OSC drawable surface. It keeps `hitTestOSC`, `mouseDown`, and `mouseDragged` active, so the host interaction path remains available while the only visible handles are the image-space handles rendered by the filter output.
- Risk to watch: if Final Cut requires visible OSC pixels for hit dispatch rather than only an active OSC object plus hit-test return values, this could reduce drag reliability. Re-test by deleting/re-adding the effect after rebuilding.

## 2026-06-07 Canvas Y Direction Retest

- Failed attempt: changing `AUCanvasSurfaceMapper` to use the same Y direction for canvas and surface-local event coordinates did not fix Final Cut dragging. User validation showed clicking the visible top-left handle still changed the bottom-left handle, and dragging downward moved the handle upward.
- Conclusion: Final Cut's OSC mouse positions for this effect behave like top-origin surface-local coordinates. The mapper must flip Y when converting between surface-local events and canvas/object coordinates.
- Current behavior to preserve: `eventPoint(fromCanvasPoint:)` maps the visual top-left handle to a smaller event Y than the bottom-left handle, and `canvasPoint(fromEventPoint:)` maps that top-origin event back to the canvas top handle.

## 2026-06-07 Source Quad Raw Canvas Writeback

- User validation after the retest still showed the visible top-left Source Quad handle writing the bottom-left corner, and downward drags moving the stored handle upward.
- Failed follow-up attempt: adding a new y-flipped-canvas event candidate and making Source Quad hit-test prefer it broke Final Cut dragging; clicks no longer started a drag. Do not change the `hitTestOSC` candidate order just to repair Source Quad Y semantics.
- Root-cause refinement: the existing hit-test path is needed for host dispatch, but raw canvas Source Quad drags use the opposite Y semantic when writing hidden source-corner parameters.
- Fix direction: keep the original raw/mapped hit-test candidate order, then in Source Quad writeback only, flip object Y for raw-canvas drags and remap top/bottom corner or edge parts before calling `setCorner`/`translateCorners`.
- Scope: this changes Source Quad parameter writeback only. Output Corners keeps the existing coordinate behavior.

## 2026-06-07 Source Quad Hit-Test Follow-Up

- User report after `e2c7d46`: after dragging a Source Quad point once, the visible point moved, but a second drag had to start from the point's original location. Dragging the point's new visible location did nothing.
- Root cause: Source Quad edit visuals are rendered in the filter output as top-origin source-image coordinates, while the raw-canvas OSC hit-test was still comparing against the unflipped y-up object points. Parameter writeback moved the visible source quad, but the raw-canvas clickable handles stayed tied to the old invisible object-space positions.
- Fix: for `Source Quad` raw-canvas hit testing only, compare mouse events against vertically flipped object points so the hit handles follow the visible source quad. Keep mapped-surface hit testing on the existing object/canvas points, because that path is still needed for Motion-style surface-local events.
- Important constraint from the previous failed attempt: do not globally change event candidate order or introduce a separate y-flipped event candidate. The fix is local to the geometry used for raw-canvas handle/edge/body comparisons.
- Corner labels are not remapped in this pass. `topLeft` remains `topLeft`; only the raw-canvas object Y used for hit geometry and writeback is flipped. This avoids the earlier top/bottom mismatch where the visible top-left interaction controlled bottom-left storage.
- Regression coverage: `testQuadSourceRawCanvasHitPointsFollowVisibleSourceQuad` documents that unflipped object-space hit pixels would remain at the stale invisible top-left, while the flipped raw-canvas hit pixels match the moved visible Source Quad handle.
