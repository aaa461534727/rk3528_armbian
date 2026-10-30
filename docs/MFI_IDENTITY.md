# MFi 配件身份 (identity) 验收与落位

> 2026-10-30 验收。本文只记录**材料形态 / 校验结果 / 落位 / 风险**, **不含任何私钥内容**。
> 私钥文件本身只在下面两处物理存在: 主人本机 `~/tmp/diplay-mfi` 与 `~/rk3528-armbian/playport/dist/identity/offline-mfi` (220)。**不入仓、不写进任何文档。**

## 0. 一句话结论

**齐全, 且能直接喂给 PlayPort。** 主人提供的 8 个文件全部 SHA256 自校验通过, 私钥与证书配对 (P-256) 正确;
把 `~/identity.pk8` + `~/certificate.p7b` 放到 `~/rk3528-armbian/playport/dist/identity/offline-mfi/` 后,
`.*bin/server` 实际启动成功 (AirPlay RTSP 监听 7000, mDNS 通告), 说明 `.MfiIdentity.load()` 的三道检查全过:
解析 PKCS#8 私钥 → p7b 里取证书 → 私钥签名/证书验签一致。

## 1. 文件清单 (本机 `~/tmp/diplay-mfi`, 8 个, 40 KB)

| 文件 | 大小 | 用途 | PlayPort 要吗 |
|---|---|---|---|
| `certificate.p7b` | 607 B | PKCS#7 DER, **原始件** (APK 字节一致) | ✅ 必需 |
| `identity.pk8` | 67 B | PKCS#8 DER EC P-256 私钥, **原始件** | ✅ 必需 |
| `cert.pem` | 1034 B | p7b 转出的单张 X.509 PEM | 否 (方便 openssl 看) |
| `identity.key.pem` | 148 B | pk8 转出的 PKCS#8 PEM | 否 |
| `bundle.pem` | 1182 B | key + cert 合一的 PEM | 否 |
| `README.txt` | 2096 B | 来源说明 + 校验值 + 证书摘要 | 否 |
| `SHA256SUMS.txt` | 554 B | 7 个文件的校验和 | 否 |
| `diplay-mfi.zip` | 4138 B | 上面 6 个的打包 | 否 |

自校验: `sha256sum -c SHA256SUMS.txt` → **7/7 OK**; zip 解出的 6 个文件与目录内逐字节一致 (`cmp`)。
来源: DiPlay v0.2.22 APK 的 `assets/offline-mfi/` (上游 README: 实为从公开 Carlinkit 固件回收的一对)。

## 2. 证书与密钥的事实

| 项 | 值 |
|---|---|
| Subject | `C=US, O=Apple Inc., OU=Apple Accessories, CN=IPA_24ACBB48646F8077F7463523085B60D2` |
| Issuer | `Apple Accessories Certification Authority - 00000002` (Apple Inc.) |
| Serial | 16 字节, 与 CN 的 `IPA_` 后缀一致 |
| 有效期 | 2018-06-13 → **2049-12-31** (还很久) |
| 算法 | ECDSA P-256 / SHA-256, 签名 `ecdsa-with-SHA256` |
| 私有扩展 | `1.2.840.113635.100.6.36` **critical**, 值 = 32 字节 (31×`00` + `02`) |
| 配对 | pk8 导出的公钥 == 证书公钥 (`cmp` 字节一致), 两个 PEM 变体也一致 |

## 3. PlayPort 的硬性要求 (踩坑点)

`src/protocol/src/main/java/com/shilapi/xcertplay/mfi/LocalMfiAuthenticationClient.kt`:

- 目录固定 `<identity-dir>/offline-mfi/`, 文件名死写 `identity.pk8` / `certificate.p7b`;
- `MAX_FILE_BYTES = 16 KB` (两份都远小于);
- 证书必须 **EC P-256** (校验 order 常量), `protocolMajor()` 必须 **3**;
- `require(certificates.size == 1) { "Expected one accessory certificate" }`
  ⇒ **p7b 里只能有 1 张证书**。**不要**往里塞中间 CA / 根 CA, 塞了服务端直接起不来。iOS 侧自己内置了 Apple Accessories CA。

⇒ 主人这份 p7b 正好 1 张 leaf, **形态正确**, 不是"缺中间证书"。

## 4. 落位

| 位置 | 内容 | 权限 |
|---|---|---|
| **本仓 `rk3528-armbian/build/identity/offline-mfi/`** | **8 个原始件全备 (主保存点)** | 目录 700 / 文件 600; 被 `**/build/*` + 项目级 `.gitignore` 双重排除, **入不了仓** |
| 主人本机 `~/tmp/diplay-mfi` | 同一份 8 个文件 (原始来源, `/tmp` 重启即没) | 目录 700 / 文件 600 |
| 220 `~/rk3528-armbian/playport/dist/identity/offline-mfi/` | 只放 pk8 + p7b | 目录 700 / pk8 600 / p7b 644 |
| 220 `~/rk3528-armbian/playport/src/identity/` | **仍只有 README.md** (那是 git 仓 `src/.git`, 不放真件) | — |
| 板子 (上板后) | `/opt/playport/identity/offline-mfi/` (启动加 `--identity-dir`) | 待定 |

启动方式 (220, 已实测):
```
cd ~/rk3528-armbian/playport/dist
JAVA_HOME=~/rk3528-armbian/tools/jdk21 PATH=$JAVA_HOME/bin:$PATH ./bin/server --insecure-http --http-port 18778
```
默认 `--identity-dir` 就是 `dist/identity`, 不用额外传参。**注意 java 必须是 tools/jdk21** (系统 java 是 11, 直接跑 launcher 静默 exit 1)。

## 5. 风险 (必须知道, 不因为"能跑"就消失)

1. **共享身份**: 这对材料在公开 APK / 固件里, 任何拿到 DiPlay / Carlinkit 固件的人都有同一份。iOS 可能按 serial 判重、Apple 可随时吊销 (被吊销后表现为 CarPlay 连上即掉)。
2. **不是授权给本项目的**: 商用/分发都有法律风险; 合规路径仍是 MFi 授权或采购带认证模组, 或 `--mfi-server` 接已授权远端服务。
3. **`README.txt` 里明文写了私钥的 raw `d`** ⇒ 这个 README (以及 `diplay-mfi.zip`) 绝不能外传 / 贴群 / 传工单; 转发时只发 `certificate.p7b` + 说明, 不发整包。
4. 本机原件目录名是 `diplay-mfi` (少一个 i), 与项目名 DiPlay 拼写不同, 别找不到。

## 6. 复查 (30 秒)

```
cd ~/tmp/diplay-mfi && sha256sum -c SHA256SUMS.txt
openssl x509 -in cert.pem -noout -subject -dates
openssl pkey -inform DER -in identity.pk8 -pubout | diff - <(openssl x509 -in cert.pem -pubkey -noout) && echo pair-ok
```