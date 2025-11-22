#!/bin/bash

################################################################################
# Log Management Script
#
# Manages server logs including rotation, archiving, and cleanup
#
# Usage: sudo bash manage-logs.sh [rotate|archive|clean|analyze|tail]
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail

LOG_DIR="/var/log/nginx"
ARCHIVE_DIR="/var/backups/logs"
DAYS_TO_KEEP=90

RED='\033[0;31m'
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

rotate_logs() {
    echo -e "${YELLOW}━━━ Rotating Logs ━━━${NC}"
    sudo logrotate -f /etc/logrotate.conf
    log "Logs rotated successfully"
}

archive_logs() {
    echo -e "${YELLOW}━━━ Archiving Logs ━━━${NC}"
    mkdir -p "$ARCHIVE_DIR"

    find "$LOG_DIR" -name "*.gz" -type f -exec cp {} "$ARCHIVE_DIR/" \; 2>/dev/null || true

    local count=$(find "$ARCHIVE_DIR" -type f | wc -l)
    log "Archived $count log files to $ARCHIVE_DIR"
}

clean_logs() {
    echo -e "${YELLOW}━━━ Cleaning Old Logs ━━━${NC}"

    local before=$(df -h "$LOG_DIR" | tail -1 | awk '{print $3}')

    find "$LOG_DIR" -name "*.log" -type f -mtime +$DAYS_TO_KEEP -delete
    find "$LOG_DIR" -name "*.gz" -type f -mtime +$DAYS_TO_KEEP -delete

    sudo journalctl --vacuum-time=${DAYS_TO_KEEP}d

    local after=$(df -h "$LOG_DIR" | tail -1 | awk '{print $3}')
    log "Cleaned old logs (Before: $before, After: $after)"
}

analyze_logs() {
    echo -e "${YELLOW}━━━ Log Analysis ━━━${NC}"

    echo -e "\n${BLUE}Top 10 Most Visited URLs:${NC}"
    awk '{print $7}' "$LOG_DIR"/*.log 2>/dev/null | sort | uniq -c | sort -rn | head -10

    echo -e "\n${BLUE}Top 10 IP Addresses:${NC}"
    awk '{print $1}' "$LOG_DIR"/*.log 2>/dev/null | sort | uniq -c | sort -rn | head -10

    echo -e "\n${BLUE}HTTP Status Codes:${NC}"
    awk '{print $9}' "$LOG_DIR"/*.log 2>/dev/null | sort | uniq -c | sort -rn

    echo -e "\n${BLUE}Recent Errors:${NC}"
    tail -20 "$LOG_DIR"/error.log 2>/dev/null || echo "No recent errors"
}

tail_logs() {
    echo -e "${YELLOW}━━━ Following Logs (Ctrl+C to stop) ━━━${NC}"
    tail -f "$LOG_DIR"/*.log
}

show_usage() {
    cat <<EOF
Log Management Tool

Usage:
  $(basename $0) rotate    Rotate logs
  $(basename $0) archive   Archive compressed logs
  $(basename $0) clean     Remove logs older than $DAYS_TO_KEEP days
  $(basename $0) analyze   Analyze log patterns
  $(basename $0) tail      Follow logs in real-time
  $(basename $0) all       Run all tasks (rotate, archive, clean)

EOF
}

main() {
    check_root

    case "${1:-all}" in
        rotate) rotate_logs ;;
        archive) archive_logs ;;
        clean) clean_logs ;;
        analyze) analyze_logs ;;
        tail) tail_logs ;;
        all)
            rotate_logs
            archive_logs
            clean_logs
            log "All log management tasks complete"
            ;;
        *) show_usage ;;
    esac
}

main "$@"
