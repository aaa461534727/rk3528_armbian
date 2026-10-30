#!/bin/bash
# 构建 M28K Armbian 镜像
#   ./scripts/build-image.sh            全量 (清 output)
#   ./scripts/build-image.sh --no-clean 复用缓存, 快
#   ./scripts/build-image.sh --driver   顺便重编 aic8800 驱动
#
# 历史成功参数 (2026-10-29 v3): BOARD=mangopi-m28k BRANCH=vendor RELEASE=trixie
#   BUILD_MINIMAL=yes BUILD_DESKTOP=no DOWNLOAD_MIRROR=cn KERNEL_GIT=shallow
#   KERNEL_CONFIGURE=no PREFER_DOCKER=no
set -euo pipefail

SDK="$(cd "$(dirname "$0")/.." && pwd)"
FW="$SDK/framework"
UP="$SDK/userpatches"

[ -d "$FW/.git" ] || { echo "✗ 先跑 ./scripts/init-framework.sh" >&2; exit 1; }

CLEAN=yes
DO_DRIVER=no
for a in "$@"; do
    case "$a" in
        --no-clean) CLEAN=no ;;
        --driver)   DO_DRIVER=yes ;;
        *) echo "未知参数: $a" >&2; exit 1 ;;
    esac
done

[ "$DO_DRIVER" = yes ] && "$SDK/scripts/build-driver.sh"

LOGDIR="$SDK/artifacts/logs"
mkdir -p "$LOGDIR"
STAMP="$(date +%Y%m%d-%H%M)"
LOG="$LOGDIR/build-image-$STAMP.log"

echo "→ 构建 (日志 $LOG)"
cd "$FW"
USERPATCHES_PATH="$UP" ./compile.sh m28k \
    BOARD=mangopi-m28k BRANCH=vendor RELEASE=trixie \
    BUILD_MINIMAL=yes BUILD_DESKTOP=no \
    DOWNLOAD_MIRROR=cn KERNEL_GIT=shallow \
    KERNEL_CONFIGURE=no PREFER_DOCKER=no \
    CLEAN_LEVEL="$([ "$CLEAN" = yes ] && echo "make,debs" || echo "")" \
    2>&1 | tee "$LOG"

IMG="$(ls -t "$FW"/output/images/*.img 2>/dev/null | head -1 || true)"
if [ -n "$IMG" ]; then
    mkdir -p "$SDK/artifacts/images"
    cp -f "$IMG" "$SDK/artifacts/images/"
    echo "✓ 镜像: $SDK/artifacts/images/$(basename "$IMG")"
    md5sum "$SDK/artifacts/images/$(basename "$IMG")"
else
    echo "✗ 未找到镜像, 看日志: $LOG" >&2
    exit 1
fi
