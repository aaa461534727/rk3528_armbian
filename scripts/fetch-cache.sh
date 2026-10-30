#!/bin/bash
# fetch-cache.sh —— 拉「编译期联网物料」, 让 clone 本仓的机器断网也能编镜像
#
# armbian 构建会从网上抓这些东西, 本仓已打包成 GitHub Release 物料:
#   cache/git-bare/            内核 / u-boot 裸库 (git clone --bare 的产物)
#   cache/sources/             驱动 / 固件 / rkbin 源码树 (git clone 的产物)
#   cache/aptcache/            debootstrap + apt 的包索引与 .deb
#   cache/patch/ rootfs/ pip/ initrd/ tools/ memoize/ git-bundles/
#   cache/apt-utils-json/      github.armbian.com/*.json 的本地副本 (base-files 版本表)
#   cache/keyrings/            发行版 keyring — 还原时装到 /armbian/cache/keyrings
# 另有 framework 源码快照 (armbian/build 固定 commit), 省掉 git clone。
#
# 用法:
#   ./scripts/fetch-cache.sh                       从 GitHub Release 下 (断点续传)
#   ./scripts/fetch-cache.sh --check               只检查齐不齐 (0=齐)
#   ./scripts/fetch-cache.sh --file <dir>          从本地目录 / 移动硬盘导入
#   ./scripts/fetch-cache.sh --rsync <host:path>   从另一台机器直接拉
#
# 凭据: 私仓下载需要 token。读环境变量 GITHUB_TOKEN, 或 ~/.gh_token。
set -uo pipefail

SDK="$(cd "$(dirname "$0")/.." && pwd)"
FW="$SDK/framework"
CACHE="$FW/cache"
DL="$SDK/.dl-tmp"

REPO=aaa461534727/rk3528_armbian
TAG=buildcache-20261030
CACHE_PKG=armbian-cache-20261030.tar.zst
SUMS=armbian-cache-20261030.sha256

say() { echo "[fetch-cache] $*"; }
die() { echo "[fetch-cache] ✗ $*" >&2; exit 1; }

need_token() {
  if [ -z "${GITHUB_TOKEN:-}" ] && [ -f "$HOME/.gh_token" ]; then
    GITHUB_TOKEN="$(tr -d '\r\n' < "$HOME/.gh_token")"
    export GITHUB_TOKEN
  fi
}

# ---------- 就位判定 ----------
cache_ok() {
  local d
  for d in git-bare sources aptcache memoize apt-utils-json; do
    [ -d "$CACHE/$d" ] || return 1
  done
  [ -f "$CACHE/apt-utils-json/base-files.json" ] || return 1
  return 0
}
fw_ok() { [ -f "$FW/compile.sh" ] && [ -f "$FW/lib/library-functions.sh" ]; }

state() {
  if cache_ok; then echo "cache:     OK ($(du -sh "$CACHE" 2>/dev/null | cut -f1))"; else echo "cache:     缺"; fi
  if fw_ok; then echo "framework: OK"; else echo "framework: 缺"; fi
}

# ---------- GitHub Release 通道 (私仓必须走 API asset, 不能用 browser_download_url) ----------
gh_asset_id() {
  local name="$1"
  curl -fsS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases/tags/$TAG" 2>/dev/null |
    python3 -c 'import sys,json
n=sys.argv[1]
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
for a in d.get("assets",[]):
    if a["name"]==n: print(a["id"]); break' "$name"
}

gh_get() {
  local name="$1" out="$2" id
  id="$(gh_asset_id "$name")"
  [ -n "$id" ] || die "Release $TAG 里没有 asset: $name"
  curl -fL -C - --retry 10 --retry-delay 15 --retry-all-errors --connect-timeout 20 \
    -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/octet-stream" \
    "https://api.github.com/repos/$REPO/releases/assets/$id" -o "$out" ||
    die "$name 下载失败 (可直接重跑, 会续传)"
}

# ---------- 取 framework 包名 (名字里带 commit, 从清单里找) ----------
fw_pkg_name() {
  local dir="$1"
  local n
  n=$(ls "$dir"/armbian-framework-*.tar.zst 2>/dev/null | head -1)
  [ -n "$n" ] && { basename "$n"; return 0; }
  [ -f "$dir/$SUMS" ] && awk '$2 ~ /^armbian-framework-.*\.tar\.zst$/ {print $2; exit}' "$dir/$SUMS"
}

# ---------- 还原 ----------
restore_framework() {
  local tarball="$1"
  if fw_ok; then say "framework 已就位, 跳过"; return 0; fi
  say "解 framework 快照 ($(basename "$tarball")) ..."
  tar --zstd -xf "$tarball" -C "$SDK" || die "framework 解包失败"
  fw_ok || die "解包后仍没有 framework/compile.sh"
}

install_keyrings() {
  [ -d "$CACHE/keyrings" ] || return 0
  say "装 keyrings -> /armbian/cache/keyrings (需要 sudo)"
  sudo mkdir -p /armbian/cache
  sudo cp -a "$CACHE/keyrings" /armbian/cache/ || say "! keyrings 装失败 (只影响发行版签名校验)"
}

# ---------- 参数 ----------
MODE=fetch
ARG=""
case "${1:-}" in
  --check) MODE=check ;;
  --file)  MODE=file;  ARG="${2:?--file 需要目录}" ;;
  --rsync) MODE=rsync; ARG="${2:?--rsync 需要 host:path}" ;;
  "") ;;
  *) die "未知参数 $1 (支持 --check / --file <dir> / --rsync <host:path>)" ;;
esac

if [ "$MODE" = check ]; then
  state
  cache_ok && fw_ok && exit 0
  exit 1
fi

mkdir -p "$DL"

if [ "$MODE" = fetch ]; then
  need_token
  [ -n "${GITHUB_TOKEN:-}" ] || die "私仓需要 token: export GITHUB_TOKEN=... 或 echo xxx > ~/.gh_token"
  say "从 Release $TAG 拉清单"
  gh_get "$SUMS" "$DL/$SUMS"
  FW_PKG="$(fw_pkg_name "$DL")"
  [ -n "$FW_PKG" ] || die "清单里没有 armbian-framework-*.tar.zst"
  say "framework 包: $FW_PKG"
  local_n=0
  while read -r _sum name; do
    [ -n "${name:-}" ] || continue
    gh_get "$name" "$DL/$name"
    local_n=$((local_n + 1))
    say "  已下 $local_n: $name"
  done < "$DL/$SUMS"
  say "校验 sha256 ..."
  (cd "$DL" && sha256sum -c "$SUMS") || die "sha256 校验失败, 删掉 $DL 重来"
  say "拼分片并解 cache (几 GB, 要几分钟) ..."
  mkdir -p "$FW"
  cat "$DL"/$CACHE_PKG.part* | tar --zstd -xf - -C "$FW" --skip-old-files || die "cache 解包失败"
  restore_framework "$DL/$FW_PKG"
  install_keyrings
  say "清理临时文件 $DL"
  rm -rf "$DL"
fi

if [ "$MODE" = rsync ]; then
  say "从 $ARG 拉 (会续传)"
  mkdir -p "$FW"
  rsync -av --partial --info=progress2 \
    "$ARG/$SUMS" "$ARG"/$CACHE_PKG.part* "$ARG"/armbian-framework-*.tar.zst "$SDK/" ||
    die "rsync 失败"
  MODE=file
  ARG="$SDK"
fi

if [ "$MODE" = file ]; then
  [ -f "$ARG/$SUMS" ] || die "$ARG 里没有 $SUMS"
  [ -f "$ARG/$CACHE_PKG.part00" ] || die "$ARG 里没有 $CACHE_PKG.part00"
  FW_PKG="$(fw_pkg_name "$ARG")"
  [ -n "$FW_PKG" ] || die "$ARG 里没有 armbian-framework-*.tar.zst"
  say "校验 sha256 ..."
  (cd "$ARG" && sha256sum -c "$SUMS") || say "! 清单校验不通过, 仍继续 (可能只拷了部分)"
  say "解 cache ..."
  mkdir -p "$FW"
  cat "$ARG"/$CACHE_PKG.part* | tar --zstd -xf - -C "$FW" --skip-old-files || die "cache 解包失败"
  restore_framework "$ARG/$FW_PKG"
  install_keyrings
fi

say "完成:"
state
echo
say "下一步: ./scripts/build-image.sh --offline"
