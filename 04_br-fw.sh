#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста BR-FW (Межсетевой экран филиала BR)
# Поддерживает VirtualBox, Proxmox, VMware (автоопределение интерфейсов)
# ==============================================================================
set -e

# --- ПЕРЕМЕННЫЕ ПОД ВАШ ВАРИАНТ ---
HOSTNAME="br-fw.au-team.irpo"
TIMEZONE="Europe/Moscow"

IP_FW_NET="172.16.10.2/30"
GW_FW_NET="172.16.10.1"

IP_BR_NET="172.16.20.1/28"

# --- АВТООПРЕДЕЛЕНИЕ СЕТЕВЫХ ИНТЕРФЕЙСОВ ---
ETH=($(ip -o link show | awk -F': ' '$2 !~ /^(lo|tun|vlan|virbr|docker)/ {print $2}'))
INT_RTR="${ETH[0]}" # 1-й адаптер: В сторону BR-RTR
INT_SRV="${ETH[1]}" # 2-й адаптер: В сторону сервера BR-SRV

echo "=== Определены интерфейсы: RTR=$INT_RTR, SRV=$INT_SRV ==="

echo "[1/4] Имя хоста, часовой пояс и ip_forward..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "[2/4] Настройка сетевых интерфейсов..."
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_RTR" '$2==d {print $1}' | xargs -r nmcli connection delete
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_SRV" '$2==d {print $1}' | xargs -r nmcli connection delete

# В сторону BR-RTR
nmcli connection add type ethernet ifname "$INT_RTR" con-name "FW-NET" \
    ip4 "$IP_FW_NET" gw4 "$GW_FW_NET" ipv4.dns 77.88.8.8 ipv6.method disabled

# В сторону сервера BR-SRV
nmcli connection add type ethernet ifname "$INT_SRV" con-name "BR-NET" \
    ip4 "$IP_BR_NET" ipv6.method disabled

nmcli connection up "FW-NET" || true
nmcli connection up "BR-NET" || true

echo "[3/4] Установка и настройка OSPF (FRR)..."
dnf install -y frr

sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons

cat << EOF > /etc/frr/frr.conf
frr defaults traditional
hostname $HOSTNAME
!
interface $INT_RTR
 no ip ospf passive
!
router ospf
 passive-interface default
 network 172.16.10.0/30 area 0
 network 172.16.20.0/28 area 0
!
line vty
!
EOF

chown -R frr:frr /etc/frr
chmod 640 /etc/frr/frr.conf
systemctl enable --now frr
systemctl restart frr

echo "=== BR-FW настроен успешно! ==="
ip -c -br a
