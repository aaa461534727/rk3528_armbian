#!/bin/bash
# build-image.sh —— 出 M28K Armbian 镜像
#   ./scripts/build-image.sh              全量 (清 output)
#   ./scripts/build-image.sh --no-clean   复用上次编译缓存, 快
#   ./scripts/build-image.sh --offline    断网构建 (要求先跑 ./scripts/fetch-cache.sh)
#   ./scripts/build-image.sh --driver     顺便重编 aic8800 驱动
#
# 历史成功参数 (2026-10-29 v3): BOARD=mangopi-m28k BRANCH=vendor RELEASE=trixie
#   BUILD_MINIMAL=yes BUILD_DESKTOP=no DOWNLOAD_MIRROR=cn KERNEL_GIT=shallow
#   KERNEL_CONFIGURE=no PREFER_DOCKER=no
set -euo pipefail

SDK="$(cd "$(dirname "$0")/.." && pwd)"
FW="$SDK/framework"
UP="$SDK/userpatches"

[ -f "$FW/compile.sh" ] || {
    echo "✗ 先跑 ./scripts/init-framework.sh (有网) 或 ./scripts/fetch-cache.sh (离线物料)" >&2
    exit 1
}

CLEAN=yes
DO_DRIVER=no
OFFLINE=no
for a in "$@"; do
    case "$a" in
        --no-clean) CLEAN=no ;;
        --driver)   DO_DRIVER=yes ;;
        --offline)  OFFLINE=yes ;;
        *) echo "未知参数: $a" >&2; exit 1 ;;
    esac
done

EXTRA=()
EXT_NAME=""
if [ "$OFFLINE" = yes ]; then
    if ! "$SDK/scripts/fetch-cache.sh" --check >/dev/null 2>&1; then
        echo "✗ --offline 要求离线物料已就位, 但还缺东西:" >&2
        "$SDK/scripts/fetch-cache.sh" --check >&2 || true
        echo "  先跑: ./scripts/fetch-cache.sh" >&2
        exit 1
    fi
    # OFFLINE_WORK=yes: 框架跳过主机依赖安装 / git fetch / ls-remote / 时钟同步
    # offline-cache 扩展: 补框架没管的 3 处 (base-files.json / apt update / customize 阶段 apt)
    EXTRA=(OFFLINE_WORK=yes ENABLE_EXTENSIONS=offline-cache)
    EXT_NAME=offline-cache
    export OFFLINE_WORK=yes
    export ENABLE_EXTENSIONS=$EXT_NAME
    echo "→ 离线模式: OFFLINE_WORK=yes + 扩展 $EXT_NAME"
fi

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
    "${EXTRA[@]+"${EXTRA[@]}"}" \
    2>&1 | tee "$LOG"

IMG="$(ls -t "$FW"/output/images/*.img 2>/dev/null | head -1 || true)"
if [ -n "$IMG" ]; then
    mkdir -p "$SDK/artifacts/images"
    cp -f "$IMG" "$SDK/artifacts/images/"
    echo "✓ 镜像: $SDK/artifacts/images/$(basename "$IMG")"
    sha256sum "$SDK/artifacts/images/$(basename "$IMG")"
else
    echo "✗ 未找到镜像, 看日志: $LOG" >&2
    exit 1
fi
