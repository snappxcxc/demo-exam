#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста BR-SRV (Сервер филиала BR: SSH-hardening)
# ==============================================================================
set -e

HOSTNAME="br-srv.au-team.irpo"
TIMEZONE="Europe/Moscow"
ADMIN_USER="net_admin"
ADMIN_PASS="P@ssw0rd"
SSH_USER="sshuser"
SSH_PASS="P@ssw0rd"
SSH_PORT="2027"

echo "[1/4] Имя хоста, часовой пояс и пользователи..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

# Создаём net_admin (по заданию 1)
if ! id "$ADMIN_USER" &>/dev/null; then
    useradd "$ADMIN_USER" -U
    echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
fi
echo "$ADMIN_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$ADMIN_USER"
chmod 0440 "/etc/sudoers.d/$ADMIN_USER"

# Также создаём sshuser (для тестов из задания 5)
if ! id "$SSH_USER" &>/dev/null; then
    useradd "$SSH_USER" -u 2027 -U 2>/dev/null || useradd "$SSH_USER" -U
    echo "$SSH_USER:$SSH_PASS" | chpasswd
fi
echo "$SSH_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$SSH_USER"
chmod 0440 "/etc/sudoers.d/$SSH_USER"

echo "[2/4] Настройка сетевого интерфейса enp0s3..."
nmcli connection delete "BR-NET" 2>/dev/null || true
nmcli connection delete "enp0s3" 2>/dev/null || true

nmcli connection add type ethernet ifname enp0s3 con-name "BR-NET" \
    ip4 172.16.20.2/28 gw4 172.16.20.1 ipv4.dns "192.168.100.2 77.88.8.8" ipv6.method disabled

nmcli connection up "BR-NET" || true

echo "[3/4] Безопасность SSH (Порт $SSH_PORT, баннер, ограничение пользователей)..."
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
    echo "AllowUsers $ADMIN_USER $SSH_USER" >> /etc/ssh/sshd_config
else
    sed -i "s/^AllowUsers .*/AllowUsers $ADMIN_USER $SSH_USER/" /etc/ssh/sshd_config
fi

systemctl restart sshd

echo "=== BR-SRV настроен успешно! ==="
ip -c -br a
