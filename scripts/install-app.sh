#!/bin/bash
# 构建并安装原生 App 到 /Applications（或 ~/Applications）。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/app/build.sh" >/dev/null

osascript -e 'tell application "Google TV Remote" to quit' >/dev/null 2>&1 || true
pkill -f "Google TV Remote.app/Contents/MacOS/GoogleTVRemote" >/dev/null 2>&1 || true
sleep 1

DEST="/Applications/Google TV Remote.app"
rm -rf "$DEST" 2>/dev/null || true
if ! cp -R "$ROOT/app/dist/Google TV Remote.app" "$DEST" 2>/dev/null; then
  DEST="$HOME/Applications/Google TV Remote.app"
  mkdir -p "$HOME/Applications"
  rm -rf "$DEST"
  cp -R "$ROOT/app/dist/Google TV Remote.app" "$DEST"
fi
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "已安装：$DEST"
echo "首次打开后，在 系统设置 → 隐私与安全性 里勾选："
echo "  · 输入监控：读取遥控器按键"
echo "  · 辅助功能：向系统发送按键"
echo "授权后回到 App 即可直接使用。"
open "$DEST"
