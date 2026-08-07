# AnyUpright GitHub Release 流程

本文覆盖非商业 GitHub Release。当前流程不使用 Apple Developer ID，也不做 Apple 公证；应用使用 ad-hoc 签名维持 App、XPC 与嵌入框架之间的代码完整性。

## 发布边界

- 二进制：`AnyUpright.app`，安装到 `/Applications`。
- Final Cut Pro Effects：由 Motion 创建的四个 `.moef` 模板，安装到当前用户的 `~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/`。Finder 和 Apple 文档通常把这些目录显示为不带 `.localized` 后缀的 `Motion Templates/Effects`。
- 架构：Apple Silicon (`arm64`)。
- 最低系统：macOS 14.0。实际宿主要求仍以所使用的 Motion、Final Cut Pro 和 FxPlug SDK 版本为准。
- 签名：ad-hoc，不需要 Apple 开发者账号，不等同于 Developer ID 签名，也不能提交 Apple 公证。

### Release App 与 Debug 构建的管理边界

`/Applications/AnyUpright.app` 及其安装窗口只管理 Release。发行 App 的 bundle ID 为 `AnyUpright`，内嵌 XPC 的 bundle ID 为 `AnyUpright-XPC-Service`；安装、卸载和状态检查均只针对这套生产身份。安装窗口不负责发现、注册、取消注册或清理 Debug 构建。

Debug 产物名为 `AnyUpright (Debug).app`，其 wrapper ID 为 `AnyUpright-Debug`，XPC ID 为 `AnyUpright-XPC-Service-Debug`，滤镜名称也带 `(Debug)`。不要重命名后复制到 `/Applications/AnyUpright.app`，不要把它放入发行 DMG，也不要使用 Release App 的安装窗口管理 Debug。Debug 的构建、注册、路径冲突和清理由开发者或 Agent 直接使用 Xcode、Launch Services 和 PlugInKit 工具处理。

Debug App 可能出现在以下位置：

```text
# 项目规定的 canonical 路径
/private/tmp/AnyUprightDerivedData/Build/Products/Debug/AnyUpright (Debug).app

# 与 canonical 路径指向同一位置的 macOS 路径写法
/tmp/AnyUprightDerivedData/Build/Products/Debug/AnyUpright (Debug).app

# Xcode 默认 Derived Data
~/Library/Developer/Xcode/DerivedData/AnyUpright-*/Build/Products/Debug/AnyUpright (Debug).app

# 调用 xcodebuild 时指定的自定义 Derived Data
<derived-data-path>/Build/Products/Debug/AnyUpright (Debug).app

# 人工复制产生的遗留副本，例如桌面、下载目录或 ~/Applications
<copied-location>/AnyUpright (Debug).app
```

日常 Motion 调试只使用第一项 canonical 路径。`/tmp` 与 `/private/tmp` 是同一位置，不属于两个副本。其他 Debug 路径一旦被 Launch Services 或 PlugInKit 发现，就可能与 canonical Debug 注册竞争；它们应视为开发环境冲突，而不是由发行 App 代为处理。

构建和定位 Debug 注册：

```sh
xcodebuild \
  -project AnyUpright.xcodeproj \
  -scheme 'Wrapper Application' \
  -configuration Debug \
  -derivedDataPath /private/tmp/AnyUprightDerivedData \
  build

pluginkit -m -ADv -i AnyUpright-XPC-Service-Debug
pluginkit -m -ADv -i AnyUpright-XPC-Service
```

第一条 `pluginkit` 命令只检查 Debug，第二条只检查 Release。正常开发机可以同时存在一个 canonical Debug 注册和一个 `/Applications/AnyUpright.app` Release 注册；同一 bundle ID 返回多个不同 App 路径才是冲突。清理冲突前应完全退出 Motion 和 Final Cut Pro，再由开发者或 Agent 对查到的具体 Debug 遗留路径执行 `lsregister -u '/path/to/AnyUpright (Debug).app'`，并删除不再需要的副本。不得把 `/Applications/AnyUpright.app` 当作 Debug 清理目标。

## 1. 构建 Release 二进制

前置条件：

- Xcode 和 Metal Toolchain 已安装。
- FxPlug SDK 位于 `/Library/Developer/SDKs/FxPlug.sdk`。
- `FxPlug.framework` 与 `PluginManager.framework` 位于 `/Library/Developer/Frameworks/`。
- 仓库内的忽略资源 `GeoCalibCoreML/` 和 `ScaleLSDCoreML/` 已准备完整。

在仓库根目录执行：

```sh
./scripts/build-release.sh
```

默认使用 `/private/tmp/AnyUprightDerivedDataRelease`，输出到 `build/release/`：

```text
AnyUpright-<version>-macos-arm64.dmg
AnyUpright-<version>-macos-arm64.dSYM.zip
AnyUpright-<version>-macos-arm64.build-info.txt
SHA256SUMS
```

脚本固定执行以下门槛：

1. Release + `arm64` 构建。
2. 验证 manifest 模板的 Debug/Release 身份均完整，并确认实际 Release App/XPC 使用生产 bundle ID、生产 FxPlug 组和原始七个 UUID；检测到 Debug 身份会直接失败。
3. 对最终嵌套布局中的 `PluginManager.framework`、`FxPlug.framework`、XPC 和 App 依次 ad-hoc 重签。
4. `codesign --verify --deep --strict` 严格验签。
5. 验证 App/XPC 架构、最低系统、两种语言资源和至少九个 Core ML model bundle。
6. 生成带 `/Applications` 快捷方式的 App DMG、dSYM ZIP、构建环境记录和 SHA-256。

Xcode 在把 XPC 嵌入 App 时会移除 framework 的 `Modules`。如果只看 `BUILD SUCCEEDED`，`PluginManager.framework` 的旧资源封印可能仍引用已移除的 `module.modulemap`。发行脚本在最终 App 布局上重新签名并严格验签，不能省略这一段。

如需隔离路径：

```sh
DERIVED_DATA_PATH=/private/tmp/AnyUprightRelease \
OUTPUT_DIR="$PWD/build/release" \
./scripts/build-release.sh
```

GitHub Release 上传 App DMG、`SHA256SUMS` 和 `build-info.txt`。dSYM 建议同时保留，用于定位用户崩溃；它不是安装内容。

## 2. 在 Motion 创建四个 Final Cut Effect

Apple 的标准流程是从 Motion Project Browser 创建 `Final Cut Effect`，把滤镜加到唯一的 `Effect Source` placeholder，发布希望在 Final Cut Pro Inspector 中显示的参数，然后发布模板。模板保存后会进入 Final Cut Pro Effects Browser。

先准备二进制：

1. 打开 Release DMG，把 `AnyUpright.app` 拖到 DMG 中的 `Applications` 快捷方式。
2. 打开 `/Applications/AnyUpright.app`，在左侧“插件注册”中确认状态；若显示未安装，点击“安装”。
3. 完全退出并重新打开 Motion。
4. 在 Motion 的 Filters Library 中确认 `AnyUpright` 分类下四个滤镜都存在。

Release 滤镜名称不带后缀。若看到 `(Debug)`，说明当前选择的是独立的开发身份；不要用它创建发行模板。`.moef` 会绑定滤镜 UUID，因此 Debug 模板不会在只安装 Release 的用户机器上自动改绑。

四个模板分别执行一次：

1. 选择 `File > New from Project Browser`（`Option-Command-N`）。
2. 选择 `Final Cut Effect`。
3. 使用预期支持的最高分辨率，建议 4K；`Color Processing` 选择 `Automatic`。
4. 打开项目后保留唯一的 `Effect Source`，不要删除或另外创建 placeholder。
5. 将对应 AnyUpright 滤镜拖到 `Effect Source`：
   - `AnyUpright Horizon`
   - `AnyUpright Inner Stretch`
   - `AnyUpright Outer Stretch`
   - `AnyUpright Upright`
6. 在 Inspector 中逐项发布希望出现在 Final Cut Pro 的参数。至少保留对应滤镜当前的用户可见控制；不要发布内部隐藏参数。普通数值参数使用 Motion 的发布菜单；FxPlug push button 在当前 Motion 界面中没有同等发布入口，必须在保存后的 `.moef` XML 中补充 `<publishSettings>` target，方法见下文。特别确认 Analyze、Defaults、Edit Mode、四角坐标和 Set/Unset Key Frame 在模板发布后是否仍可见、可点击。
7. 如使用参考图片检查预览，发布前从 `Effect Source` 清除，避免把测试素材打进模板。
8. `File > Save`，名称与滤镜商品名完全一致，Category 统一新建为 `AnyUpright`，Theme 留空，关闭 `Include unused media`；Preview Movie 可选。
9. 点击 `Publish`。

### 发布 FxPlug 按钮参数

FxPlug 通过 `addPushButton` 注册的按钮可以正常出现在 Motion Inspector 中，但当前 Motion 界面不会像普通数值参数那样提供直接发布入口。按钮在 Motion 中可见，不代表它已经进入 `.moef` 的 `<publishSettings>`；未列入该节点的按钮不会出现在 Final Cut Pro Inspector 中。

保存模板后，编辑当前 `.moef` 的 `<publishSettings>`，为按钮补充 target。`object` 必须取自同一文件中当前 Release 滤镜的 `<filter ... id="...">`，不能从旧 `.motn`、自动保存文件或其他模板复制。`channel` 是 `./` 加 FxPlug 参数 ID。例如 Horizon 当前参数 ID 为：

```text
Analyze Horizon = 102
Rotation        = 100
Fill Frame      = 101
Defaults        = 103
Publish OSC     = 10005
```

若当前 `.moef` 中 Release Horizon 的滤镜对象 ID 为 `10015`，发布 Analyze、Rotation、Fill Frame 和 Defaults 的写法是：

```xml
<publishSettings>
    <version>2</version>
    <target object="10015" channel="./102" name="分析水平线"/>
    <target object="10015" channel="./100" name="旋转"/>
    <target object="10015" channel="./101" name="填满画面"/>
    <target object="10015" channel="./103" name="默认设置..."/>
</publishSettings>
```

`10015` 只是该次模板保存产生的对象 ID；Motion 重新创建或保存模板后可能变化，必须重新读取当前文件。`Publish OSC` 是独立的宿主设置，只在需要 Final Cut 画布 OSC 或 Horizon 分析状态叠层时另行发布 `./10005`，不要把它与按钮发布混为一谈。

不要用旧 `.motn` 整体覆盖当前 `.moef`。旧文件可能绑定旧的 Debug/Release 插件 UUID、旧对象 ID或旧参数状态；只把所需 target 加入当前 Release `.moef`。直接编辑磁盘文件时，应先关闭 Motion 中已打开的同一文档，或确保关闭时不保存旧的内存版本，否则 Motion 可能覆盖 XML 修改。

修改后至少执行：

```sh
xmllint --noout '/path/to/Horizon.moef'
xmllint --xpath '//publishSettings' '/path/to/Horizon.moef'
```

然后完全退出并重新打开 Final Cut Pro，删除旧效果实例，再从 Effects Browser 重新拖入模板。Final Cut Pro 可能缓存旧模板和旧实例，仅重开 Inspector 不足以验证发布结果。可迁移的宿主边界和排错清单见 [`engineering-notes/motion-fxplug-button-publishing.md`](engineering-notes/motion-fxplug-button-publishing.md)。

完成后应得到：

```text
~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/
├── AnyUpright Horizon/
├── AnyUpright Inner Stretch/
├── AnyUpright Outer Stretch/
└── AnyUpright Upright/
```

每个目录应包含一个 `.moef` 以及 Motion 生成的 `large.png`、`small.png` 等资源。除上述 `<publishSettings>` 按钮 target 外，不要手工改 `.moef` 内部引用。先在 Final Cut Pro 中逐个验证，再把模板接入 Wrapper 的 Motion Effects 安装功能。

建议 Final Cut Pro 验收矩阵：

- 四个 Effect 都在 `AnyUpright` 分类出现。
- 所有发布参数、按钮、Popup、关键帧和 OSC 均可用。
- 1080p 与 4K、SDR 与 HDR 各跑一次。
- Horizon/Upright 分析完成后宿主任务结束。
- Inner/Outer 拖拽、关键帧、撤销和画布外预览正常。
- 重启 Final Cut Pro 后模板与参数仍可用。

Apple 文档：

- [Create an effect template in Motion](https://support.apple.com/guide/motion/create-an-effect-template-motn141bbb1f/mac)
- [Where are Final Cut Pro templates saved in Motion?](https://support.apple.com/guide/motion/where-are-final-cut-pro-templates-saved-motn141bd88c/mac)

## 3. DMG 与安装应用

本项目不提供 PKG。DMG 只包含：

1. `AnyUpright.app`
2. 指向 `/Applications` 的快捷方式

用户把 App 拖入 `/Applications` 后打开它。安装窗口分为两列：

- “插件注册”显示当前内嵌 FxPlug 的注册状态，并提供安装和卸载注册按钮。
- “Motion Effects 文件”显示模板安装状态，并提供安装和卸载按钮；在四个正式 `.moef` 模板加入发行资源前，这两个按钮只显示“尚未实现”提示。

左侧“卸载”只取消当前 App 内嵌 FxPlug 的 PlugInKit 注册，不删除 `/Applications/AnyUpright.app`。需要彻底移除时，先退出 Motion/Final Cut Pro 和 AnyUpright，再从 `/Applications` 删除 App。系统自动发现机制可能再次发现仍留在磁盘上的 App，因此发行说明不得把“取消注册”描述为删除二进制。

Motion Effects 安装完成后的目标目录仍为 `~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/`。该功能后续由 Wrapper 在当前登录用户上下文中管理，不需要 root installer 脚本。

## 4. 用户安装与 Gatekeeper

面向最终用户的简版说明维护在仓库根目录 [INSTALL.md](../INSTALL.md)。结论如下：

- 正常情况下不必须执行 `xattr`。
- 未公证 App 被拦截时，先尝试打开一次，再进入 `System Settings > Privacy & Security` 点击 `Open Anyway`。Apple 将该软件保存为安全例外，之后可正常打开。
- 对嵌套 FxPlug 没有出现图形界面放行入口、或宿主仍拒绝加载时，才使用文档中的 `xattr` + 按嵌套顺序 ad-hoc 重签兜底命令。私人自签证书不会让其他 Mac 的 Gatekeeper 自动信任该软件。
- `Open Anyway` 与删除 quarantine 都会绕过一部分 Gatekeeper 保护，只应对已核对 GitHub Release SHA-256 的文件执行。

Apple 明确说明，macOS 会检查 App、plug-in 和 installer package 的 Developer ID；未公证 plug-in 需要用户明确批准。参见：

- [Open apps safely on your Mac](https://support.apple.com/102445)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
