#!/bin/bash
# 让 App 在登录时自动打开（不改变 App 的权限）。
set -euo pipefail
PLIST="$HOME/Library/LaunchAgents/com.gvtv.app.plist"
LABEL="com.gvtv.app"
UID_NUM="$(id -u)"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>/Applications/Google TV Remote.app</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST_EOF
launchctl bootout "gui/${UID_NUM}" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$PLIST"
echo "已设置登录自动打开：Google TV Remote"
