#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста HQ-SRV (Сервер HQ: DNS, SSH-hardening)
# Поддерживает VirtualBox, Proxmox, VMware (автоопределение интерфейсов)
# ==============================================================================
set -e

# --- ПЕРЕМЕННЫЕ ПОД ВАШ ВАРИАНТ ---
HOSTNAME="hq-srv.au-team.irpo"
TIMEZONE="Europe/Moscow"
DOMAIN="au-team.irpo"

SSH_USER="sshuser"
SSH_UID="2027"
SSH_PASS="P@ssw0rd"
SSH_PORT="2027"

VLAN_ID=100
IP_SRV="192.168.100.2/27"
GW_SRV="192.168.100.1"

# --- АВТООПРЕДЕЛЕНИЕ СЕТЕВОГО ИНТЕРФЕЙСА ---
ETH=($(ip -o link show | awk -F': ' '$2 !~ /^(lo|tun|vlan|virbr|docker)/ {print $2}'))
INT_LAN="${ETH[0]}" # Физический адаптер, подключенный к сети

echo "=== Определен интерфейс: $INT_LAN ==="

echo "[1/5] Имя хоста, часовой пояс и создание пользователя..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

if ! id "$SSH_USER" &>/dev/null; then
    useradd "$SSH_USER" -u "$SSH_UID" -U
    echo "$SSH_USER:$SSH_PASS" | chpasswd
fi
echo "$SSH_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$SSH_USER"
chmod 0440 "/etc/sudoers.d/$SSH_USER"

echo "[2/5] Настройка сети (VLAN $VLAN_ID на $INT_LAN)..."
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_LAN" '$2==d {print $1}' | xargs -r nmcli connection delete
nmcli connection delete "vlan$VLAN_ID" 2>/dev/null || true

nmcli connection add type vlan ifname "vlan$VLAN_ID" con-name "vlan$VLAN_ID" dev "$INT_LAN" id "$VLAN_ID" \
    ip4 "$IP_SRV" gw4 "$GW_SRV" ipv4.dns "192.168.100.2 77.88.8.8" ipv6.method disabled

nmcli connection up "vlan$VLAN_ID" || true

echo "[3/5] Безопасность SSH (Порт $SSH_PORT, баннер, ограничение пользователей)..."
dnf install -y policycoreutils-python-utils

semanage port -a -t ssh_port_t -p tcp "$SSH_PORT" 2>/dev/null || \
semanage port -m -t ssh_port_t -p tcp "$SSH_PORT" 2>/dev/null || true

cat << 'EOF' > /etc/ssh_banner
***************************
*                         *
*  Authorized access only *
*                         *
***************************
EOF

sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^#\?MaxAuthTries .*/MaxAuthTries 2/" /etc/ssh/sshd_config
sed -i "s/^#\?Banner .*/Banner \/etc\/ssh_banner/" /etc/ssh/sshd_config

if ! grep -q "^AllowUsers" /etc/ssh/sshd_config; then
    echo "AllowUsers $SSH_USER" >> /etc/ssh/sshd_config
else
    sed -i "s/^AllowUsers .*/AllowUsers $SSH_USER/" /etc/ssh/sshd_config
fi

systemctl restart sshd

echo "[4/5] Установка и настройка DNS (BIND named)..."
dnf install -y bind bind-utils

cat << EOF > /etc/named.conf
options {
    listen-on port 53 { 127.0.0.1; 192.168.100.2; };
    listen-on-v6 port 53 { none; };
    directory       "/var/named";
    dump-file       "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file   "/var/named/data/named.secroots";
    recursing-file  "/var/named/data/named.recursing";
    allow-query     { 192.168.100.0/27; 192.168.200.0/28; 172.16.20.0/28; localhost; };
    forwarders      { 77.88.8.8; };

    recursion yes;
    dnssec-validation no;
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

zone "." IN {
    type hint;
    file "named.ca";
};

zone "$DOMAIN" {
    type master;
    file "master/au-team.db";
};

zone "100.168.192.in-addr.arpa" {
    type master;
    file "master/au-team_rev1.db";
};

zone "20.16.172.in-addr.arpa" {
    type master;
    file "master/au-team_rev2.db";
};
EOF

mkdir -p /var/named/master

cat << EOF > /var/named/master/au-team.db
\$TTL 1D
@       IN SOA  $DOMAIN. root.$DOMAIN. (
                                0       ; serial
                                1D      ; refresh
                                1H      ; retry
                                1W      ; expire
                                3H )    ; minimum
        IN NS   $DOMAIN.
        IN A    192.168.100.2
hq-rtr  IN A    192.168.100.1
hq-rtr  IN A    192.168.200.1
hq-rtr  IN A    192.168.99.1
br-rtr  IN A    172.16.10.1
hq-srv  IN A    192.168.100.2
hq-cli  IN A    192.168.200.2
br-fw   IN A    172.16.10.2
br-srv  IN A    172.16.20.2
docker  IN A    172.16.1.1
web     IN A    172.16.2.1
EOF

cat << EOF > /var/named/master/au-team_rev1.db
\$TTL 1D
@       IN SOA  $DOMAIN. root.$DOMAIN. (
                                0       ; serial
                                1D      ; refresh
                                1H      ; retry
                                1W      ; expire
                                3H )    ; minimum
        IN NS   $DOMAIN.
2       IN PTR  hq-srv.$DOMAIN.
EOF

cat << EOF > /var/named/master/au-team_rev2.db
\$TTL 1D
@       IN SOA  $DOMAIN. root.$DOMAIN. (
                                0       ; serial
                                1D      ; refresh
                                1H      ; retry
                                1W      ; expire
                                3H )    ; minimum
        IN NS   $DOMAIN.
2       IN PTR  br-srv.$DOMAIN.
EOF

chown -R root:named /var/named/master
chmod 0640 /var/named/master/*
named-checkconf -z

echo "[5/5] Запуск named DNS..."
systemctl enable --now named
systemctl restart named

echo "=== HQ-SRV настроен успешно! ==="
ip -c -br a
