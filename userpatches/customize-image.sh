#!/bin/bash
# M28K PlayPort 适配 + 远程访问 (root/root, SSH 开启)
# 由 armbian 在镜像定制阶段以 chroot 方式执行; overlay 挂在 /tmp/overlay
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[customize] 1/5 装包" >&2
apt-get update
apt-get install -y --no-install-recommends \
    openjdk-21-jre-headless bluez iw rfkill openssh-server

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
