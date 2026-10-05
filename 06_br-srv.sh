#!/bin/bash
# ==============================================================================
# Скрипт настройки хоста BR-SRV (Сервер филиала BR: SSH-hardening)
# Поддерживает VirtualBox, Proxmox, VMware (автоопределение интерфейсов)
# ==============================================================================
set -e

# --- ПЕРЕМЕННЫЕ ПОД ВАШ ВАРИАНТ ---
HOSTNAME="br-srv.au-team.irpo"
TIMEZONE="Europe/Moscow"
ADMIN_USER="net_admin"
ADMIN_PASS="P@ssw0rd"
SSH_USER="sshuser"
SSH_PASS="P@ssw0rd"
SSH_PORT="2027"

IP_BR_SRV="172.16.20.2/28"
GW_BR_SRV="172.16.20.1"

# --- АВТООПРЕДЕЛЕНИЕ СЕТЕВОГО ИНТЕРФЕЙСА ---
ETH=($(ip -o link show | awk -F': ' '$2 !~ /^(lo|tun|vlan|virbr|docker)/ {print $2}'))
INT_LAN="${ETH[0]}" # Физический адаптер к сети BR-NET

echo "=== Определен интерфейс: $INT_LAN ==="

echo "[1/4] Имя хоста, часовой пояс и пользователи..."
hostnamectl set-hostname "$HOSTNAME"
timedatectl set-timezone "$TIMEZONE"

# Создаём net_admin (по заданию)
if ! id "$ADMIN_USER" &>/dev/null; then
    useradd "$ADMIN_USER" -U
    echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
fi
echo "$ADMIN_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$ADMIN_USER"
chmod 0440 "/etc/sudoers.d/$ADMIN_USER"

# Создаём sshuser (для тестов доступа)
if ! id "$SSH_USER" &>/dev/null; then
    useradd "$SSH_USER" -u 2027 -U 2>/dev/null || useradd "$SSH_USER" -U
    echo "$SSH_USER:$SSH_PASS" | chpasswd
fi
echo "$SSH_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$SSH_USER"
chmod 0440 "/etc/sudoers.d/$SSH_USER"

echo "[2/4] Настройка сетевого интерфейса $INT_LAN..."
nmcli -t -f UUID,DEVICE connection show | awk -F: -v d="$INT_LAN" '$2==d {print $1}' | xargs -r nmcli connection delete
nmcli connection delete "BR-NET" 2>/dev/null || true

nmcli connection add type ethernet ifname "$INT_LAN" con-name "BR-NET" \
    ip4 "$IP_BR_SRV" gw4 "$GW_BR_SRV" ipv4.dns "192.168.100.2 77.88.8.8" ipv6.method disabled

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
