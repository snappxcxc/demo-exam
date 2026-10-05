#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста BR-RTR (Маршрутизатор филиала BR)
# ==============================================================================
set -e

HOSTNAME="br-rtr.au-team.irpo"
TIMEZONE="Europe/Moscow"
OSPF_KEY="P@ssw0rd"

echo "[1/5] Имя хоста, часовой пояс и ip_forward..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

echo "[2/5] Настройка сетевых интерфейсов..."
nmcli connection delete "ISP-BR" 2>/dev/null || true
nmcli connection delete "FW-NET" 2>/dev/null || true
nmcli connection delete "tun1" 2>/dev/null || true

# В сторону провайдера
nmcli connection add type ethernet ifname enp0s3 con-name "ISP-BR" \
    ip4 172.16.2.2/28 gw4 172.16.2.1 ipv4.dns 77.88.8.8 ipv6.method disabled

# В сторону межсетевого экрана BR-FW
nmcli connection add type ethernet ifname enp0s8 con-name "FW-NET" \
    ip4 172.16.10.1/30 ipv6.method disabled

echo "[3/5] Настройка GRE-туннеля tun1..."
nmcli connection add type ip-tunnel ifname tun1 con-name "tun1" mode gre \
    parent enp0s3 local 172.16.2.2 remote 172.16.1.2 \
    ip4 10.10.10.2/30 ipv6.method disabled
nmcli connection modify tun1 ip-tunnel.ttl 64

# Поднимаем подключения
nmcli connection up "ISP-BR" || true
nmcli connection up "FW-NET" || true
nmcli connection up "tun1" || true

echo "[4/5] Настройка NAT (nftables)..."
mkdir -p /etc/nftables
cat << 'EOF' > /etc/nftables/br-rtr.nft
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat;
        oifname "enp0s3" masquerade
    }
}
EOF

if ! grep -q 'include "/etc/nftables/br-rtr.nft"' /etc/sysconfig/nftables.conf; then
    echo 'include "/etc/nftables/br-rtr.nft"' >> /etc/sysconfig/nftables.conf
fi

systemctl enable --now nftables
systemctl restart nftables

echo "[5/5] Установка и настройка OSPF (FRR)..."
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
interface enp0s8
 no ip ospf passive
!
router ospf
 passive-interface default
 network 10.10.10.0/30 area 0
 network 172.16.10.0/30 area 0
!
line vty
!
EOF

chown -R frr:frr /etc/frr
chmod 640 /etc/frr/frr.conf
systemctl enable --now frr
systemctl restart frr

echo "=== BR-RTR настроен успешно! ==="
ip -c -br a
