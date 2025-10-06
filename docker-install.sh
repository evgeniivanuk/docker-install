#!/bin/bash

# Docker Installation Script for Ubuntu
# This script installs Docker CE on Ubuntu systems

set -euo pipefail  # Enable strict mode for error handling
IFS=$'\n\t'

# Global variables
SCRIPT_NAME="$(basename "$0")"
LOG_FILE="/tmp/docker-install.log"
DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
DOCKER_APT_REPO="https://download.docker.com/linux/ubuntu"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Info logging with color
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    log "INFO" "$1"
}

# Warning logging with color
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    log "WARN" "$1"
}

# Error logging with color
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    log "ERROR" "$1"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Установка Docker завершилась с ошибкой (код выхода: $exit_code)"
        log_info "Проверьте лог файл: $LOG_FILE"
    fi
    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT

# Check if script is run as root or with sudo
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        log_warn "Скрипт запущен от имени root"
    elif ! sudo -n true 2>/dev/null; then
        log_error "Этот скрипт требует sudo привилегии"
        exit 1
    fi
}

# Check Ubuntu version
check_ubuntu_version() {
    if ! command -v lsb_release &> /dev/null; then
        log_error "lsb_release не найден. Убедитесь, что это система Ubuntu"
        exit 1
    fi
    
    local distro=$(lsb_release -si)
    if [[ "$distro" != "Ubuntu" ]]; then
        log_error "Этот скрипт предназначен для Ubuntu, обнаружена система: $distro"
        exit 1
    fi
    
    log_info "Обнаружена система: $distro $(lsb_release -sr)"
}

# Check if Docker is already installed
check_existing_docker() {
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version 2>/dev/null || echo "неизвестная версия")
        log_warn "Docker уже установлен: $docker_version"
        read -p "Продолжить установку? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Установка отменена пользователем"
            exit 0
        fi
    fi
}

# Retry function for unreliable operations
retry() {
    local retries=$1
    local wait=$2
    shift 2
    local count=0
    
    until "$@"; do
        local exit_code=$?
        count=$((count + 1))
        if [[ $count -lt $retries ]]; then
            log_warn "Команда завершилась неудачно (код выхода $exit_code), повтор через ${wait}с..."
            sleep $wait
        else
            log_error "Команда завершилась неудачно после $count попыток"
            return $exit_code
        fi
    done
    return 0
}

# Main installation function
install_docker() {
    log_info "Начинаем установку Docker..."
    
    # Update package list
    log_info "Обновляем список пакетов..."
    retry 3 5 sudo apt-get update
    
    # Install prerequisites
    log_info "Устанавливаем необходимые пакеты..."
    sudo apt-get install -y ca-certificates curl
    
    # Create directory for keyrings
    log_info "Создаём директорию для ключей..."
    sudo install -m 0755 -d /etc/apt/keyrings
    
    # Download and install Docker GPG key
    log_info "Загружаем GPG ключ Docker..."
    retry 3 5 sudo curl -fsSL "$DOCKER_GPG_URL" -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add Docker repository
    log_info "Добавляем репозиторий Docker..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $DOCKER_APT_REPO $(. /etc/os-release && echo \"\${UBUNTU_CODENAME:-\$VERSION_CODENAME}\") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    
    # Update package list with Docker repository
    log_info "Обновляем список пакетов с репозиторием Docker..."
    retry 3 5 sudo apt-get update
    
    # Install Docker packages
    log_info "Устанавливаем Docker и связанные пакеты..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Start and enable Docker service
    log_info "Запускаем и включаем службу Docker..."
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Add current user to docker group (if not root)
    if [[ $EUID -ne 0 ]]; then
        log_info "Добавляем пользователя $USER в группу docker..."
        sudo usermod -aG docker "$USER"
        log_warn "Для применения изменений группы выполните: newgrp docker или перезайдите в систему"
    fi
}

# Verify installation
verify_installation() {
    log_info "Проверяем установку Docker..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker не найден после установки"
        return 1
    fi
    
    local docker_version=$(docker --version)
    log_info "Установленная версия Docker: $docker_version"
    
    if command -v docker-compose &> /dev/null; then
        local compose_version=$(docker compose version)
        log_info "Установленная версия Docker Compose: $compose_version"
    fi
    
    # Test Docker daemon
    if sudo docker run --rm hello-world &> /dev/null; then
        log_info "Docker работает корректно"
    else
        log_warn "Не удалось запустить тестовый контейнер Docker"
    fi
}

# Main execution
main() {
    log_info "Запуск скрипта установки Docker: $SCRIPT_NAME"
    log_info "Лог файл: $LOG_FILE"
    
    check_privileges
    check_ubuntu_version
    check_existing_docker
    install_docker
    verify_installation
    
    log_info "Установка Docker успешно завершена!"
    log_info "Для использования Docker без sudo выполните: newgrp docker"
}

# Run main function
main "$@"
