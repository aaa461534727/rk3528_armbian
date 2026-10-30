#!/bin/bash
# build.sh — 交叉编译 AIC8800 SDIO WiFi+BT 三个模块 (Armbian 6.1 vendor), 组装 deploy/ 并打包
# 用法: ./build.sh [clean]
# 前置: 内核树已由 armbian 编译过 (.config / Module.symvers / autoconf.h 都在)
set -e
cd "$(dirname "$0")"

K=${KDIR:-/home/bob/rk3528_armbian/framework/cache/sources/linux-kernel-worktree/6.1__rk35xx__arm64}
REL=${REL:-6.1.172-vendor-rk35xx}
B=$PWD/aic8800/sdio/aic8800
MAKE_ARGS="ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CONFIG_PLATFORM_UBUNTU=y LOCALVERSION=-vendor-rk35xx"

[ -f "$K/Module.symvers" ] || { echo "✗ 内核树未编译: $K"; exit 1; }

if [ "${1:-}" = "clean" ]; then
    for d in aic8800_bsp aic8800_fdrv aic8800_btlpm; do
        make -C "$K" M="$B/$d" $MAKE_ARGS clean >/dev/null 2>&1 || true
    done
fi

echo "=== 1/4 aic8800_bsp ==="
make -C "$K" M="$B/aic8800_bsp" $MAKE_ARGS modules

echo "=== 2/4 aic8800_fdrv (依赖 bsp 导出符号) ==="
make -C "$K" M="$B/aic8800_fdrv" $MAKE_ARGS KBUILD_EXTRA_SYMBOLS="$B/aic8800_bsp/Module.symvers" modules

echo "=== 3/4 aic8800_btlpm ==="
make -C "$K" M="$B/aic8800_btlpm" $MAKE_ARGS KBUILD_EXTRA_SYMBOLS="$B/aic8800_bsp/Module.symvers" modules

echo "=== 4/4 组装 deploy/ ==="
D=$PWD/deploy
mkdir -p "$D/lib/modules/$REL/updates" "$D/lib/firmware/aic8800D80" "$D/boot" "$D/etc/modprobe.d" "$D/etc/modules-load.d" "$D/usr/local/sbin"
cp -f "$B/aic8800_bsp/aic8800_bsp.ko"     "$D/lib/modules/$REL/updates/"
cp -f "$B/aic8800_fdrv/aic8800_fdrv.ko"   "$D/lib/modules/$REL/updates/"
cp -f "$B/aic8800_btlpm/aic8800_btlpm.ko" "$D/lib/modules/$REL/updates/"
cp -f aic8800/fw/aic8800D80/*.bin aic8800/fw/aic8800D80/*.txt "$D/lib/firmware/aic8800D80/"

DTB="$K/arch/arm64/boot/dts/rockchip/rk3528-mangopi-m28k.dtb"
if [ -f "$DTB" ] && strings "$DTB" | grep -q "aic8800-bt"; then
    cp -f "$DTB" "$D/boot/"
    echo "  dtb 带 aic8800-bt 节点 ✓"
else
    echo "  ⚠ dtb 里没有 aic8800-bt 节点, 不打包 (先打 dts 补丁)"
fi

echo "=== 打包 ==="
OUT=~/rk3528_armbian/artifacts/build/aic8800-m28k-$REL-$(date +%Y%m%d-%H%M).tar.gz
tar czf "$OUT" -C "$D" .
md5sum "$OUT"
echo "✅ $OUT"
