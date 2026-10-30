#!/bin/bash
# 板子起来后自检: 驱动 / WiFi / BT / PlayPort 四件事
#   ./scripts/verify-board.sh <板子IP> [root密码]
set -uo pipefail
IP="${1:?用法: verify-board.sh <板子IP> [密码]}"
PW="${2:-1234}"

run() { sshpass -p "$PW" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 "root@$IP" "$@" 2>/dev/null; }

echo "== 内核 ==";  run "uname -r; uname -m"
echo "== SDIO ==";  run "ls /sys/bus/sdio/devices/ 2>/dev/null || echo '(空)'"
echo "== 模块 ==";  run "lsmod | grep -E 'aic8800' || echo '(未加载)'"
echo "== WiFi ==";  run "ip -br link | grep -E 'wlan|eth'; iw dev 2>/dev/null | head -5"
echo "== BT ==";    run "hciconfig -a 2>/dev/null | head -8; dmesg | grep -i hci_uart | tail -5"
echo "== PlayPort =="; run "systemctl is-active playport; systemctl status playport --no-pager | head -12"
echo "== 身份 ==";  run "ls -l /opt/playport/identity/offline-mfi 2>/dev/null || echo '(未放入)'"
