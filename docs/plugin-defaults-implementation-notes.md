# Plugin Defaults Implementation Notes

Last updated: 2026-08-03 10:51 MDT
Reference commit: 3bb0d6d626d5382565f0158e6c21bdb93cd46f2e
Observed host versions: macOS 26.5.1 (25F80), Motion Creator Studio 6.3 (450156), Xcode 26.6 (17F113), FxPlug framework 4.3.4 (18567.3)

本文记录 AnyUpright 的产品级默认设置实现。可迁移的 FxPlug 远程窗口和 ViewBridge 规则见 `engineering-notes/fxplug-remote-window-hosting.md`；宿主构建身份核验见 `engineering-notes/stretch-host-validation.md`。

## Product Boundary

- Horizon、Inner Stretch 和 Upright 各自在 inspector 中提供 `Defaults...` 按钮。
- 三个滤镜共享远程窗口 presenter、表单辅助组件和强类型 store，但拥有独立 editor、设置类型和 plist。
- Outer Stretch 没有默认设置窗口。
- 保存的默认值只在注册一个新的滤镜实例时读取。已有实例继续由 FxPlug 参数完整持久化；render、OSC 和 analysis 不读取默认值 plist。

## Stored Settings

目录：`~/Library/Application Support/AnyUpright/Defaults/`

| Filter | File | Settings | Factory defaults |
| --- | --- | --- | --- |
| Horizon | `Horizon.plist` | `Fill Frame` | Off |
| Inner Stretch | `InnerStretch.plist` | `Ratio` | None |
| Upright | `Upright.plist` | `Direction`, `Mode`, `Auto Crop` | Vertical, Auto, On |

每个 plist 使用独立 `Codable` 类型并携带 `schemaVersion`。文件不存在、解码失败或 schema 不匹配时 fail closed 到 factory defaults。保存使用 XML property list 和原子文件替换。

## Editing State

每次窗口开始编辑时，在内存中捕获三份强类型状态：

- `factoryDefaults`：编译期产品默认值。
- `saved`：窗口打开时从对应 plist 读取的值。
- `current`：控件当前显示的值，初始等于 `saved`。

按钮规则：

- `Restore Factory Defaults` 仅当 `current != factoryDefaults` 时启用。
- `Save` 仅当 `current != saved` 时启用。
- Restore 只把 `current` 和表单改成 factory defaults，不写磁盘。
- Save 是唯一 plist 写入操作；原子写入成功后才把 `saved` 更新为 `current`。
- Save 或 Restore 成功后不显示 `Saved`/`Restored` 文本，只通过禁用对应按钮反馈。
- 保存失败时保留错误提示，且不得推进 `saved` snapshot。

该状态机由 `AUPluginDefaultsEditingState` 和 `AUPluginDefaultsEditorSession` 负责，UI controller 只映射控件与状态，不自行推断脏状态。

## UI And Lifecycle Ownership

- `AnyUprightWarpEffect` 每实例强持有一个 `AUPluginDefaultsWindowPresenter`。
- 自定义按钮 selector 可以由 Motion 在后台线程调用。
- `presentPluginDefaults` 在原 FxPlug callback context 查询基础 `FxRemoteWindowAPI`，然后仅把 AppKit editor 创建和展示调度到主线程。
- presenter 在请求提交前设置 `requestPending`，忽略在途重复点击；已显示窗口则前置复用。
- callback parent 到达后，`AUPluginDefaultsRemoteWindowMount` 使用 `parentView.superview ?? parentView` 作为已验证 Motion 6.3 host，移除相同 root identifier 的旧内容，再四边约束新 root。
- presenter 强持有 view controller；对 host view 只保留弱引用，避免反向拥有宿主窗口。
- root 内部使用一个纵向布局：标题和说明、各滤镜表单、弹性 spacer、全宽 footer。

## Diagnostics

默认设置诊断当前写入 `/tmp/AnyUprightPluginDefaults.log`，同时发送到 `NSLog`。关键事件包括：

- effect init/deinit 与 Defaults selector 进入。
- callback 源线程和 API lookup 结果。
- request ID、pending/reuse 决策和 remote callback。
- callback parent、实际 host 和 root 的 frame/bounds/subview count。

日志 build marker 当前为 `defaults-diagnostics-v2`。进行 Motion 验证前应先轮转旧日志，并按 `AGENTS.md` 的 canonical Derived Data 流程确认正在运行的 XPC 二进制。

## Validation Surface

- `AnyUprightPluginDefaultsTests`：store round trip、坏 plist/schema fallback、三个设置类型、编辑状态的 Save/Restore 比较语义。
- `tools/audit-feature-surface.swift`：三个 Defaults 按钮和产品边界。
- Wrapper Application Debug build：插件编译、嵌入和注册路径。
- Motion：每个 editor 的单击打开、快速重复点击、窗口复用、控件布局、Save/Restore 启用状态和新实例默认值。
- Final Cut Pro：仍需确认远程窗口 view 层级、布局和新实例默认值。

## History And Remaining Gap

- 初始功能提交：`36a9ba47c9788a2d97f84ad706f0ee5eba53dac9`。
- 线程、状态、远程窗口挂载和 canonical build-identity 修复：`eeac20ca9c136eef2ca166cc77171b02bab965af`。
- 成功状态文本移除：`3bb0d6d626d5382565f0158e6c21bdb93cd46f2e`。
- 当前 canonical binary 日志确认三个 editor 都能得到 `480 x 260` 的 host，且 root 与 host 对齐。三种 editor 的最终 Motion 视觉确认和 Final Cut Pro 复测仍是未完成验收边界。
