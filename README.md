# rk3528_armbian — MangoPi M28K (RK3528) 单一 SDK

> **一个目录搞定一切**: 框架 / 我们的改动 / 自研源码 / 构建脚本 / 文档 都在这里。
> 产物 (镜像 · 编译日志 · JDK) 在 `artifacts/`, **不入仓**。

板子: **MangoPi M28K** (Rockchip RK3528, 4×Cortex-A53, HDMI, GbE, PCIe2x1, AIC8800 WiFi6+BT)
目标: 把这板子做成 **原生 CarPlay 车机端** (不挂 dongle)

---

## 📂 目录 (只有 7 项)

| 目录 | 是什么 | 入仓 |
|---|---|---|
| `framework/` | **armbian/build** 构建框架 (我们只读它, 不改它) | ❌ 可 `scripts/init-framework.sh` 重建 |
| `userpatches/` | **我们对镜像的全部改动** (armbian 官方注入点) | ✅ |
| `src/` | 自研 / 移植源码: `aic8800-sdio` 驱动 · `playport` Linux 移植 | ✅ |
| `scripts/` | 构建 / 部署 / 烧录 / 初始化 | ✅ |
| `docs/` | 文档 | ✅ |
| `artifacts/` | 镜像 · 驱动包 · 编译日志 · JDK21 · playport dist | ❌ 本机产物 |
| `README.md` | 本文件 | ✅ |

**为什么这么分**: 只有 `userpatches/` + `src/` + `scripts/` 是"我们的东西", 其余不是框架就是产物。
换台机器只要 clone 本仓 + 跑 `scripts/init-framework.sh` 就能复现。

---

## 🚀 从零到镜像 (3 步)

```sh
# 1) 拉框架 (首次; 20 GB 缓存由构建自己下载)
./scripts/init-framework.sh

# 2) 出镜像 (产物在 framework/output/images/)
./scripts/build-image.sh            # 全量
./scripts/build-image.sh --no-clean # 复用上次编译缓存, 快

# 3) 烧 SD 卡
sudo ./scripts/flash-sd.sh /dev/sdX artifacts/images/m28k-trixie-*.img
```

## 🔧 驱动 (AIC8800 WiFi6 + BT)

内核 6.1.172-vendor **没有** aic8800 (WiFi 必须外置编), 但**自带** `hci_aic.c` (BT 走 serdev)。见 `src/aic8800-sdio/README.md`。

```sh
./scripts/build-driver.sh          # 出 ~/.../artifacts/driver/aic8800-m28k-*.tar.gz
```

## 📺 PlayPort (CarPlay 协议端)

上游 [youcci/playport](https://github.com/youcci/playport), 我们只做了 **Linux 化** (蓝牙桥 + WiFi 信息)。见 `src/playport/README.md`。

---

## 关键路径 (220 = dev-u22)

| 东西 | 路径 |
|---|---|
| 本 SDK | `/home/bob/rk3528_armbian` |
| 镜像 | `artifacts/images/m28k-trixie-v3-playport.img` (2.6 GB) |
| 驱动包 | `artifacts/build/aic8800-m28k-6.1.172-vendor-rk35xx-*.tar.gz` |
| JDK21 | `artifacts/tools/jdk21` |

## 历史

- 2026-10-29 出第一版镜像 `m28k-trixie-v1-cachekernel.img`
- 2026-10-29 出 PlayPort 版 `m28k-trixie-v3-playport.img`
- 2026-10-30 AIC8800 WiFi+BT 适配 (编译侧)
- 2026-10-30 **目录重组**: 由 `~/rk3528-armbian/{build,docs,drivers,images,logs,playport,sdk,tools}` 8 个平级目录
  收敛为本仓 (`userpatches` 从框架里提出来, 框架降为可重建的 `framework/`)

## License

本仓自有代码 (scripts / userpatches / playport 移植) — 内部使用。
`src/aic8800-sdio` 来自 Rockchip/AMPAK 厂商驱动, `src/playport` 上游为 youcci/playport — 各自遵循其原始许可。
