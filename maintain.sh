#!/bin/bash

################################################################################
# Preview Server Maintenance Script
#
# This script handles routine maintenance tasks including:
# - System package updates
# - SSL certificate renewal
# - Database optimization
# - Log cleanup
# - Cleanup of old preview environments
#
# Usage:
#   sudo bash maintain.sh [--all|--update|--optimize|--clean|--ssl]
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

PREVIEW_DIR="/var/www/previews"
LOG_DIR="/var/log/nginx"
PHP_VERSION="8.3"
OLD_PREVIEW_DAYS=30
OLD_LOG_DAYS=90

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

################################################################################
# Helper Functions
################################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

log_section() {
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

check_root() {
    # Allow both root and github-actions user
    if [[ $EUID -ne 0 ]] && [[ "$USER" != "github-actions" ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

################################################################################
# Update Functions
################################################################################

update_system() {
    log_section "System Package Updates"

    log "Updating package lists..."
    sudo apt update

    log "Checking for available upgrades..."
    local upgrade_count=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")

    if [[ $upgrade_count -eq 0 ]]; then
        log "System is up to date"
        return
    fi

    log_info "Found $upgrade_count package(s) to upgrade"

    # Show upgradable packages
    log "Packages to be upgraded:"
    sudo apt list --upgradable 2>/dev/null | grep "upgradable" | head -20

    read -p "Proceed with upgrade? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Upgrading packages..."
        DEBIAN_FRONTEND=noninteractive apt upgrade -y

        log "Removing unnecessary packages..."
        sudo apt autoremove -y

        log "Cleaning package cache..."
        sudo apt clean

        # Check if reboot required
        if [[ -f /var/run/reboot-required ]]; then
            log_warning "System reboot is required!"
            log_info "Reboot reasons:"
            cat /var/run/reboot-required.pkgs 2>/dev/null || true
        fi

        log "System update complete"
    else
        log "Update cancelled"
    fi
}

update_composer() {
    log_section "Composer Update"

    if command -v composer &>/dev/null; then
        log "Updating Composer to latest version..."
        composer self-update

        local version=$(composer --version --no-ansi | awk '{print $3}')
        log "Composer version: $version"
    else
        log_warning "Composer not installed"
    fi
}

renew_ssl_certificates() {
    log_section "SSL Certificate Renewal"

    if ! command -v certbot &>/dev/null; then
        log_warning "Certbot not installed"
        return
    fi

    log "Checking SSL certificates for renewal..."
    sudo certbot renew --dry-run

    log "Renewing SSL certificates..."
    sudo certbot renew --quiet --post-hook "systemctl reload nginx"

    log "Certificate renewal complete"

    # Show certificate status
    log_info "Current certificates:"
    sudo certbot certificates 2>/dev/null | grep -E "Certificate Name:|Expiry Date:" || true
}

################################################################################
# Optimization Functions
################################################################################

optimize_databases() {
    log_section "Database Optimization"

    log "Analyzing and optimizing preview databases..."

    # Get list of preview databases
    local databases=$(mysql -u root -e "SHOW DATABASES LIKE 'preview_%';" -s -N)

    if [[ -z "$databases" ]]; then
        log_info "No preview databases found"
        return
    fi

    local db_count=0
    for db in $databases; do
        ((db_count++))
        log_info "Optimizing database: $db"

        # Analyze tables
        mysql -u root -e "USE $db; ANALYZE TABLE $(mysql -u root -e "SELECT GROUP_CONCAT(table_name) FROM information_schema.tables WHERE table_schema='$db';" -s -N);" 2>/dev/null || true

        # Optimize tables
        mysql -u root -e "USE $db; OPTIMIZE TABLE $(mysql -u root -e "SELECT GROUP_CONCAT(table_name) FROM information_schema.tables WHERE table_schema='$db';" -s -N);" 2>/dev/null || true
    done

    log "Optimized $db_count database(s)"

    # Show database sizes
    log_info "Database sizes after optimization:"
    mysql -u root -e "
        SELECT
            table_schema AS 'Database',
            ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
        FROM information_schema.tables
        WHERE table_schema LIKE 'preview_%'
        GROUP BY table_schema
        ORDER BY SUM(data_length + index_length) DESC;
    " 2>/dev/null || true
}

optimize_php() {
    log_section "PHP Optimization"

    log "Restarting PHP-FPM to clear OPcache..."
    sudo systemctl restart php${PHP_VERSION}-fpm

    log "Checking PHP-FPM status..."
    sudo systemctl status php${PHP_VERSION}-fpm --no-pager | head -10

    log "PHP optimization complete"
}

optimize_nginx() {
    log_section "Nginx Optimization"

    log "Testing Nginx configuration..."
    if ! nginx -t; then
        log_error "Nginx configuration test failed!"
        return
    fi

    log "Reloading Nginx..."
    sudo systemctl reload nginx

    log "Nginx optimization complete"
}

################################################################################
# Cleanup Functions
################################################################################

cleanup_old_previews() {
    log_section "Cleanup Old Preview Environments"

    log "Searching for preview environments older than $OLD_PREVIEW_DAYS days..."

    if [[ ! -d "$PREVIEW_DIR" ]]; then
        log_info "Preview directory does not exist"
        return
    fi

    local old_previews=$(find "$PREVIEW_DIR" -maxdepth 1 -type d -name "pr-*" -mtime +$OLD_PREVIEW_DAYS 2>/dev/null || true)

    if [[ -z "$old_previews" ]]; then
        log "No old preview environments found"
        return
    fi

    local count=0
    echo "$old_previews" | while read preview_path; do
        ((count++))
        local preview_id=$(basename "$preview_path")
        local age=$(find "$preview_path" -maxdepth 0 -printf '%Td days\n')

        log_info "Found old preview: $preview_id (age: $age)"
    done

    echo
    read -p "Delete these old previews? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$old_previews" | while read preview_path; do
            local preview_id=$(basename "$preview_path")
            log "Cleaning up: $preview_id"

            # Use preview-cleanup if available
            if command -v preview-cleanup &>/dev/null; then
                preview-cleanup "$preview_id"
            else
                # Manual cleanup
                rm -rf "$preview_path"
                local db_name="preview_${preview_id//-/_}"
                mysql -u root -e "DROP DATABASE IF EXISTS $db_name;" 2>/dev/null || true
                rm -f "/etc/nginx/sites-enabled/$preview_id" "/etc/nginx/sites-available/$preview_id"
            fi
        done

        sudo systemctl reload nginx 2>/dev/null || true
        log "Old preview cleanup complete"
    else
        log "Cleanup cancelled"
    fi
}

cleanup_logs() {
    log_section "Log Cleanup"

    log "Cleaning up logs older than $OLD_LOG_DAYS days..."

    # Nginx logs
    if [[ -d "$LOG_DIR" ]]; then
        local log_count=$(find "$LOG_DIR" -name "*.log" -mtime +$OLD_LOG_DAYS 2>/dev/null | wc -l)

        if [[ $log_count -gt 0 ]]; then
            log_info "Found $log_count old log file(s) in $LOG_DIR"
            find "$LOG_DIR" -name "*.log" -mtime +$OLD_LOG_DAYS -delete 2>/dev/null || true
            log "Nginx logs cleaned"
        else
            log_info "No old nginx logs found"
        fi
    fi

    # Compress recent logs
    log "Compressing recent uncompressed logs..."
    find "$LOG_DIR" -name "*.log" -size +100M -exec gzip {} \; 2>/dev/null || true

    # System logs
    log "Cleaning journal logs..."
    sudo journalctl --vacuum-time=30d 2>/dev/null || true

    # PHP-FPM logs
    if [[ -d "/var/log/php${PHP_VERSION}-fpm" ]]; then
        find "/var/log/php${PHP_VERSION}-fpm" -name "*.log" -mtime +$OLD_LOG_DAYS -delete 2>/dev/null || true
    fi

    log "Log cleanup complete"

    # Show disk usage
    log_info "Current log disk usage:"
    du -sh "$LOG_DIR" 2>/dev/null || true
    du -sh /var/log/journal 2>/dev/null || true
}

cleanup_temp_files() {
    log_section "Temporary Files Cleanup"

    log "Cleaning temporary files..."

    # Clean /tmp files older than 7 days
    find /tmp -type f -atime +7 -delete 2>/dev/null || true

    # Clean PHP sessions older than 7 days
    if [[ -d "/var/lib/php/sessions" ]]; then
        find /var/lib/php/sessions -type f -mtime +7 -delete 2>/dev/null || true
    fi

    # Clean composer cache
    if command -v composer &>/dev/null; then
        log "Cleaning Composer cache..."
        composer clear-cache 2>/dev/null || true
    fi

    log "Temporary files cleanup complete"
}

cleanup_package_cache() {
    log_section "Package Cache Cleanup"

    log "Cleaning APT cache..."
    sudo apt clean
    sudo apt autoclean

    log "Removing old kernels..."
    local current_kernel=$(uname -r)
    log_info "Current kernel: $current_kernel"

    # List old kernels
    local old_kernels=$(dpkg -l | grep linux-image | grep -v "$current_kernel" | awk '{print $2}' || true)

    if [[ -n "$old_kernels" ]]; then
        log_info "Old kernels found:"
        echo "$old_kernels"
        read -p "Remove old kernels? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo apt purge -y $old_kernels
            log "Old kernels removed"
        fi
    else
        log_info "No old kernels to remove"
    fi

    log "Package cache cleanup complete"
}

################################################################################
# Status and Reporting
################################################################################

show_disk_usage() {
    log_section "Disk Usage Report"

    log_info "Overall disk usage:"
    df -h / | tail -1

    echo
    log_info "Largest directories:"
    du -h --max-depth=1 /var 2>/dev/null | sort -hr | head -10

    echo
    if [[ -d "$PREVIEW_DIR" ]]; then
        log_info "Preview environments disk usage:"
        du -sh "$PREVIEW_DIR"/* 2>/dev/null | sort -hr | head -10 || true
    fi
}

show_service_status() {
    log_section "Service Status"

    local services=("nginx" "mysql" "php${PHP_VERSION}-fpm")

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            echo -e "${GREEN}✓${NC} $service: running"
        else
            echo -e "${RED}✗${NC} $service: not running"
        fi
    done
}

generate_maintenance_report() {
    log_section "Maintenance Report"

    cat <<EOF
Maintenance completed at: $(date)

System Information:
  Hostname: $(hostname)
  Uptime: $(uptime -p)
  Load: $(uptime | awk -F'load average:' '{print $2}')

Disk Usage:
  Root: $(df -h / | tail -1 | awk '{print $5 " used (" $3 "/" $2 ")"}')

Memory:
  $(free -h | grep Mem | awk '{print $3 " used / " $2 " total"}')

Preview Environments:
  Active: $(find "$PREVIEW_DIR" -maxdepth 1 -type d -name "pr-*" 2>/dev/null | wc -l)
  Total Size: $(du -sh "$PREVIEW_DIR" 2>/dev/null | awk '{print $1}' || echo "N/A")

Databases:
  Preview DBs: $(mysql -u root -e "SHOW DATABASES LIKE 'preview_%';" -s -N 2>/dev/null | wc -l)

Services:
  Nginx: $(systemctl is-active nginx 2>/dev/null || echo "inactive")
  MySQL: $(systemctl is-active mysql 2>/dev/null || echo "inactive")
  PHP-FPM: $(systemctl is-active php${PHP_VERSION}-fpm 2>/dev/null || echo "inactive")

EOF
}

################################################################################
# Main Functions
################################################################################

run_all_maintenance() {
    log_section "Running Full Maintenance"

    update_system
    update_composer
    renew_ssl_certificates
    optimize_databases
    optimize_php
    optimize_nginx
    cleanup_old_previews
    cleanup_logs
    cleanup_temp_files
    cleanup_package_cache
    show_disk_usage
    show_service_status
    generate_maintenance_report
}

show_usage() {
    cat <<EOF
Preview Server Maintenance Tool

Usage:
  $(basename $0) [OPTIONS]

Options:
  --all         Run all maintenance tasks (default)
  --update      Update system packages and software
  --optimize    Optimize databases and services
  --clean       Clean up old data and logs
  --ssl         Renew SSL certificates
  --status      Show system status
  --help        Show this help message

Examples:
  sudo bash $(basename $0)                 # Run all maintenance
  sudo bash $(basename $0) --update        # Update packages only
  sudo bash $(basename $0) --clean         # Clean up only
  sudo bash $(basename $0) --optimize      # Optimize only

EOF
}

################################################################################
# Main
################################################################################

main() {
    check_root

    local mode="${1:---all}"

    case "$mode" in
        --all)
            run_all_maintenance
            ;;
        --update)
            update_system
            update_composer
            ;;
        --optimize)
            optimize_databases
            optimize_php
            optimize_nginx
            ;;
        --clean)
            cleanup_old_previews
            cleanup_logs
            cleanup_temp_files
            cleanup_package_cache
            show_disk_usage
            ;;
        --ssl)
            renew_ssl_certificates
            ;;
        --status)
            show_service_status
            show_disk_usage
            generate_maintenance_report
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown option: $mode"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
