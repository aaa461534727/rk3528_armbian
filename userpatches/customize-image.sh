#!/bin/bash
# M28K PlayPort 适配 + 远程访问 (root/root, SSH 开启)
# 由 armbian 在镜像定制阶段以 chroot 方式执行; overlay 挂在 /tmp/overlay
set -e
export DEBIAN_FRONTEND=noninteractive

# 网络不稳定时 apt 会偶发失败: 重试 5 次 + 拉长超时 + 单包失败不整体放弃
APT_OPTS="-o Acquire::Retries=5 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60"
echo "[customize] 1/5 装包" >&2
for i in 1 2 3; do
  apt-get $APT_OPTS update && break
  echo "[customize] apt update 第 $i 次失败, 5s 后重试" >&2; sleep 5
done
for i in 1 2 3; do
  apt-get $APT_OPTS install -y --no-install-recommends \
      openjdk-21-jre-headless bluez iw rfkill openssh-server && break
  echo "[customize] apt install 第 $i 次失败, 10s 后重试" >&2; sleep 10
  apt-get $APT_OPTS update >/dev/null 2>&1 || true
done
# 三个关键包必须真的装上, 否则镜像白出
for pkg in openjdk-21-jre-headless bluez openssh-server; do
  dpkg -s "$pkg" >/dev/null 2>&1 || { echo "[customize] !! 缺关键包 $pkg" >&2; exit 1; }
done

echo "[customize] 2/5 开 SSH + root 登录 (root/root)" >&2
systemctl enable ssh.service || true
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-m28k.conf <<EOF
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
UseDNS no
EOF
# 主配置里若有冲突项, 用 drop-in 优先; 同时兜底改主配置
sed -i "s/^#\?PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication.*/PasswordAuthentication yes/" /etc/ssh/sshd_config

echo "[customize] 3/5 设 root 密码 = root" >&2
echo "root:root" | chpasswd

echo "[customize] 4/5 应用 overlay (/opt/playport + systemd unit)" >&2
if [ -d /tmp/overlay ]; then
  cp -a /tmp/overlay/. /
  chmod 755 /opt/playport/bin/server /opt/playport/bin/bt-bridge || true
  echo "[customize] overlay applied: $(ls /opt/playport | tr "\n" " ")" >&2
else
  echo "[customize] !! /tmp/overlay 不存在, 跳过" >&2
fi

echo "[customize] 5/5 enable playport.service" >&2
systemctl enable playport.service || true

echo "[customize] done" >&2
