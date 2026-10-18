#!/bin/bash
set -euo pipefail
PLIST="$HOME/Library/LaunchAgents/com.gvtv.remote.plist"
UID_NUM="$(id -u)"
launchctl bootout "gui/${UID_NUM}" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
echo "已卸载 LaunchAgent。配置保留在 ~/.config/gvtv-remote/。"
