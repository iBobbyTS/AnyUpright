# FxPlug Remote Window Hosting And Layout

Last updated: 2026-08-03 10:51 MDT
Reference commit: 3bb0d6d626d5382565f0158e6c21bdb93cd46f2e
Observed versions: macOS 26.5.1 (25F80), Motion Creator Studio 6.3 (450156), Xcode 26.6 (17F113), FxPlug framework and SDK 4.3.4 (18567.3)

本文记录 FxPlug 远程窗口中可迁移的宿主边界、线程边界和布局诊断方法。具体产品设置、plist、类名和本地日志路径不属于通用契约，见 `../plugin-defaults-implementation-notes.md`。

## Official API Baseline

Apple 的 [`FxRemoteWindowAPI`](https://developer.apple.com/documentation/professional_video_applications/fxremotewindowapi) 和本机 FxPlug 4.3.4 SDK 头文件说明：

- `remoteWindowOfSize:reply:` 请求一个具有目标 content size 的宿主窗口。
- reply 返回供插件添加自定义视图的 remote content view；失败时 view 为 `nil` 并提供错误。
- 每个插件实例只能拥有一个远程窗口。用户未关闭窗口时，后续请求返回同一个 parent view。
- [`FxRemoteWindowAPI_v2`](https://developer.apple.com/documentation/professional_video_applications/fxremotewindowapi_v2/remotewindow%28withminimumsize%3Amaximumsize%3Areply%3A%29) 只增加可调整窗口的最小和最大尺寸请求；固定尺寸窗口不需要 v2。

Apple 文档没有规定：

- FxPlug 自定义按钮 selector、API 查询或 reply block 的执行线程。
- callback parent view 与其 superview 的几何关系。
- callback parent view 是否就是 ViewBridge/XPC 的实际内容根视图。
- 插件能否安全地把 Auto Layout 约束跨过 callback view 边界连接到宿主拥有的其他视图。

因此，线程和视图层级都必须作为运行时边界验证，不能从方法签名推断。

## Versioned Motion Observations

以下只是在上述版本上的实测，不是 Apple 的跨版本保证：

1. Motion 从后台线程调用了自定义 Defaults selector。
2. 在 selector 的原始 FxPlug callback context 查询 `FxRemoteWindowAPI` 可以成功；把 API 查询整体移动到主队列后，同一插件实例曾返回 `nil`。
3. AppKit editor 构造必须在主线程进行。Apple 的 [Thread Safety Summary](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html) 明确要求只在主线程创建、销毁、移动和调整 `NSView`。
4. 固定请求 `480 x 260` 时，Motion 返回的 callback parent view 曾具有 `frame.origin = (129, 51)`、`bounds.origin = (0, 0)`，而它的 superview 是 `480 x 260`、origin 为零的实际 XPC 内容宿主。
5. 直接把内容当作 callback parent 的局部根视图时，窗口标题、表单和 footer 可分别表现出不同的水平基准；缩放窗口会出现右侧裁切、按钮移出可见区或首帧偏移。
6. 同一插件实例重复请求窗口时，宿主会复用窗口。并发或快速点击需要本地 pending gate，避免同时向宿主提交多个未完成请求。

## External Implementation Reference

公开项目 [overpolish/keyframeless](https://github.com/overpolish/keyframeless) 在提交 [`60aa96bd174074c0d5cc9649d38db417c13f2a58`](https://github.com/overpolish/keyframeless/commit/60aa96bd174074c0d5cc9649d38db417c13f2a58) 中提供了与上述 Motion 现象相同的独立实现证据：

- [`KKPlugin+CustomViews.m` 283-385](https://github.com/overpolish/keyframeless/blob/60aa96bd174074c0d5cc9649d38db417c13f2a58/KeyframelessKit/KeyframelessKit/Plugin/KKPlugin%2BCustomViews.m#L283-L385) 使用基础 `FxRemoteWindowAPI` 请求固定窗口。
- 代码注释记录 callback parent 在 superview 中有非零 origin，直接挂载会产生右侧裁切和首帧偏移。
- 它选择 `parentView.superview ?: parentView` 作为实际 host，按 identifier 删除旧内容，再把包装视图和内容四边约束到各自所有者。
- 该项目同样从系统 `/Library/Developer/SDKs/FxPlug.sdk` 构建，因此使用的是相同 FxPlug API surface；仓库本身没有固定 SDK patch version，不能据此证明运行时版本完全相同。

许可边界：该提交使用 [PolyForm Noncommercial 1.0.0](https://github.com/overpolish/keyframeless/blob/60aa96bd174074c0d5cc9649d38db417c13f2a58/LICENSE)。它只能作为宿主行为和设计模式的参考；商业项目不得直接复制其代码，除非另有适用许可。本文记录的是 API 边界和独立观察，不是源代码移植。

## Layer And Ownership Contract

将流程明确拆成四层：

1. **FxPlug callback context**
   - 接收自定义按钮 selector。
   - 立即获取 callback-context-sensitive 的宿主 API。
   - 不构造或修改 AppKit view。
2. **Main-thread presentation**
   - 创建 editor、view controller 和 AppKit controls。
   - 管理每实例 pending 状态和已显示窗口复用。
3. **Remote-window callback**
   - 检查 `parentView` 和 `error`。
   - 无论宿主当前在哪个线程回调，最终都在主线程挂载。
4. **Plugin-owned layout root**
   - 先确定实际 host：已验证的宿主可使用 `callbackParent.superview ?? callbackParent`；必须记录两层 geometry 以便验证。
   - 只在插件拥有的 root 内建立复杂 Auto Layout。
   - root 本身只做一件事：四边贴合实际 host。
   - 用稳定 identifier 删除旧 root，避免宿主复用窗口时叠加多个内容树。

不要让业务 editor 直接拥有 FxPlug API，也不要让持久化 store 持有窗口或宿主 view。窗口生命周期、表单状态和磁盘状态是三个不同所有者。

## Correct Fix Pattern

1. 固定尺寸内容使用基础 `FxRemoteWindowAPI`，不要无故要求 v2。
2. 在 FxPlug selector 的原始 callback context 取得 API 引用。
3. 将 AppKit 构造和 view attachment 调度到主线程。
4. 在提交请求前设置 pending；callback 的所有成功和失败路径都清除 pending。
5. 已存在可见窗口时前置并复用，不重复提交请求。
6. callback 后同时记录 parent 和 superview 的 frame、bounds、subview count 与线程。
7. 若宿主返回已知的非零-origin wrapper，则把插件 root 挂到实际 XPC host，并只约束 root 的四边。
8. root 内使用单一布局系统。对于顶部表单、底部按钮的窗口，可使用纵向 stack、弹性 spacer 和全宽 footer；不要混用手工 frame 和 Auto Layout。
9. footer 中可伸缩状态文本应具有低 horizontal compression resistance；操作按钮保持 required hugging/compression resistance。
10. 关闭或复用窗口时保留明确的 controller 所有权，避免 view tree 因弱引用提前释放。

## Diagnostic Checklist

- selector 是否进入，进入线程是什么。
- 宿主 API 在哪个线程和 callback context 查询，返回的具体协议对象是什么。
- 请求是否被 pending gate 接受、忽略或复用。
- reply 是否到达，`parentView` 和 `error` 是否互斥符合预期。
- callback parent 的 `frame`、`bounds`、`superview.frame`、`superview.bounds` 是否使用同一 origin。
- root 最终挂载到哪一层；root frame 是否与该 host bounds 一致。
- 同 identifier root 是否只有一个。
- 窗口宽度变化时，内容 root、表单和 footer 是否共享同一布局根。
- 当前日志是否来自正在运行的目标构建；先完成 `stretch-host-validation.md` 的 build-identity 核验，再相信截图或 geometry 日志。

## Remaining Evidence Gap

- Apple 没有公开说明 callback parent 非零 origin 或建议使用其 superview。因此 `superview ?? parentView` 是 Motion 6.3 和社区实现共同支持的经验性适配，不是正式 API 保证。
- 本次 canonical build 已通过日志确认 `hostIsSuperview=true` 且 root 与 host 都是 `480 x 260`；当前布局仍需要 Motion 对三种 editor 的最终视觉确认。不能把旧二进制的多宽度截图当作当前实现的验收结果。
- Final Cut Pro 没有在本轮复测；应验证它是否返回相同 ViewBridge 层级。

## Previous Wrong Attempts

- **在后台 callback 中直接初始化 editor。** Swift 在进入主线程闭包前先求值构造参数，导致 AppKit controls 在后台线程创建；表现为点击无窗口，多次点击后宿主崩溃。
- **把整个流程都移到主线程。** AppKit 线程正确了，但宿主 API 查询离开 FxPlug callback context 后返回 `nil`。
- **只请求 `FxRemoteWindowAPI_v2`。** 固定尺寸窗口只需要基础协议；Motion 未提供 v2 时功能被错误判定为不可用。
- **直接使用 callback parent 作为绝对布局根。** 非零 parent origin 被重复计入，造成首帧偏移和右侧裁切。
- **跨宿主边界建立复杂约束。** ViewBridge 层级不是公开 Auto Layout 契约，约束可能在不同坐标基础之间求解。
- **在 `viewDidLayout()` 手工摆放按钮。** 宿主动画改变宽度时，手工 frame 与 Auto Layout 分裂，Save/Restore 仍会被推出窗口。
- **认为固定请求尺寸就是永不变化的窗口尺寸。** 宿主可在创建/动画阶段改变远程 view geometry；布局必须响应实际 bounds。
- **用截图判断新修复。** 截图来自旧 XPC 时，继续改布局只会围绕不存在的当前问题迭代。
