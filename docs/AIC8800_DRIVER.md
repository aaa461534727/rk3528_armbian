# AIC8800 无线 + 蓝牙驱动适配 (Armbian 6.1 vendor)

> 环境: MangoPi M28K (RK3528) · Armbian trixie · kernel **6.1.172-vendor-rk35xx** · 走 Armbian 验证 (不改 OpenWrt)
> 驱动源码: `bob@10.0.100.220:~/rk3528-armbian/drivers/aic8800-sdio/` (来自 224 `pangu-owrt/package/carystudio/kernel/aic8800`)
> 产物: `bob@10.0.100.220:~/rk3528-armbian/build/aic8800-m28k-6.1.172-vendor-rk35xx-*.tar.gz`

---

## 0. 一句话结论

**WiFi 要自己编 3 个 out-of-tree 模块; 蓝牙不用编 —— 内核 6.1 vendor 已经内置 `hci_aic.c` (serdev), 只差 dts 一个节点。**

## 1. 取证: 板子到底装了什么

| 证据 | 内容 | 结论 |
|---|---|---|
| `pangu-owrt` 当前分支 | `2102_aic8800_rid` | 产品就是 AIC8800 版 |
| `pangu-owrt/.config` | `CONFIG_AIC8800_SDIO=y`, `CONFIG_AIC8800_PCIE` 未选 | **SDIO 接口**, 不是 PCIe |
| `package/carystudio/kernel/aic8800/{sdio,fw}` | `aic8800_bsp` + `aic8800_fdrv` + `aic8800_btlpm`; `fw/aic8800D80/` 有 `fmacfwbt_8800d80_u02.bin` | D80 芯片, BT 固件由 **SDIO** 下载 |
| 6.1 内核 `drivers/bluetooth/hci_aic.c` | FriendlyElec 提供, `of_match = "cvte,aic8800-bt"`, serdev 绑定 | **BT 走 UART2 + serdev**, 内核已内置 |
| `hci_aic.c: aic_setup()` | 等 CTS → `request_module("aic8800_fdrv_sdio")` → 读 local name | BT 固件**不是** UART 下的, 是 SDIO 驱动下的 |
| 6.1 内核 `drivers/net/wireless/` | **没有** aic8800 | WiFi 必须外置编译 |

### 1.1 和 AP6275S 的关系

M28K 的 dts (`rk3528-mangopi-m28k.dts`) 里写 `wifi_chip_type = "ap6275s"` —— 那是 **MangoPi 原厂配置**, 不是我们这块板的。
AIC 的 SDIO 驱动按 `SDIO_DEVICE_CLASS(SDIO_CLASS_WLAN)` + vendor/device id 匹配, **不依赖 dts 的 `wifi_chip_type`**, 所以不用改。

## 2. 编译 (已跑通, 零代码修改)

三个模块在 6.1.172 上**一次编过**, 只有两处 Makefile 开关必须打开:

| 文件 | 改动 | 为什么 |
|---|---|---|
| `aic8800_bsp/Makefile` | `CONFIG_AIC_FW_PATH = "/lib/firmware/aic8800D80"` | 原值是 Android 的 `/vendor/etc/firmware`, Debian 上没有 |
| `aic8800_bsp/Makefile` | `CONFIG_SDIO_BT = y` | **关键**: 关着时固件表用 `fmacfw_8800d80_u02.bin` (纯 WiFi), 开着才是 `fmacfwbt_8800d80_u02.bin` (带 BT)。不开这个 BT 永远起不来 |
| `aic8800_fdrv/Makefile` | `CONFIG_SDIO_BT=y` | 把 `aic_btsdio.o` 编进 fdrv (BT over SDIO 的通道) |

编译命令 (`build.sh` 已封装):

```bash
K=~/rk3528-armbian/sdk/armbian/cache/sources/linux-kernel-worktree/6.1__rk35xx__arm64
ARGS="ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CONFIG_PLATFORM_UBUNTU=y LOCALVERSION=-vendor-rk35xx"
make -C $K M=$PWD/aic8800_bsp $ARGS modules
make -C $K M=$PWD/aic8800_fdrv $ARGS KBUILD_EXTRA_SYMBOLS=$PWD/aic8800_bsp/Module.symvers modules
make -C $K M=$PWD/aic8800_btlpm $ARGS KBUILD_EXTRA_SYMBOLS=$PWD/aic8800_bsp/Module.symvers modules
```

产物 vermagic 实测: `6.1.172-vendor-rk35xx SMP mod_unload modversions aarch64` ✓

### 2.1 三个必踩的坑

1. **`fdrv` 必须带 `KBUILD_EXTRA_SYMBOLS`** —— 否则 modpost 报一堆 undefined (`get_testmode`/`aicbsp_get_feature`/...), 那些符号是 bsp 导出的。
2. **`make` 会重写 `include/config/kernel.release`, 把 `-vendor-rk35xx` 丢掉** (变成 `6.1.172`)。丢了之后编出来的 ko vermagic 就对不上。两招: 编时加 `LOCALVERSION=-vendor-rk35xx`; 或者编完把 `include/config/kernel.release` 写回 `6.1.172-vendor-rk35xx`。
3. **内核树是 root 拥有的** (`cache/sources/linux-kernel-worktree/...`), `make dtbs` 要 `sudo`; `M=` 编外部模块不用 sudo (只写模块目录)。

## 3. 蓝牙: 只差一个 dts 节点

内核 `hci_aic.c` 走 serdev, 要求 uart2 下挂一个 `compatible = "cvte,aic8800-bt"` 的子节点, 并且 **RTS 也要进 pinctrl** (`hci_uart_has_flow_control` 要 RTS+CTS 都在)。

同平台 NanoPi R28S 的写法就是标准答案 (`rk3528-nanopi-rev03.dts`):

```dts
&uart2 {
	pinctrl-names = "default";
	pinctrl-0 = <&uart2m1_xfer &uart2m1_ctsn &uart2m1_rtsn>;
	status = "okay";
	bluetooth {
		compatible = "cvte,aic8800-bt";
		device-wake-gpios = <&gpio1 RK_PB4 GPIO_ACTIVE_HIGH>;
	};
};
```

M28K 的 `BT,wake_gpio` 正好也是 `gpio1 RK_PB4` (和 NanoPi 同一个参考设计), 所以这一行直接照抄。
补丁: `drivers/aic8800-sdio/patches/0001-dts-uart2-aic8800-bt.patch` (原 dts 备份 `drivers/rk3528-mangopi-m28k.dts.orig`)。

### 3.1 模块名对不上要 alias

`hci_aic.c` 里写死 `request_module("aic8800_fdrv_sdio")` (FriendlyElec 的 dkms 包名), 我们的 ko 叫 `aic8800_fdrv`:

```
# /etc/modprobe.d/aic8800.conf
alias aic8800_fdrv_sdio aic8800_fdrv
softdep aic8800_fdrv pre: aic8800_bsp
softdep aic8800_btlpm pre: aic8800_bsp
```

## 4. 部署

板上 (root):

```bash
tar xzf aic8800-m28k-6.1.172-vendor-rk35xx-*.tar.gz -C /tmp/aic8800
cd /tmp/aic8800 && ./install.sh
reboot
```

`install.sh` 干的事: 拷 ko 到 `/lib/modules/<rel>/updates/` · 拷固件到 `/lib/firmware/aic8800D80/` · 装 `modprobe.d`/`modules-load.d` · 备份并替换 `/boot/dtb/rockchip/rk3528-mangopi-m28k.dtb` · `depmod -a`。

起来后验收:

```bash
dmesg | grep -iE 'aicbsp|aic8800|hci_uart'   # 期望看到 firmware path 与 sdio probe
ip -br link | grep wlan                      # 期望 wlan0
hciconfig -a                                 # 期望 hci0
bluetoothctl list                            # 期望一个 controller
/usr/local/sbin/aic8800-load.sh status       # 一次性看全 (模块/固件/sdio/wlan/hci)
```

## 5. 还没验证的 (上板才算数)

| # | 待验证 | 失败时的备选方案 |
|---|---|---|
| 1 | SDIO 枚举到 AIC8800 (`/sys/bus/sdio/devices/` 有条目) | 查 `sdio_pwrseq` reset-gpio (gpio1 PA6) 时序; `post-power-on-delay-ms` 加大 |
| 2 | 固件下载成功 (dmesg 有 `aicbsp`/fmac 版本号) | 检查 `/lib/firmware/aic8800D80` 是否齐全; 试 `modprobe aic8800_bsp aic_fw_path=/lib/firmware/aic8800D80` |
| 3 | `wlan0` 出现且能扫到 AP | 可能是 D80 vs DC 判错, 看 dmesg 里的 chip id |
| 4 | **BT 的 CTS 能拉高** (hci_aic 等 10 s) | M28K 有 `BT,reset_gpio = gpio1 PC1`, 但 6.1 内核**没有** `bluetooth-platdata` 驱动认领它 → 若 CTS 一直低, 需要加 gpio-hog 把 PC1 拉高释放复位 |
| 5 | HDMI / mpp 与本适配无关 | — |

## 6. 回归到 OpenWrt 时

OpenWrt (`pangu-owrt`, kernel 5.10) 已经有自己的 `package/carystudio/kernel/aic8800` 包, 但:
- 它的 Makefile **没开 `CONFIG_SDIO_BT`** (默认 n) → 那份 OpenWrt 里的 BT 其实也是不工作的;
- 它的 `CONFIG_AIC_FW_PATH` 指向 `/vendor/etc/firmware`, 与它的 install 段 (`$(1)/vendor/etc/firmware`) 是一致的。
真要产品化搬回 OpenWrt 时, 这两处照本文件第 2 节改, 再选上 `kmod-bluetooth`/`bluez` 即可。

---

## 7. 为什么不在 OpenWrt(5.10) 上做这套

2026-10-30 在 224 上核对过 `build_dir/.../linux-5.10.198-android`:

| 项 | OpenWrt 5.10 | Armbian 6.1 vendor |
|---|---|---|
| `drivers/bluetooth/hci_aic.c` | **没有** | **有** |
| `.config` 里 `CONFIG_BT` | **未启用** | `CONFIG_BT=y` + `BT_HCIUART_AIC=y` |
| AIC8800 WiFi 驱动 | 有 (`package/carystudio/kernel/aic8800`) 但 `CONFIG_SDIO_BT=n` | 要自己编 (本文已完成) |
| 加 BT 的代价 | 开 BT 栈 + 反向移植 `hci_aic.c`(serdev) + 改 dts + **重编内核并重刷整机** | 编 3 个外部模块 + 换一个 dtb |

⇒ **验证阶段用 Armbian** (工作量差一个数量级)。产品化真要回 OpenWrt 时, 照第 2 节的两处开关 + 移植 `hci_aic.c` 即可, 但那是另一件事。

## 8. 板子接上后: 一条命令

```bash
cd <仓库>/rk3528-armbian/scripts/aic8800
./deploy-aic8800.sh 192.168.x.x 1234                       # Armbian 默认 root/1234
./deploy-aic8800.sh 192.168.x.x 1234 --jump bob@10.0.100.220  # 板子只对 220 可见
```

脚本会: 校验板上内核是不是 `6.1.172-vendor-rk35xx` → 从 220 取最新的 `aic8800-m28k-*.tar.gz` → scp 上去 → 跑 `install.sh` → `reboot` → 等回来 → 打印 `aic8800-load.sh status`。

⚠ 如果板上是 OpenWrt (内核 5.10.x), 脚本会提示并让你确认; 这种情况**先烧 Armbian**, 用 220 的 `images/m28k-trixie-v3-playport.img`:

```bash
# 写 SD 卡 (本机或 220 上, 目标盘别选错)
ssh bob@10.0.100.220 'cat ~/rk3528-armbian/images/m28k-trixie-v3-playport.img' | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

### 8.1 判断"成功"的三条硬指标

| 指标 | 命令 | 期望 |
|---|---|---|
| SDIO 枚举 | `ls /sys/bus/sdio/devices/` | 有 `mmc2:0001:1` 之类的条目 |
| WiFi | `ip -br link \| grep wlan` | `wlan0` 存在, `dmesg \| grep -i aicbsp` 有固件版本 |
| 蓝牙 | `hciconfig -a` | `hci0` 存在, `bluetoothctl list` 有一个 controller |

### 8.2 BT 起不来时按这个顺序查

1. `dmesg | grep -i hci_uart` —— 有没有 `Wait for CTS failed`
   - 有 ⇒ **CTS 没拉高**: 说明 AIC 的 BT 还在复位态。M28K 的 `BT,reset_gpio = gpio1 PC1`, 而 6.1 内核没有 `bluetooth-platdata` 驱动认领它, 需要在 dtb 里加 gpio-hog 把 PC1 拉高 (下一步就是改这个)。
2. `dmesg | grep -i request_module` —— 有没有 `request_module failed`
   - 有 ⇒ `alias aic8800_fdrv_sdio` 没生效, 看 `/etc/modprobe.d/aic8800.conf` 是否装上了、`depmod` 跑没跑。
3. `dmesg | grep -iE 'aicbsp|fmac'` —— 有没有固件下载失败的报错
   - 有 ⇒ 固件不全或路径不对, `ls /lib/firmware/aic8800D80/` 应该有 13 个文件。

## 9. 待办 (按优先级)

- [ ] **上板验证** (板子接入后立刻做): `deploy-aic8800.sh`
- [ ] BT 若 CTS 不过 → dtb 加 gpio-hog (`gpio1 RK_PC1` 输出高)
- [ ] WiFi 通后: 把 `scripts/aic8800/` 的 dts 补丁并入 arbmian `userpatches`, 这样重烧镜像自带, 不用每次换 dtb
- [ ] BT 通后: 跑 `playport/bt-bridge.py` 看能否搜到 iAP2 SDP (`00000000-deca-fade-deca-deafdecacafe`)
