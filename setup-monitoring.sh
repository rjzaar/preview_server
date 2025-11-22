#!/bin/bash

################################################################################
# Monitoring Setup Script
#
# Installs and configures monitoring tools for the preview server
#
# Usage: sudo bash setup-monitoring.sh [netdata|prometheus|simple]
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }

check_root() {
    # Allow both root and github-actions user
    if [[ $EUID -ne 0 ]] && [[ "$USER" != "github-actions" ]]; then
        echo "Error: This script must be run as root or github-actions user"
        exit 1
    fi
}

install_netdata() {
    log "Installing Netdata monitoring..."

    bash <(curl -Ss https://my-netdata.io/kickstart.sh) --non-interactive

    log "Netdata installed successfully"
    log_info "Access Netdata at: http://$(hostname -I | awk '{print $1}'):19999"
}

install_simple_monitoring() {
    log "Setting up simple monitoring with cron jobs..."

    mkdir -p /var/log/monitoring

    # Create monitoring script
    cat > /usr/local/bin/simple-monitor.sh <<'EOF'
#!/bin/bash
LOG="/var/log/monitoring/system-$(date +%Y%m%d).log"

{
    echo "=== System Monitor - $(date) ==="
    echo "Uptime: $(uptime -p)"
    echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
    echo "Memory: $(free -h | grep Mem | awk '{print "Used: "$3" / "$2}')"
    echo "Disk: $(df -h / | tail -1 | awk '{print "Used: "$3" / "$2" ("$5")"}')"
    echo "Services:"
    sudo systemctl is-active nginx && echo "  nginx: OK" || echo "  nginx: FAIL"
    sudo systemctl is-active mariadb && echo "  mariadb: OK" || echo "  mariadb: FAIL"
    sudo systemctl is-active php8.3-fpm && echo "  php-fpm: OK" || echo "  php-fpm: FAIL"
    echo
} >> "$LOG"
EOF

    chmod +x /usr/local/bin/simple-monitor.sh

    # Add cron job
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/simple-monitor.sh") | crontab -

    log "Simple monitoring configured"
    log_info "Logs are stored in /var/log/monitoring/"
}

setup_email_alerts() {
    log "Setting up email alerts..."

    sudo apt install -y mailutils

    # Create alert script
    cat > /usr/local/bin/alert-check.sh <<'EOF'
#!/bin/bash
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

if [[ $DISK_USAGE -gt 90 ]]; then
    echo "Disk usage is at ${DISK_USAGE}%" | mail -s "Alert: High Disk Usage" admin@localhost
fi
EOF

    chmod +x /usr/local/bin/alert-check.sh

    log "Email alerts configured"
}

main() {
    check_root

    local mode="${1:-simple}"

    case "$mode" in
        netdata)
            install_netdata
            ;;
        simple)
            install_simple_monitoring
            ;;
        alerts)
            setup_email_alerts
            ;;
        *)
            cat <<EOF
Monitoring Setup Tool

Usage:
  $(basename $0) netdata    Install Netdata (full monitoring dashboard)
  $(basename $0) simple     Simple cron-based monitoring
  $(basename $0) alerts     Set up email alerts

EOF
            ;;
    esac
}

main "$@"
