#!/bin/bash

# Docker Installation Script for Ubuntu
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Определяем кодовое имя Ubuntu напрямую
get_codename() {
    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -cs
    else
        # Определяем по версии из /etc/os-release
        if [ -f /etc/os-release ]; then
            VERSION_ID=$(grep '^VERSION_ID=' /etc/os-release | cut -d'"' -f2)
            case "$VERSION_ID" in
                "24.04") echo "noble" ;;
                "22.04") echo "jammy" ;;
                "20.04") echo "focal" ;;
                "18.04") echo "bionic" ;;
                *) echo "unknown" ;;
            esac
        else
            echo "unknown"
        fi
    fi
}

# Проверяем права
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    log_error "Требуются sudo права"
    exit 1
fi

# Проверяем Ubuntu
if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    log_error "Скрипт работает только на Ubuntu"
    exit 1
fi

# Получаем кодовое имя
CODENAME=$(get_codename)
if [ "$CODENAME" = "unknown" ]; then
    log_error "Не удалось определить версию Ubuntu"
    exit 1
fi

ARCH=$(dpkg --print-architecture)
log_info "Ubuntu codename: $CODENAME"
log_info "Architecture: $ARCH"

# Удаляем старые версии Docker
log_info "Удаляем старые версии Docker..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Обновляем пакеты
log_info "Обновляем список пакетов..."
sudo apt-get update

# Устанавливаем зависимости
log_info "Устанавливаем зависимости..."
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Создаём директорию для ключей
sudo install -m 0755 -d /etc/apt/keyrings

# Загружаем GPG ключ
log_info "Загружаем GPG ключ Docker..."
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Создаём файл репозитория БЕЗ переменных - только статические значения
log_info "Создаём репозиторий Docker..."
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Проверяем созданный файл
log_info "Содержимое файла репозитория:"
cat /etc/apt/sources.list.d/docker.list

# Обновляем список пакетов
log_info "Обновляем пакеты с новым репозиторием..."
sudo apt-get update

# Устанавливаем Docker
log_info "Устанавливаем Docker..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Запускаем Docker
log_info "Запускаем службу Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# Добавляем пользователя в группу docker
if [ "$EUID" -ne 0 ]; then
    log_info "Добавляем пользователя в группу docker..."
    sudo usermod -aG docker "$USER"
    log_warn "Выйдите и войдите заново или выполните: newgrp docker"
fi

# Проверяем установку
log_info "Проверяем установку..."
docker --version
docker compose version

log_info "Docker успешно установлен!"
