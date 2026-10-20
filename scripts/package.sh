#!/bin/bash
# 打本地发布包：源码 tar.gz + 含 .git 的仓库备份 + SHA256。
# 用法：./scripts/package.sh [tag]   默认 v1.2.0
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-v1.2.0}"
VERSION_NUM="${VERSION#v}"
DIST="dist"
mkdir -p "$DIST"

git archive --format=tar.gz --prefix="gvtv-remote-${VERSION_NUM}/" \
    -o "$DIST/gvtv-remote-${VERSION_NUM}-src.tar.gz" "$VERSION"

STAMP="$(date +%Y%m%d-%H%M%S)"
REPO_NAME="$(basename "$PWD")"
tar -czf "$DIST/gvtv-remote-repo-${STAMP}.tar.gz" \
    --exclude="${REPO_NAME}/${DIST}" \
    --exclude='.DS_Store' \
    -C "$(dirname "$PWD")" "$REPO_NAME"

( cd "$DIST" && shasum -a 256 *.tar.gz > SHA256SUMS.txt )
echo "打包完成："
ls -lh "$DIST"
