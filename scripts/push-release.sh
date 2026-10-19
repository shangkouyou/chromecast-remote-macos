#!/bin/bash
# GitHub 解封后执行：推送 main + tag，并创建 Release。
# 用法：./scripts/push-release.sh [tag]   默认 v1.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-v1.1.0}"
GH_BIN="${GH_BIN:-gh}"

if ! command -v "$GH_BIN" >/dev/null 2>&1; then
    echo "找不到 gh CLI，请先安装或设置 GH_BIN=/path/to/gh" >&2
    exit 1
fi

"$GH_BIN" auth status
git push origin main
git push origin "$VERSION"
"$GH_BIN" release create "$VERSION" \
    --title "v${VERSION#v} — 按需虚拟管道" \
    --notes-file "docs/releases/${VERSION#v}.md"
