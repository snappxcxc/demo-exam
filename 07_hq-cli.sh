#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста HQ-CLI (Клиент HQ: DHCP)
# Поддерживает VirtualBox, Proxmox, VMware (автоопределение интерфейсов)
# ==============================================================================
set -e

# --- ПЕРЕМЕННЫЕ ПОД ВАШ ВАРИАНТ ---
HOSTNAME="hq-cli.au-team.irpo"
TIMEZONE="Europe/Moscow"
VLAN_ID=200

# --- АВТООПРЕДЕЛЕНИЕ СЕТЕВОГО ИНТЕРФЕЙСА ---
ETH=($(ip -o link show | awk -F': ' '$2 !~ /^(lo|tun|vlan|virbr|docker)/ {print $2}'))
INT_LAN="${ETH[0]}" # Физический адаптер к свитчу HQ

echo "=== Определен интерфейс: $INT_LAN ==="

echo "[1/2] Имя хоста и часовой пояс..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

echo "[2/2] Настройка VLAN $VLAN_ID на $INT_LAN (DHCP)..."
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_LAN" '$2==d {print $1}' | xargs -r nmcli connection delete
nmcli connection delete "vlan$VLAN_ID" 2>/dev/null || true

nmcli connection add type vlan ifname "vlan$VLAN_ID" con-name "vlan$VLAN_ID" dev "$INT_LAN" id "$VLAN_ID" \
    ipv4.method auto ipv6.method disabled

nmcli connection up "vlan$VLAN_ID" || true

echo "=== HQ-CLI настроен! Проверяем получение IP адреса: ==="
sleep 2
ip -c -br a
