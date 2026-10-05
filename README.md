# Инструкция и антистресс-шпаргалка для демоэкзамена

> [!IMPORTANT]
> **Репозиторий с вашими скриптами:**  
> `https://github.com/snappxcxc/demo-exam.git`  
> 
> **Главное правило: НЕ ПАНИКОВАТЬ!**  
> Идем строго по шагам от 1 до 7. Всё уже автоматизировано.

---

## Сводная таблица запуска

| Шаг | Виртуалка в VirtualBox | Скрипт | Что настраивает |
| :-: | :--- | :--- | :--- |
| **1** | **`ISP`** | `01_isp.sh` | Провайдер, NAT (маскарадинг), раздача интернета в сеть |
| **2** | **`HQ-RTR`** | `02_hq-rtr.sh` | VLAN 100/200/999, NAT, DHCP, первая сторона GRE-туннеля |
| **3** | **`BR-RTR`** | `03_br-rtr.sh` | Стык с ISP, NAT, вторая сторона GRE-туннеля, OSPF |
| **4** | **`BR-FW`** | `04_br-fw.sh` | Межсетевой экран филиала, маршрутизация OSPF |
| **5** | **`HQ-SRV`** | `05_hq-srv.sh` | DNS-сервер (все зоны), юзер sshuser, SSH на порт 2027 |
| **6** | **`BR-SRV`** | `06_br-srv.sh` | Сервер филиала, пользователи, SSH на порт 2027 |
| **7** | **`HQ-CLI`** | `07_hq-cli.sh` | Клиент HQ: получение настроек по DHCP, финальный тест |

---

## Два способа доставки скриптов на виртуалки

### Способ 1: Через общий буфер обмена (САМЫЙ БЫСТРЫЙ И НАДЁЖНЫЙ)
В VirtualBox включите: **Устройства ➔ Общий буфер обмена ➔ Двунаправленный**.
1. На хосте скопируйте текст нужного `.sh` файла целиком (`Ctrl+A`, `Ctrl+C`).
2. В терминале виртуалки напишите:
   ```bash
   cat << 'EOF' > run.sh
   ```
3. Вставьте скопированный текст (нажатием **ПКМ** или клавиш **Shift + Insert**).
4. Нажмите Enter, напишите:
   ```bash
   EOF
   ```
5. Запустите:
   ```bash
   bash run.sh
   ```

---

### Способ 2: Через Git Clone (с вашего GitHub)

#### На машине 1: [ ISP ]
У машины ISP интернет есть сразу:
```bash
dnf install -y git
git clone https://github.com/snappxcxc/demo-exam.git
cd demo-exam
bash 01_isp.sh
```

#### На машинах 2 и 3: [ HQ-RTR ] и [ BR-RTR ]
На них еще нет IP-адресов, поэтому даем временный интернет **одной строчкой**, чтобы сработал `git clone`:

* **На HQ-RTR:**
  ```bash
  ip a a 172.16.1.2/28 dev enp0s3; ip l s enp0s3 up; ip r a default via 172.16.1.1; echo "nameserver 77.88.8.8" > /etc/resolv.conf
  dnf install -y git
  git clone https://github.com/snappxcxc/demo-exam.git
  cd demo-exam
  bash 02_hq-rtr.sh
  ```

* **На BR-RTR:**
  ```bash
  ip a a 172.16.2.2/28 dev enp0s3; ip l s enp0s3 up; ip r a default via 172.16.2.1; echo "nameserver 77.88.8.8" > /etc/resolv.conf
  dnf install -y git
  git clone https://github.com/snappxcxc/demo-exam.git
  cd demo-exam
  bash 03_br-rtr.sh
  ```

---

## Пошаговый план выполнения и быстрая проверка

### Шаг 1. Машина [ ISP ]
* **Запуск:** `bash 01_isp.sh`
* **Проверка:**
  ```bash
  ping ya.ru -c 2
  ```

### Шаг 2. Машина [ HQ-RTR ]
* **Запуск:** `bash 02_hq-rtr.sh`
* **Проверка:**
  ```bash
  ping 172.16.1.1 -c 2
  ```

### Шаг 3. Машина [ BR-RTR ]
* **Запуск:** `bash 03_br-rtr.sh`
* **Проверка связности GRE-туннеля между HQ и BR:**
  ```bash
  ping 10.10.10.1 -c 2
  ```

### Шаг 4. Машина [ BR-FW ]
* **Запуск:** `bash 04_br-fw.sh`
* **Проверка:**
  ```bash
  ping 172.16.10.1 -c 2
  ```

### Шаг 5. Машина [ HQ-SRV ]
* **Запуск:** `bash 05_hq-srv.sh`
* **Проверка зон DNS:**
  ```bash
  named-checkconf -z
  ```

### Шаг 6. Машина [ BR-SRV ]
* **Запуск:** `bash 06_br-srv.sh`
* **Проверка маршрута через всю сеть:**
  ```bash
  traceroute 192.168.100.2
  ```

### Шаг 7. Машина [ HQ-CLI ]
* **Запуск:** `bash 07_hq-cli.sh`
* **Финальная проверка всей работы:**
  ```bash
  host au-team.irpo
  host br-srv.au-team.irpo
  ping 77.88.8.8 -c 2
  ```

---

## Если в билете другие данные (правило 30% изменений)

Если требуется изменить порт SSH (например, `2024` вместо `2027`) или ключ OSPF:
1. Откройте нужный файл:
   ```bash
   nano 05_hq-srv.sh
   ```
2. В самом начале измените значение переменной:
   ```bash
   SSH_PORT="2027"
   OSPF_KEY="P@ssw0rd"
   ```
3. Сохраните: **`Ctrl + O`** ➔ **`Enter`**.
4. Выйдите: **`Ctrl + X`**.
5. Запустите скрипт заново:
   ```bash
   bash 05_hq-srv.sh
   ```
