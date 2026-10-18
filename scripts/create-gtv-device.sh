#!/bin/bash
# 可选：把已安装的 BlackHole 2ch 复制/改名为独立的 "Google TV 2ch"。
# 仅在本机修改 GPL-3.0 驱动，不随仓库分发；需要管理员密码。
set -euo pipefail

SRC="/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver"
if [ ! -d "$SRC" ]; then
  echo "请先运行 ./scripts/install-blackhole.sh"
  exit 1
fi
if [ -d "/Library/Audio/Plug-Ins/HAL/GoogleTV2ch.driver" ]; then
  echo "Google TV 2ch 已存在。"
  exit 0
fi

WORK="/tmp/GoogleTV2ch.driver"
rm -rf "$WORK"
cp -R "$SRC" "$WORK"
BIN="$(find "$WORK/Contents/MacOS" -type f | head -1)"

python3 - "$BIN" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
data = p.read_bytes()
if b"BlackHole" not in data:
    raise SystemExit("驱动里找不到 BlackHole 标识，版本可能不兼容")
p.write_bytes(data.replace(b"BlackHole", b"Google TV"))
PY

mv "$BIN" "$WORK/Contents/MacOS/GoogleTV2ch"
python3 - "$WORK/Contents/Info.plist" <<'PY'
import pathlib, plistlib, sys
p = pathlib.Path(sys.argv[1])
d = plistlib.loads(p.read_bytes())
d["CFBundleIdentifier"] = "com.gvtv.googletv2ch"
d["CFBundleName"] = "Google TV 2ch"
d["CFBundleExecutable"] = "GoogleTV2ch"
p.write_bytes(plistlib.dumps(d))
PY
rm -rf "$WORK/Contents/_CodeSignature"
codesign --force --deep --sign - "$WORK"

osascript -e 'do shell script "rm -rf /Library/Audio/Plug-Ins/HAL/GoogleTV2ch.driver; cp -R /tmp/GoogleTV2ch.driver /Library/Audio/Plug-Ins/HAL/; chown -R root:wheel /Library/Audio/Plug-Ins/HAL/GoogleTV2ch.driver; killall coreaudiod" with administrator privileges'
echo "已创建独立设备：Google TV 2ch"
echo "在输入法里选择它，并用 GVTV_AUDIO_DEVICE=\"Google TV 2ch\" ./scripts/install-mic.sh"
