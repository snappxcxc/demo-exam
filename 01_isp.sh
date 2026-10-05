#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста ISP (Провайдер)
# ==============================================================================
set -e

# Переменные (при необходимости измените под свой вариант)
HOSTNAME="isp"
TIMEZONE="Europe/Moscow"
NET_HQ_IP="172.16.1.1/28"
NET_BR_IP="172.16.2.1/28"

echo "[1/4] Настройка имени хоста и часового пояса..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

echo "[2/4] Включение маршрутизации ядра (ip_forward)..."
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "[3/4] Настройка сетевых интерфейсов..."
# Удаляем старые профили, если есть конфликты
nmcli connection delete "Internet" 2>/dev/null || true
nmcli connection delete "ISP-HQ" 2>/dev/null || true
nmcli connection delete "ISP-BR" 2>/dev/null || true

# enp0s3 - Внешний интернет (DHCP)
nmcli connection add type ethernet ifname enp0s3 con-name "Internet" ipv4.method auto ipv6.method disabled

# enp0s8 - В сторону HQ
nmcli connection add type ethernet ifname enp0s8 con-name "ISP-HQ" ip4 "$NET_HQ_IP" ipv6.method disabled

# enp0s9 - В сторону BR
nmcli connection add type ethernet ifname enp0s9 con-name "ISP-BR" ip4 "$NET_BR_IP" ipv6.method disabled

# Поднимаем подключения
nmcli connection up "Internet" || true
nmcli connection up "ISP-HQ" || true
nmcli connection up "ISP-BR" || true

echo "[4/4] Настройка NAT (nftables)..."
mkdir -p /etc/nftables
cat << 'EOF' > /etc/nftables/isp.nft
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat;
        oifname "enp0s3" masquerade
    }
}
EOF

# Подключение правила в основной конфиг
if ! grep -q 'include "/etc/nftables/isp.nft"' /etc/sysconfig/nftables.conf; then
    echo 'include "/etc/nftables/isp.nft"' >> /etc/sysconfig/nftables.conf
fi

systemctl enable --now nftables
systemctl restart nftables

echo "=== ISP настроен успешно! ==="
ip -c -br a
