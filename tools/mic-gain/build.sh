#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/MicGain.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library MicGain.swift -o "$APP/Contents/MacOS/MicGain"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built: $APP"
