#!/bin/bash
# 把 Chatterfly（搜狗输入法）的麦克风固定为虚拟麦克风。
# 解决：连接蓝牙耳机（带麦克风）后，Chatterfly 改用耳机麦克风，遥控器语音不再上屏。
set -euo pipefail
DOMAIN="com.tencent.inputmethod.chatterfly"
KEY="kSGSpeechAudioInputDeviceUID"
NAME="${1:-Google TV 2ch}"

case "$NAME" in
  *"Google TV"*) DEVICE_UID="Google TV2ch_UID" ;;
  *"BlackHole"*) DEVICE_UID="BlackHole2ch_UID" ;;
  *) echo "用法: $0 [Google TV 2ch|BlackHole 2ch]" >&2; exit 1 ;;
esac

if [ ! -d "/Library/Input Methods/Chatterfly.app" ]; then
  echo "未安装 Chatterfly，跳过 IME 麦克风设置"
  exit 0
fi

defaults write "$DOMAIN" "$KEY" -string "$DEVICE_UID"
killall Chatterfly 2>/dev/null || true
echo "已把 Chatterfly 麦克风固定为：$NAME ($DEVICE_UID)"
echo "切换一次输入法或按语音键即可生效。"
