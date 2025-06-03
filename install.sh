#!/bin/bash

# UrBackup Server Docker Installation Script
# Ubuntu 24.04 LTS - Fixed Docker Compose compatibility
# Author: DevOps Engineer
# Date: 2025-06-03
# Version: 1.1

set -e

# Переменные окружения с дефолтными значениями
URBACKUP_WEB_PORT=${URBACKUP_WEB_PORT:-55414}
URBACKUP_SERVER_PORT=${URBACKUP_SERVER_PORT:-55413}
URBACKUP_FASTCGI_PORT=${URBACKUP_FASTCGI_PORT:-35623}
SKIP_UFW=${SKIP_UFW:-no}
INSTALL_DIR=${INSTALL_DIR:-$(pwd)/urbackup-docker}

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# Проверка root прав
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Не запускайте скрипт от root! Используйте обычного пользователя с sudo правами."
        log_info "Правильное использование: curl -sSL https://raw.githubusercontent.com/ваш_repo/install.sh | bash"
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

# Проверка системных требований
check_system_requirements() {
    log_step "Проверка системных требований..."
    
    # Проверка памяти
    local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_gb -lt 2 ]]; then
        log_warning "Обнаружено ${mem_gb}GB RAM. Рекомендуется минимум 2GB."
    else
        log_success "RAM: ${mem_gb}GB ✓"
    fi
    
    # Проверка места на диске
    local available_gb=$(df . | awk 'NR==2 {print int($4/1024/1024)}')
    if [[ $available_gb -lt 5 ]]; then
        log_error "Недостаточно места на диске: ${available_gb}GB. Требуется минимум 5GB."
        exit 1
    else
        log_success "Свободное место: ${available_gb}GB ✓"
    fi
    
    # Проверка портов
    local ports_in_use=()
    for port in $URBACKUP_WEB_PORT $URBACKUP_SERVER_PORT $URBACKUP_FASTCGI_PORT; do
        if ss -tlnp | grep ":$port " &> /dev/null; then
            ports_in_use+=($port)
        fi
    done
    
    if [[ ${#ports_in_use[@]} -gt 0 ]]; then
        log_error "Порты уже используются: ${ports_in_use[*]}"
        log_info "Используйте переменные окружения для изменения портов:"
        log_info "URBACKUP_WEB_PORT=8080 curl -sSL ... | bash"
        exit 1
    else
        log_success "Порты $URBACKUP_WEB_PORT, $URBACKUP_SERVER_PORT, $URBACKUP_FASTCGI_PORT свободны ✓"
    fi
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

# Обновление системы
update_system() {
    log_step "Обновление системы..."
    show_progress 1 10 "Обновление списка пакетов"
    
    sudo apt update -qq
    show_progress 3 10 "Установка базовых зависимостей"
    
    sudo apt install -y -qq \
        curl \
        wget \
        gnupg \
        lsb-release \
        ca-certificates \
        apt-transport-https \
        software-properties-common \
        net-tools \
        htop \
        tree
    
    show_progress 5 10 "Базовые пакеты установлены"
}

# Установка Docker
install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker уже установлен: $(docker --version)"
        show_progress 8 10 "Docker проверен"
        return 0
    fi

    log_step "Установка Docker..."
    show_progress 6 10 "Добавление репозитория Docker"
    
    # Удаление старых версий
    sudo apt remove -y -qq docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Добавление официального GPG ключа Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Добавление репозитория
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    show_progress 7 10 "Установка Docker Engine"
    sudo apt update -qq
    sudo apt install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Настройка прав пользователя
    sudo usermod -aG docker $USER
    
    # Включение автозапуска
    sudo systemctl enable docker
    sudo systemctl start docker
    
    show_progress 8 10 "Docker установлен и запущен"
    log_success "Docker установлен: $(docker --version)"
}

# Установка Docker Compose Plugin
install_docker_compose() {
    log_info "Проверка Docker Compose Plugin..."
    
    # Удаляем старый docker-compose если установлен
    sudo apt remove -y -qq docker-compose 2>/dev/null || true
    sudo rm -f /usr/local/bin/docker-compose 2>/dev/null || true
    
    # Проверяем новый plugin
    if docker compose version &> /dev/null; then
        log_success "Docker Compose Plugin уже установлен"
        return 0
    fi

    log_info "Установка Docker Compose Plugin..."
    sudo apt install -y -qq docker-compose-plugin
    
    # Проверяем что plugin работает
    if docker compose version &> /dev/null; then
        log_success "Docker Compose Plugin установлен"
    else
        log_error "Ошибка установки Docker Compose Plugin"
        exit 1
    fi
}

# Создание рабочей директории
create_working_directory() {
    log_step "Создание рабочей директории..."
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Создание структуры директорий
    mkdir -p urbackup/{backups,database,config}
    chmod -R 755 urbackup/
    
    log_success "Рабочая директория создана: $INSTALL_DIR"
}

# Создание docker-compose.yml
create_docker_compose() {
    log_step "Создание конфигурации Docker Compose..."
    
    cat > docker-compose.yml << EOF
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

EOF
    
    log_success "docker-compose.yml создан"
}

# Создание systemd сервиса
create_systemd_service() {
    log_step "Создание systemd сервиса..."
    
    sudo tee /etc/systemd/system/urbackup-docker.service > /dev/null << EOF
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
User=$USER
Group=docker

[Install]
WantedBy=multi-user.target

EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable urbackup-docker.service
    
    log_success "Systemd сервис создан и включен"
}

# Настройка firewall
configure_firewall() {
    if [[ "$SKIP_UFW" == "yes" ]]; then
        log_warning "Настройка UFW пропущена (SKIP_UFW=yes)"
        return 0
    fi
    
    log_step "Настройка UFW firewall..."
    
    # Установка UFW если не установлен
    if ! command -v ufw &> /dev/null; then
        sudo apt install -y -qq ufw
    fi
    
    # Настройка базовых правил
    sudo ufw --force reset > /dev/null 2>&1
    sudo ufw default deny incoming > /dev/null 2>&1
    sudo ufw default allow outgoing > /dev/null 2>&1
    
    # SSH доступ
    sudo ufw allow ssh > /dev/null 2>&1
    
    # UrBackup порты
    sudo ufw allow $URBACKUP_SERVER_PORT/tcp comment 'UrBackup Internet Protocol' > /dev/null 2>&1
    sudo ufw allow $URBACKUP_WEB_PORT/tcp comment 'UrBackup Web Interface' > /dev/null 2>&1
    sudo ufw allow $URBACKUP_FASTCGI_PORT/tcp comment 'UrBackup FastCGI' > /dev/null 2>&1
    
    # Включение UFW
    sudo ufw --force enable > /dev/null 2>&1
    
    log_success "UFW настроен и активирован"
}

# Запуск контейнера
start_urbackup() {
    log_step "Запуск UrBackup сервера..."
    show_progress 9 10 "Запуск Docker контейнера"
    
    # Проверка доступа к Docker
    if ! docker ps &> /dev/null; then
        log_warning "Требуется перелогин для применения прав Docker. Используем sudo..."
        sudo docker compose up -d
    else
        docker compose up -d
    fi
    
    # Ожидание готовности сервиса
    log_info "Ожидание готовности сервиса (может занять до 2 минут)..."
    local max_attempts=40
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -f -s "http://localhost:$URBACKUP_WEB_PORT/x?a=status" > /dev/null 2>&1; then
            break
        fi
        
        if [[ $((attempt % 5)) -eq 0 ]]; then
            printf "."
        fi
        
        sleep 3
        ((attempt++))
    done
    
    echo
    
    # Проверка статуса
    if docker compose ps | grep -q "Up"; then
        show_progress 10 10 "UrBackup сервер готов"
        log_success "UrBackup сервер запущен успешно!"
    else
        log_error "Ошибка запуска контейнера"
        echo "Логи контейнера:"
        docker compose logs --tail=20
        exit 1
    fi
}

# Создание скрипта управления
create_management_script() {
    log_step "Создание скрипта управления..."
    
    cat > urbackup-control.sh << 'EOF'
#!/bin/bash

# UrBackup Control Script
# Управление UrBackup сервером

set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_compose() {
    if [[ ! -f "docker-compose.yml" ]]; then
        log_error "docker-compose.yml не найден. Запустите из директории установки UrBackup."
        exit 1
    fi
}

get_server_ip() {
    SERVER_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}' 2>/dev/null || hostname -I | awk '{print $1}')
}

case "$1" in
    start)
        check_compose
        log_info "Запуск UrBackup сервера..."
        docker compose up -d
        log_success "UrBackup сервер запущен"
        ;;
    stop)
        check_compose
        log_info "Остановка UrBackup сервера..."
        docker compose down
        log_success "UrBackup сервер остановлен"
        ;;
    restart)
        check_compose
        log_info "Перезапуск UrBackup сервера..."
        docker compose restart
        log_success "UrBackup сервер перезапущен"
        ;;
    status)
        check_compose
        echo "Статус UrBackup сервера:"
        docker compose ps
        echo
        echo "Статус systemd сервиса:"
        systemctl is-active urbackup-docker.service || true
        ;;
    logs)
        check_compose
        log_info "Логи UrBackup сервера (Ctrl+C для выхода):"
        docker compose logs -f --tail=50
        ;;
    update)
        check_compose
        log_info "Обновление UrBackup сервера..."
        docker compose pull
        docker compose up -d
        log_success "UrBackup сервер обновлен"
        ;;
    backup-config)
        check_compose
        BACKUP_NAME="urbackup-config-$(date +%Y%m%d-%H%M%S).tar.gz"
        log_info "Создание бэкапа конфигурации..."
        tar -czf "$BACKUP_NAME" urbackup/ docker-compose.yml urbackup-control.sh 2>/dev/null || true
        log_success "Бэкап сохранен: $BACKUP_NAME"
        ;;
    info)
        check_compose
        get_server_ip
        echo "=========================================="
        echo "  UrBackup Server Information"
        echo "=========================================="
        echo "Web Interface: http://$SERVER_IP:$(grep -A1 'ports:' docker-compose.yml | grep '55414' | cut -d':' -f1 | tr -d ' -')"
        echo "Server Address: $SERVER_IP"
        echo "Working Directory: $(pwd)"
        echo
        echo "Data Directories:"
        echo "  Backups:  $(pwd)/urbackup/backups/"
        echo "  Database: $(pwd)/urbackup/database/"
        echo "  Config:   $(pwd)/urbackup/config/"
        echo
        echo "Management:"
        echo "  Start:    ./urbackup-control.sh start"
        echo "  Stop:     ./urbackup-control.sh stop"  
        echo "  Status:   ./urbackup-control.sh status"
        echo "  Logs:     ./urbackup-control.sh logs"
        echo "  Update:   ./urbackup-control.sh update"
        ;;
    *)
        echo "UrBackup Control Script"
        echo
        echo "Использование: $0 {command}"
        echo
        echo "Commands:"
        echo "  start         - запуск сервера"
        echo "  stop          - остановка сервера"
        echo "  restart       - перезапуск сервера"
        echo "  status        - статус сервера"
        echo "  logs          - просмотр логов"
        echo "  update        - обновление сервера"
        echo "  backup-config - бэкап конфигурации"
        echo "  info          - информация о сервере"
        echo
        exit 1
        ;;
esac
EOF
    
    chmod +x urbackup-control.sh
    log_success "Скрипт управления создан"
}

# Вывод информации о завершении
print_completion_info() {
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
    echo "   ./urbackup-control.sh start      # запуск"
    echo "   ./urbackup-control.sh stop       # остановка"  
    echo "   ./urbackup-control.sh restart    # перезапуск"
    echo "   ./urbackup-control.sh status     # статус"
    echo "   ./urbackup-control.sh logs       # логи"
    echo "   ./urbackup-control.sh update     # обновление"
    echo "   ./urbackup-control.sh info       # информация"
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
}

# Основная функция
main() {
    clear
    echo "=========================================="
    echo "  🐳 UrBackup Docker Installer v1.1"
    echo "  Ubuntu 24.04 LTS Compatible"
    echo "=========================================="
    echo
    
    check_root
    check_ubuntu
    get_server_ip
    check_system_requirements
    
    update_system
    install_docker
    install_docker_compose
    create_working_directory
    create_docker_compose
    create_systemd_service
    configure_firewall
    start_urbackup
    create_management_script
    
    print_completion_info
}

# Запуск
main "$@"
