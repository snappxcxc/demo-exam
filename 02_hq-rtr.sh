#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста HQ-RTR (Маршрутизатор HQ)
# Поддерживает VirtualBox, Proxmox, VMware (автоопределение интерфейсов)
# ==============================================================================
set -e

# --- ПЕРЕМЕННЫЕ ПОД ВАШ ВАРИАНТ ---
HOSTNAME="hq-rtr.au-team.irpo"
TIMEZONE="Europe/Moscow"
DOMAIN="au-team.irpo"
OSPF_KEY="P@ssw0rd"
ADMIN_USER="net_admin"
ADMIN_PASS="P@ssw0rd"

# Сети и VLAN
IP_ISP="172.16.1.2/28"
GW_ISP="172.16.1.1"
REMOTE_BR="172.16.2.2"
TUN_IP="10.10.10.1/30"

VLAN100_ID=100
VLAN100_IP="192.168.100.1/27"

VLAN200_ID=200
VLAN200_IP="192.168.200.1/28"

VLAN999_ID=999
VLAN999_IP="192.168.99.1/29"

# DHCP настройки для VLAN 200
DHCP_NET="192.168.200.0"
DHCP_MASK="255.255.255.240"
DHCP_START="192.168.200.2"
DHCP_END="192.168.200.14"
DHCP_DNS="192.168.100.2"
DHCP_ROUTER="192.168.200.1"

# --- АВТООПРЕДЕЛЕНИЕ СЕТЕВЫХ ИНТЕРФЕЙСОВ ---
ETH=($(ip -o link show | awk -F': ' '$2 !~ /^(lo|tun|vlan|virbr|docker)/ {print $2}'))
INT_ISP="${ETH[0]}"  # 1-й адаптер: В сторону ISP
INT_LAN="${ETH[1]}"  # 2-й адаптер: Внутренний свитч HQ

echo "=== Определены интерфейсы: ISP=$INT_ISP, LAN=$INT_LAN ==="

echo "[1/7] Имя хоста, часовой пояс, модуль 8021q и ip_forward..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

modprobe 8021q
echo "8021q" > /etc/modules-load.d/8021q.conf

if ! id "$ADMIN_USER" &>/dev/null; then
    useradd "$ADMIN_USER" -U
    echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
    echo "$ADMIN_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$ADMIN_USER"
fi

echo "[2/7] Настройка интерфейсов и VLAN (802.1Q)..."
# Удаляем старые подключения на этих интерфейсах
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_ISP" '$2==d {print $1}' | xargs -r nmcli connection delete
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_LAN" '$2==d {print $1}' | xargs -r nmcli connection delete
nmcli connection delete "vlan$VLAN100_ID" 2>/dev/null || true
nmcli connection delete "vlan$VLAN200_ID" 2>/dev/null || true
nmcli connection delete "vlan$VLAN999_ID" 2>/dev/null || true
nmcli connection delete "tun1" 2>/dev/null || true

# Внешний интерфейс в сторону ISP
nmcli connection add type ethernet ifname "$INT_ISP" con-name "ISP-HQ" \
    ip4 "$IP_ISP" gw4 "$GW_ISP" ipv4.dns 77.88.8.8 ipv6.method disabled

# Активация физического интерфейса под VLAN
nmcli connection add type ethernet ifname "$INT_LAN" con-name "$INT_LAN" ipv4.method disabled ipv6.method disabled 2>/dev/null || true

# Сабинтерфейсы VLAN
nmcli connection add type vlan ifname "vlan$VLAN100_ID" con-name "vlan$VLAN100_ID" dev "$INT_LAN" id "$VLAN100_ID" \
    ip4 "$VLAN100_IP" ipv6.method disabled

nmcli connection add type vlan ifname "vlan$VLAN200_ID" con-name "vlan$VLAN200_ID" dev "$INT_LAN" id "$VLAN200_ID" \
    ip4 "$VLAN200_IP" ipv6.method disabled

nmcli connection add type vlan ifname "vlan$VLAN999_ID" con-name "vlan$VLAN999_ID" dev "$INT_LAN" id "$VLAN999_ID" \
    ip4 "$VLAN999_IP" ipv6.method disabled

echo "[3/7] Настройка GRE-туннеля tun1..."
nmcli connection add type ip-tunnel ifname tun1 con-name "tun1" mode gre \
    parent "$INT_ISP" local "${IP_ISP%/*}" remote "$REMOTE_BR" \
    ip4 "$TUN_IP" ipv6.method disabled
nmcli connection modify tun1 ip-tunnel.ttl 64

nmcli connection up "ISP-HQ" || true
nmcli connection up "vlan$VLAN100_ID" || true
nmcli connection up "vlan$VLAN200_ID" || true
nmcli connection up "vlan$VLAN999_ID" || true
nmcli connection up "tun1" || true

echo "[4/7] Настройка NAT (nftables)..."
mkdir -p /etc/nftables
cat << EOF > /etc/nftables/hq-rtr.nft
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat;
        oifname "$INT_ISP" masquerade
    }
}
EOF

if ! grep -q 'include "/etc/nftables/hq-rtr.nft"' /etc/sysconfig/nftables.conf; then
    echo 'include "/etc/nftables/hq-rtr.nft"' >> /etc/sysconfig/nftables.conf
fi

systemctl enable --now nftables
systemctl restart nftables

echo "[5/7] Установка и настройка DHCP-сервера..."
dnf install -y dhcp-server

cat << EOF > /etc/dhcp/dhcpd.conf
subnet $DHCP_NET netmask $DHCP_MASK {
  range $DHCP_START $DHCP_END;
  option domain-name-servers $DHCP_DNS;
  option domain-name "$DOMAIN";
  option routers $DHCP_ROUTER;
  default-lease-time 600;
  max-lease-time 7200;
}
EOF

systemctl enable --now dhcpd
systemctl restart dhcpd

echo "[6/7] Установка и настройка OSPF (FRR)..."
dnf install -y frr

sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons

cat << EOF > /etc/frr/frr.conf
frr defaults traditional
hostname $HOSTNAME
!
interface tun1
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 $OSPF_KEY
 no ip ospf passive
!
router ospf
 passive-interface default
 network 10.10.10.0/30 area 0
 network 192.168.99.0/29 area 0
 network 192.168.100.0/27 area 0
 network 192.168.200.0/28 area 0
!
line vty
!
EOF

chown -R frr:frr /etc/frr
chmod 640 /etc/frr/frr.conf
systemctl enable --now frr
systemctl restart frr

echo "=== HQ-RTR настроен успешно! ==="
ip -c -br a
