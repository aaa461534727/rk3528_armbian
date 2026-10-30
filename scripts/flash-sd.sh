#!/bin/bash
# 烧镜像到 SD 卡
#   sudo ./scripts/flash-sd.sh /dev/sdX artifacts/images/m28k-trixie-v3-playport.img
set -euo pipefail
DEV="${1:?用法: flash-sd.sh <块设备> <镜像>}"
IMG="${2:?用法: flash-sd.sh <块设备> <镜像>}"

[ -b "$DEV" ] || { echo "✗ $DEV 不是块设备" >&2; exit 1; }
[ -f "$IMG" ] || { echo "✗ 镜像不存在: $IMG" >&2; exit 1; }

lsblk "$DEV"
echo
echo "⚠ 即将覆写 $DEV 的全部数据"
read -r -p "确认? 输入 yes: " a
[ "$a" = yes ] || exit 1

dd if="$IMG" of="$DEV" bs=4M status=progress conv=fsync
sync
echo "✓ 完成"
