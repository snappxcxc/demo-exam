#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста HQ-RTR (Маршрутизатор HQ)
# ==============================================================================
set -e

# Переменные (при необходимости измените под свой вариант)
HOSTNAME="hq-rtr.au-team.irpo"
TIMEZONE="Europe/Moscow"
DOMAIN="au-team.irpo"
OSPF_KEY="P@ssw0rd"
ADMIN_USER="net_admin"
ADMIN_PASS="P@ssw0rd"

echo "[1/7] Имя хоста, часовой пояс, модуль 8021q и ip_forward..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

modprobe 8021q
echo "8021q" > /etc/modules-load.d/8021q.conf

# Создание пользователя net_admin для проверки SSH-доступа
if ! id "$ADMIN_USER" &>/dev/null; then
    useradd "$ADMIN_USER" -U
    echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
    echo "$ADMIN_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$ADMIN_USER"
fi

echo "[2/7] Настройка интерфейсов и VLAN (802.1Q)..."
# Очистка старых профилей
nmcli connection delete "ISP-HQ" 2>/dev/null || true
nmcli connection delete "vlan100" 2>/dev/null || true
nmcli connection delete "vlan200" 2>/dev/null || true
nmcli connection delete "vlan999" 2>/dev/null || true
nmcli connection delete "tun1" 2>/dev/null || true

# Внешний интерфейс в сторону ISP
nmcli connection add type ethernet ifname enp0s3 con-name "ISP-HQ" \
    ip4 172.16.1.2/28 gw4 172.16.1.1 ipv4.dns 77.88.8.8 ipv6.method disabled

# Активация физического интерфейса enp0s8 под VLAN
nmcli connection add type ethernet ifname enp0s8 con-name "enp0s8" ipv4.method disabled ipv6.method disabled 2>/dev/null || true

# Сабинтерфейсы VLAN
nmcli connection add type vlan ifname vlan100 con-name "vlan100" dev enp0s8 id 100 \
    ip4 192.168.100.1/27 ipv6.method disabled

nmcli connection add type vlan ifname vlan200 con-name "vlan200" dev enp0s8 id 200 \
    ip4 192.168.200.1/28 ipv6.method disabled

nmcli connection add type vlan ifname vlan999 con-name "vlan999" dev enp0s8 id 999 \
    ip4 192.168.99.1/29 ipv6.method disabled

echo "[3/7] Настройка GRE-туннеля tun1..."
nmcli connection add type ip-tunnel ifname tun1 con-name "tun1" mode gre \
    parent enp0s3 local 172.16.1.2 remote 172.16.2.2 \
    ip4 10.10.10.1/30 ipv6.method disabled
nmcli connection modify tun1 ip-tunnel.ttl 64

# Поднимаем все соединения
nmcli connection up "ISP-HQ" || true
nmcli connection up "vlan100" || true
nmcli connection up "vlan200" || true
nmcli connection up "vlan999" || true
nmcli connection up "tun1" || true

echo "[4/7] Настройка NAT (nftables)..."
mkdir -p /etc/nftables
cat << 'EOF' > /etc/nftables/hq-rtr.nft
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat;
        oifname "enp0s3" masquerade
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
subnet 192.168.200.0 netmask 255.255.255.240 {
  range 192.168.200.2 192.168.200.14;
  option domain-name-servers 192.168.100.2;
  option domain-name "$DOMAIN";
  option routers 192.168.200.1;
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
