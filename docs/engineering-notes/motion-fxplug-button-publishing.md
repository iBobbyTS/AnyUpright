# Motion FxPlug Push Button Publishing

Last updated: 2026-08-06 19:08 MDT
Observed host: Motion Creator Studio 6.3

本文记录 Motion Final Cut Effect 模板发布 FxPlug push button 时的宿主边界。它适用于通过 `FxParameterCreationAPI` 的 `addPushButton` 注册、依靠 Objective-C selector 执行动作的按钮，例如 AnyUpright 的 Analyze、Defaults 和 Set/Unset Key Frame。

## Observed Boundary

在已验证的 Motion 版本中：

- FxPlug push button 会正常出现在 Motion Filters Inspector 中，selector 也可以在 Motion 内被调用。
- 这类按钮没有普通数值、布尔或 popup 参数所具有的直接发布菜单。
- Motion Inspector 中存在参数，不等于 Final Cut Effect 模板已经发布该参数。
- Final Cut Pro 只显示 `.moef` 的 `<publishSettings>` 中列出的 target。
- 按钮无需像普通参数一样在 `<filter>` 节点中保存 `default` 或 `value`；`<publishSettings>` 可以直接通过 `object` 和 `channel` 引用按钮参数。

因此，当前可靠方法是在 Motion 保存 `.moef` 后，直接向 XML 的 `<publishSettings>` 补充按钮 target。

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
4. 在 `<publishSettings>` 内新增缺失的按钮 target；保留现有 target 和 `<version>2</version>`。
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
- **Final Cut Pro 显示参数但按钮行为错误或无效：** 先检查 target 是否引用了错误的 Motion object ID，之后再检查当前实例加载的插件 UUID/XPC 身份。
- **XML 修改后再次消失：** Motion 仍持有编辑前的文档并在关闭或保存时覆盖了磁盘文件。
- **修改后 Final Cut Pro 仍显示旧列表：** Final Cut Pro 或现有效果实例缓存了旧模板；重启宿主、删除旧实例并重新添加。
- **复制旧 `.motn` 后 Release 模板失效：** 旧文件绑定了不同 FxPlug UUID 或对象图；恢复当前 `.moef`，只迁移所需 publish target。

## Previous Wrong Assumptions

- 认为按钮在 Motion Inspector 中可见，就会自动出现在 Final Cut Pro。
- 反复寻找按钮的普通“发布”菜单；当前宿主没有提供这个入口。
- 为解决模板发布问题去修改插件的 `addPushButton` 注册；按钮已经存在，缺失的是模板 publish target。
- 把旧 `.motn` 或自动保存文件整体覆盖当前 `.moef`；这会同时迁移不兼容的 UUID、对象 ID 和场景状态。
- 硬编码其他模板中的 `object` ID；Motion object ID 只在当前文档对象图中有意义。
