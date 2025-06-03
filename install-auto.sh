#!/bin/bash

# UrBackup Docker Auto Installer with User Creation
# Ubuntu 24.04 LTS Full Auto Installer
# Author: DevOps Engineer
# Date: 2025-06-03
# Version: 1.1

set -e

# Переменные окружения с дефолтными значениями
URBACKUP_USER=${URBACKUP_USER:-urbackup}
URBACKUP_WEB_PORT=${URBACKUP_WEB_PORT:-55414}
URBACKUP_SERVER_PORT=${URBACKUP_SERVER_PORT:-55413}
URBACKUP_FASTCGI_PORT=${URBACKUP_FASTCGI_PORT:-35623}
SKIP_UFW=${SKIP_UFW:-no}

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функции логирования
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Функция для отображения прогресса
show_progress() {
    local current=$1
    local total=$2
    local desc=$3
    local percent=$((current * 100 / total))
    local bar_length=30
    local filled_length=$((percent * bar_length / 100))
    
    printf "\r${CYAN}Progress:${NC} ["
    printf "%*s" $filled_length | tr ' ' '='
    printf "%*s" $((bar_length - filled_length)) | tr ' ' '-'
    printf "] %d%% - %s" $percent "$desc"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# Проверка что мы под root
check_root_required() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Для автоматического создания пользователя нужны root права!"
        log_info "Запустите: sudo bash install.sh"
        exit 1
    fi
}

# Проверка Ubuntu
check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_error "Скрипт поддерживает только Ubuntu. Обнаружена другая ОС."
        exit 1
    fi
    
    local ubuntu_version=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
    if [[ "$ubuntu_version" < "20.04" ]]; then
        log_warning "Обнаружена Ubuntu $ubuntu_version. Рекомендуется Ubuntu 20.04+"
        read -p "Продолжить установку? (y/N): " -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Обнаружена Ubuntu $ubuntu_version"
    fi
}

# Создание пользователя
create_user() {
    log_step "Создание пользователя $URBACKUP_USER..."
    
    # Проверить что пользователь не существует
    if id "$URBACKUP_USER" &>/dev/null; then
        log_warning "Пользователь $URBACKUP_USER уже существует"
        return 0
    fi
    
    # Создать пользователя без интерактивного ввода
    useradd -m -s /bin/bash "$URBACKUP_USER"
    
    # Создать случайный пароль
    local password=$(openssl rand -base64 12)
    echo "$URBACKUP_USER:$password" | chpasswd
    
    # Добавить в группу sudo
    usermod -aG sudo "$URBACKUP_USER"
    
    # Настроить sudo без пароля для этого пользователя (только для установки)
    echo "$URBACKUP_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$URBACKUP_USER"
    
    log_success "Пользователь $URBACKUP_USER создан"
    log_info "Пароль: $password (сохраните его!)"
}

# Получение IP адреса
get_server_ip() {
    SERVER_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}' 2>/dev/null)
    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP=$(hostname -I | awk '{print $1}')
    fi
    if [[ -z "$SERVER_IP" ]]; then
        log_error "Не удалось определить IP адрес сервера"
        exit 1
    fi
    log_success "IP сервера: $SERVER_IP"
}

# Создание установочного скрипта для пользователя
create_user_install_script() {
    log_step "Создание установочного скрипта для пользователя..."
    
    local user_home="/home/$URBACKUP_USER"
    local script_path="$user_home/urbackup_install.sh"
    
    cat > "$script_path" << 'EOF'
#!/bin/bash

# UrBackup Installation Script (User Part)
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

show_progress() {
    local current=$1
    local total=$2
    local desc=$3
    local percent=$((current * 100 / total))
    local bar_length=30
    local filled_length=$((percent * bar_length / 100))
    
    printf "\r${CYAN}Progress:${NC} ["
    printf "%*s" $filled_length | tr ' ' '='
    printf "%*s" $((bar_length - filled_length)) | tr ' ' '-'
    printf "] %d%% - %s" $percent "$desc"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

# Переменные (будут заменены основным скриптом)
URBACKUP_WEB_PORT="PLACEHOLDER_WEB_PORT"
URBACKUP_SERVER_PORT="PLACEHOLDER_SERVER_PORT"
URBACKUP_FASTCGI_PORT="PLACEHOLDER_FASTCGI_PORT"
SKIP_UFW="PLACEHOLDER_SKIP_UFW"
SERVER_IP="PLACEHOLDER_SERVER_IP"

log_step "Установка UrBackup Docker от пользователя $(whoami)..."

# Обновление системы
log_step "Обновление системы..."
show_progress 1 10 "Обновление списка пакетов"
sudo apt update -qq

show_progress 2 10 "Установка базовых пакетов"
sudo apt install -y -qq curl wget gpg lsb-release ca-certificates apt-transport-https software-properties-common

# Установка Docker
if ! command -v docker &> /dev/null; then
    log_step "Установка Docker..."
    show_progress 3 10 "Добавление репозитория Docker"
    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    show_progress 5 10 "Установка Docker Engine"
    sudo apt update -qq
    sudo apt install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    sudo usermod -aG docker $(whoami)
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log_success "Docker установлен"
else
    log_success "Docker уже установлен"
fi

# Проверка Docker Compose (используем plugin, а не standalone)
if ! docker compose version &> /dev/null; then
    log_step "Настройка Docker Compose..."
    show_progress 6 10 "Проверка Docker Compose Plugin"
    
    # Удаляем старый docker-compose если установлен
    sudo apt remove -y -qq docker-compose 2>/dev/null || true
    sudo rm -f /usr/local/bin/docker-compose 2>/dev/null || true
    
    # Проверяем что plugin установлен с Docker
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose plugin не найден. Переустанавливаем Docker..."
        sudo apt install -y -qq docker-compose-plugin
    fi
    
    log_success "Docker Compose plugin готов"
else
    log_success "Docker Compose plugin уже установлен"
fi

# Создание рабочей директории
INSTALL_DIR="$HOME/urbackup-docker"
log_step "Создание рабочей директории: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Создание структуры директорий
mkdir -p urbackup/{backups,database,config}
chmod -R 755 urbackup/

show_progress 7 10 "Создание конфигурации Docker"

# Создание docker-compose.yml
cat > docker-compose.yml << COMPOSE_EOF
version: '3.8'

services:
  urbackup-server:
    image: uroni/urbackup-server:latest
    container_name: urbackup-server
    restart: unless-stopped
    ports:
      - "${URBACKUP_SERVER_PORT}:55413"
      - "${URBACKUP_WEB_PORT}:55414"
      - "${URBACKUP_FASTCGI_PORT}:35623"
    volumes:
      - ./urbackup/backups:/var/urbackup:rw
      - ./urbackup/database:/var/lib/urbackup:rw
      - ./urbackup/config:/etc/urbackup:rw
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Moscow
    networks:
      - urbackup-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:55414/x?a=status"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  urbackup-net:
    driver: bridge

COMPOSE_EOF

# Создание systemd сервиса
log_step "Создание systemd сервиса..."
sudo tee /etc/systemd/system/urbackup-docker.service > /dev/null << SERVICE_EOF
[Unit]
Description=UrBackup Docker Service
Documentation=https://urbackup.org/
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStartPre=/usr/bin/docker compose pull -q
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=300
User=$(whoami)
Group=docker

[Install]
WantedBy=multi-user.target

SERVICE_EOF

sudo systemctl daemon-reload
sudo systemctl enable urbackup-docker.service

# Настройка firewall
if [[ "$SKIP_UFW" != "yes" ]]; then
    log_step "Настройка UFW firewall..."
    
    if ! command -v ufw &> /dev/null; then
        sudo apt install -y -qq ufw
    fi
    
    sudo ufw --force reset > /dev/null 2>&1
    sudo ufw default deny incoming > /dev/null 2>&1
    sudo ufw default allow outgoing > /dev/null 2>&1
    sudo ufw allow ssh > /dev/null 2>&1
    sudo ufw allow $URBACKUP_SERVER_PORT/tcp comment 'UrBackup Internet Protocol' > /dev/null 2>&1
    sudo ufw allow $URBACKUP_WEB_PORT/tcp comment 'UrBackup Web Interface' > /dev/null 2>&1
    sudo ufw allow $URBACKUP_FASTCGI_PORT/tcp comment 'UrBackup FastCGI' > /dev/null 2>&1
    sudo ufw --force enable > /dev/null 2>&1
    
    log_success "UFW настроен"
fi

show_progress 8 10 "Запуск UrBackup сервера"

# Запуск UrBackup
log_step "Запуск UrBackup сервера..."
sudo docker compose up -d

# Ожидание готовности
log_info "Ожидание готовности сервиса..."
sleep 15

# Проверка статуса
if sudo docker compose ps | grep -q "Up"; then
    show_progress 10 10 "UrBackup сервер готов"
    log_success "UrBackup сервер запущен успешно!"
else
    log_error "Ошибка запуска контейнера"
    sudo docker compose logs
    exit 1
fi

# Создание скрипта управления
cat > urbackup-control.sh << 'CONTROL_EOF'
#!/bin/bash
case "$1" in
    start)
        echo "Запуск UrBackup сервера..."
        docker compose up -d
        ;;
    stop)
        echo "Остановка UrBackup сервера..."
        docker compose down
        ;;
    restart)
        echo "Перезапуск UrBackup сервера..."
        docker compose restart
        ;;
    status)
        echo "Статус UrBackup сервера:"
        docker compose ps
        ;;
    logs)
        echo "Логи UrBackup сервера:"
        docker compose logs -f
        ;;
    update)
        echo "Обновление UrBackup сервера..."
        docker compose pull
        docker compose up -d
        ;;
    info)
        SERVER_IP=$(hostname -I | awk '{print $1}')
        echo "=========================================="
        echo "  UrBackup Server Information"
        echo "=========================================="
        echo "Web Interface: http://$SERVER_IP:PLACEHOLDER_WEB_PORT"
        echo "Server Address: $SERVER_IP"
        echo "Working Directory: $(pwd)"
        echo
        echo "Data Directories:"
        echo "  Backups:  $(pwd)/urbackup/backups/"
        echo "  Database: $(pwd)/urbackup/database/"
        echo "  Config:   $(pwd)/urbackup/config/"
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|status|logs|update|info}"
        exit 1
        ;;
esac
CONTROL_EOF

chmod +x urbackup-control.sh

# Вывод финальной информации
clear
echo
echo "=========================================="
log_success "🎉 UrBackup установлен успешно! 🎉"
echo "=========================================="
echo
echo -e "${BLUE}📍 Веб-интерфейс:${NC}"
echo "   http://$SERVER_IP:$URBACKUP_WEB_PORT"
echo
echo -e "${BLUE}🖥️  Адрес сервера для клиентов:${NC}"
echo "   $SERVER_IP"
echo
echo -e "${BLUE}🎛️  Управление сервером:${NC}"
echo "   cd $INSTALL_DIR"
echo "   ./urbackup-control.sh start|stop|restart|status|logs|update|info"
echo
echo -e "${BLUE}📁 Директории:${NC}"
echo "   $INSTALL_DIR/urbackup/backups/   # хранилище бэкапов"
echo "   $INSTALL_DIR/urbackup/database/  # база данных"
echo "   $INSTALL_DIR/urbackup/config/    # конфигурация"
echo
echo -e "${YELLOW}🚀 Следующие шаги:${NC}"
echo "1. Откройте http://$SERVER_IP:$URBACKUP_WEB_PORT в браузере"
echo "2. Пройдите мастер первоначальной настройки"
echo "3. Скачайте клиенты для Windows компьютеров"
echo "4. Настройте расписания бэкапов"
echo
echo -e "${GREEN}✨ Установка завершена! Приятного использования! ✨${NC}"
echo

EOF

    # Заменить плейсхолдеры на реальные значения
    sed -i "s/PLACEHOLDER_WEB_PORT/$URBACKUP_WEB_PORT/g" "$script_path"
    sed -i "s/PLACEHOLDER_SERVER_PORT/$URBACKUP_SERVER_PORT/g" "$script_path"
    sed -i "s/PLACEHOLDER_FASTCGI_PORT/$URBACKUP_FASTCGI_PORT/g" "$script_path"
    sed -i "s/PLACEHOLDER_SKIP_UFW/$SKIP_UFW/g" "$script_path"
    sed -i "s/PLACEHOLDER_SERVER_IP/$SERVER_IP/g" "$script_path"
    
    # Установить права
    chown "$URBACKUP_USER:$URBACKUP_USER" "$script_path"
    chmod +x "$script_path"
    
    log_success "Установочный скрипт создан: $script_path"
}

# Запуск установки от пользователя
run_user_installation() {
    log_step "Запуск установки от пользователя $URBACKUP_USER..."
    
    local user_home="/home/$URBACKUP_USER"
    local script_path="$user_home/urbackup_install.sh"
    
    # Переключиться на пользователя и запустить скрипт
    sudo -u "$URBACKUP_USER" bash "$script_path"
    
    # Удалить временный скрипт
    rm -f "$script_path"
    
    # Удалить sudo права без пароля после установки
    rm -f "/etc/sudoers.d/$URBACKUP_USER"
    
    log_success "Установка завершена!"
}

# Основная функция
main() {
    clear
    echo "=========================================="
    echo "  🐳 UrBackup Docker Auto Installer"
    echo "  Full Automation with User Creation"
    echo "  Ubuntu 24.04 LTS"
    echo "=========================================="
    echo
    
    check_root_required
    check_ubuntu
    get_server_ip
    create_user
    create_user_install_script
    run_user_installation
}

# Запуск
main "$@"
