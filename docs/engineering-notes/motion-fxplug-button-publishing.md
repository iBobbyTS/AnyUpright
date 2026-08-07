# Motion FxPlug Button And Parameter Group Publishing

Last updated: 2026-08-06 19:29 MDT
Observed host: Motion Creator Studio 6.3

本文记录 Motion Final Cut Effect 模板发布 FxPlug push button 和 parameter subgroup 时的宿主边界。它适用于通过 `FxParameterCreationAPI` 注册的下列控制：

- 通过 `addPushButton` 注册、依靠 Objective-C selector 执行动作的按钮，例如 AnyUpright 的 Analyze、Defaults 和 Set/Unset Key Frame。
- 通过 `startParameterSubGroup` / `endParameterSubGroup` 注册的参数子组，例如 Inner Stretch 的“左上”组及其 X/Y 参数。

## Observed Boundary

在已验证的 Motion 版本中：

- FxPlug push button 会正常出现在 Motion Filters Inspector 中，selector 也可以在 Motion 内被调用。
- 这类按钮没有普通数值、布尔或 popup 参数所具有的直接发布菜单。
- Motion Inspector 中存在参数，不等于 Final Cut Effect 模板已经发布该参数。
- Final Cut Pro 只显示 `.moef` 的 `<publishSettings>` 中列出的 target。
- 按钮无需像普通参数一样在 `<filter>` 节点中保存 `default` 或 `value`；`<publishSettings>` 可以直接通过 `object` 和 `channel` 引用按钮参数。

因此，当前可靠方法是在 Motion 保存 `.moef` 后，直接向 XML 的 `<publishSettings>` 补充按钮 target。

## FxPlug Parameter Subgroup Boundary

FxPlug parameter subgroup 在 Motion Inspector 中可以正常显示为带 disclosure triangle 的可折叠组，但这不代表 Motion 能把这个组结构直接发布到 Final Cut Pro。实测限制如下：

- 打开 FxPlug 参数子组标题的快捷菜单时，`发布`命令为禁用状态，无法从 Motion GUI 发布父组。
- 如果分别发布组内的 X/Y 叶子参数，`.moef` 会记录完整 channel 路径，但 Final Cut Pro Inspector 会把它们显示为两个平铺参数，不会保留父组 disclosure triangle。
- 若要在 Final Cut Pro 中保留可折叠组，需要删除叶子 target，改为在 `<publishSettings>` 中直接引用父组 channel。
- 父组的默认展开或折叠状态由 `<filter>` 参数树中该组的 `<foldFlags>` 决定；`<foldFlags>4</foldFlags>` 表示本次实测所需的默认折叠状态。

以 Inner Stretch 的“左上”组为例，以下写法会在 Final Cut Pro 中平铺 X/Y：

```xml
<target object="10096" channel="./220/202" name="左上 X px"/>
<target object="10096" channel="./220/203" name="左上 Y px"/>
```

应改为只发布父组：

```xml
<target object="10096" channel="./220" name="左上"/>
```

同时确认 `<filter>` 中的父组仍包含原有子参数，并按产品要求设置折叠状态：

```xml
<parameter name="左上" id="220" flags="8589938704">
    <foldFlags>4</foldFlags>
    <parameter name="左上 X px" id="202" flags="12884901904" default="0" value="0"/>
    <parameter name="左上 Y px" id="203" flags="12884901904" default="0" value="0"/>
</parameter>
```

上述父组发布方法已在 Motion Creator Studio 6.3 生成的 Inner Stretch `.moef` 和 Final Cut Pro Inspector 中实机验证：Final Cut Pro 显示“左上”折叠组，展开后包含 X/Y 两个参数。

与按钮发布一样，`10096`、`220`、`202` 和 `203` 都必须从当前目标 `.moef` 重新读取。不要假设其他模板或重新保存后的对象 ID、参数 ID 和 channel 路径相同。

## Ownership And Identity

一个 target 有三个关键字段：

```xml
<target object="FILTER_OBJECT_ID" channel="./PARAMETER_ID" name="USER_VISIBLE_NAME"/>
```

- `object`：必须等于当前 `.moef` 中目标 Release `<filter>` 的 `id`。这是 Motion 文档对象 ID，不是 FxPlug UUID，也不是跨文件稳定 ID。
- `channel`：`./` 加 FxPlug 参数 ID。例如 Horizon 的 Analyze 是 `./102`，Defaults 是 `./103`。
- `name`：Final Cut Pro Inspector 中显示的发布名称，应与当前模板语言和用户可见文案一致。

先在同一文件定位目标滤镜：

```xml
<filter name="AnyUpright Horizon"
        id="10015"
        pluginUUID="2E32E3C2-91C7-44D4-A0AC-0E87832A86A1"
        pluginName="AnyUpright Horizon">
```

再把相同的 `id` 写入 target：

```xml
<publishSettings>
    <version>2</version>
    <target object="10015" channel="./102" name="分析水平线"/>
    <target object="10015" channel="./100" name="旋转"/>
    <target object="10015" channel="./101" name="填满画面"/>
    <target object="10015" channel="./103" name="默认设置..."/>
</publishSettings>
```

上述 `10015` 和 UUID 只记录本次观察到的当前 Release 模板身份。Motion 重新创建对象、复制滤镜或重建模板后，`id` 可能变化；Debug 与 Release 也使用不同插件 UUID。每次编辑都必须从目标 `.moef` 重新读取，不得把示例值当作常量。

## Safe Editing Procedure

1. 在 Motion 中使用正确的 Release FxPlug 创建并保存 Final Cut Effect 模板。
2. 关闭 Motion 中打开的同一模板，或确认稍后关闭时不会保存旧的内存版本。
3. 在当前 `.moef` 中找到 Release `<filter>`，核对 `pluginName`、`pluginUUID` 和 `id`。
4. 在 `<publishSettings>` 内新增缺失的按钮或父组 target；若改为发布父组，删除同一组下不再需要的叶子 target，避免重复和平铺显示。保留其他现有 target 和 `<version>2</version>`。
5. 同一 `object + channel` 只允许出现一次。
6. 不修改 `<filter>` UUID、factory ID、timing、参数状态或其他 Motion 场景节点。
7. 解析 XML并检查最终发布列表。
8. 完全退出并重新打开 Final Cut Pro，删除旧实例，再从 Effects Browser 添加新实例。

最小验证命令：

```sh
xmllint --noout '/path/to/Effect.moef'
xmllint --xpath '//publishSettings' '/path/to/Effect.moef'
```

还应人工确认：

- Final Cut Pro Inspector 出现按钮且名称正确。
- 点击按钮会进入对应 FxPlug selector，而不只是显示静态标签。
- 现有数值参数仍然存在且顺序符合产品要求。
- 删除并重新添加效果后结果仍一致。

## Publish OSC Is Separate

Motion 的内建 `Publish OSC` 使用参数 ID `10005`。它控制 Final Cut Pro 是否建立和派发 FxOnScreenControl 相关行为，也用于 Horizon 的 OSC 分析状态叠层，但它不是发布自定义按钮的前置条件。

需要它时单独加入：

```xml
<target object="FILTER_OBJECT_ID" channel="./10005" name="发布 OSC"/>
```

不要因为 Analyze 或 Defaults 按钮缺失而盲目加入 `Publish OSC`；先分别验证按钮 target 和 OSC target。

## Failure Signatures

- **Motion 中按钮可见，Final Cut Pro 中缺失：** `.moef` 的 `<publishSettings>` 没有对应 `./PARAMETER_ID` target。
- **Motion 中参数组可折叠，Final Cut Pro 中 X/Y 被平铺：** 发布的是 `./GROUP_ID/CHILD_ID` 叶子 target；删除这些 target，改为发布 `./GROUP_ID` 父组。
- **Motion 参数组菜单中的“发布”不可用：** 这是已验证的 FxPlug parameter subgroup GUI 限制；直接编辑 `.moef` 的 `<publishSettings>`。
- **Final Cut Pro 中父组默认展开：** 检查 `<filter>` 参数树中父组是否包含正确的 `<foldFlags>`；本次验证的折叠值是 `4`。
- **Final Cut Pro 显示参数但按钮行为错误或无效：** 先检查 target 是否引用了错误的 Motion object ID，之后再检查当前实例加载的插件 UUID/XPC 身份。
- **XML 修改后再次消失：** Motion 仍持有编辑前的文档并在关闭或保存时覆盖了磁盘文件。
- **修改后 Final Cut Pro 仍显示旧列表：** Final Cut Pro 或现有效果实例缓存了旧模板；重启宿主、删除旧实例并重新添加。
- **复制旧 `.motn` 后 Release 模板失效：** 旧文件绑定了不同 FxPlug UUID 或对象图；恢复当前 `.moef`，只迁移所需 publish target。

## Previous Wrong Assumptions

- 认为按钮在 Motion Inspector 中可见，就会自动出现在 Final Cut Pro。
- 反复寻找按钮的普通“发布”菜单；当前宿主没有提供这个入口。
- 认为 Motion Inspector 中 FxPlug 参数子组的 disclosure triangle 会随子参数自动发布；发布叶子参数会在 Final Cut Pro 中丢失组层级。
- 继续寻找参数子组父行的可用“发布”命令；当前宿主会显示该命令，但它处于禁用状态。
- 为解决模板发布问题去修改插件的 `addPushButton` 注册；按钮已经存在，缺失的是模板 publish target。
- 把旧 `.motn` 或自动保存文件整体覆盖当前 `.moef`；这会同时迁移不兼容的 UUID、对象 ID 和场景状态。
- 硬编码其他模板中的 `object` ID；Motion object ID 只在当前文档对象图中有意义。
