#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста HQ-CLI (Клиент HQ: DHCP)
# ==============================================================================
set -e

HOSTNAME="hq-cli.au-team.irpo"
TIMEZONE="Europe/Moscow"

echo "[1/2] Имя хоста и часовой пояс..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

echo "[2/2] Настройка VLAN 200 на enp0s3 (DHCP)..."
nmcli connection delete "vlan200" 2>/dev/null || true
nmcli connection delete "enp0s3" 2>/dev/null || true

nmcli connection add type vlan ifname vlan200 con-name "vlan200" dev enp0s3 id 200 \
    ipv4.method auto ipv6.method disabled

nmcli connection up "vlan200" || true

echo "=== HQ-CLI настроен! Проверяем получение IP адреса: ==="
sleep 2
ip -c -br a
