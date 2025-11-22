#!/bin/bash

################################################################################
# Preview Server Backup & Restore Script
#
# This script provides comprehensive backup and restore functionality for the
# preview server, including configurations, databases, and preview environments.
#
# Usage:
#   sudo bash backup-restore.sh backup [destination]
#   sudo bash backup-restore.sh restore <backup-file>
#   sudo bash backup-restore.sh list
#   sudo bash backup-restore.sh schedule
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

BACKUP_DIR="/var/backups/preview-server"
PREVIEW_DIR="/var/www/previews"
PREVIEW_USER="github-actions"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="preview-server-backup-${DATE}.tar.gz"

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

################################################################################
# Backup Functions
################################################################################

backup_databases() {
    local backup_temp="$1"

    log "Backing up MySQL databases..."

    mkdir -p "$backup_temp/databases"

    # Backup all preview databases
    mysql -u root -e "SHOW DATABASES LIKE 'preview_%';" -s -N | while read db; do
        log_info "  Backing up database: $db"
        mysqldump -u root --single-transaction --routines --triggers "$db" | gzip > "$backup_temp/databases/${db}.sql.gz"
    done

    # Count databases
    local db_count=$(ls -1 "$backup_temp/databases/" 2>/dev/null | wc -l)
    log "Backed up $db_count database(s)"
}

backup_configurations() {
    local backup_temp="$1"

    log "Backing up configurations..."

    mkdir -p "$backup_temp/config"

    # Nginx configurations
    if [[ -d /etc/nginx ]]; then
        log_info "  Backing up Nginx config"
        tar -czf "$backup_temp/config/nginx.tar.gz" -C /etc nginx 2>/dev/null || true
    fi

    # PHP configurations
    if [[ -d /etc/php ]]; then
        log_info "  Backing up PHP config"
        tar -czf "$backup_temp/config/php.tar.gz" -C /etc php 2>/dev/null || true
    fi

    # MySQL configurations
    if [[ -d /etc/mysql ]]; then
        log_info "  Backing up MySQL config"
        tar -czf "$backup_temp/config/mysql.tar.gz" -C /etc mysql 2>/dev/null || true
    fi

    # UFW rules
    if command -v ufw &>/dev/null; then
        log_info "  Backing up UFW rules"
        ufw status numbered > "$backup_temp/config/ufw-rules.txt" 2>/dev/null || true
    fi

    # Crontabs
    log_info "  Backing up crontabs"
    crontab -l > "$backup_temp/config/root-crontab.txt" 2>/dev/null || true
    if crontab -u "$PREVIEW_USER" -l &>/dev/null; then
        crontab -u "$PREVIEW_USER" -l > "$backup_temp/config/preview-user-crontab.txt" 2>/dev/null || true
    fi

    # Helper scripts
    if [[ -d /usr/local/bin ]]; then
        log_info "  Backing up helper scripts"
        mkdir -p "$backup_temp/config/scripts"
        cp /usr/local/bin/preview-* "$backup_temp/config/scripts/" 2>/dev/null || true
    fi

    # Stored credentials and config files
    log_info "  Backing up credentials"
    mkdir -p "$backup_temp/config/credentials"
    cp /root/.preview_mysql_password "$backup_temp/config/credentials/" 2>/dev/null || true
    cp /root/.mysql_root_password "$backup_temp/config/credentials/" 2>/dev/null || true
    cp /root/.preview_domain "$backup_temp/config/credentials/" 2>/dev/null || true
    cp /root/.certbot_email "$backup_temp/config/credentials/" 2>/dev/null || true
    cp /root/.my.cnf "$backup_temp/config/credentials/" 2>/dev/null || true

    log "Configuration backup complete"
}

backup_preview_environments() {
    local backup_temp="$1"

    log "Backing up preview environments..."

    if [[ -d "$PREVIEW_DIR" ]]; then
        local preview_count=$(find "$PREVIEW_DIR" -maxdepth 1 -type d -name "pr-*" 2>/dev/null | wc -l)

        if [[ $preview_count -gt 0 ]]; then
            log_info "  Found $preview_count preview environment(s)"
            mkdir -p "$backup_temp/previews"

            # Backup each preview
            find "$PREVIEW_DIR" -maxdepth 1 -type d -name "pr-*" | while read preview_dir; do
                local preview_id=$(basename "$preview_dir")
                log_info "    Backing up: $preview_id"
                tar -czf "$backup_temp/previews/${preview_id}.tar.gz" -C "$PREVIEW_DIR" "$preview_id" 2>/dev/null || true
            done
        else
            log_info "  No preview environments to backup"
        fi
    else
        log_warning "Preview directory does not exist"
    fi
}

backup_ssl_certificates() {
    local backup_temp="$1"

    log "Backing up SSL certificates..."

    if [[ -d /etc/letsencrypt ]]; then
        log_info "  Backing up Let's Encrypt certificates"
        tar -czf "$backup_temp/config/letsencrypt.tar.gz" -C /etc letsencrypt 2>/dev/null || true
    else
        log_info "  No SSL certificates found"
    fi
}

create_backup_metadata() {
    local backup_temp="$1"

    log "Creating backup metadata..."

    cat > "$backup_temp/backup-info.txt" <<EOF
Preview Server Backup
=====================

Backup Date: $(date)
Hostname: $(hostname)
IP Address: $(hostname -I | awk '{print $1}')
OS: $(lsb_release -d | cut -f2)
Kernel: $(uname -r)

Backup Contents:
----------------
$(find "$backup_temp" -type f | wc -l) files
$(du -sh "$backup_temp" | awk '{print $1}') total size

Preview Environments:
--------------------
$(find "$PREVIEW_DIR" -maxdepth 1 -type d -name "pr-*" 2>/dev/null | wc -l) active previews

Databases:
---------
$(mysql -u root -e "SHOW DATABASES LIKE 'preview_%';" -s -N | wc -l) preview databases

Services Status:
---------------
Nginx: $(systemctl is-active nginx 2>/dev/null || echo "inactive")
MySQL: $(systemctl is-active mysql 2>/dev/null || echo "inactive")
PHP-FPM: $(systemctl is-active php8.3-fpm 2>/dev/null || echo "inactive")

Software Versions:
-----------------
Nginx: $(nginx -v 2>&1 | cut -d'/' -f2)
MySQL: $(mysql --version | awk '{print $5}' | sed 's/,//')
PHP: $(php -v | head -n1 | awk '{print $2}')
Composer: $(composer --version --no-ansi 2>/dev/null | awk '{print $3}')

EOF

    # Create file listing
    find "$backup_temp" -type f > "$backup_temp/file-listing.txt"
}

perform_backup() {
    local destination="${1:-$BACKUP_DIR}"

    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Starting Preview Server Backup"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # Create backup directories
    mkdir -p "$destination"
    local backup_temp=$(mktemp -d)

    # Perform backups
    backup_databases "$backup_temp"
    backup_configurations "$backup_temp"
    backup_preview_environments "$backup_temp"
    backup_ssl_certificates "$backup_temp"
    create_backup_metadata "$backup_temp"

    # Create compressed archive
    log "Creating compressed backup archive..."
    tar -czf "$destination/$BACKUP_NAME" -C "$backup_temp" . 2>/dev/null

    # Clean up temp directory
    rm -rf "$backup_temp"

    # Set permissions
    chmod 600 "$destination/$BACKUP_NAME"

    # Get backup size
    local backup_size=$(du -sh "$destination/$BACKUP_NAME" | awk '{print $1}')

    echo
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Backup Complete!"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log_info "Backup file: $destination/$BACKUP_NAME"
    log_info "Backup size: $backup_size"
    echo
    log "To restore this backup, run:"
    log_info "  sudo bash $(basename $0) restore $destination/$BACKUP_NAME"
    echo
}

################################################################################
# Restore Functions
################################################################################

restore_backup() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi

    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Restoring Preview Server from Backup"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log_warning "This will restore configurations and data from the backup"
    log_warning "Existing data may be overwritten!"
    echo

    read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log "Restore cancelled"
        exit 0
    fi

    # Extract backup
    local restore_temp=$(mktemp -d)
    log "Extracting backup archive..."
    tar -xzf "$backup_file" -C "$restore_temp"

    # Show backup info
    if [[ -f "$restore_temp/backup-info.txt" ]]; then
        echo
        log_info "Backup Information:"
        cat "$restore_temp/backup-info.txt"
        echo
    fi

    # Restore databases
    if [[ -d "$restore_temp/databases" ]]; then
        log "Restoring databases..."
        for db_file in "$restore_temp/databases"/*.sql.gz; do
            if [[ -f "$db_file" ]]; then
                local db_name=$(basename "$db_file" .sql.gz)
                log_info "  Restoring database: $db_name"
                mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`$db_name\`;"
                gunzip < "$db_file" | mysql -u root "$db_name"
            fi
        done
    fi

    # Restore configurations
    if [[ -d "$restore_temp/config" ]]; then
        log "Restoring configurations..."

        # Nginx
        if [[ -f "$restore_temp/config/nginx.tar.gz" ]]; then
            log_info "  Restoring Nginx config"
            tar -xzf "$restore_temp/config/nginx.tar.gz" -C /etc/
            nginx -t && systemctl reload nginx
        fi

        # PHP
        if [[ -f "$restore_temp/config/php.tar.gz" ]]; then
            log_info "  Restoring PHP config"
            tar -xzf "$restore_temp/config/php.tar.gz" -C /etc/
            systemctl restart php8.3-fpm
        fi

        # MySQL
        if [[ -f "$restore_temp/config/mysql.tar.gz" ]]; then
            log_info "  Restoring MySQL config (requires manual restart)"
            tar -xzf "$restore_temp/config/mysql.tar.gz" -C /etc/
        fi

        # Credentials
        if [[ -d "$restore_temp/config/credentials" ]]; then
            log_info "  Restoring credentials"
            cp "$restore_temp/config/credentials"/* /root/ 2>/dev/null || true
            chmod 600 /root/.*.* 2>/dev/null || true
        fi

        # Scripts
        if [[ -d "$restore_temp/config/scripts" ]]; then
            log_info "  Restoring helper scripts"
            cp "$restore_temp/config/scripts"/* /usr/local/bin/ 2>/dev/null || true
            chmod +x /usr/local/bin/preview-* 2>/dev/null || true
        fi

        # SSL Certificates
        if [[ -f "$restore_temp/config/letsencrypt.tar.gz" ]]; then
            log_info "  Restoring SSL certificates"
            tar -xzf "$restore_temp/config/letsencrypt.tar.gz" -C /etc/
        fi
    fi

    # Restore preview environments
    if [[ -d "$restore_temp/previews" ]]; then
        log "Restoring preview environments..."
        mkdir -p "$PREVIEW_DIR"

        for preview_file in "$restore_temp/previews"/*.tar.gz; do
            if [[ -f "$preview_file" ]]; then
                local preview_id=$(basename "$preview_file" .tar.gz)
                log_info "  Restoring: $preview_id"
                tar -xzf "$preview_file" -C "$PREVIEW_DIR"
            fi
        done

        chown -R "$PREVIEW_USER:www-data" "$PREVIEW_DIR"
    fi

    # Clean up
    rm -rf "$restore_temp"

    echo
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Restore Complete!"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    log_info "Please verify all services are working correctly"
    log_info "You may need to restart MySQL: systemctl restart mysql"
    echo
}

################################################################################
# List Backups
################################################################################

list_backups() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Available Backups"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A $BACKUP_DIR/*.tar.gz 2>/dev/null)" ]]; then
        log_info "No backups found in $BACKUP_DIR"
        return
    fi

    echo -e "${CYAN}Backup File${NC}\t\t\t\t${CYAN}Size${NC}\t${CYAN}Date${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    for backup in "$BACKUP_DIR"/*.tar.gz; do
        if [[ -f "$backup" ]]; then
            local filename=$(basename "$backup")
            local size=$(du -sh "$backup" | awk '{print $1}')
            local date=$(stat -c %y "$backup" | cut -d. -f1)
            echo -e "$filename\t$size\t$date"
        fi
    done

    echo
}

################################################################################
# Schedule Automated Backups
################################################################################

schedule_backups() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Schedule Automated Backups"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    echo "Select backup frequency:"
    echo "  1) Daily at 2 AM"
    echo "  2) Weekly (Sunday at 2 AM)"
    echo "  3) Monthly (1st of month at 2 AM)"
    echo "  4) Custom"
    echo "  5) Remove scheduled backups"
    echo

    read -p "Selection (1-5): " choice

    local cron_entry=""
    local script_path="$(readlink -f $0)"

    case $choice in
        1)
            cron_entry="0 2 * * * $script_path backup >> /var/log/preview-backup.log 2>&1"
            log "Scheduling daily backups at 2 AM"
            ;;
        2)
            cron_entry="0 2 * * 0 $script_path backup >> /var/log/preview-backup.log 2>&1"
            log "Scheduling weekly backups (Sunday at 2 AM)"
            ;;
        3)
            cron_entry="0 2 1 * * $script_path backup >> /var/log/preview-backup.log 2>&1"
            log "Scheduling monthly backups (1st at 2 AM)"
            ;;
        4)
            echo
            log_info "Enter cron schedule (e.g., '0 2 * * *' for daily at 2 AM):"
            read -p "Schedule: " custom_schedule
            cron_entry="$custom_schedule $script_path backup >> /var/log/preview-backup.log 2>&1"
            log "Scheduling custom backup: $custom_schedule"
            ;;
        5)
            log "Removing scheduled backups..."
            (crontab -l 2>/dev/null | grep -v "backup-restore.sh") | crontab -
            log "Scheduled backups removed"
            return
            ;;
        *)
            log_error "Invalid selection"
            return
            ;;
    esac

    # Add to crontab
    (crontab -l 2>/dev/null | grep -v "backup-restore.sh"; echo "$cron_entry") | crontab -

    echo
    log "Backup scheduled successfully"
    log_info "Backups will be saved to: $BACKUP_DIR"
    log_info "Backup logs: /var/log/preview-backup.log"
    echo
    log "Current crontab:"
    crontab -l | grep "backup-restore.sh"
    echo
}

################################################################################
# Main
################################################################################

show_usage() {
    cat <<EOF
Preview Server Backup & Restore Tool

Usage:
  $(basename $0) backup [destination]     Create a backup
  $(basename $0) restore <backup-file>    Restore from backup
  $(basename $0) list                     List available backups
  $(basename $0) schedule                 Schedule automated backups

Examples:
  sudo bash $(basename $0) backup
  sudo bash $(basename $0) backup /mnt/external-drive
  sudo bash $(basename $0) restore /var/backups/preview-server/preview-server-backup-20250101-120000.tar.gz
  sudo bash $(basename $0) list
  sudo bash $(basename $0) schedule

EOF
}

main() {
    check_root

    local command="${1:-}"

    case "$command" in
        backup)
            perform_backup "${2:-$BACKUP_DIR}"
            ;;
        restore)
            if [[ -z "${2:-}" ]]; then
                log_error "Please specify a backup file to restore"
                show_usage
                exit 1
            fi
            restore_backup "$2"
            ;;
        list)
            list_backups
            ;;
        schedule)
            schedule_backups
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
