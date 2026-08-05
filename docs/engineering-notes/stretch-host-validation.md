# Stretch Host Validation Notes

Last updated: 2026-08-03 10:51 MDT
Reference commit: 3bb0d6d626d5382565f0158e6c21bdb93cd46f2e
Observed host versions: macOS 26.5.1 (25F80), Motion Creator Studio 6.2 (447036) and 6.3 (450156), Final Cut Pro 12.2, Xcode 26.5 (17F42) and 26.6 (17F113), FxPlug framework 4.3.4 (18567.3)

This note records reusable host-state validation practices and host pitfalls found while debugging four-corner FxPlug controls. It does not record product features or implementation choices. Project-specific choices live outside `engineering-notes`; in this repository they are recorded in `../stretch-implementation-notes.md`.

For coordinate bugs, pair this host-state checklist with `stretch-coordinate-layer-contract.md`. Many apparent math failures were stale-host or missing-OSC-publication failures.

## Host Validation Rules

- After changing plugin registration, template publication, OSC class shape, or parameter surface, restart Motion/Final Cut or delete and re-add the effect.
- After changing static effect properties, render pipeline state, Metal shader semantics, or matrix conventions, restart the host or delete and re-add the effect before judging render math.
- If PlugInKit identity looks stale, quit host apps, kill stale wrapper/XPC processes, rebuild/register the intended wrapper, and re-add the effect.
- Rebuilding the same registered wrapper path and killing the plug-in XPC can be enough for Motion to launch a new binary without restarting the host. This proves new diagnostic code is loaded, but it does not prove an already-applied effect instance has re-read static properties.
- Before judging a Motion/FCP rendering or OSC fix, verify there is exactly one PlugInKit entry for the configuration-specific plug-in bundle ID and that its path is the intended build:

```bash
pluginkit -m -ADv -i AnyUpright-XPC-Service-Debug
pluginkit -m -ADv -i AnyUpright-XPC-Service
```

- Current Debug and Release builds intentionally have separate bundle IDs and FxPlug UUID sets, so one entry for each is valid. If multiple entries with the same configuration-specific bundle ID exist, remove stale plug-ins with `pluginkit -r '/path/to/wrapper.app/Contents/PlugIns/AnyUpright XPC Service.pluginkit'`, unregister the matching wrapper with `lsregister -u '/path/to/wrapper.app'`, then register the intended wrapper. Debug wrappers are named `AnyUpright (Debug).app`; Release wrappers are named `AnyUpright.app`.
- Avoid testing an old already-open effect instance after changing template state.
- Avoid stacking another effect instance over the old one as a shortcut. It can create misleading black or duplicated viewer states.
- For Final Cut OSC dragging, confirm Motion template publication includes the built-in `Publish OSC` setting enabled.
- Keep debug logging behind an explicit temporary flag and remove the flag during normal use.

### Build Identity Is A Four-Part Assertion

“已构建”不等于“宿主正在运行该构建”。在接受截图、交互或日志为修复证据前，同时验证：

1. PlugInKit/Launch Services 解析到唯一且预期的 wrapper/XPC 路径。
2. 该路径内嵌 XPC binary 的修改时间属于最新构建。
3. 当前运行的 XPC 进程启动时间晚于 binary 修改时间。
4. 本轮清空后的日志包含当前 build marker 或当前二进制独有字符串。

只满足其中一项不能证明 build identity。特别是重启 Motion 并不能纠正注册到另一个 Derived Data 目录的 wrapper。

公开项目 Keyframeless 的 [`CONTRIBUTING.md` 31-57](https://github.com/overpolish/keyframeless/blob/60aa96bd174074c0d5cc9649d38db417c13f2a58/CONTRIBUTING.md#L31-L57) 独立记录了相同类别的 Launch Services/PlugInKit stale registration：磁盘上仍存在的多个构建可共享 bundle ID，宿主可能继续选择旧路径。该来源使用 PolyForm Noncommercial 许可，仅作为诊断证据和流程参考。

## Versioned Host Observations

These observations are not Apple API guarantees. They were measured on macOS 26.5 with Motion Studio 6.2 and Final Cut Pro 12.2:

- Existing Motion/Final Cut instances and already-applied effects could keep stale template, PlugInKit, or XPC state after code/template changes. Re-add the effect and restart/kill stale processes before changing coordinate math.
- Motion could keep using an older build when two PlugInKit entries shared `AnyUpright-XPC-Service`. In the observed case, `pluginkit -m -v` showed only the older Debug path, while `pluginkit -m -ADv -i AnyUpright-XPC-Service` revealed both Debug and Release entries. Removing the stale entry and restarting Motion made the XPC process launch from the intended Release path.
- Motion could keep rendering with an old effect instance after shader or render-matrix changes. Deleting and re-adding the filter, or restarting Motion when re-add is not enough, was required before visual validation matched the freshly built code.
- Motion could launch a newly rebuilt XPC from the same registered path after the stale XPC process was killed, while an already-applied filter instance still behaved as if an old static property value was cached. In the observed path, the new binary emitted render logs, but the existing instance still received partial destination tiles after the plug-in code had changed its full-buffer property. Deleting and re-adding the filter refreshed that instance state.
- Motion 6.3 defaults-window debugging exposed a second stale-build signature: screenshots appeared to prove that the current Auto Layout still clipped at several widths, while the running XPC binary contained earlier manual-layout log strings and predated the newly built binary in a different Derived Data directory. Rebuilding the registered canonical path and comparing process/binary timestamps changed the runtime marker. The old screenshots remain valid evidence for the old implementation only.
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
- Process path and timestamp for the running XPC service after the host has reopened the document or re-added the effect.
- Binary-string or version-marker evidence from the running build path when checking whether a new XPC binary is actually loaded.
- A log snapshot of callback width/height, destination image bounds, object/input bounds, raw event point, converted canvas point, chosen event interpretation, and active part before changing coordinate math.

## External References Checked

- Apple FxPlug OSC docs: separate OSC classes, `drawingCoordinates`, object/canvas conversion, and `forceUpdate` are the relevant conceptual model.
- FCP Cafe FxPlug notes: useful for host-side OSC caveats such as object-bounds caching and valid texture requirements.
- `overpolish/keyframeless`: strongest public source-code reference found for real FxPlug OSC drawing/hit testing/dragging/parameter writeback. Use only as behavior reference; do not copy code.
- `overpolish/keyframeless` commit `60aa96bd174074c0d5cc9649d38db417c13f2a58`: its remote-window implementation documents the non-zero callback-parent origin workaround, while its `CONTRIBUTING.md` documents stale wrapper/extension registration. The current source is PolyForm Noncommercial 1.0.0; use it as evidence, not code to copy into a commercial plug-in.
- Pixel Film Studios `PFSMaskV2`: installed closed-source binary confirms the same separate `FxOnScreenControl` plus `supportedPlugins` shape.
- CommandPost viewer overlays: useful UX reference for external overlays, but not evidence for FxPlug OSC callback behavior.

## Previous Wrong Attempts

- Treating accessibility `OZFxPlugOnscreenControl` as proof of plug-in callback dispatch was wrong. It only proves the host has an OSC accessibility element.
- Changing plist version strings, moving OSC methods onto the filter class, or making the OSC class inherit directly from `NSObject` did not make Motion dispatch callbacks.
- Using stale Motion/FCP instances after rebuilds repeatedly produced false negatives.
- Judging a render-matrix or shader fix while Motion still held the previous effect instance was wrong. A stale host can make correct code look mathematically wrong.
- Treating "new XPC binary is running" as proof that static effect properties have refreshed was wrong. Binary reload and effect-instance/property refresh are separate host-state layers.
- Treating a successful Xcode build in any Derived Data directory as evidence that Motion loaded it was wrong. Registration path, binary mtime, process start time, and current marker must agree.
- Assuming the Publishing pane exposes OSC state was wrong in the observed Motion path. The Motion Filters inspector `Publish OSC` checkbox controlled whether Final Cut users got onscreen controls.
- Assuming FxPlug angle writeback uses degrees was wrong in the validated Motion path; angle parameter reads/writes behaved as radians. That note matters for angle-writing effects, but not directly for Stretch.
