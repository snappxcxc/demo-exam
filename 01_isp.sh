#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста ISP (Провайдер)
# Поддерживает VirtualBox (enp0sX), Proxmox (ensX / ethX), VMware (ens33/34)
# ==============================================================================
set -e

# --- ПЕРЕМЕННЫЕ ПОД ВАШ ВАРИАНТ ---
HOSTNAME="isp"
TIMEZONE="Europe/Moscow"
NET_HQ_IP="172.16.1.1/28"
NET_BR_IP="172.16.2.1/28"

# --- АВТООПРЕДЕЛЕНИЕ СЕТЕВЫХ ИНТЕРФЕЙСОВ ---
# Находим все физические Ethernet-адаптеры по порядку
ETH=($(ip -o link show | awk -F': ' '$2 !~ /^(lo|tun|vlan|virbr|docker)/ {print $2}'))
INT_INET="${ETH[0]}"  # 1-й адаптер: Интернет (DHCP)
INT_HQ="${ETH[1]}"    # 2-й адаптер: В сторону HQ
INT_BR="${ETH[2]}"    # 3-й адаптер: В сторону BR

echo "=== Определены интерфейсы: Интернет=$INT_INET, HQ=$INT_HQ, BR=$INT_BR ==="

echo "[1/4] Имя хоста и часовой пояс..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

echo "[2/4] Включение маршрутизации ядра (ip_forward)..."
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "[3/4] Настройка сетевых интерфейсов..."
# Удаляем старые привязки к этим устройствам
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_INET" '$2==d {print $1}' | xargs -r nmcli connection delete
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_HQ" '$2==d {print $1}' | xargs -r nmcli connection delete
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_BR" '$2==d {print $1}' | xargs -r nmcli connection delete

# 1. Внешний интернет (DHCP)
nmcli connection add type ethernet ifname "$INT_INET" con-name "Internet" ipv4.method auto ipv6.method disabled

# 2. В сторону HQ
nmcli connection add type ethernet ifname "$INT_HQ" con-name "ISP-HQ" ip4 "$NET_HQ_IP" ipv6.method disabled

# 3. В сторону BR
nmcli connection add type ethernet ifname "$INT_BR" con-name "ISP-BR" ip4 "$NET_BR_IP" ipv6.method disabled

nmcli connection up "Internet" || true
nmcli connection up "ISP-HQ" || true
nmcli connection up "ISP-BR" || true

echo "[4/4] Настройка NAT (nftables)..."
mkdir -p /etc/nftables
cat << EOF > /etc/nftables/isp.nft
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat;
        oifname "$INT_INET" masquerade
    }
}
EOF

if ! grep -q 'include "/etc/nftables/isp.nft"' /etc/sysconfig/nftables.conf; then
    echo 'include "/etc/nftables/isp.nft"' >> /etc/sysconfig/nftables.conf
fi

systemctl enable --now nftables
systemctl restart nftables

echo "=== ISP настроен успешно! ==="
ip -c -br a
