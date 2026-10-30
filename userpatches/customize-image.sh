#!/bin/bash
# M28K PlayPort 适配: JDK21 + BlueZ + /opt/playport (overlay 挂在 /tmp/overlay)
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends openjdk-21-jre-headless bluez iw rfkill
if [ -d /tmp/overlay ]; then
  cp -a /tmp/overlay/. /
  echo "[customize] overlay applied: $(ls /opt/playport | tr '\n' ' ')" >&2
fi
systemctl enable playport.service || true
echo "[customize] done" >&2
