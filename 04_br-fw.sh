#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста BR-FW (Межсетевой экран филиала BR)
# ==============================================================================
set -e

HOSTNAME="br-fw.au-team.irpo"
TIMEZONE="Europe/Moscow"

echo "[1/4] Имя хоста, часовой пояс и ip_forward..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "[2/4] Настройка сетевых интерфейсов..."
nmcli connection delete "FW-NET" 2>/dev/null || true
nmcli connection delete "BR-NET" 2>/dev/null || true

# В сторону BR-RTR
nmcli connection add type ethernet ifname enp0s3 con-name "FW-NET" \
    ip4 172.16.10.2/30 gw4 172.16.10.1 ipv4.dns 77.88.8.8 ipv6.method disabled

# В сторону сервера BR-SRV
nmcli connection add type ethernet ifname enp0s8 con-name "BR-NET" \
    ip4 172.16.20.1/28 ipv6.method disabled

nmcli connection up "FW-NET" || true
nmcli connection up "BR-NET" || true

echo "[3/4] Установка и настройка OSPF (FRR)..."
dnf install -y frr

sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons

cat << EOF > /etc/frr/frr.conf
frr defaults traditional
hostname $HOSTNAME
!
interface enp0s3
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
