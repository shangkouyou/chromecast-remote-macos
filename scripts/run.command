#!/bin/bash
# 双击运行：在终端窗口里启动映射服务（Ctrl-C 退出）。
cd "$(dirname "$0")/.."
exec ./bin/gvtv-remote run "$@"
