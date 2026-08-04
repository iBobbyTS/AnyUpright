# AnyUpright GitHub Release 流程

本文覆盖非商业 GitHub Release。当前流程不使用 Apple Developer ID，也不做 Apple 公证；应用使用 ad-hoc 签名维持 App、XPC 与嵌入框架之间的代码完整性。

## 发布边界

- 二进制：`AnyUpright.app`，安装到 `/Applications`。
- Final Cut Pro Effects：由 Motion 创建的四个 `.moef` 模板，安装到当前用户的 `~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/`。Finder 和 Apple 文档通常把这些目录显示为不带 `.localized` 后缀的 `Motion Templates/Effects`。
- 架构：Apple Silicon (`arm64`)。
- 最低系统：macOS 14.0。实际宿主要求仍以所使用的 Motion、Final Cut Pro 和 FxPlug SDK 版本为准。
- 签名：ad-hoc，不需要 Apple 开发者账号，不等同于 Developer ID 签名，也不能提交 Apple 公证。

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
AnyUpright-<version>-macos-arm64.zip
AnyUpright-<version>-macos-arm64.dSYM.zip
AnyUpright-<version>-macos-arm64.build-info.txt
SHA256SUMS
```

脚本固定执行以下门槛：

1. Release + `arm64` 构建。
2. 对最终嵌套布局中的 `PluginManager.framework`、`FxPlug.framework`、XPC 和 App 依次 ad-hoc 重签。
3. `codesign --verify --deep --strict` 严格验签。
4. 验证 App/XPC 架构、最低系统、两种语言资源和至少九个 Core ML model bundle。
5. 生成 App ZIP、dSYM ZIP、构建环境记录和 SHA-256。

Xcode 在把 XPC 嵌入 App 时会移除 framework 的 `Modules`。如果只看 `BUILD SUCCEEDED`，`PluginManager.framework` 的旧资源封印可能仍引用已移除的 `module.modulemap`。发行脚本在最终 App 布局上重新签名并严格验签，不能省略这一段。

如需隔离路径：

```sh
DERIVED_DATA_PATH=/private/tmp/AnyUprightRelease \
OUTPUT_DIR="$PWD/build/release" \
./scripts/build-release.sh
```

GitHub Release 上传 App ZIP、`SHA256SUMS` 和 `build-info.txt`。dSYM 建议同时保留，用于定位用户崩溃；它不是安装内容。

## 2. 在 Motion 创建四个 Final Cut Effect

Apple 的标准流程是从 Motion Project Browser 创建 `Final Cut Effect`，把滤镜加到唯一的 `Effect Source` placeholder，发布希望在 Final Cut Pro Inspector 中显示的参数，然后发布模板。模板保存后会进入 Final Cut Pro Effects Browser。

先准备二进制：

1. 解压 Release ZIP，把 `AnyUpright.app` 放入 `/Applications`。
2. 打开一次 `/Applications/AnyUpright.app`，让 Launch Services 和 PlugInKit 注册嵌入的 FxPlug XPC。
3. 完全退出并重新打开 Motion。
4. 在 Motion 的 Filters Library 中确认 `AnyUpright` 分类下四个滤镜都存在。

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
6. 在 Inspector 中逐项发布希望出现在 Final Cut Pro 的参数。至少保留对应滤镜当前的用户可见控制；不要发布内部隐藏参数。特别确认 Analyze、Defaults、Edit Mode、四角坐标和 Set/Unset Key Frame 在模板发布后是否仍可见、可点击。
7. 如使用参考图片检查预览，发布前从 `Effect Source` 清除，避免把测试素材打进模板。
8. `File > Save`，名称与滤镜商品名完全一致，Category 统一新建为 `AnyUpright`，Theme 留空，关闭 `Include unused media`；Preview Movie 可选。
9. 点击 `Publish`。

完成后应得到：

```text
~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/
├── AnyUpright Horizon/
├── AnyUpright Inner Stretch/
├── AnyUpright Outer Stretch/
└── AnyUpright Upright/
```

每个目录应包含一个 `.moef` 以及 Motion 生成的 `large.png`、`small.png` 等资源。不要手工改 `.moef` 内部引用。先在 Final Cut Pro 中逐个验证，再进入 PKG 阶段。

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

## 3. PKG 设计（模板完成后执行）

最终 PKG 将包含两个 payload：

1. `/Applications/AnyUpright.app`
2. 四个 Motion Effect 模板

Apple 将共享模板的规范位置显示为用户目录下的 `~/Movies/Motion Templates/Effects/`；实际磁盘目录通常带 `.localized` 后缀。Installer 脚本以 root 身份执行，不能直接依赖 `$HOME`；因此后续打包脚本会：

1. 把 App 安装到 `/Applications`。
2. 把模板暂存到 `/Library/Application Support/AnyUpright/Motion Templates/Effects/AnyUpright/`。
3. `postinstall` 解析当前 console user 的真实 home，优先使用已有的 `Motion Templates.localized/Effects.localized` 目录；目录不存在时按该磁盘名称创建，再复制 `AnyUpright` 模板并修正 owner/group。
4. 强制注册 `/Applications/AnyUpright.app`，但不在安装时启动 Motion 或 Final Cut Pro。

不在四个模板完成前生成 PKG，避免把不完整或手工猜测的模板目录固化到发行流程。PKG 本身将保持未签名；Installer package 不能用普通 `codesign` 做 ad-hoc 签名。未来如有 Apple Developer ID，应使用 `Developer ID Application` 签 App、`Developer ID Installer` 签 PKG，再使用 `notarytool` 公证。

## 4. 用户安装与 Gatekeeper

面向最终用户的简版说明维护在仓库根目录 [INSTALL.md](../INSTALL.md)。结论如下：

- 正常情况下不必须执行 `xattr`。
- 未公证 PKG/App 被拦截时，先尝试打开一次，再进入 `System Settings > Privacy & Security` 点击 `Open Anyway`。Apple 将该软件保存为安全例外，之后可正常打开。
- 对嵌套 FxPlug 没有出现图形界面放行入口、或宿主仍拒绝加载时，才使用文档中的 `xattr` + 按嵌套顺序 ad-hoc 重签兜底命令。私人自签证书不会让其他 Mac 的 Gatekeeper 自动信任该软件。
- `Open Anyway` 与删除 quarantine 都会绕过一部分 Gatekeeper 保护，只应对已核对 GitHub Release SHA-256 的文件执行。

Apple 明确说明，macOS 会检查 App、plug-in 和 installer package 的 Developer ID；未公证 plug-in 需要用户明确批准。参见：

- [Open apps safely on your Mac](https://support.apple.com/102445)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
