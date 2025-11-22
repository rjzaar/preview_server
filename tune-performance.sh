#!/bin/bash

################################################################################
# Performance Tuning Script
#
# Optimizes PHP, MySQL, and Nginx for better performance
#
# Usage: sudo bash tune-performance.sh [--apply]
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail

PHP_VERSION="8.3"
APPLY_CHANGES=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}✓${NC} $*"; }
log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
}

analyze_system() {
    echo -e "${YELLOW}━━━ System Resources ━━━${NC}"

    local total_mem=$(free -m | grep Mem | awk '{print $2}')
    local cpu_cores=$(nproc)

    log_info "Total Memory: ${total_mem}MB"
    log_info "CPU Cores: $cpu_cores"

    echo
}

tune_php() {
    echo -e "${YELLOW}━━━ PHP-FPM Performance Tuning ━━━${NC}"

    local total_mem=$(free -m | grep Mem | awk '{print $2}')
    local pm_max_children=$((total_mem / 50))

    log_info "Recommended pm.max_children: $pm_max_children"

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        local pool_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

        sed -i "s/^pm.max_children = .*/pm.max_children = $pm_max_children/" "$pool_conf"
        sed -i "s/^pm.start_servers = .*/pm.start_servers = $((pm_max_children / 4))/" "$pool_conf"
        sed -i "s/^pm.min_spare_servers = .*/pm.min_spare_servers = $((pm_max_children / 8))/" "$pool_conf"
        sed -i "s/^pm.max_spare_servers = .*/pm.max_spare_servers = $((pm_max_children / 2))/" "$pool_conf"

        log "PHP-FPM pool settings updated"
    else
        log_warn "Run with --apply to apply changes"
    fi
}

tune_mysql() {
    echo -e "${YELLOW}━━━ MySQL Performance Tuning ━━━${NC}"

    local total_mem=$(free -m | grep Mem | awk '{print $2}')
    local innodb_buffer=$((total_mem / 2))

    log_info "Recommended innodb_buffer_pool_size: ${innodb_buffer}MB"

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        cat > /etc/mysql/mysql.conf.d/99-performance.cnf <<EOF
[mysqld]
innodb_buffer_pool_size = ${innodb_buffer}M
innodb_log_file_size = 256M
max_connections = 200
query_cache_size = 0
query_cache_type = 0
EOF

        log "MySQL performance settings updated (restart required)"
        log_warn "Run: systemctl restart mysql"
    else
        log_warn "Run with --apply to apply changes"
    fi
}

tune_nginx() {
    echo -e "${YELLOW}━━━ Nginx Performance Tuning ━━━${NC}"

    local cpu_cores=$(nproc)

    log_info "Recommended worker_processes: $cpu_cores"

    if [[ "$APPLY_CHANGES" == "true" ]]; then
        sed -i "s/^worker_processes.*/worker_processes $cpu_cores;/" /etc/nginx/nginx.conf

        # Add to http block if not exists
        if ! grep -q "worker_connections" /etc/nginx/nginx.conf; then
            sed -i '/events {/a\    worker_connections 2048;' /etc/nginx/nginx.conf
        fi

        nginx -t && systemctl reload nginx
        log "Nginx performance settings updated"
    else
        log_warn "Run with --apply to apply changes"
    fi
}

show_current_config() {
    echo -e "${YELLOW}━━━ Current Configuration ━━━${NC}"

    echo -e "\n${BLUE}PHP-FPM:${NC}"
    grep -E "^pm\." "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf" 2>/dev/null || echo "Not found"

    echo -e "\n${BLUE}MySQL:${NC}"
    mysql -u root -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null || echo "Not accessible"

    echo -e "\n${BLUE}Nginx:${NC}"
    grep "worker_processes" /etc/nginx/nginx.conf 2>/dev/null || echo "Not found"

    echo
}

main() {
    check_root

    if [[ "${1:-}" == "--apply" ]]; then
        APPLY_CHANGES=true
        echo -e "${GREEN}Applying performance optimizations...${NC}\n"
    else
        echo -e "${BLUE}Running in analysis mode (use --apply to make changes)${NC}\n"
    fi

    analyze_system
    show_current_config
    tune_php
    tune_mysql
    tune_nginx

    echo
    if [[ "$APPLY_CHANGES" == "true" ]]; then
        log "Performance tuning complete!"
    else
        log_info "Run with --apply to apply recommended settings"
    fi
}

main "$@"
