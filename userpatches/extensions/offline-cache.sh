#
# offline-cache.sh -- 断网构建扩展 (由 scripts/build-image.sh --offline 自动启用)
#
# armbian 框架没有"完全断网"模式: OFFLINE_WORK=yes 只跳过主机依赖安装 / git fetch /
# 时钟同步, 构建过程中还有三处硬编码联网点。本扩展只在 OFFLINE_WORK=yes 时生效,
# 把这三处接到 <SDK>/framework/cache/ 下的本地缓存, 有网构建行为完全不变。
#
# 1) artifact-armbian-base-files 的 prepare_version 无条件请求
#    https://github.armbian.com/base-files.json 解析上游 base-files 版本。
#    -> 拦截这一类 URL, 改读 cache/apt-utils-json/<pkg>.json
#
# 2) rootfs 阶段的 chroot_sdcard_apt_get_update 必然连镜像站。
#    框架自己会把 cache/aptcache/lists/<rel>-<arch> bind 到 chroot 的
#    /var/lib/apt/lists, .deb bind 到 /var/cache/apt/archives, 所以断网时跳过 update。
#    注意: 索引按下载源主机名命名, 离线构建别改 DOWNLOAD_MIRROR。
#
# 3) customize-image.sh 阶段框架不再挂 apt 缓存, 脚本里的 apt-get 会真去联网。
#    -> pre_customize_image 时把 cache 里的 lists / archives 挂进 SDCARD,
#       post_customize_image 时卸掉 (不落进镜像)。

if [[ "${OFFLINE_WORK:-}" == "yes" ]]; then
  # ---- 1) base-files.json: 走本地副本 ----
  function curl() {
    local -a args=("$@")
    local url="" out="" i
    for ((i = 0; i < ${#args[@]}; i++)); do
      case "${args[i]}" in
        -o | --output) out="${args[i + 1]}" ;;
        http://* | https://*) url="${args[i]}" ;;
      esac
    done
    if [[ "${url}" == https://github.armbian.com/*.json ]]; then
      local name="${url##*/}"
      local json_dir="${SRC}/cache/apt-utils-json"
      if [[ -f "${json_dir}/${name}" ]]; then
        display_alert "curl (offline)" "serving ${name} from ${json_dir}" "info"
        if [[ -n "${out}" ]]; then cp -f "${json_dir}/${name}" "${out}"; else cat "${json_dir}/${name}"; fi
        return 0
      fi
      display_alert "curl (offline)" "no local copy for ${name} in ${json_dir}, will try network" "wrn"
    fi
    command curl "$@"
  }

  # ---- 2) chroot 里的 apt-get update: 用缓存索引, 不联网 ----
  function chroot_sdcard_apt_get_update() {
    local lists_dir="${SRC}/cache/aptcache/lists/${RELEASE}-${ARCH}"
    local count=0
    if [[ -d "${lists_dir}" ]]; then
      count=$(find "${lists_dir}" -maxdepth 1 -type f -name "*_Packages" 2>/dev/null | wc -l)
    fi
    if (( count > 0 )); then
      display_alert "apt-get update (offline)" "skipped; using ${count} cached index files from ${lists_dir}" "wrn"
      return 0
    fi
    display_alert "apt-get update (offline)" "no cached package indexes under ${lists_dir}" "err"
    return 1
  }

  # ---- 3) customize-image.sh 阶段: 挂上本地 apt 缓存 ----
  function pre_customize_image__offline_cache() {
    local rel_arch="${RELEASE}-${ARCH}"
    local lists_dir="${SRC}/cache/aptcache/lists/${rel_arch}"
    local debs_dir="${SRC}/cache/aptcache/${rel_arch}/archives"
    [[ -d "${lists_dir}" ]] || return 0
    mkdir -p "${SDCARD}/var/lib/apt/lists" "${SDCARD}/var/cache/apt/archives"
    mountpoint -q "${SDCARD}/var/lib/apt/lists" || mount --bind "${lists_dir}" "${SDCARD}/var/lib/apt/lists"
    if [[ -d "${debs_dir}" ]]; then
      mountpoint -q "${SDCARD}/var/cache/apt/archives" || mount --bind "${debs_dir}" "${SDCARD}/var/cache/apt/archives"
    fi
    display_alert "offline apt cache mounted for customize-image" "${rel_arch}" "info"
  }

  function post_customize_image__offline_cache() {
    mountpoint -q "${SDCARD}/var/cache/apt/archives" && umount "${SDCARD}/var/cache/apt/archives" || true
    mountpoint -q "${SDCARD}/var/lib/apt/lists" && umount "${SDCARD}/var/lib/apt/lists" || true
    return 0
  }
fi
