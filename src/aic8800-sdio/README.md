# aic8800-sdio —— AIC8800 WiFi6 + BT 驱动 (RK3528 / kernel 6.1 vendor)

来源: 224 `~/rid/pangu-owrt/package/carystudio/kernel/aic8800` (Rockchip BSP 里的 SDIO 版厂商驱动)。

## 为什么需要它

- Armbian 的 **6.1.172-vendor** 内核 `drivers/net/wireless/` 里**没有** aic8800 ⇒ WiFi 必须外置编译。
- 但内核 **自带** `drivers/bluetooth/hci_aic.c` (FriendlyElec, serdev 绑定, `of_match="cvte,aic8800-bt"`, init 1500000)
  ⇒ **BT 一个模块都不用编**, 只要 dts 节点 + modprobe alias。

## 三个模块

| 模块 | 作用 |
|---|---|
| `aic8800_bsp` | SDIO 枚举 + 固件下载 (导出符号给另两个) |
| `aic8800_fdrv` | WiFi 主驱动 (含 `aic_btsdio` → BT over SDIO 通道) |
| `aic8800_btlpm` | BT 低功耗管理 |

## 我们对厂商包的两处改动

`build.sh` 会在编译前打上 (见 `patches/`):

1. `CONFIG_AIC_FW_PATH = "/lib/firmware/aic8800D80"` (原 `/vendor/etc/firmware`)
2. **`CONFIG_SDIO_BT = y`** (原 `n`) —— 这是 **BT 能不能起来的总开关**:
   `n` → 固件表选 `fmacfw_8800d80_u02.bin` (纯 WiFi); `y` → 选 `fmacfwbt_8800d80_u02.bin` (带 BT)

## 编

```sh
~/rk3528_armbian/scripts/build-driver.sh
```

三个必踩的坑 (build.sh 已处理):

1. **vermagic**: 内核 `CONFIG_LOCALVERSION=""` 但 `include/config/kernel.release` 是 `6.1.172-vendor-rk35xx`;
   `make` 会把它改写成 `6.1.172` ⇒ 必须带 `LOCALVERSION=-vendor-rk35xx`。
2. **modpost 未定义符号**: `fdrv` / `btlpm` 依赖 `bsp` 导出符号 ⇒ 必须
   `KBUILD_EXTRA_SYMBOLS=<bsp>/Module.symvers`。
3. **内核树属 root**: 改 dtb 要 `sudo make`。

## 蓝牙还差什么

内核侧已就绪, 只缺 dts:

```dts
&uart2 {
	pinctrl-0 = <&uart2m1_xfer &uart2m1_ctsn &uart2m1_rtsn>;  /* RTS 必须进, 否则无硬件流控 */
	bluetooth {
		compatible = "cvte,aic8800-bt";
		device-wake-gpios = <&gpio1 RK_PB4 GPIO_ACTIVE_HIGH>;
	};
};
```

补丁: `patches/0001-dts-uart2-aic8800-bt.patch` (参照同平台 `rk3528-nanopi-rev03.dts` 写法)。

⚠ **已知风险**: M28K 的 `BT,reset_gpio = gpio1 RK_PC1` 无人认领 —— 6.1 内核**没有** `bluetooth-platdata` 驱动。
若 `hci_aic` 报 `Wait for CTS failed`, 就要在 dts 里加 `gpio-hog` 把 PC1 输出高。

## 部署包内容

`scripts/build-driver.sh` 产出 `artifacts/build/aic8800-m28k-<rel>-<ts>.tar.gz`:

```
aic8800_bsp.ko  aic8800_fdrv.ko  aic8800_btlpm.ko
lib/firmware/aic8800D80/*.bin
etc/modprobe.d/aic8800.conf      # alias aic8800_fdrv_sdio aic8800_fdrv + softdep
etc/modules-load.d/aic8800.conf
install.sh                       # 板上 root 跑: 校验 vermagic → 装 ko/fw → 换 dtb → depmod
usr/local/sbin/aic8800-load.sh   # status / reload
boot/rk3528-mangopi-m28k.dtb     # 打过 BT 补丁的 dtb
```
