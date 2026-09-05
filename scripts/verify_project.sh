#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
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
  swift run --disable-sandbox CodexTouchBarCoreChecks

if grep -ERn --exclude='*.icns' \
  '(sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|tool_input|tool_response|transcript_path)' \
  Sources/CodexTouchBar Sources/CodexTouchBarCore Resources; then
  print -u2 "Sensitive field names or secret-like material found in runtime sources"
  exit 1
fi

if grep -ERn \
  '(thread\["(title|preview|firstUserMessage)"\]|NULLIF\((title|preview|first_user_message))' \
  Sources/CodexTouchBar Sources/TouchBarPrivateBridge; then
  print -u2 "Request-derived text is used as a Touch Bar label source"
  exit 1
fi

if ! grep -q 'SELECT display_title FROM local_thread_catalog' \
  Sources/TouchBarPrivateBridge/TouchBarPrivateBridge.m; then
  print -u2 "Codex task-list display_title source is missing"
  exit 1
fi

if ! grep -q 'id of tab currentIndex of targetWindow' \
  Sources/CodexTouchBar/ChromeTabController.swift; then
  print -u2 "Chrome tab switching is not resolving the stable tab identifier at touch time"
  exit 1
fi

if grep -q 'activate(windowID:.*tabIndex:' \
  Sources/CodexTouchBar/ChromeTabController.swift Sources/CodexTouchBar/TouchBarController.swift; then
  print -u2 "Chrome tab switching still depends on a stale tab index"
  exit 1
fi

if ! grep -q 'leftMediaStack.isHidden = true' \
  Sources/CodexTouchBar/GlassBlockView.swift; then
  print -u2 "Chrome mode still reserves space for media controls"
  exit 1
fi

if ! grep -q 'private static let automationQueue' \
  Sources/CodexTouchBar/ChromeTabController.swift; then
  print -u2 "Chrome Automation is running on the Touch Bar UI path"
  exit 1
fi

if grep -q 'ChromeTabController.frontWindowTabs' \
  Sources/CodexTouchBar/TouchBarController.swift; then
  print -u2 "Touch Bar controller performs synchronous Chrome Automation"
  exit 1
fi

if ! grep -q 'chromeSelectionInFlight' \
  Sources/CodexTouchBar/TouchBarController.swift; then
  print -u2 "Rapid Chrome touches are not protected from stale queued actions"
  exit 1
fi

if ! grep -q 'private let titleLabel = NSTextField(labelWithString: "")' \
  Sources/CodexTouchBar/GlassBlockView.swift; then
  print -u2 "Chrome tab titles do not use a physical-Touch-Bar-safe AppKit text field"
  exit 1
fi

if ! grep -q 'String(fullTitle.prefix(2))' \
  Sources/CodexTouchBar/GlassBlockView.swift; then
  print -u2 "Narrow Chrome tabs do not preserve the first two title characters"
  exit 1
fi

if grep -q 'chromeMarkLayer\|private let titleLayer = CATextLayer' \
  Sources/CodexTouchBar/GlassBlockView.swift; then
  print -u2 "Chrome tab logo or unstable CATextLayer still consumes title width"
  exit 1
fi

if ! grep -q 'private enum ChromeTabTheme' \
  Sources/CodexTouchBar/GlassBlockView.swift; then
  print -u2 "Chrome tabs do not have title-derived in-memory theme accents"
  exit 1
fi

print "CodexTouchBar verification passed"
