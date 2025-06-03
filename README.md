# UrBackup Docker Auto Install

Автоматическая установка UrBackup сервера в Docker контейнере для Ubuntu 24.04 LTS.

## 🚀 Быстрая установка

### Полностью автоматическая установка (рекомендуется):
```bash
curl -sSL https://raw.githubusercontent.com/instocky/urbackup-docker-install/main/install-auto.sh | sudo bash
```
**Эта команда автоматически:**
- Создает пользователя `urbackup` с случайным паролем
- Устанавливает Docker и UrBackup от созданного пользователя  
- Настраивает все сервисы и firewall
- Показывает финальную информацию с паролем пользователя

### Ручная установка от существующего пользователя:
```bash
curl -sSL https://raw.githubusercontent.com/instocky/urbackup-docker-install/main/install.sh | bash
```

### С дополнительными параметрами:
```bash
# Пропустить настройку UFW firewall
SKIP_UFW=yes curl -sSL https://raw.githubusercontent.com/instocky/urbackup-docker-install/main/install-auto.sh | sudo bash

# Создать пользователя с другим именем
URBACKUP_USER=backup curl -sSL https://raw.githubusercontent.com/instocky/urbackup-docker-install/main/install-auto.sh | sudo bash

# Задать кастомные порты
URBACKUP_WEB_PORT=8080 curl -sSL https://raw.githubusercontent.com/instocky/urbackup-docker-install/main/install-auto.sh | sudo bash
```

## 📋 Что устанавливается

- **Docker CE** - последняя стабильная версия
- **Docker Compose** - как плагин Docker  
- **UrBackup Server** - последняя версия в контейнере
- **UFW Firewall** - автоматическая настройка правил
- **Systemd сервис** - автозапуск UrBackup
- **Скрипт управления** - для удобного администрирования
- Настройка автозапуска всех сервисов
- Организованная структура директорий

## ✅ Требования

- **ОС**: Ubuntu 20.04+ (рекомендуется 24.04)
- **RAM**: минимум 2GB (рекомендуется 4GB+)
- **Диск**: минимум 10GB свободного места + место для бэкапов
- **Права**: пользователь с sudo доступом (НЕ root)
- **Сеть**: доступ к интернету для скачивания пакетов
- **Порты**: 55413, 55414, 35623 должны быть свободны

## Что делает скрипт

1. ✅ Проверяет системные требования
2. 🐳 Устанавливает Docker и Docker Compose
3. 📁 Создает структуру директорий
4. ⚙️ Генерирует docker-compose.yml
5. 🚀 Создает systemd сервис
6. 🔥 Настраивает firewall правила
7. 🏃 Запускает UrBackup сервер
8. 🎛️ Создает скрипт управления

## Управление сервером

После установки используйте скрипт управления:

```bash
# Запуск сервера
./urbackup-control.sh start

# Остановка сервера
./urbackup-control.sh stop

# Перезапуск сервера
./urbackup-control.sh restart

# Проверка статуса
./urbackup-control.sh status

# Просмотр логов
./urbackup-control.sh logs

# Обновление сервера
./urbackup-control.sh update

# Бэкап конфигурации
./urbackup-control.sh backup-config
```

## Доступ к веб-интерфейсу

После установки откройте в браузере:
```
http://ВАШ_IP:55414
```

## Структура проекта

```
urbackup-docker-installer/
├── install.sh              # Основной скрипт установки
├── docker-compose.yml      # Конфигурация Docker (создается автоматически)
├── urbackup-control.sh     # Скрипт управления (создается автоматически)
├── urbackup/               # Данные сервера (создается автоматически)
│   ├── backups/            # Хранилище бэкапов
│   ├── database/           # База данных UrBackup
│   └── config/             # Конфигурационные файлы
└── README.md               # Документация
```

## Настройка клиентов Windows

1. Откройте веб-интерфейс UrBackup
2. Перейдите в "Add new client"
3. Укажите имя компьютера
4. Скачайте клиент для Windows
5. Установите на целевом компьютере
6. Настройте папки для бэкапа

## Рекомендуемые настройки

### Для домашнего использования (20 ГБ данных):

- **File Backup**: каждые 4 часа
- **Image Backup**: еженедельно
- **Retention**: 30 файловых версий, 4 образа
- **Compression**: включена
- **Deduplication**: включена

### Мониторинг места на диске:

```bash
# Проверка использования места
du -sh urbackup/
df -h
```

## Устранение неполадок

### Проверка статуса сервера:
```bash
docker-compose ps
docker-compose logs urbackup-server
```

### Перезапуск при проблемах:
```bash
./urbackup-control.sh stop
./urbackup-control.sh start
```

### Проверка портов:
```bash
netstat -tlnp | grep -E '55413|55414|35623'
```

### Права доступа к директориям:
```bash
ls -la urbackup/
sudo chown -R $USER:$USER urbackup/
```

## Обновление

Для обновления UrBackup сервера:

```bash
./urbackup-control.sh update
```

## Удаление

Для полного удаления:

```bash
# Остановка сервера
./urbackup-control.sh stop

# Удаление systemd сервиса
sudo systemctl disable urbackup-docker.service
sudo rm /etc/systemd/system/urbackup-docker.service
sudo systemctl daemon-reload

# Удаление контейнера и образов
docker-compose down --rmi all

# Удаление данных (ОСТОРОЖНО!)
rm -rf urbackup/
```

## Системные требования

- **CPU**: любой x64 (Celeron 2013+ вполне достаточно)
- **RAM**: минимум 2 ГБ, рекомендуется 4 ГБ
- **Диск**: 50 ГБ для системы + место для бэкапов
- **Сеть**: Gigabit Ethernet рекомендуется

## Безопасность

- Сервер доступен только по HTTP (без HTTPS)
- Рекомендуется использовать в локальной сети
- Настройте firewall для ограничения доступа
- Регулярно создавайте бэкапы конфигурации

## Поддержка

При возникновении проблем:

1. Проверьте логи: `./urbackup-control.sh logs`
2. Проверьте статус: `./urbackup-control.sh status`
3. Изучите официальную документацию UrBackup
4. Создайте issue в репозитории

## Лицензия

MIT License

## Автор

DevOps Engineer with 20+ years experience
