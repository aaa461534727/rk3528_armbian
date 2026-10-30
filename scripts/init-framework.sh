#!/bin/bash
# 拉取 / 更新 armbian/build 框架到 framework/
# 用法: ./scripts/init-framework.sh [--update]
set -euo pipefail

SDK="$(cd "$(dirname "$0")/.." && pwd)"
FW="$SDK/framework"
ARMBRANCH="${ARMBIAN_BRANCH:-main}"

if [ -d "$FW/.git" ]; then
    echo "✓ framework 已存在: $(git -C "$FW" log --oneline -1)"
    if [ "${1:-}" = "--update" ]; then
        git -C "$FW" fetch --depth 1 origin "$ARMBRANCH"
        git -C "$FW" reset --hard FETCH_HEAD
        echo "✓ 已更新到 $(git -C "$FW" log --oneline -1)"
    fi
    exit 0
fi

echo "→ clone armbian/build 到 $FW (浅克隆)"
git clone --depth 1 --branch "$ARMBRANCH" https://github.com/armbian/build.git "$FW"
mkdir -p "$FW/userpatches"
echo "✓ 完成: $(git -C "$FW" log --oneline -1)"
echo "  下一步: ./scripts/build-image.sh"
