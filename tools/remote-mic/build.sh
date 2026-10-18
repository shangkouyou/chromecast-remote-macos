#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swiftc -O "$ROOT/RemoteMic.swift" -o "$ROOT/RemoteMic"
echo "built: $ROOT/RemoteMic"
