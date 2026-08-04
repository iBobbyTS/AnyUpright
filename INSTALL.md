# Installing AnyUpright from GitHub Releases

AnyUpright GitHub builds are ad-hoc signed and are not notarized by Apple. Install only releases downloaded from this repository, and verify the published SHA-256 checksum before bypassing macOS security warnings.

## Requirements

- Apple Silicon Mac
- macOS 14.0 or later
- A compatible version of Motion or Final Cut Pro

## Install

When the GitHub Release provides the installer package:

1. Download the `.pkg` and `SHA256SUMS` from the same release.
2. Verify the package checksum:

   ```sh
   shasum -a 256 -c SHA256SUMS
   ```

3. Quit Motion and Final Cut Pro.
4. Open the package and finish installation.
5. Open `/Applications/AnyUpright.app` once, then reopen Motion or Final Cut Pro.

The installer places the application in `/Applications` and the four Final Cut Effect templates in:

```text
~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/
```

## If macOS blocks the installer or application

First try Apple's supported UI override:

1. Try to open the blocked package or `/Applications/AnyUpright.app` once.
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

## Manual ZIP installation

If a release contains only `AnyUpright-<version>-macos-arm64.zip`:

1. Verify its SHA-256.
2. Extract `AnyUpright.app` and move it to `/Applications`.
3. Follow the Gatekeeper steps above.
4. Install the four template directories under `~/Movies/Motion Templates.localized/Effects.localized/AnyUpright/` while preserving their directory structure. Finder and Apple documentation normally display these localized folders without the `.localized` suffix.

Apple references:

- [Open apps safely on your Mac](https://support.apple.com/102445)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
