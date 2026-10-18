#!/bin/bash
# 构建 "Google TV Remote.app"（原生 SwiftUI，无第三方依赖）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/dist/Google TV Remote.app"
BIN="$APP/Contents/MacOS/GoogleTVRemote"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "== 编译 =="
swiftc -parse-as-library -O -swift-version 5 \
  "$ROOT"/Sources/*.swift \
  -o "$BIN" \
  -framework SwiftUI -framework AppKit -framework IOKit -framework CoreGraphics

echo "== 组装 .app =="
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
chmod +x "$BIN"

echo "== ad-hoc 签名 =="
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo
echo "构建完成：$APP"
echo "运行：open \"$APP\""
echo "自检：\"$BIN\" --selftest"
