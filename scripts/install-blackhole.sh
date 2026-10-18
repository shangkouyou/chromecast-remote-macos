#!/bin/bash
# 安装 BlackHole 2ch（虚拟声卡，GPL-3.0，来自 Existential Audio）。
# 只在需要“遥控器麦克风 → 虚拟声卡”时才用；普通按键/语音键不需要。
set -euo pipefail

if [ -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" ]; then
  echo "BlackHole 2ch 已安装。"
  exit 0
fi

if command -v brew >/dev/null 2>&1; then
  echo "使用 Homebrew 安装 blackhole-2ch…"
  brew install --cask blackhole-2ch
  echo "完成。设备名：BlackHole 2ch"
  exit 0
fi

echo "未检测到 Homebrew，改用官方 pkg（会弹一次管理员密码）。"
META="$(curl -fsSL https://formulae.brew.sh/api/cask/blackhole-2ch.json)"
URL="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["version"], end="")' <<<"$META")"
URL="https://existential.audio/downloads/BlackHole2ch-${URL}.pkg"
PKG="/tmp/BlackHole2ch.pkg"
echo "下载：$URL"
curl -fL --retry 3 -o "$PKG" "$URL"
osascript -e "do shell script \"installer -pkg '$PKG' -target /\" with administrator privileges"
echo "完成。设备名：BlackHole 2ch"
