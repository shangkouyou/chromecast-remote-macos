#!/bin/bash
# 设置遥控器麦克风增益（dB），下一次按住语音键生效。
# 用法：./scripts/set-gain.sh 10
set -euo pipefail
GAIN="${1:?用法: set-gain.sh <dB，-24..24>}"
DIR="$HOME/Library/Application Support/gvtv-remote"
mkdir -p "$DIR"
python3 - "$GAIN" "$DIR/mic-config.json" <<'PY'
import json, sys
gain = max(-24.0, min(24.0, float(sys.argv[1])))
with open(sys.argv[2], "w", encoding="utf-8") as f:
    json.dump({"gain_db": gain}, f, ensure_ascii=False)
print(f"已设置 {gain:+.1f} dB，下一次按住语音键生效")
PY
