#!/bin/bash
# 语音不上屏时的修复：重启麦克风桥 + 重启当前输入法，清掉卡住的音频会话。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

launchctl kickstart -k "gui/$(id -u)/com.gvtv.remote-mic" 2>/dev/null || true

if [ -d "/Library/Input Methods/DoubaoIme.app" ]; then
  killall DoubaoIme 2>/dev/null || true
  sleep 1
  open "/Library/Input Methods/DoubaoIme.app" 2>/dev/null || true
fi

if [ -d "/Library/Input Methods/Chatterfly.app" ]; then
  "$ROOT/scripts/set-ime-mic.sh" "Google TV 2ch" >/dev/null 2>&1 || true
  open "/Library/Input Methods/Chatterfly.app" 2>/dev/null || true
fi

sleep 2
echo "已重启麦克风桥和输入法。请按住语音键再试一次。"
