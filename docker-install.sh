#!/bin/bash

# Docker Installation Script for Ubuntu
# This script installs Docker CE on Ubuntu systems

set -euo pipefail
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
NC='\033[0m'

# Logging functions
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    log "INFO" "$1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    log "WARN" "$1"
}

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

trap cleanup EXIT

# Get Ubuntu codename reliably
get_ubuntu_codename() {
    local codename=""
    
    # Try multiple methods to get codename
    if command -v lsb_release &> /dev/null; then
        codename=$(lsb_release -cs 2>/dev/null)
    fi
    
    # Fallback to /etc/os-release
    if [[ -z "$codename" ]] && [[ -f /etc/os-release ]]; then
        source /etc/os-release
        codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
    fi
    
    # Manual mapping for common versions if still empty
    if [[ -z "$codename" ]]; then
        local version=$(lsb_release -rs 2>/dev/null || echo "")
        case "$version" in
            "24.04") codename="noble" ;;
            "22.04") codename="jammy" ;;
            "20.04") codename="focal" ;;
            "18.04") codename="bionic" ;;
            *) 
                log_error "Не удалось определить кодовое имя Ubuntu для версии: $version"
                exit 1
                ;;
        esac
    fi
    
    echo "$codename"
}

# Check if script is run as root or with sudo
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        log_warn "Скрипт запущен от имени root"
    elif ! sudo -n true 2>/dev/null; then
        log_error "Этот скрипт требует sudo привилегии"
        exit 1
    fi
}

# Check Ubuntu version and codename
check_ubuntu_version() {
    if ! command -v lsb_release &> /dev/null; then
        log_error "lsb_release не найден. Устанавливаем lsb-release..."
        sudo apt-get update && sudo apt-get install -y lsb-release
    fi
    
    local distro=$(lsb_release -si)
    local version=$(lsb_release -sr)
    
    if [[ "$distro" != "Ubuntu" ]]; then
        log_error "Этот скрипт предназначен для Ubuntu, обнаружена система: $distro"
        exit 1
    fi
    
    local codename=$(get_ubuntu_codename)
    log_info "Обнаружена система: $distro $version ($codename)"
    
    # Validate codename
    if [[ -z "$codename" ]]; then
        log_error "Не удалось определить кодовое имя Ubuntu"
        exit 1
    fi
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

# Remove old Docker packages
remove_old_docker() {
    log_info "Удаляем старые версии Docker..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
}

# Main installation function
install_docker() {
    log_info "Начинаем установку Docker..."
    
    # Remove old Docker packages
    remove_old_docker
    
    # Update package list
    log_info "Обновляем список пакетов..."
    retry 3 5 sudo apt-get update
    
    # Install prerequisites
    log_info "Устанавливаем необходимые пакеты..."
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    # Create directory for keyrings
    log_info "Создаём директорию для ключей..."
    sudo install -m 0755 -d /etc/apt/keyrings
    
    # Download and install Docker GPG key
    log_info "Загружаем GPG ключ Docker..."
    retry 3 5 sudo curl -fsSL "$DOCKER_GPG_URL" -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    # Get Ubuntu codename
    local codename=$(get_ubuntu_codename)
    log_info "Используем кодовое имя Ubuntu: $codename"
    
    # Add Docker repository
    log_info "Добавляем репозиторий Docker..."
    local arch=$(dpkg --print-architecture)
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] $DOCKER_APT_REPO $codename stable" | \
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
    
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        local compose_version=$(docker compose version)
        log_info "Установленная версия Docker Compose: $compose_version"
    fi
    
    # Test Docker daemon
    log_info "Тестируем работу Docker..."
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
