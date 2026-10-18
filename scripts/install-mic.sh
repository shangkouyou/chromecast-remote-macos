#!/bin/bash
# 安装/启动“遥控器麦克风 → Google TV 2ch 虚拟声卡”后台桥。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/tools/remote-mic/RemoteMic"
DEVICE="${GVTV_AUDIO_DEVICE:-BlackHole 2ch}"
PLIST="$HOME/Library/LaunchAgents/com.gvtv.remote-mic.plist"
LABEL="com.gvtv.remote-mic"
UID_NUM="$(id -u)"

[ -x "$BIN" ] || "$ROOT/tools/remote-mic/build.sh"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BIN}</string>
    <string>--device</string>
    <string>${DEVICE}</string>
  </array>
  <key>WorkingDirectory</key><string>${ROOT}/tools/remote-mic</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/RemoteMic.out.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/RemoteMic.err.log</string>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/${UID_NUM}" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$PLIST"
launchctl enable "gui/${UID_NUM}/${LABEL}"
launchctl kickstart -k "gui/${UID_NUM}/${LABEL}"

echo "已启动：遥控器麦克风 → ${DEVICE}"
echo "在输入法/语音软件的麦克风里选择：${DEVICE}"
echo "日志：~/Library/Logs/RemoteMic.log"
