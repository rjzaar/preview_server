#!/bin/bash

################################################################################
# Preview Server Quick Health Check
#
# A lightweight health check script for quick system status verification.
# For comprehensive diagnostics, use check.sh instead.
#
# Usage: sudo bash health-check.sh [--json]
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

PREVIEW_DIR="/var/www/previews"
PREVIEW_USER="github-actions"
PHP_VERSION="8.3"
DISK_WARNING_THRESHOLD=80
MEMORY_WARNING_THRESHOLD=85
LOAD_WARNING_THRESHOLD=4.0

# Colors (disabled in JSON mode)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Status
OVERALL_STATUS="healthy"
JSON_MODE=false

################################################################################
# Helper Functions
################################################################################

check_json_mode() {
    if [[ "${1:-}" == "--json" ]]; then
        JSON_MODE=true
        # Disable colors in JSON mode
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        CYAN=''
        NC=''
    fi
}

log() {
    if [[ "$JSON_MODE" == "false" ]]; then
        echo -e "${GREEN}✓${NC} $*"
    fi
}

log_warning() {
    if [[ "$JSON_MODE" == "false" ]]; then
        echo -e "${YELLOW}⚠${NC} $*"
    fi
    OVERALL_STATUS="warning"
}

log_error() {
    if [[ "$JSON_MODE" == "false" ]]; then
        echo -e "${RED}✗${NC} $*"
    fi
    OVERALL_STATUS="critical"
}

log_info() {
    if [[ "$JSON_MODE" == "false" ]]; then
        echo -e "${BLUE}ℹ${NC} $*"
    fi
}

log_header() {
    if [[ "$JSON_MODE" == "false" ]]; then
        echo
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}$*${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
}

################################################################################
# Check Functions
################################################################################

declare -A CHECKS

check_services() {
    local nginx_status="unknown"
    local mariadb_status="unknown"
    local php_status="unknown"

    # Check Nginx
    if systemctl is-active --quiet nginx; then
        nginx_status="running"
        log "Nginx is running"
    else
        nginx_status="stopped"
        log_error "Nginx is not running"
    fi

    # Check MariaDB
    if systemctl is-active --quiet mariadb; then
        mariadb_status="running"
        log "MariaDB is running"
    else
        mariadb_status="stopped"
        log_error "MariaDB is not running"
    fi

    # Check PHP-FPM
    if systemctl is-active --quiet php${PHP_VERSION}-fpm; then
        php_status="running"
        log "PHP-FPM is running"
    else
        php_status="stopped"
        log_error "PHP-FPM is not running"
    fi

    CHECKS["nginx"]="$nginx_status"
    CHECKS["mariadb"]="$mariadb_status"
    CHECKS["php_fpm"]="$php_status"
}

check_disk_space() {
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    local disk_total=$(df -h / | tail -1 | awk '{print $2}')
    local disk_used=$(df -h / | tail -1 | awk '{print $3}')
    local disk_available=$(df -h / | tail -1 | awk '{print $4}')

    CHECKS["disk_usage_percent"]="$disk_usage"
    CHECKS["disk_total"]="$disk_total"
    CHECKS["disk_used"]="$disk_used"
    CHECKS["disk_available"]="$disk_available"

    if [[ $disk_usage -ge $DISK_WARNING_THRESHOLD ]]; then
        log_error "Disk usage critical: ${disk_usage}% used ($disk_used / $disk_total)"
    elif [[ $disk_usage -ge $((DISK_WARNING_THRESHOLD - 10)) ]]; then
        log_warning "Disk usage high: ${disk_usage}% used ($disk_used / $disk_total)"
    else
        log "Disk usage healthy: ${disk_usage}% used ($disk_used / $disk_total)"
    fi
}

check_memory() {
    local mem_total=$(free -m | grep Mem | awk '{print $2}')
    local mem_used=$(free -m | grep Mem | awk '{print $3}')
    local mem_available=$(free -m | grep Mem | awk '{print $7}')
    local mem_usage_percent=$((mem_used * 100 / mem_total))

    CHECKS["memory_total_mb"]="$mem_total"
    CHECKS["memory_used_mb"]="$mem_used"
    CHECKS["memory_available_mb"]="$mem_available"
    CHECKS["memory_usage_percent"]="$mem_usage_percent"

    if [[ $mem_usage_percent -ge $MEMORY_WARNING_THRESHOLD ]]; then
        log_warning "Memory usage high: ${mem_usage_percent}% (${mem_used}MB / ${mem_total}MB)"
    else
        log "Memory usage healthy: ${mem_usage_percent}% (${mem_used}MB / ${mem_total}MB)"
    fi
}

check_load_average() {
    local load_1min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs)
    local load_5min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | xargs)
    local load_15min=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $3}' | xargs)
    local cpu_cores=$(nproc)

    CHECKS["load_1min"]="$load_1min"
    CHECKS["load_5min"]="$load_5min"
    CHECKS["load_15min"]="$load_15min"
    CHECKS["cpu_cores"]="$cpu_cores"

    # Compare load to threshold
    local load_high=$(awk "BEGIN {print ($load_1min > $LOAD_WARNING_THRESHOLD)}")

    if [[ $load_high -eq 1 ]]; then
        log_warning "Load average high: $load_1min, $load_5min, $load_15min (${cpu_cores} cores)"
    else
        log "Load average healthy: $load_1min, $load_5min, $load_15min (${cpu_cores} cores)"
    fi
}

check_nginx_config() {
    if nginx -t &>/dev/null; then
        log "Nginx configuration is valid"
        CHECKS["nginx_config"]="valid"
    else
        log_error "Nginx configuration has errors"
        CHECKS["nginx_config"]="invalid"
    fi
}

check_database_connection() {
    if mysql -u root -e "SELECT 1;" &>/dev/null 2>&1; then
        log "MariaDB connection successful"
        CHECKS["mariadb_connection"]="ok"

        # Count preview databases
        local db_count=$(mysql -u root -e "SHOW DATABASES LIKE 'preview_%';" -s -N 2>/dev/null | wc -l)
        CHECKS["preview_databases"]="$db_count"
    else
        log_error "Cannot connect to MariaDB"
        CHECKS["mariadb_connection"]="failed"
        CHECKS["preview_databases"]="0"
    fi
}

check_preview_environments() {
    if [[ -d "$PREVIEW_DIR" ]]; then
        local preview_count=$(find "$PREVIEW_DIR" -maxdepth 1 -type d -name "pr-*" 2>/dev/null | wc -l)
        local preview_size=$(du -sh "$PREVIEW_DIR" 2>/dev/null | awk '{print $1}' || echo "0")

        CHECKS["active_previews"]="$preview_count"
        CHECKS["previews_total_size"]="$preview_size"

        if [[ $preview_count -gt 0 ]]; then
            log_info "Active previews: $preview_count (Total size: $preview_size)"
        else
            log_info "No active preview environments"
        fi
    else
        log_warning "Preview directory does not exist"
        CHECKS["active_previews"]="0"
        CHECKS["previews_total_size"]="0"
    fi
}

check_ssl_certificates() {
    if ! command -v certbot &>/dev/null; then
        CHECKS["ssl_certificates"]="0"
        return
    fi

    local cert_count=$(certbot certificates 2>/dev/null | grep -c "Certificate Name:" || echo "0")
    CHECKS["ssl_certificates"]="$cert_count"

    if [[ $cert_count -gt 0 ]]; then
        # Check for expiring certificates (within 30 days)
        local expiring=$(certbot certificates 2>/dev/null | grep -B2 "VALID:" | grep -c "30 days" || echo "0")

        if [[ $expiring -gt 0 ]]; then
            log_warning "SSL certificates found: $cert_count ($expiring expiring soon)"
        else
            log "SSL certificates: $cert_count"
        fi
    fi
}

check_connectivity() {
    # Check outbound connectivity
    if curl -s --connect-timeout 5 https://www.google.com > /dev/null 2>&1; then
        log "Outbound connectivity: OK"
        CHECKS["outbound_connectivity"]="ok"
    else
        log_error "No outbound connectivity"
        CHECKS["outbound_connectivity"]="failed"
    fi

    # Check HTTP port
    if nc -z localhost 80 2>/dev/null; then
        CHECKS["port_80"]="open"
    else
        CHECKS["port_80"]="closed"
        log_warning "Port 80 not accessible"
    fi

    # Check HTTPS port
    if nc -z localhost 443 2>/dev/null; then
        CHECKS["port_443"]="open"
    else
        CHECKS["port_443"]="closed"
    fi
}

check_recent_errors() {
    # Check nginx error log for recent errors
    local nginx_errors=0
    if [[ -f /var/log/nginx/error.log ]]; then
        nginx_errors=$(grep -c "error" /var/log/nginx/error.log 2>/dev/null | tail -100 || echo "0")
    fi

    # Check PHP-FPM error log
    local php_errors=0
    if [[ -f "/var/log/php${PHP_VERSION}-fpm.log" ]]; then
        php_errors=$(grep -c "ERROR" "/var/log/php${PHP_VERSION}-fpm.log" 2>/dev/null | tail -100 || echo "0")
    fi

    CHECKS["recent_nginx_errors"]="$nginx_errors"
    CHECKS["recent_php_errors"]="$php_errors"

    if [[ $nginx_errors -gt 100 ]] || [[ $php_errors -gt 100 ]]; then
        log_warning "High error count in logs (Nginx: $nginx_errors, PHP: $php_errors)"
    fi
}

################################################################################
# Output Functions
################################################################################

output_json() {
    cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "status": "$OVERALL_STATUS",
  "checks": {
    "services": {
      "nginx": "${CHECKS[nginx]:-unknown}",
      "mariadb": "${CHECKS[mariadb]:-unknown}",
      "php_fpm": "${CHECKS[php_fpm]:-unknown}"
    },
    "resources": {
      "disk": {
        "usage_percent": ${CHECKS[disk_usage_percent]:-0},
        "total": "${CHECKS[disk_total]:-unknown}",
        "used": "${CHECKS[disk_used]:-unknown}",
        "available": "${CHECKS[disk_available]:-unknown}"
      },
      "memory": {
        "usage_percent": ${CHECKS[memory_usage_percent]:-0},
        "total_mb": ${CHECKS[memory_total_mb]:-0},
        "used_mb": ${CHECKS[memory_used_mb]:-0},
        "available_mb": ${CHECKS[memory_available_mb]:-0}
      },
      "load": {
        "1min": ${CHECKS[load_1min]:-0},
        "5min": ${CHECKS[load_5min]:-0},
        "15min": ${CHECKS[load_15min]:-0},
        "cpu_cores": ${CHECKS[cpu_cores]:-0}
      }
    },
    "configuration": {
      "nginx_config": "${CHECKS[nginx_config]:-unknown}",
      "mariadb_connection": "${CHECKS[mariadb_connection]:-unknown}"
    },
    "previews": {
      "active_count": ${CHECKS[active_previews]:-0},
      "total_size": "${CHECKS[previews_total_size]:-0}",
      "databases": ${CHECKS[preview_databases]:-0}
    },
    "ssl": {
      "certificates": ${CHECKS[ssl_certificates]:-0}
    },
    "connectivity": {
      "outbound": "${CHECKS[outbound_connectivity]:-unknown}",
      "port_80": "${CHECKS[port_80]:-unknown}",
      "port_443": "${CHECKS[port_443]:-unknown}"
    },
    "errors": {
      "nginx_recent": ${CHECKS[recent_nginx_errors]:-0},
      "php_recent": ${CHECKS[recent_php_errors]:-0}
    }
  }
}
EOF
}

output_summary() {
    echo
    log_header "Health Check Summary"
    echo

    case "$OVERALL_STATUS" in
        healthy)
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}✓ System Status: HEALTHY${NC}"
            echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            ;;
        warning)
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}⚠ System Status: WARNING${NC}"
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            ;;
        critical)
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${RED}✗ System Status: CRITICAL${NC}"
            echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            ;;
    esac

    echo
    echo "Checked at: $(date)"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p)"
    echo
}

################################################################################
# Main
################################################################################

main() {
    check_json_mode "$@"

    if [[ "$JSON_MODE" == "false" ]]; then
        clear
        cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║          Preview Server Quick Health Check                  ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

EOF
    fi

    # Run all checks
    if [[ "$JSON_MODE" == "false" ]]; then
        log_header "Service Status"
    fi
    check_services

    if [[ "$JSON_MODE" == "false" ]]; then
        log_header "Resource Usage"
    fi
    check_disk_space
    check_memory
    check_load_average

    if [[ "$JSON_MODE" == "false" ]]; then
        log_header "Configuration & Connectivity"
    fi
    check_nginx_config
    check_database_connection
    check_connectivity

    if [[ "$JSON_MODE" == "false" ]]; then
        log_header "Preview Environments"
    fi
    check_preview_environments

    if [[ "$JSON_MODE" == "false" ]]; then
        log_header "SSL & Security"
    fi
    check_ssl_certificates

    if [[ "$JSON_MODE" == "false" ]]; then
        log_header "Error Monitoring"
    fi
    check_recent_errors

    # Output results
    if [[ "$JSON_MODE" == "true" ]]; then
        output_json
    else
        output_summary

        if [[ "$OVERALL_STATUS" != "healthy" ]]; then
            echo "For detailed diagnostics, run: sudo bash check.sh"
            echo
        fi
    fi

    # Set exit code based on status
    case "$OVERALL_STATUS" in
        healthy)
            exit 0
            ;;
        warning)
            exit 1
            ;;
        critical)
            exit 2
            ;;
    esac
}

main "$@"
