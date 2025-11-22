#!/bin/bash

################################################################################
# Preview Server Security Audit Script
#
# Performs security checks and generates a security report including:
# - SSH configuration
# - Firewall rules
# - Service security
# - File permissions
# - Password policies
# - Outdated packages
#
# Usage: sudo bash security-audit.sh [--fix]
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

FIX_MODE=false
SECURITY_SCORE=100
ISSUES_FOUND=0
CRITICAL_ISSUES=0

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
    echo -e "${GREEN}✓${NC} $*"
}

log_fail() {
    echo -e "${RED}✗${NC} $*"
    ((ISSUES_FOUND++))
    ((SECURITY_SCORE-=5))
}

log_critical() {
    echo -e "${RED}⚠ CRITICAL:${NC} $*"
    ((CRITICAL_ISSUES++))
    ((ISSUES_FOUND++))
    ((SECURITY_SCORE-=10))
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
    ((ISSUES_FOUND++))
    ((SECURITY_SCORE-=2))
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_section() {
    echo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$*${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Error: This script must be run as root"
        exit 1
    fi
}

################################################################################
# Security Checks
################################################################################

check_ssh_security() {
    log_section "SSH Security Configuration"

    # Check if root login is disabled
    if grep -qE "^PermitRootLogin\s+(no|prohibit-password)" /etc/ssh/sshd_config* 2>/dev/null; then
        log "Root login is restricted"
    else
        log_fail "Root login should be disabled"
        if [[ "$FIX_MODE" == "true" ]]; then
            echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config.d/99-security-audit.conf
            log_info "Fixed: Disabled root password login"
        fi
    fi

    # Check password authentication
    if grep -qE "^PasswordAuthentication\s+no" /etc/ssh/sshd_config* 2>/dev/null; then
        log "Password authentication is disabled"
    else
        log_critical "Password authentication should be disabled (SSH keys only)"
        if [[ "$FIX_MODE" == "true" ]]; then
            echo "PasswordAuthentication no" >> /etc/ssh/sshd_config.d/99-security-audit.conf
            log_info "Fixed: Disabled password authentication"
        fi
    fi

    # Check SSH protocol
    if grep -qE "^Protocol\s+1" /etc/ssh/sshd_config 2>/dev/null; then
        log_critical "SSH Protocol 1 detected (should use Protocol 2)"
    else
        log "SSH Protocol 2 in use"
    fi

    # Check for empty passwords
    if grep -qE "^PermitEmptyPasswords\s+yes" /etc/ssh/sshd_config* 2>/dev/null; then
        log_critical "Empty passwords are permitted"
    else
        log "Empty passwords are not permitted"
    fi

    # Check MaxAuthTries
    local max_auth=$(grep -E "^MaxAuthTries" /etc/ssh/sshd_config* 2>/dev/null | head -1 | awk '{print $2}' || echo "6")
    if [[ $max_auth -gt 3 ]]; then
        log_warning "MaxAuthTries is $max_auth (recommended: 3)"
    else
        log "MaxAuthTries is set to $max_auth"
    fi
}

check_firewall() {
    log_section "Firewall Configuration"

    if command -v ufw &>/dev/null; then
        if ufw status | grep -q "Status: active"; then
            log "UFW firewall is active"

            # Check if SSH is allowed
            if ufw status | grep -q "22/tcp.*ALLOW"; then
                log "SSH access is allowed"
            else
                log_warning "SSH might not be allowed in firewall"
            fi

            # Check default policies
            if ufw status verbose | grep -q "Default: deny (incoming)"; then
                log "Default incoming policy is deny"
            else
                log_fail "Default incoming policy should be deny"
            fi
        else
            log_critical "UFW firewall is not active"
            if [[ "$FIX_MODE" == "true" ]]; then
                ufw --force enable
                log_info "Fixed: Enabled UFW firewall"
            fi
        fi
    else
        log_critical "UFW firewall is not installed"
        if [[ "$FIX_MODE" == "true" ]]; then
            apt install -y ufw
            ufw default deny incoming
            ufw default allow outgoing
            ufw allow ssh
            ufw allow 'Nginx Full'
            ufw --force enable
            log_info "Fixed: Installed and configured UFW"
        fi
    fi
}

check_automatic_updates() {
    log_section "Automatic Security Updates"

    if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
        log "Unattended upgrades are configured"

        if systemctl is-enabled unattended-upgrades &>/dev/null; then
            log "Automatic updates service is enabled"
        else
            log_warning "Automatic updates service is not enabled"
        fi
    else
        log_fail "Automatic security updates are not configured"
        if [[ "$FIX_MODE" == "true" ]]; then
            apt install -y unattended-upgrades
            dpkg-reconfigure -plow unattended-upgrades
            log_info "Fixed: Configured automatic updates"
        fi
    fi
}

check_fail2ban() {
    log_section "Intrusion Prevention (Fail2ban)"

    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active --quiet fail2ban; then
            log "Fail2ban is active"

            # Check active jails
            local jail_count=$(fail2ban-client status | grep "Jail list:" | cut -d: -f2 | tr ',' '\n' | wc -l)
            log_info "Active jails: $jail_count"
        else
            log_fail "Fail2ban is installed but not running"
            if [[ "$FIX_MODE" == "true" ]]; then
                systemctl enable fail2ban
                systemctl start fail2ban
                log_info "Fixed: Started Fail2ban"
            fi
        fi
    else
        log_warning "Fail2ban is not installed (recommended for brute-force protection)"
        if [[ "$FIX_MODE" == "true" ]]; then
            apt install -y fail2ban
            systemctl enable fail2ban
            systemctl start fail2ban
            log_info "Fixed: Installed and started Fail2ban"
        fi
    fi
}

check_file_permissions() {
    log_section "Critical File Permissions"

    # Check /etc/shadow permissions
    local shadow_perms=$(stat -c %a /etc/shadow)
    if [[ "$shadow_perms" == "640" ]] || [[ "$shadow_perms" == "600" ]]; then
        log "/etc/shadow has secure permissions ($shadow_perms)"
    else
        log_fail "/etc/shadow has incorrect permissions ($shadow_perms, should be 640)"
        if [[ "$FIX_MODE" == "true" ]]; then
            chmod 640 /etc/shadow
            log_info "Fixed: Set /etc/shadow permissions to 640"
        fi
    fi

    # Check /etc/passwd permissions
    local passwd_perms=$(stat -c %a /etc/passwd)
    if [[ "$passwd_perms" == "644" ]]; then
        log "/etc/passwd has correct permissions"
    else
        log_fail "/etc/passwd has incorrect permissions ($passwd_perms, should be 644)"
    fi

    # Check for world-writable files
    log_info "Checking for world-writable files in /etc..."
    local writable_count=$(find /etc -xdev -type f -perm -002 2>/dev/null | wc -l)
    if [[ $writable_count -eq 0 ]]; then
        log "No world-writable files found in /etc"
    else
        log_warning "Found $writable_count world-writable files in /etc"
    fi
}

check_user_security() {
    log_section "User Account Security"

    # Check for users with empty passwords
    local empty_pass=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | wc -l)
    if [[ $empty_pass -eq 0 ]]; then
        log "No users with empty passwords"
    else
        log_critical "Found $empty_pass user(s) with empty passwords"
    fi

    # Check for users with UID 0 (besides root)
    local uid_zero=$(awk -F: '($3 == 0 && $1 != "root") {print $1}' /etc/passwd | wc -l)
    if [[ $uid_zero -eq 0 ]]; then
        log "Only root has UID 0"
    else
        log_critical "Found $uid_zero non-root user(s) with UID 0"
    fi

    # Check password policy
    if [[ -f /etc/login.defs ]]; then
        local pass_max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
        if [[ $pass_max_days -le 90 ]]; then
            log "Password max age is set to $pass_max_days days"
        else
            log_warning "Password max age is $pass_max_days days (recommended: 90 or less)"
        fi
    fi
}

check_service_security() {
    log_section "Service Security"

    # Check MySQL remote access
    if netstat -an | grep -q ":3306.*0.0.0.0"; then
        log_fail "MySQL is listening on all interfaces (security risk)"
    else
        log "MySQL is not exposed to external networks"
    fi

    # Check for unnecessary services
    local unnecessary_services=("telnet" "ftp" "rsh" "rlogin")
    for service in "${unnecessary_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_critical "Unnecessary service is running: $service"
        fi
    done

    # Check PHP expose_php
    if grep -qE "^expose_php\s*=\s*Off" /etc/php/*/fpm/php.ini 2>/dev/null; then
        log "PHP expose_php is disabled"
    else
        log_warning "PHP expose_php should be disabled"
    fi
}

check_kernel_security() {
    log_section "Kernel Security Parameters"

    # Check if kernel parameters are hardened
    local params=(
        "net.ipv4.conf.all.accept_source_route:0"
        "net.ipv4.conf.all.accept_redirects:0"
        "net.ipv4.conf.all.send_redirects:0"
        "net.ipv4.icmp_echo_ignore_broadcasts:1"
    )

    for param in "${params[@]}"; do
        local key="${param%%:*}"
        local expected="${param##*:}"
        local actual=$(sysctl -n "$key" 2>/dev/null || echo "unknown")

        if [[ "$actual" == "$expected" ]]; then
            log "$key is set correctly ($actual)"
        else
            log_warning "$key is $actual (should be $expected)"
        fi
    done
}

check_outdated_packages() {
    log_section "Package Security Updates"

    apt update -qq

    local upgradable=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")

    if [[ $upgradable -eq 0 ]]; then
        log "All packages are up to date"
    else
        log_warning "$upgradable package(s) can be upgraded"

        # Check for security updates specifically
        local security_updates=$(apt list --upgradable 2>/dev/null | grep -c "security" || echo "0")
        if [[ $security_updates -gt 0 ]]; then
            log_critical "$security_updates security update(s) available"
        fi
    fi
}

check_web_server_security() {
    log_section "Web Server Security"

    # Check Nginx version
    if command -v nginx &>/dev/null; then
        if grep -q "server_tokens off" /etc/nginx/nginx.conf; then
            log "Nginx server tokens are hidden"
        else
            log_warning "Nginx server_tokens should be off"
        fi

        # Check for SSL/TLS configuration
        if grep -q "ssl_protocols TLSv1.2 TLSv1.3" /etc/nginx/nginx.conf; then
            log "Strong SSL/TLS protocols configured"
        else
            log_warning "SSL/TLS protocols should be TLSv1.2 and TLSv1.3 only"
        fi
    fi
}

check_file_integrity() {
    log_section "File Integrity Monitoring"

    if command -v aide &>/dev/null; then
        log "AIDE file integrity monitoring is installed"
    else
        log_info "AIDE not installed (optional but recommended)"
    fi
}

check_logging() {
    log_section "Logging and Auditing"

    # Check if logging is enabled
    if systemctl is-active --quiet rsyslog; then
        log "System logging (rsyslog) is active"
    else
        log_fail "System logging is not active"
    fi

    # Check disk space for logs
    local log_space=$(df /var/log | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $log_space -lt 90 ]]; then
        log "Log partition has adequate space (${log_space}% used)"
    else
        log_warning "Log partition is nearly full (${log_space}% used)"
    fi
}

################################################################################
# Report Generation
################################################################################

generate_report() {
    log_section "Security Audit Summary"

    # Calculate final score
    if [[ $SECURITY_SCORE -lt 0 ]]; then
        SECURITY_SCORE=0
    fi

    # Determine grade
    local grade="A"
    local color=$GREEN
    if [[ $SECURITY_SCORE -lt 90 ]]; then
        grade="B"
        color=$BLUE
    fi
    if [[ $SECURITY_SCORE -lt 80 ]]; then
        grade="C"
        color=$YELLOW
    fi
    if [[ $SECURITY_SCORE -lt 70 ]]; then
        grade="D"
        color=$RED
    fi
    if [[ $SECURITY_SCORE -lt 60 ]] || [[ $CRITICAL_ISSUES -gt 0 ]]; then
        grade="F"
        color=$RED
    fi

    cat <<EOF

${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
           Security Audit Complete
${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

Security Score: ${color}${SECURITY_SCORE}/100 (Grade: $grade)${NC}

Issues Found: $ISSUES_FOUND
Critical Issues: ${RED}$CRITICAL_ISSUES${NC}

EOF

    if [[ $CRITICAL_ISSUES -gt 0 ]]; then
        echo -e "${RED}⚠ ATTENTION: Critical security issues detected!${NC}"
        echo -e "${RED}   Run with --fix to automatically fix some issues${NC}"
        echo
    elif [[ $ISSUES_FOUND -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Security improvements recommended${NC}"
        echo -e "${YELLOW}   Run with --fix to automatically fix some issues${NC}"
        echo
    else
        echo -e "${GREEN}✓ No security issues detected${NC}"
        echo
    fi

    echo "Audit completed at: $(date)"
    echo "Hostname: $(hostname)"
    echo
}

################################################################################
# Main
################################################################################

show_usage() {
    cat <<EOF
Security Audit Script

Usage:
  $(basename $0)          Run security audit
  $(basename $0) --fix    Run audit and fix issues automatically

Examples:
  sudo bash $(basename $0)
  sudo bash $(basename $0) --fix

EOF
}

main() {
    check_root

    if [[ "${1:-}" == "--fix" ]]; then
        FIX_MODE=true
        echo -e "${YELLOW}Running in FIX mode - will attempt to fix issues${NC}"
        echo
    fi

    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        show_usage
        exit 0
    fi

    clear
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║            Preview Server Security Audit                    ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

EOF

    # Run all security checks
    check_ssh_security
    check_firewall
    check_automatic_updates
    check_fail2ban
    check_file_permissions
    check_user_security
    check_service_security
    check_kernel_security
    check_outdated_packages
    check_web_server_security
    check_file_integrity
    check_logging

    # Generate report
    generate_report

    if [[ "$FIX_MODE" == "true" ]] && [[ $ISSUES_FOUND -gt 0 ]]; then
        echo "Some issues have been fixed. Please restart affected services:"
        echo "  sudo systemctl restart sshd"
        echo "  sudo systemctl restart nginx"
        echo
    fi
}

main "$@"
