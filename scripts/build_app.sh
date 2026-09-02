#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/CodexTouchBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
MODULE_CACHE="${TMPDIR:-/private/tmp}/codex-touchbar-module-cache"

if [[ ! -d "$SDK_PATH" ]]; then
  SDK_PATH="$(xcrun --show-sdk-path)"
fi

mkdir -p "$MODULE_CACHE"
cd "$PROJECT_DIR"

env SDKROOT="$SDK_PATH" \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
  swift build --disable-sandbox -c release --product CodexTouchBar

BUILD_DIR="$(env SDKROOT="$SDK_PATH" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" swift build --disable-sandbox -c release --show-bin-path)"

rm -rf -- "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
ditto "$BUILD_DIR/CodexTouchBar" "$MACOS_DIR/CodexTouchBar"
ditto "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$PROJECT_DIR/Resources/CodexTouchBar.icns" "$RESOURCES_DIR/CodexTouchBar.icns"
chmod 755 "$MACOS_DIR/CodexTouchBar"
codesign --force --sign - --timestamp=none "$APP_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"
codesign --verify --deep --strict "$APP_DIR"

print "$APP_DIR"
