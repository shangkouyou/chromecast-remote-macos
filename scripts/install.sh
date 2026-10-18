#!/bin/bash
# 安装为登录自启的 LaunchAgent（可选）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY=/usr/bin/python3
CONFIG_DIR="$HOME/.config/gvtv-remote"
PLIST="$HOME/Library/LaunchAgents/com.gvtv.remote.plist"
LABEL="com.gvtv.remote"
UID_NUM="$(id -u)"

mkdir -p "$CONFIG_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
if [ ! -f "$CONFIG_DIR/mapping.json" ]; then
  cp "$ROOT/config/mapping.json" "$CONFIG_DIR/mapping.json"
  echo "已写入默认配置: $CONFIG_DIR/mapping.json"
fi

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${PY}</string>
    <string>-m</string>
    <string>gvtv_remote</string>
    <string>run</string>
    <string>--config</string>
    <string>${CONFIG_DIR}/mapping.json</string>
  </array>
  <key>WorkingDirectory</key><string>${ROOT}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PYTHONPATH</key><string>${ROOT}</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key><false/>
  </dict>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>${HOME}/Library/Logs/gvtv-remote.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/gvtv-remote.err.log</string>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/${UID_NUM}" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$PLIST"
launchctl enable "gui/${UID_NUM}/${LABEL}"
launchctl kickstart -k "gui/${UID_NUM}/${LABEL}"

echo
echo "已安装并启动 LaunchAgent: ${LABEL}"
echo "日志: ~/Library/Logs/gvtv-remote.log"
echo
echo "首次使用还差权限（必须，否则收不到/发不出按键）："
echo "  1) 系统设置 → 隐私与安全性 → 输入监控：勾选 /usr/bin/python3"
echo "  2) 系统设置 → 隐私与安全性 → 辅助功能：勾选 /usr/bin/python3"
echo "  3) 修改权限后执行: launchctl kickstart -k gui/${UID_NUM}/${LABEL}"
echo
echo "也可以不用 LaunchAgent，直接双击 scripts/run.command 在终端里运行（沿用终端权限）。"
