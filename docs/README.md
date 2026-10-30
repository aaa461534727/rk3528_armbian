# docs — SDK 文档

> ⚠ **2026-10-30 目录重组**: 老的每项一个平级目录 (`~/rk3528-armbian/{build,docs,drivers,images,logs,playport,sdk,tools}`)
> 已收敛为本 SDK。文档里出现的旧路径按下面这张表翻译。

| 旧路径 | 新路径 |
|---|---|
| `~/rk3528-armbian/sdk/armbian` | `~/rk3528_armbian/framework` |
| `~/rk3528-armbian/drivers/aic8800-sdio` | `~/rk3528_armbian/src/aic8800-sdio` |
| `~/rk3528-armbian/playport` | `~/rk3528_armbian/src/playport` + `artifacts/playport-dist` |
| `~/rk3528-armbian/tools/jdk21` | `~/rk3528_armbian/artifacts/tools/jdk21` |
| `~/rk3528-armbian/images/` | `~/rk3528_armbian/artifacts/images/` |
| `~/rk3528-armbian/build/` | `~/rk3528_armbian/artifacts/build/` |
| `~/rk3528-armbian/logs/` | `~/rk3528_armbian/artifacts/logs/` |
| `framework/userpatches/` | `~/rk3528_armbian/userpatches/` (构建时 `USERPATCHES_PATH` 指过去) |

## 文档清单

| 文件 | 内容 |
|---|---|
| [AIC8800_DRIVER.md](AIC8800_DRIVER.md) | AIC8800 WiFi/BT 驱动适配全过程 (取证 / 编译 / 三个坑 / 上板验证 / 排障) |
| [CARPLAY_PLAN.md](CARPLAY_PLAN.md) | 原生 CarPlay 整体方案 (§0.5 分阶段路线: 先 PC 浏览器跑通协议, 再板上屏) |
| [MFI_IDENTITY.md](MFI_IDENTITY.md) | MFi 配件身份的验收 / 落位 / 红线 (**不含任何私钥**) |

## 相关仓

- 项目主仓 (文档 / 进度 / 板卡): `dengbaowen/project-framework` → `rk3528-armbian/`
- 本 SDK 仓: <https://github.com/aaa461534727/rk3528_armbian>
