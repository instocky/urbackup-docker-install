#!/bin/bash

# UrBackup Server Docker Auto Installation Script
# Ubuntu 24.04 LTS Auto Installer
# Author: DevOps Engineer
# Date: 2025-06-03
# Version: 1.0

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
    log_info "Создание docker-compose.yml..."
    
    cat > docker-compose.yml << EOF
version: '3.8'

services:
  urbackup-server:
    image: uroni/urbackup-server:latest
    container_name: urbackup-server
    restart: unless-stopped
    ports:
      - "55413:55413"   # UrBackup Internet Protocol
      - "55414:55414"   # Web Interface HTTP
      - "35623:35623"   # FastCGI
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

networks:
  urbackup-net:
    driver: bridge

EOF
    
    log_success "docker-compose.yml создан"
}

# Создание systemd сервиса
create_systemd_service() {
    log_info "Создание systemd сервиса..."
    
    sudo tee /etc/systemd/system/urbackup-docker.service > /dev/null << EOF
[Unit]
Description=UrBackup Docker Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target

EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable urbackup-docker.service
    
    log_success "Systemd сервис создан и включен"
}

# Настройка firewall
configure_firewall() {
    log_info "Настройка firewall..."
    
    if command -v ufw &> /dev/null; then
        sudo ufw allow 55413/tcp comment 'UrBackup Internet Protocol'
        sudo ufw allow 55414/tcp comment 'UrBackup Web Interface'
        sudo ufw allow 35623/tcp comment 'UrBackup FastCGI'
        log_success "UFW правила добавлены"
    else
        log_warning "UFW не установлен, настройте firewall вручную"
    fi
}

# Запуск контейнера
start_container() {
    log_info "Запуск UrBackup сервера..."
    
    # Проверка что пользователь в группе docker
    if ! groups $USER | grep -q docker; then
        log_warning "Пользователь не в группе docker. Перелогиньтесь или используйте sudo."
        sudo docker-compose up -d
    else
        docker-compose up -d
    fi
    
    # Ожидание запуска
    log_info "Ожидание запуска сервиса..."
    sleep 10
    
    # Проверка статуса
    if docker-compose ps | grep -q "Up"; then
        log_success "UrBackup сервер запущен успешно!"
    else
        log_error "Ошибка запуска контейнера"
        docker-compose logs
        exit 1
    fi
}

# Создание скрипта управления
create_management_script() {
    log_info "Создание скрипта управления..."
    
    cat > urbackup-control.sh << 'EOF'
#!/bin/bash

case "$1" in
    start)
        echo "Запуск UrBackup сервера..."
        docker-compose up -d
        ;;
    stop)
        echo "Остановка UrBackup сервера..."
        docker-compose down
        ;;
    restart)
        echo "Перезапуск UrBackup сервера..."
        docker-compose restart
        ;;
    status)
        echo "Статус UrBackup сервера:"
        docker-compose ps
        ;;
    logs)
        echo "Логи UrBackup сервера:"
        docker-compose logs -f
        ;;
    update)
        echo "Обновление UrBackup сервера..."
        docker-compose pull
        docker-compose up -d
        ;;
    backup-config)
        echo "Создание бэкапа конфигурации..."
        tar -czf "urbackup-config-$(date +%Y%m%d-%H%M%S).tar.gz" urbackup/ docker-compose.yml
        echo "Бэкап сохранен"
        ;;
    *)
        echo "Использование: $0 {start|stop|restart|status|logs|update|backup-config}"
        exit 1
        ;;
esac
EOF
    
    chmod +x urbackup-control.sh
    log_success "Скрипт управления создан (./urbackup-control.sh)"
}

# Вывод информации о завершении
print_completion_info() {
    echo
    echo "=========================================="
    log_success "Установка UrBackup завершена успешно!"
    echo "=========================================="
    echo
    echo -e "${BLUE}Веб-интерфейс:${NC} http://$SERVER_IP:55414"
    echo -e "${BLUE}Адрес сервера для клиентов:${NC} $SERVER_IP"
    echo
    echo -e "${YELLOW}Управление сервером:${NC}"
    echo "  ./urbackup-control.sh start    - запуск"
    echo "  ./urbackup-control.sh stop     - остановка"  
    echo "  ./urbackup-control.sh restart  - перезапуск"
    echo "  ./urbackup-control.sh status   - статус"
    echo "  ./urbackup-control.sh logs     - логи"
    echo "  ./urbackup-control.sh update   - обновление"
    echo
    echo -e "${YELLOW}Директории:${NC}"
    echo "  $(pwd)/urbackup/backups/  - хранилище бэкапов"
    echo "  $(pwd)/urbackup/database/ - база данных"
    echo "  $(pwd)/urbackup/config/   - конфигурация"
    echo
    echo -e "${GREEN}Следующие шаги:${NC}"
    echo "1. Откройте http://$SERVER_IP:55414 в браузере"
    echo "2. Пройдите мастер первоначальной настройки"
    echo "3. Скачайте клиенты для Windows компьютеров"
    echo "4. Настройте расписания бэкапов"
    echo
}

# Основная функция
main() {
    echo "=========================================="
    echo "  UrBackup Server Docker Installation"
    echo "  Ubuntu 24.04 LTS"
    echo "=========================================="
    echo
    
    check_root
    check_ubuntu
    get_server_ip
    
    install_docker
    install_docker_compose
    create_directories
    create_docker_compose
    create_systemd_service
    configure_firewall
    start_container
    create_management_script
    
    print_completion_info
}

# Запуск
main "$@"
