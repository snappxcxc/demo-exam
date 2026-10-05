# Бронебойная шпаргалка: Порядок запуска без зависаний

> [!IMPORTANT]
> **Репозиторий:** `https://github.com/snappxcxc/demo-exam`  
> **Скрипты обновлены:** теперь они сами определяют сетевые карты в **Proxmox**, **VMware** и **VirtualBox**!
>
> ❌ **НЕ вставляйте текст скриптов через буфер (Shift+Insert в VNC)** — это намертво вешает веб-консоль Proxmox/VMware!  
> ❌ **НЕ ставьте тяжелый `git`** — скачивание через `curl` занимает ровно 0.1 секунды.

---

## ⚡ Самый быстрый и надежный способ запуска (Через curl)

### Шаг 1. Перейдите на машину [ ISP ]
На ISP внешний интернет работает сразу из коробки:
```bash
curl -sO https://raw.githubusercontent.com/snappxcxc/demo-exam/main/01_isp.sh
bash 01_isp.sh
```

> **Лайфхак для остальных машин:** чтобы не зависеть от интернета на других виртуалках, прямо на ISP запустите локальную раздачу файлов в фоне:
> ```bash
> python3 -m http.server 80 &
> ```
> *(Теперь все остальные машины могут скачивать скрипты мгновенно прямо с ISP!)*

---

### Шаг 2. Перейдите на машину [ HQ-RTR ]
Скачиваем скрипт прямо с ISP (IP 172.16.1.1) одной строкой:
```bash
ip a a 172.16.1.2/28 dev $(ip -o link show | awk -F': ' '$2 !~ /lo/ {print $2; exit}')
curl -sO http://172.16.1.1/02_hq-rtr.sh || curl -sO https://raw.githubusercontent.com/snappxcxc/demo-exam/main/02_hq-rtr.sh
bash 02_hq-rtr.sh
```
*Проверка:* `ping 172.16.1.1 -c 2`

---

### Шаг 3. Перейдите на машину [ BR-RTR ]
Скачиваем скрипт прямо с ISP (IP 172.16.2.1) одной строкой:
```bash
ip a a 172.16.2.2/28 dev $(ip -o link show | awk -F': ' '$2 !~ /lo/ {print $2; exit}')
curl -sO http://172.16.2.1/03_br-rtr.sh || curl -sO https://raw.githubusercontent.com/snappxcxc/demo-exam/main/03_br-rtr.sh
bash 03_br-rtr.sh
```
*Проверка связности туннеля:* `ping 10.10.10.1 -c 2`

---

### Шаг 4. Перейдите на машину [ BR-FW ]
На роутере BR-RTR поднят OSPF, интернет теперь есть:
```bash
curl -sO https://raw.githubusercontent.com/snappxcxc/demo-exam/main/04_br-fw.sh
bash 04_br-fw.sh
```
*Проверка:* `ping 172.16.10.1 -c 2`

---

### Шаг 5. Перейдите на машину [ HQ-SRV ]
```bash
curl -sO https://raw.githubusercontent.com/snappxcxc/demo-exam/main/05_hq-srv.sh
bash 05_hq-srv.sh
```
*Проверка DNS:* `named-checkconf -z`

---

### Шаг 6. Перейдите на машину [ BR-SRV ]
```bash
curl -sO https://raw.githubusercontent.com/snappxcxc/demo-exam/main/06_br-srv.sh
bash 06_br-srv.sh
```
*Проверка связи с сервером главного офиса:* `traceroute 192.168.100.2`

---

### Шаг 7. Перейдите на машину [ HQ-CLI ]
```bash
curl -sO https://raw.githubusercontent.com/snappxcxc/demo-exam/main/07_hq-cli.sh
bash 07_hq-cli.sh
```
*Финальная проверка:*
```bash
host au-team.irpo
host br-srv.au-team.irpo
ping 77.88.8.8 -c 2
```

---

## 🛠 Что делать, если в билете другие IP / пароли / порты
Перед запуском скрипта откройте его в `nano`:
```bash
nano 02_hq-rtr.sh
```
В самом верху файла в блоке **`ПЕРЕМЕННЫЕ ПОД ВАШ ВАРИАНТ`** измените нужные значения.  
Сохранение: **`Ctrl + O`** ➔ **`Enter`**, выход: **`Ctrl + X`**.
