# RK3528 / MangoPi M28K 做原生 CarPlay —— 方案与落地路径

> 调研日期 2026-10-30 · 只读取证, 未上板、未改任何 SDK
> 相关: 顶层 `../K230/docs/CARPLAY_FEASIBILITY.md` (K230 的同类调研, 结论是只能挂 dongle; 本板不一样)

---

## 0. 一句话结论

**能做。** 但这块板子能不能做出 CarPlay, 不取决于"协议难不难", 而是取决于**三件事各有归属**:

| 事 | 谁负责 | 现状 |
|---|---|---|
| ① iAP2 + AirPlay + 拆包 | **不写**, 直接复用 PlayPort 的 Kotlin 实现 | 220 上已经 Linux 化 (蓝牙桥重写成 `bt-bridge.py`) |
| ② H.264 硬解 → HDMI 上屏 + 触摸回传 + 音频 | **要自己写**, 这是板子独有的一段 | 未开始, 有 Rockchip mpp 可依赖 |
| ③ MFi 配件身份 (Apple 证书 + 私钥) | **主人自己落实** | 缺; 开源项目用的是从 Carlinkit 固件提取的未授权材料 |

PlayPort 把 ⑤"显示"交给了**浏览器 WebCodecs** —— 板子上不该有浏览器, 这层必须换成原生渲染器。**这就是整个方案的真正工作量所在。**

---

## 0.5 分阶段路线 (2026-10-30 主人定: 先跑通协议, 显示先借 PC 浏览器)

**一句话**: 可行, 而且这是**最短路径** —— 因为"板子出流 + PC 浏览器看"本来就是 PlayPort 的原生形态,
阶段一**一行代码都不用写**, 只需要部署 + 配置。

```
iPhone ──BT(iAP2 over RFCOMM)──► bt-bridge.py ─┐
   │                                           ├─► PlayPort JVM (板子)
   └──WiFi(连到同一个 AP)──AirPlay RTSP 7000───┘        │
                                                       │ WebSocket /ws (:8080)
                                                       ▼
                                        PC 上的 Chrome (WebCodecs 解码 + canvas)
```

| 阶段 | 目标 | 板子做什么 | 要写代码吗 | 验收 |
|---|---|---|---|---|
| **0** | 驱动就位 | AIC8800 WiFi(3 个 ko) + BT(dts + hci_aic) | 否 (已编好) | `wlan0` + `hci0` 出现 |
| **1** | **协议跑通, PC 浏览器看图** | 烧 `m28k-trixie-v3-playport.img` → 装驱动 → 放 identity → 配 WiFi 凭据 → 起 `playport.service` | **否** | iPhone 的「CarPlay 可用车辆」里出现板子; PC 浏览器出画面 + 触摸能点 |
| **2** | 板子本地 HDMI 上屏 | 换成 `playport-render` (自己写) | **是** | 拔掉 PC, 板子自己上屏 + 出声 + 触摸回传 |
| **3** | 稳定/固化 | 驱动并入 userpatches 重烧镜像 | 少量 | 30 min 不掉不花, 延迟达标 |

### 为什么先做阶段 1 (不是"绕路", 是最优顺序)

1. **零开发量**: 220 的 `m28k-trixie-v3-playport.img` 里**已经装好了** —— `/opt/playport`(bin+lib+web+identity)、
   `openjdk-21-jre-headless`、`bluez 5.82`+`bluetoothd`、`wpa_supplicant`+`iw`, 以及已 enable 的
   `playport.service` (参数 `--wireless --bt-bridge /opt/playport/bin/bt-bridge`)。**烧进去就能起。**
2. **它验证的是全案最不确定的三件事**: BT 能不能起 · MFi 能不能过 · iPhone 认不认这个身份。
   这三件只要有一样不成, 阶段 2 写了也白写。
3. **阶段 2 的调试可以完全脱离 iPhone**: 用 220 上的 PlayPort 当服务端喂假流, `playport-render` 离线开发。
   也就是说阶段 2 不依赖阶段 1 通过, 但**先做阶段 1 能避免白写**。

### 阶段一必须满足的前提 (缺一不可)

| 前提 | 现状 | 备注 |
|---|---|---|
| **BT (`hci0`)** | 待上板 | **硬门槛, 绕不过** —— 无线 CarPlay 靠 BT 配对 + 通过 iAP2 把 WiFi 凭据交给 iPhone |
| **WiFi 凭据** | 需手工给 | `WifiInfo.kt` 只能探测 SSID/信道, **探测不到密码** ⇒ 必须 `--wifi-passphrase` 写进 `/etc/default/playport` |
| **MFi 身份** | ✅ 就绪 | 放 `/opt/playport/identity/offline-mfi/` (只放 pk8 + p7b) |
| **PC 浏览器** | 需 Chrome/Edge 94+ | WebCodecs 要求 **HTTPS + secure context**; PlayPort 自带自签证书 + `?token=` 链接, 接受一次告警即可 |
| **同网段** | 一个 AP 即可 | 板子 + iPhone + PC 挂同一个 AP |

### ★ 一个可能大幅降低门槛的点 (未验证)

镜像里**没有 NetworkManager**, 只有 `wpa_supplicant` + `iw` ⇒ `WifiInfo` 走 `iw` 兜底能拿到 SSID/信道,
但**拿不到密码**, 所以无论如何都要手工给 `--wifi-passphrase`。

反过来说: **板子自己不一定非要无线联网**。板子有 GbE 口 —— 只要
① 用 `--wifi-ssid/--wifi-passphrase/--wifi-channel` 手工告诉 iPhone 连哪个 AP,
② 板子 eth0 与那个 AP 桥接到同一网段,
那么**即使 WiFi 驱动只起了一半, 图像通路也能走以太网** (`--bind <eth-ip>`)。
唯一疑问是 jmDNS 能否在 eth 接口上被 iPhone 发现 —— **需实测, 不作承诺**。

---

## 1. 把"原生 CarPlay"拆开看

| 段 | 内容 | 现在有没有 |
|---|---|---|
| ① 无线链路 | BT 配对 → iAP2 over RFCOMM → 把 WiFi 凭据交给 iPhone | ✅ PlayPort (`bt-bridge.py`) |
| ①' 有线链路 | USB host 枚举 iPhone → iAP2 → iPhone 暴露 NCM 网卡 → AirPlay 跑在该网卡上 | ❌ PlayPort 只做无线, 要自己写 |
| ② MFi 认证 | iPhone 发 challenge, 配件用 Apple 证书签名应答 | ⚠️ **缺身份材料** |
| ③ AirPlay RTSP | pairing / `/info` / SETUP / RECORD, 协商 H.264 | ✅ PlayPort |
| ④ 媒体解密 + 拆包 | RTP → 解密 → **H.264 Annex B** + 音频帧 | ✅ PlayPort |
| ⑤ 显示 | 浏览器 WebCodecs → canvas | ❌ **要自己写** (板子不装浏览器) |
| ⑥ 触摸/按键回传 | HID 事件 (web 侧发 JSON) | ✅ PlayPort 定义了格式 |
| ⑦ 音频出声 | 解码 + ALSA | 🔶 PlayPort 解出帧, 接 ALSA 要自己写 |

**自己写的只有 ⑤⑥⑦ 的板端一半** —— 而这三块在 K230 上已经有几乎同构的实现 (MPP/V4L2 解码 + DRM plane + uinput 触摸 + ALSA FIFO), 可以直接照抄结构。

---

## 2. 板子有什么 (查证: dts + 板级资料, 未上板)

| 项 | 值 | 依据 |
|---|---|---|
| SoC | **RK3528**, **4 × Cortex-A53** | `rk3528.dtsi` 里 4 个 `arm,cortex-a53` 节点 |
| 显示 | **HDMI** 输出 + `hdmi-sound` 音频回传 | `rk3528-mangopi-m28k.dts` `&hdmi / &hdmiphy / hdmi-sound` |
| 存储/网络 | eMMC + GbE + **PCIe2x1** | 同上 |
| 无线 | **AIC8800**: WiFi6 (SDIO) + BT | 220 `drivers/aic8800/` 全套 (含 `aicbluetooth` / `aicwf_usb`) |
| USB | `usbdrd_dwc3` (OTG, 可 host) + `usb_host0_ehci/ohci` | dts `&usbdrd30 / &usbdrd_dwc3` |
| 硬解 | Rockchip **mpp** (H.264 / HEVC), 走 `/dev/mpp_service` | Rockchip BSP 通用能力; 需板上确认节点存在 |
| 内存 | 板子有 1~8 GB 版本 | 板级资料, **需上板 `free -m` 核实** |

对比 K230 (1 核 RISC-V / 969 MB / **无蓝牙**): 这块板子**四核 + 有蓝牙 + 有 PCIe + 有 GbE**, 先天条件好得多 —— 尤其**有蓝牙**这点, 直接决定无线 CarPlay 在物理上可行 (K230 上是死路)。

---

## 3. 两套 SDK 现在走到哪

### 3.1 OpenWrt — `bob@10.0.100.224:~/rid/pangu-owrt` (21 GB)

| 项 | 实测 |
|---|---|
| profile | `CONFIG_TARGET_rockchip_rk3528_DEVICE_rk3528-mangopi-m28k=y` (已选) |
| 内核 | `KERNEL_PATCHVER:=5.10` (Rockchip **BSP**, 不是 mainline) |
| libc | **`CONFIG_USE_GLIBC=y`** —— 不是 musl, 这点很关键 (JVM 有理论可能) |
| 多媒体 feed | rockchip feed **已有** `drivers/kmpp` / `libs/rkmpp` / `libs/libv4l-rkmpp` / `libs/libdrm-rockchip` |
| 已选情况 | **一个都没选** — `# CONFIG_PACKAGE_rkmpp is not set`, `libv4l-rockchip` / `libdrm-rockchip` 同样未选 |
| 蓝牙 | `# CONFIG_PACKAGE_kmod-bluetooth is not set`, 无 bluez |
| 有线 CarPlay 前置 | `# CONFIG_PACKAGE_kmod-usb-net-cdc-ncm is not set` (iPhone 的 NCM 网卡驱动) |

⇒ **OpenWrt 这套是"干净底子"**: 组件都在 feed 里, 但全部要手动开。

### 3.2 Armbian — `bob@10.0.100.220:~/rk3528-armbian` (24 GB)

| 项 | 实测 |
|---|---|
| 构建框架 | 完整 `armbian-build` + `config/boards/mangopi-m28k.csc` (`KERNEL_TARGET=vendor`) |
| 已出镜像 | `images/m28k-trixie-v1-cachekernel.img` (2.2 GB) · **`images/m28k-trixie-v3-playport.img` (2.5 GB)** |
| 内核 | 日志确认 **6.1.172 vendor**, rootfs Debian **trixie** minimal |
| PlayPort | `playport/src/` 完整源码 + `dist/` (jars + `web-dist`) + `bin/bt-bridge` |
| **已做的 Linux 移植** | `bt-bridge.py` = 用 **BlueZ RFCOMM** 打开 iPhone 的 iAP2 服务, 内置 SDP 客户端 (L2CAP PSM 1) 找 `00000000-deca-fade-deca-deafdecacafe` UUID, 兜底 1~30 信道探测; 接口与 macOS 版 `bt-bridge` 完全一致 (子进程 + stdio) |
|  | `WifiInfo.kt` = 用 `nmcli` → `iw` 取当前 SSID/信道 (替换 macOS 的 `networksetup`) |
| JDK | `tools/jdk21` 已备 |
| **身份** | `dist/identity/` 里**只有 README.md** —— 证书/私钥没放 |

⇒ **Armbian 这条路已经走了一半**: 镜像能起、协议端能编、蓝牙桥写好了。

---

## 4. 硬卡点: MFi 身份 (只说一次, 但必须说清)

iPhone 每次连 CarPlay 都会发 challenge, 配件必须用 **Apple 签发的配件证书 + 对应私钥**签名应答, 否则不进 CarPlay 会话。PlayPort 的 README 写得很直白:

> `identity/offline-mfi/identity.pk8` (PKCS#8 EC P-256 私钥) + `identity/offline-mfi/certificate.p7b` (配件证书, Apple Accessories CA);
> **缺失则服务端启动即退出, 没有软件绕过方案**。

DiPlay 作者也自述: 用的是 **"从公开 Carlinkit 固件中提取的既有实验性配件身份", 未经 Apple 认证, 私钥可被提取, 未来 iOS 是否继续接受尚不确定**。

**本项目的立场**:
- 身份材料我不提供, 也不指导从商业固件里提取 —— 那是别人家的钥匙。
- 合规来源只有两条: **走 MFi 授权 (含采购带认证的模组)** 或 **用 `--mfi-server` 接一个已授权的远程 MFi 服务**。
- 这不影响先把软件做完: **协议栈 + 渲染器 + 触摸 + 音频全部与身份无关**, 可以做到"把 identity 目录一放就能跑"。

---

## 5. 推荐架构

```
                ┌──────────────── 板子 (RK3528) ────────────────┐
iPhone          │                                              │
  │ BT 配对     │  PlayPort server (Kotlin/JVM, JRE21)         │
  ├────────────►│    ├─ WirelessBootstrap (BlueZ / bt-bridge.py)│
  │ WiFi        │    ├─ iAP2 + AirPlay RTSP (protocol/)         │
  └────────────►│    ├─ MFi 认证 (identity/)  ← 卡点            │
                │    └─ /ws  ──── Wire 帧 ───┐                  │
                │                            ▼                 │
                │  playport-render  ← 【自己写, C】             │
                │    ├─ WebSocket 客户端 (RFC6455)              │
                │    ├─ type2 VIDEO_FRAME (Annex B) → rkmpp 硬解│
                │    ├─ NV12 → DRM/KMS plane → HDMI            │
                │    ├─ 触摸/按键 → JSON input → /ws 回传       │
                │    └─ type4 AUDIO_PACKET → ALSA              │
                └──────────────────────────────────────────────┘
```

### 5.1 PlayPort 的 Wire 协议 (直接抄, 不用猜)

`server/.../Wire.kt` 里写死了, 小端:

| type | 名字 | 布局 |
|---|---|---|
| 1 | VIDEO_CONFIG | `[1][streamType u8][codec u8][width u32][height u32][avcC/hvcC record]` |
| 2 | VIDEO_FRAME | `[2][streamType u8][flags u8][pts u64][Annex B NAL units]` |
| 3 | AUDIO_CONFIG | `[3][streamType u8][codec u8][sampleRate u32][channels u8][nameLen u8][name][description]` |
| 4 | AUDIO_PACKET | `[4][streamType u8][pts u64][one codec frame]` |
| 5 | SCREEN_ACTIVE | `[5][streamType u8][active u8]` |
| 6 | AUDIO_STOPPED | `[6][streamType u8]` |

- `codec`: 1=H.264 / 2=H.265
- `flags` 的 bit0 = **关键帧**
- WS 路径 `/ws`

**★ 关键**: type 2 的载荷是 **Annex B NAL**, **不需要重新封装** —— 直接把 NAL 喂 `/dev/mpp_service` 就行。这让渲染器的工作量直接砍掉一大半。

### 5.2 要写的组件

| 组件 | 语言 | 依赖 | 说明 |
|---|---|---|---|
| `playport-render` | C | libwebsockets (或自写 RFC6455), rockchip mpp, libdrm | 收 Wire 帧 → 硬解 → 上屏 → 触摸回传 |
| `fake-playport` | Python | 无 | **开发用假服务端**: 不连 iPhone, 只按 Wire 格式循环吐一段 H.264 测试流, 让渲染器可以先跑通 |
| 系统服务 | systemd/OpenWrt init | — | 开机自启、断连重试、HDMI 热插拔 |

---

## 6. 为什么不在**板子**上装浏览器 (注意: 与阶段一的 PC 浏览器无关)

1. 板子是 **minimal 根文件系统** (Armbian trixie minimal), 没浏览器; 装 Chromium 要 500 MB+ 依赖。
2. **WebCodecs 要硬解才有意义**, 而 RK3528 上 Chromium 没有可用的 VAAPI/V4L2 硬解通路 ⇒ 会退回软解, 4×A53 解 1080p 撑不住, 功耗和发热也不合理。
3. HDMI 全屏 kiosk + 开机自启 + 触摸映射, 用浏览器比用 DRM 直贴麻烦得多。
4. 我们只需要它**吐 Annex B** —— 那就直接连 WS 就好了。

---

## 7. OpenWrt 还是 Armbian

| | OpenWrt (224 pangu-owrt) | Armbian (220) |
|---|---|---|
| libc | glibc (非 musl) | glibc |
| 内核 | 5.10 BSP | 6.1.172 vendor |
| 硬解 | kmpp/rkmpp **在 feed 里未选** | vendor 自带 mpp |
| 蓝牙 | bluez **未选** | 需确认 AIC8800 BT 起得来 |
| 跑 JVM | 理论可行, 但 OpenWrt 无 Java 生态, 要手工塞 JDK21 tarball | **JDK21 已备, 镜像已出** |
| 现成进度 | 0 | v3-playport 镜像 + Linux 化蓝牙桥 |
| 包管理 | opkg (轻量, 适合产品) | apt |

**建议分两段**:
1. **现在: 用 Armbian 验证整条链** —— 进度最快, JDK/镜像/蓝牙桥都在, 能在真机上把"iPhone → 画面 → 触摸"跑通, 先证明方案成立。
2. **之后再看要不要搬 OpenWrt**: 如果目标是产品形态 (小固件、opkg、开机快), 就把协议端用 **C 或 Go 重写** (Go 静态链接最省事), 不要在 OpenWrt 上硬塞 JVM —— glibc-OpenWrt + 手塞 JDK 是产品级地雷 (没有包管理、升级即坏)。

---

## 8. 里程碑

| # | 目标 | 验收判据 | 依赖 |
|---|---|---|---|
| **M0** | 板上三连验 (硬前提) | `hciconfig -a` 有 hci0 且能 scan 到 iPhone · `ls /dev/mpp_service` 或 v4l2 解码节点存在 · HDMI 有画面 | 只需板子 |
| **M1** | 假服务端 + 渲染器上屏 | `fake-playport` 循环吐测试 H.264, 板上 `playport-render` 上屏, 连续 10 min 不花不卡; `dmesg` 无 mpp 报错 | 无 iPhone、无身份 |
| **M2** | 触摸回环 | 屏上点击 → 渲染器发 JSON → 假服务端打印坐标正确; 90° 旋转映射对 | M1 |
| **M3** | 音频 | type4 音频帧 → ALSA 出声, 与画面偏差可测 | M1 |
| **M4** | 真机联调 | iPhone 经 BT + WiFi 连上, 出画面 + 触摸可点 + 出声 | **identity** |
| **M5** | 稳定性 | 连续 30 min 不断/不花; 记录端到端延迟 (`framebuffer` 拍屏法) | M4 |

**M1~M3 完全不依赖 iPhone 和身份** —— 这是最该先做的一段, 也是唯一能我自己全程推进、不需要主人配合的部分。

---

## 9. 需要补的包 / 驱动 (逐条)

**OpenWrt (224), `make menuconfig` 里要开**:
- `PACKAGE_rkmpp` / `PACKAGE_libv4l-rkmpp` / `PACKAGE_libdrm-rockchip` (feed: rockchip)
- `PACKAGE_kmod-bluetooth` + `PACKAGE_bluez-daemon` + `PACKAGE_bluez-utils` (含 `bluetoothctl`/`rfcomm`)
- 有线再做时: `PACKAGE_kmod-usb-net-cdc-ncm` + `PACKAGE_kmod-usb-acm`

**Armbian (220)**:
- `bluez` / `bluez-tools` / `alsa-utils` / Rockchip mpp 用户态库 (`librockchip_mpp`)

**两块都要**:
- **AIC8800 的 BT 固件 + 加载方式** (`hciattach` 走 UART 或 `btusb`), 220 的 `drivers/aic8800/install_setup.sh` 里有线索 —— **这是 M0 的最大未知数**

---

## 10. 风险

1. **MFi 身份** — 唯一能一票否决整件事的。软件全做完也可能卡在这。
2. **AIC8800 的 BT 在 Linux 上能不能起** — 板载 WiFi 一般没问题, 但 BT 需要固件 + UART 配置, 有些板子根本没引出 BT 到 SoC。**M0 必须先验这个**。
3. **iOS 版本兼容** — CarPlay 协议随 iOS 变, PlayPort/DiPlay 都是"当前版本能用"的状态, 升级可能打回。
4. **许可证** — 复用 PlayPort 代码要看它的 LICENSE, 自用没问题, 分发要遵守。
5. **有线路径** 完全没现成实现 (PlayPort 只做无线), 要自己啃 iAP2 over USB + NCM。

---

## 11. 下一步 (建议顺序)

1. **M0 上板三连验** —— 尤其 `hci0` 和 `/dev/mpp_service`。这决定整件事成不成立, 建议先做。
2. 我同时可以**先写 `fake-playport` + `playport-render`** (M1), 不需要板子也不用 iPhone, 写完直接上板验。
3. identity 的事主人自己拿主意; 定了之后 M4 才动。
