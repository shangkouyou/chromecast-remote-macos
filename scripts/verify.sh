#!/bin/bash
# 一键体检 + 单元测试。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
echo "== doctor =="
./bin/gvtv-remote doctor
echo
echo "== app selftest =="
APP_BIN="$ROOT/app/dist/Google TV Remote.app/Contents/MacOS/GoogleTVRemote"
if [ -x "$APP_BIN" ]; then
  "$APP_BIN" --selftest
else
  echo "（未构建 App，跳过；运行 ./app/build.sh）"
fi

echo
echo "== unit tests =="
PYTHONPATH="$ROOT" /usr/bin/python3 -m unittest discover -s tests -v
