# Quad Host Validation Notes

Last updated: 2026-06-10 15:47 MDT
Reference commit: 11aa3148242f9743c8c48903739c604f84dd2e66
Observed host versions: macOS 26.5, Motion Studio 6.2, Final Cut Pro 12.2

This note records reusable host-state validation practices and host pitfalls found while debugging four-corner FxPlug controls. It does not record product features or implementation choices. Project-specific choices live outside `engineering-notes`; in this repository they are recorded in `../quad-implementation-notes.md`.

For coordinate bugs, pair this host-state checklist with `quad-coordinate-layer-contract.md`. Many apparent math failures were stale-host or missing-OSC-publication failures.

## Host Validation Rules

- After changing plugin registration, template publication, OSC class shape, or parameter surface, restart Motion/Final Cut or delete and re-add the effect.
- If PlugInKit identity looks stale, quit host apps, kill stale wrapper/XPC processes, rebuild/register the intended wrapper, and re-add the effect.
- Before judging a Motion/FCP rendering or OSC fix, verify there is exactly one PlugInKit entry for the plug-in bundle ID and that its path is the intended build:

```bash
pluginkit -m -ADv -i AnyUpright-XPC-Service
```

- If multiple entries with the same bundle ID exist, remove stale ones with `pluginkit -r /path/to/AnyUpright.app/Contents/PlugIns/AnyUpright\ XPC\ Service.pluginkit`, unregister stale wrappers with `lsregister -u /path/to/AnyUpright.app`, then register the intended wrapper.
- Avoid testing an old already-open effect instance after changing template state.
- Avoid stacking another effect instance over the old one as a shortcut. It can create misleading black or duplicated viewer states.
- For Final Cut OSC dragging, confirm Motion template publication includes the built-in `Publish OSC` setting enabled.
- Keep debug logging behind an explicit temporary flag and remove the flag during normal use.

## Versioned Host Observations

These observations are not Apple API guarantees. They were measured on macOS 26.5 with Motion Studio 6.2 and Final Cut Pro 12.2:

- Existing Motion/Final Cut instances and already-applied effects could keep stale template, PlugInKit, or XPC state after code/template changes. Re-add the effect and restart/kill stale processes before changing coordinate math.
- Motion could keep using an older build when two PlugInKit entries shared `AnyUpright-XPC-Service`. In the observed case, `pluginkit -m -v` showed only the older Debug path, while `pluginkit -m -ADv -i AnyUpright-XPC-Service` revealed both Debug and Release entries. Removing the stale entry and restarting Motion made the XPC process launch from the intended Release path.
- Final Cut templates needed Motion's built-in `Publish OSC` parameter enabled for the FxPlug filter. Custom published parameters alone were not enough to prove OSC callbacks would dispatch.
- Accessibility showed `OZFxPlugOnscreenControl` even when that did not prove the plug-in's specific OSC callbacks were firing.
- Point-parameter writeback accepted during a Motion OSC drag did not persist in the tested path; float-parameter writeback did.

## Useful Evidence Sources

- Callback logs proving `drawingCoordinates`, `drawOSC`, `hitTestOSC`, `mouseDown`, and `mouseDragged` fired.
- Inspector/template state showing the relevant edit controls and host OSC publication are enabled.
- Exports compared against a no-plugin reference for render-path shifts.
- Geometry tests for deterministic coordinate conversion.
- Swift typecheck or build after FxPlug API selector changes.
- Wrapper build from one known DerivedData path.
- A log snapshot of callback width/height, destination image bounds, object/input bounds, raw event point, converted canvas point, chosen event interpretation, and active part before changing coordinate math.

## External References Checked

- Apple FxPlug OSC docs: separate OSC classes, `drawingCoordinates`, object/canvas conversion, and `forceUpdate` are the relevant conceptual model.
- FCP Cafe FxPlug notes: useful for host-side OSC caveats such as object-bounds caching and valid texture requirements.
- `overpolish/keyframeless`: strongest public source-code reference found for real FxPlug OSC drawing/hit testing/dragging/parameter writeback. Use only as behavior reference; do not copy code.
- Pixel Film Studios `PFSMaskV2`: installed closed-source binary confirms the same separate `FxOnScreenControl` plus `supportedPlugins` shape.
- CommandPost viewer overlays: useful UX reference for external overlays, but not evidence for FxPlug OSC callback behavior.

## Previous Wrong Attempts

- Treating accessibility `OZFxPlugOnscreenControl` as proof of plug-in callback dispatch was wrong. It only proves the host has an OSC accessibility element.
- Changing plist version strings, moving OSC methods onto the filter class, or making the OSC class inherit directly from `NSObject` did not make Motion dispatch callbacks.
- Using stale Motion/FCP instances after rebuilds repeatedly produced false negatives.
- Assuming the Publishing pane exposes OSC state was wrong in the observed Motion path. The Motion Filters inspector `Publish OSC` checkbox controlled whether Final Cut users got onscreen controls.
- Assuming FxPlug angle writeback uses degrees was wrong in the validated Motion path; angle parameter reads/writes behaved as radians. That note matters for angle-writing effects, but not directly for Quad.
