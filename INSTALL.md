# Installing AnyUpright from GitHub Releases

AnyUpright GitHub builds are ad-hoc signed and are not notarized by Apple. Install only releases downloaded from this repository, and verify the published SHA-256 checksum before bypassing macOS security warnings.

## Requirements

- Apple Silicon Mac
- macOS 14.0 or later
- A compatible version of Motion or Final Cut Pro

## Install

When the GitHub Release provides the disk image:

1. Download the `.dmg` and `SHA256SUMS` from the same release.
2. Verify the disk image checksum:

   ```sh
   shasum -a 256 -c SHA256SUMS
   ```

3. Quit Motion and Final Cut Pro.
4. Open the DMG and drag `AnyUpright.app` onto its `Applications` shortcut.
5. Open `/Applications/AnyUpright.app`.
6. In Plug-in Registration, click Install if the status is Not Installed.
7. Quit and reopen Motion or Final Cut Pro.

Motion Effects installation is not implemented in the current build. Its Install and Uninstall buttons display a placeholder alert. When implemented, the four Final Cut Effect templates will be installed in:

```text
~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/
```

## If macOS blocks the installer or application

First try Apple's supported UI override:

1. Try to open `/Applications/AnyUpright.app` once.
2. Open `System Settings > Privacy & Security`.
3. Scroll to Security and click `Open Anyway` for AnyUpright.
4. Confirm `Open`, then open `/Applications/AnyUpright.app` once.
5. Quit and reopen Motion or Final Cut Pro.

This normally provides the required exception. Running `xattr` is not mandatory.

## Terminal fallback

Use this only when the UI override is unavailable or the host still refuses to load the nested FxPlug after you have verified the release checksum:

```sh
APP=/Applications/AnyUpright.app
XPC="$APP/Contents/PlugIns/AnyUpright XPC Service.pluginkit"

sudo xattr -dr com.apple.quarantine "$APP"
sudo codesign --force --sign - "$XPC/Contents/Frameworks/PluginManager.framework"
sudo codesign --force --sign - "$XPC/Contents/Frameworks/FxPlug.framework"
sudo codesign --force --sign - "$XPC"
sudo codesign --force --sign - --preserve-metadata=entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
open "$APP"
```

Then fully restart Motion or Final Cut Pro. The `xattr` command removes the quarantine marker recursively; the `codesign` commands rebuild a local ad-hoc signature from the innermost frameworks outward. Neither action notarizes the software or proves its origin. Creating a private self-signed certificate does not make the software trusted by Gatekeeper on other Macs, so it is not a substitute for an Apple Developer ID.

## Uninstall

The Plug-in Registration Uninstall button unregisters the embedded FxPlug but does not delete the application. Quit Motion, Final Cut Pro, and AnyUpright before deleting `/Applications/AnyUpright.app`. Motion Effects removal is not implemented yet.

Apple references:

- [Open apps safely on your Mac](https://support.apple.com/102445)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
