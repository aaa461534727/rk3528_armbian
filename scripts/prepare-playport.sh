#!/bin/bash
# 把 playport 的 jar/web 灌进 userpatches/overlay (它们太大, 不入仓)
#   来源优先级: artifacts/playport-dist  >  重新 gradle 构建
set -euo pipefail

SDK="$(cd "$(dirname "$0")/.." && pwd)"
OVL="$SDK/userpatches/overlay/opt/playport"
DIST="$SDK/artifacts/playport-dist"

[ -d "$DIST" ] || { echo "✗ 缺 $DIST (playport 构建产物), 见 src/playport/README.md" >&2; exit 1; }

mkdir -p "$OVL/lib" "$OVL/web"
cp -a "$DIST/lib/." "$OVL/lib/"
if [ -d "$DIST/web-dist" ]; then rm -rf "$OVL/web"; cp -a "$DIST/web-dist" "$OVL/web"; fi
echo "✓ overlay 已灌入: $(du -sh "$OVL" | cut -f1)"
echo "  (jars 不入仓; 换机器时重跑本脚本)"
