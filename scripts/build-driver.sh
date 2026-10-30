#!/bin/bash
# 编 AIC8800 (WiFi + BT 通道) 三个 out-of-tree 模块并打成部署包
# 产物: artifacts/build/aic8800-m28k-<内核版本>-<时间戳>.tar.gz
set -euo pipefail

SDK="$(cd "$(dirname "$0")/.." && pwd)"
FW="$SDK/framework"
SRC="$SDK/src/aic8800-sdio/aic8800"

KDIR="${KDIR:-$(ls -d "$FW"/cache/sources/linux-kernel-worktree/6.1__rk35xx__arm64 2>/dev/null | head -1)}"
[ -d "$KDIR" ] || { echo "✗ 找不到内核树, 先跑一次 build-image.sh 让框架把内核拉下来" >&2; exit 1; }

REL="$(cat "$KDIR/include/config/kernel.release" 2>/dev/null | tr -d '\n')"
echo "→ 内核树: $KDIR"
echo "→ vermagic: $REL"

cd "$SDK/src/aic8800-sdio"
K="$KDIR" B="$SRC" REL="$REL" ./build.sh

mkdir -p "$SDK/artifacts/build"
cp -f "$SDK"/build/aic8800-*.tar.gz "$SDK/artifacts/build/" 2>/dev/null || true
echo "✓ 产物:"; ls -lh "$SDK"/artifacts/build/aic8800-*.tar.gz 2>/dev/null | tail -2
