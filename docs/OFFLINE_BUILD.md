# 断网编译 (离线构建)

> 目标: 一台**没网**的机器, clone 本仓 + 一份离线物料, 就能编出 M28K 镜像。

## 1. 为什么不能直接断网

armbian 框架的 `OFFLINE_WORK=yes` 只关掉三件事: 主机依赖安装、`git fetch`/`ls-remote`、
时钟同步。构建过程本身还有 3 处硬编码联网, 断了就挂在半路:

| 位置 | 干什么 | 断网后果 | 本仓怎么处理 |
|---|---|---|---|
| `artifact-armbian-base-files` | 请求 `https://github.armbian.com/base-files.json` 查上游 base-files 版本 | `curl` 失败 -> 重试 10 次 -> `Error 1` | `userpatches/extensions/offline-cache.sh` 拦截该 URL, 读 `cache/apt-utils-json/base-files.json` |
| `chroot_sdcard_apt_get_update` | 在 rootfs 里 `apt-get update` | 连不上镜像站, 索引为空 -> 后续装包全失败 | 扩展直接跳过 update, 用 `cache/aptcache/lists/<rel>-<arch>` 里已缓存的索引 |
| `customize-image.sh` 里的 `apt-get install` | 装 openjdk / bluez / iw / rfkill / openssh | 缺 deb -> `E: Unable to fetch` | 扩展在 `pre_customize_image` 把 cache 的 lists/archives 挂进 SDCARD |

除此之外的联网都发生在 **下载阶段**(git clone 内核/u-boot/驱动/固件、apt debootstrap),
这些产物全在 `cache/` 里, 由 `scripts/fetch-cache.sh` 还原。

## 2. 三步

```sh
# 1) 拉本仓
git clone https://github.com/aaa461534727/rk3528_armbian.git
cd rk3528_armbian

# 2) 一次性准备离线物料 (需要网, 或从别的机器拷)
export GITHUB_TOKEN=...            # 私仓; 也可写入 ~/.gh_token
./scripts/fetch-cache.sh           # 断点续传; 已就位会跳过

# 3) 断网构建
./scripts/build-image.sh --offline
```

物料要 5 GB 左右下载、解出来约 8 GB。`fetch-cache.sh --check` 可随时看齐不齐。

也可以不用 GitHub:

```sh
./scripts/fetch-cache.sh --rsync bob@10.0.100.220:~/rk3528_armbian
./scripts/fetch-cache.sh --file /media/usb/rk3528-cache
```

## 3. 物料清单 (Release `buildcache-20261030`)

| 包 | 体积 | 是什么 |
|---|---|---|
| `armbian-framework-<sha>.tar.zst` | ~300 MB | `armbian/build` 源码快照 (固定 commit, 不含 cache) |
| `armbian-cache-20261030.tar.zst.partNN` | ~5 GB (分片 1500 MiB) | 下面这些 |
| `armbian-cache-20261030.sha256` | 1 KB | 分片 + framework 的 sha256 |

`cache/` 里装的:

| 目录 | 体积 | 编译期从哪来 |
|---|---|---|
| `git-bare/shallow-kernel-6.1` · `git-bare/u-boot` | 2.9 GB | `git clone --bare` 内核 / u-boot |
| `sources/rtl*` `sources/uwe5622` `sources/*-git` | ~800 MB | WiFi/固件/rkbin 的 `git clone` |
| `aptcache/` | ~500 MB | `apt-get download` 与 debootstrap 的 .deb + 包索引 |
| `patch/kernel-drivers` | 229 MB | 驱动补丁下载 |
| `rootfs/` | 119 MB | 预生成 rootfs 压缩包 |
| `pip/` `initrd/` `tools/` `memoize/` `git-bundles/` | ~120 MB | 杂项工具与缓存 |
| `apt-utils-json/` | 4 KB | `github.armbian.com/*.json` 本地副本 |
| `keyrings/` | 288 KB | 发行版 keyring, 还原时装到 `/armbian/cache/keyrings` |

**不发** `cache/sources/linux-kernel-worktree` (12 GB) 与 `u-boot-worktree`:
两者能从 `git-bare` 重建。若发放 `output/debs`, 内核就不会重编(更快), 但那是编译
产物不是下载物料, 本仓不放在发布件里。

## 4. 怎么证明真能离线

`unshare -n` 摘掉整个网络命名空间, 只剩 `lo`, 任何外网访问必然失败:

```sh
sudo unshare -n -- bash -c 'ip link set lo up; ./scripts/build-image.sh --offline'
```

2026-10-30 在 220 (4 核 / 7 GB, Ubuntu 22.04) 上按上面命令跑通, 产出
`Armbian-unofficial_26.11.0-trunk_Mangopi-m28k_trixie_vendor_6.1.172_minimal.img`
(3024 MiB, sha256 `7bd05818...`)。

## 5. 注意

- **别改 `DOWNLOAD_MIRROR`**。apt 索引文件名带源主机名 (`deb.debian.org_...`), 离线构建用
  `cn` 镜像会找不到自己那份索引。要换源就得重新生成一份 cache。
- **`OFFLINE_WORK=yes` 时不会装主机依赖**。宿主机需要事先具备 `qemu-user-static`
  (x86 上编 arm64 rootfs)、`e2fsprogs`、`zstd` 等; 有网时先跑一次在线构建即可。
- 缓存里的 deb 有版本时效。上游删包 (security 源滚动更新) 会导致 `apt-get` 找不到旧版,
  届时重跑一次在线 `./scripts/build-image.sh` 刷新 cache 再重新打物料。
