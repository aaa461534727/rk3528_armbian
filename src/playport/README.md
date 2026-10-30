# playport —— Linux 移植改动

上游: <https://github.com/youcci/playport> (Kotlin/JVM 的 CarPlay 协议端, 原设计跑在 macOS, 显示交给浏览器 WebCodecs)

我们**没有 fork 整个仓**, 只保留"让它在 Linux/RK3528 上能跑"的那几处改动。上游 commit 见 `UPSTREAM_COMMIT`。

## 改了什么 (共 2 个文件 / ~56 行)

| 文件 | 改动 |
|---|---|
| `server/src/main/kotlin/com/playport/server/WifiInfo.kt` | 用 `nmcli` → `iw` → `/proc/net/wireless` 取代 macOS 的 `networksetup` / `system_profiler` |
| `server/src/main/kotlin/com/playport/server/WirelessBootstrap.kt` | 蓝牙桥改走 Linux 版 `bt-bridge.py` (BlueZ RFCOMM), 不再依赖 macOS 的 `bt-bridge` 二进制 |

另有**新增**文件:

| 文件 | 作用 |
|---|---|
| `bt-bridge.py` | Linux 蓝牙桥: 打开 iPhone 的 iAP2 RFCOMM 通道, 原始字节双向管道到 stdin/stdout。内置 SDP 客户端 (L2CAP PSM 1) 找 iAP2 UUID `00000000-deca-fade-deca-deafdecacafe`, 兜底探测 1~30 信道 |
| `bin/` | dist 里的启动器 (server / bt-bridge), 由 gradle `installDist` 生成 |

## 怎么复现 (在 220 上)

```sh
cd ~/rk3528_armbian
git clone https://github.com/youcci/playport /tmp/playport
cd /tmp/playport && git checkout $(cat ~/rk3528_armbian/src/playport/UPSTREAM_COMMIT)
git apply ~/rk3528_armbian/src/playport/linux-port.patch
cp ~/rk3528_armbian/src/playport/bt-bridge.py server/src/main/resources/ 2>/dev/null || true

export JAVA_HOME=~/rk3528_armbian/artifacts/tools/jdk21
./gradlew :server:installDist          # → server/build/install/server/
./gradlew :web:assemble                # 前端

# 把产物放到 SDK 的 artifacts (不入仓)
rsync -a server/build/install/server/ ~/rk3528_armbian/artifacts/playport-dist/
rsync -a web/dist/ ~/rk3528_armbian/artifacts/playport-dist/web-dist/
```

## 注意

- **java 必须 JDK21** (`artifacts/tools/jdk21`)。220 系统 java 是 11, 直接跑 launcher 会静默 exit 1。
- 缺 `identity/offline-mfi/{identity.pk8,certificate.p7b}` 时服务端**启动即退出**, 没有软件绕过。
- `require(certificates.size == 1)` ⇒ p7b 里只能有 1 张证书, **不要塞中间 CA**。
