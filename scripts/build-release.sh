#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/AnyUprightDerivedDataRelease}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT_DIR}/build/release}"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/AnyUpright.app"
DSYM_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/AnyUpright.app.dSYM"
XPC_PATH="${APP_PATH}/Contents/PlugIns/AnyUpright XPC Service.pluginkit"
XPC_EXECUTABLE="${XPC_PATH}/Contents/MacOS/AnyUpright XPC Service"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/AnyUpright"
APP_ENTITLEMENTS="${ROOT_DIR}/AnyUpright/Wrapper Application/SandboxEntitlements.entitlements"

require_path() {
    if [[ ! -e "$1" ]]; then
        echo "error: required path is missing: $1" >&2
        exit 1
    fi
}

cd "$ROOT_DIR"

require_path "/Library/Developer/SDKs/FxPlug.sdk"
require_path "/Library/Developer/Frameworks/FxPlug.framework"
require_path "/Library/Developer/Frameworks/PluginManager.framework"
require_path "$APP_ENTITLEMENTS"

rm -rf "$DERIVED_DATA_PATH" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
    -project AnyUpright.xcodeproj \
    -scheme "Wrapper Application" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    clean build \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=

require_path "$APP_PATH"
require_path "$DSYM_PATH"
require_path "$XPC_PATH"
require_path "$APP_EXECUTABLE"
require_path "$XPC_EXECUTABLE"

# Xcode strips framework Modules while embedding the XPC service. Re-sign the
# final nested layout so each resource seal describes the shipped files.
codesign --force --sign - "${XPC_PATH}/Contents/Frameworks/PluginManager.framework"
codesign --force --sign - "${XPC_PATH}/Contents/Frameworks/FxPlug.framework"
codesign --force --sign - "$XPC_PATH"
codesign --force --sign - --entitlements "$APP_ENTITLEMENTS" "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

APP_ARCHS="$(lipo -archs "$APP_EXECUTABLE")"
XPC_ARCHS="$(lipo -archs "$XPC_EXECUTABLE")"
if [[ "$APP_ARCHS" != "arm64" || "$XPC_ARCHS" != "arm64" ]]; then
    echo "error: release must contain only arm64 executables" >&2
    echo "app architectures: $APP_ARCHS" >&2
    echo "xpc architectures: $XPC_ARCHS" >&2
    exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")"
BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")"
MINIMUM_SYSTEM="$(plutil -extract LSMinimumSystemVersion raw "$APP_PATH/Contents/Info.plist")"

if [[ "$MINIMUM_SYSTEM" != "14.0" ]]; then
    echo "error: expected macOS deployment target 14.0, got $MINIMUM_SYSTEM" >&2
    exit 1
fi

for LOCALE in en zh-Hans; do
    require_path "${XPC_PATH}/Contents/Resources/${LOCALE}.lproj/Localizable.strings"
    require_path "${XPC_PATH}/Contents/Resources/${LOCALE}.lproj/InfoPlist.strings"
done

MODEL_COUNT="$(find "${XPC_PATH}/Contents/Resources" -maxdepth 1 -type d -name '*.mlmodelc' | wc -l | tr -d ' ')"
if [[ "$MODEL_COUNT" -lt 9 ]]; then
    echo "error: expected at least 9 compiled Core ML models, got $MODEL_COUNT" >&2
    exit 1
fi

ARCHIVE_BASENAME="AnyUpright-${VERSION}-macos-arm64"
APP_ARCHIVE="${OUTPUT_DIR}/${ARCHIVE_BASENAME}.zip"
DSYM_ARCHIVE="${OUTPUT_DIR}/${ARCHIVE_BASENAME}.dSYM.zip"
BUILD_INFO="${OUTPUT_DIR}/${ARCHIVE_BASENAME}.build-info.txt"
CHECKSUMS="${OUTPUT_DIR}/SHA256SUMS"

ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$APP_ARCHIVE"
ditto -c -k --keepParent "$DSYM_PATH" "$DSYM_ARCHIVE"

GIT_COMMIT="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then
    GIT_STATE="dirty"
else
    GIT_STATE="clean"
fi

{
    echo "Product: AnyUpright"
    echo "Version: ${VERSION} (${BUILD_NUMBER})"
    echo "Architecture: arm64"
    echo "Minimum macOS: ${MINIMUM_SYSTEM}"
    echo "Signing: ad-hoc (not notarized)"
    echo "Core ML model bundles: ${MODEL_COUNT}"
    echo "Git commit: ${GIT_COMMIT}"
    echo "Git state: ${GIT_STATE}"
    xcodebuild -version
    echo "macOS SDK: $(xcrun --sdk macosx --show-sdk-version)"
} > "$BUILD_INFO"

(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$(basename "$APP_ARCHIVE")" "$(basename "$DSYM_ARCHIVE")" "$(basename "$BUILD_INFO")" > "$(basename "$CHECKSUMS")"
)

echo
echo "Release artifacts:"
echo "  $APP_ARCHIVE"
echo "  $DSYM_ARCHIVE"
echo "  $BUILD_INFO"
echo "  $CHECKSUMS"
