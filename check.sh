#!/bin/bash

################################################################################
# Preview Server Diagnostic & Validation Script
# 
# This script checks that all components are properly installed and configured,
# and provides a detailed report of the server setup.
#
# Usage: sudo bash diagnose-preview-server.sh
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

REPORT_FILE="/var/log/preview-server-diagnostic-$(date +%Y%m%d-%H%M%S).txt"
PREVIEW_USER="github-actions"
PREVIEW_DIR="/var/www/previews"
PHP_VERSION="8.3"
MYSQL_PREVIEW_USER="preview"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Status symbols
PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"
INFO="${BLUE}ℹ${NC}"

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

################################################################################
# Helper Functions
################################################################################

report() {
    echo "$*" | tee -a "$REPORT_FILE"
}

report_section() {
    echo "" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}$*${NC}" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
}

check_pass() {
    ((TOTAL_CHECKS++))
    ((PASSED_CHECKS++))
    report "  $PASS $*"
}

check_fail() {
    ((TOTAL_CHECKS++))
    ((FAILED_CHECKS++))
    report "  $FAIL $*"
}

check_warn() {
    ((TOTAL_CHECKS++))
    ((WARNING_CHECKS++))
    report "  $WARN $*"
}

check_info() {
    report "  $INFO $*"
}

run_check() {
    local description="$1"
    local command="$2"
    
    if eval "$command" &>/dev/null; then
        check_pass "$description"
        return 0
    else
        check_fail "$description"
        return 1
    fi
}

get_value() {
    local command="$1"
    eval "$command" 2>/dev/null || echo "N/A"
}

################################################################################
# Check Functions
################################################################################

check_system_info() {
    report_section "System Information"
    
    check_info "Hostname: $(hostname)"
    check_info "OS: $(lsb_release -d | cut -f2)"
    check_info "Kernel: $(uname -r)"
    check_info "Architecture: $(uname -m)"
    check_info "Uptime: $(uptime -p)"
    check_info "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    
    # IP Addresses
    check_info "IP Addresses:"
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | while read ip; do
        check_info "  - $ip"
    done
    
    # Disk Space
    check_info "Disk Usage:"
    df -h / | tail -n 1 | awk '{print "  Root: "$3" used / "$2" total ("$5" used)"}'
    
    # Memory
    check_info "Memory:"
    free -h | grep Mem | awk '{print "  Total: "$2" | Used: "$3" | Free: "$4}'
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        check_pass "Running as root (required for full diagnostics)"
    else
        check_fail "Not running as root (some checks will be skipped)"
    fi
}

check_required_packages() {
    report_section "Package Installation Checks"
    
    # Web Server
    run_check "Nginx installed" "command -v nginx"
    if command -v nginx &>/dev/null; then
        check_info "  Version: $(nginx -v 2>&1 | cut -d'/' -f2)"
    fi
    
    # Database
    run_check "MySQL installed" "command -v mysql"
    if command -v mysql &>/dev/null; then
        check_info "  Version: $(mysql --version | awk '{print $5}' | sed 's/,//')"
    fi
    
    # PHP
    run_check "PHP installed" "command -v php"
    if command -v php &>/dev/null; then
        check_info "  Version: $(php -v | head -n1 | awk '{print $2}')"
        
        # PHP Extensions
        report ""
        report "  PHP Extensions:"
        local required_extensions=("mysqli" "gd" "xml" "mbstring" "curl" "zip" "intl" "opcache")
        for ext in "${required_extensions[@]}"; do
            if php -m | grep -q "^$ext$"; then
                check_pass "  $ext"
            else
                check_fail "  $ext (missing)"
            fi
        done
    fi
    
    # Composer
    run_check "Composer installed" "command -v composer"
    if command -v composer &>/dev/null; then
        check_info "  Version: $(composer --version --no-ansi 2>/dev/null | awk '{print $3}')"
    fi
    
    # Git
    run_check "Git installed" "command -v git"
    if command -v git &>/dev/null; then
        check_info "  Version: $(git --version | awk '{print $3}')"
    fi
    
    # Certbot
    run_check "Certbot installed" "command -v certbot"
    if command -v certbot &>/dev/null; then
        check_info "  Version: $(certbot --version 2>&1 | awk '{print $2}')"
    fi
    
    # UFW
    run_check "UFW (Firewall) installed" "command -v ufw"
    
    # Optional security tools
    if command -v fail2ban-client &>/dev/null; then
        check_pass "Fail2ban installed (optional)"
        check_info "  Version: $(fail2ban-client version)"
    else
        check_warn "Fail2ban not installed (recommended)"
    fi
}

check_services() {
    report_section "Service Status Checks"
    
    # Nginx
    if systemctl is-active --quiet nginx; then
        check_pass "Nginx is running"
    else
        check_fail "Nginx is not running"
    fi
    
    if systemctl is-enabled --quiet nginx; then
        check_pass "Nginx is enabled (starts on boot)"
    else
        check_warn "Nginx is not enabled for startup"
    fi
    
    # MySQL
    if systemctl is-active --quiet mysql; then
        check_pass "MySQL is running"
    else
        check_fail "MySQL is not running"
    fi
    
    if systemctl is-enabled --quiet mysql; then
        check_pass "MySQL is enabled (starts on boot)"
    else
        check_warn "MySQL is not enabled for startup"
    fi
    
    # PHP-FPM
    if systemctl is-active --quiet php${PHP_VERSION}-fpm; then
        check_pass "PHP-FPM is running"
    else
        check_fail "PHP-FPM is not running"
    fi
    
    if systemctl is-enabled --quiet php${PHP_VERSION}-fpm; then
        check_pass "PHP-FPM is enabled (starts on boot)"
    else
        check_warn "PHP-FPM is not enabled for startup"
    fi
    
    # Fail2ban (if installed)
    if command -v fail2ban-client &>/dev/null; then
        if systemctl is-active --quiet fail2ban; then
            check_pass "Fail2ban is running"
        else
            check_warn "Fail2ban is installed but not running"
        fi
    fi
}

check_user_setup() {
    report_section "User and Permissions Setup"
    
    # Check if user exists
    if id "$PREVIEW_USER" &>/dev/null; then
        check_pass "Preview user exists: $PREVIEW_USER"
        check_info "  UID: $(id -u $PREVIEW_USER)"
        check_info "  GID: $(id -g $PREVIEW_USER)"
        check_info "  Groups: $(groups $PREVIEW_USER | cut -d: -f2)"
        check_info "  Home: $(eval echo ~$PREVIEW_USER)"
    else
        check_fail "Preview user does not exist: $PREVIEW_USER"
        return
    fi
    
    # Check SSH directory
    local ssh_dir="/home/$PREVIEW_USER/.ssh"
    if [[ -d "$ssh_dir" ]]; then
        check_pass "SSH directory exists"
        
        # Check permissions
        local ssh_perms=$(stat -c %a "$ssh_dir")
        if [[ "$ssh_perms" == "700" ]]; then
            check_pass "SSH directory has correct permissions (700)"
        else
            check_warn "SSH directory permissions: $ssh_perms (should be 700)"
        fi
        
        # Check authorized_keys
        if [[ -f "$ssh_dir/authorized_keys" ]]; then
            check_pass "authorized_keys file exists"
            local key_count=$(grep -c "^ssh-" "$ssh_dir/authorized_keys" 2>/dev/null || echo "0")
            if [[ $key_count -gt 0 ]]; then
                check_pass "authorized_keys has $key_count key(s)"
            else
                check_warn "authorized_keys file is empty"
            fi
            
            local key_perms=$(stat -c %a "$ssh_dir/authorized_keys")
            if [[ "$key_perms" == "600" ]]; then
                check_pass "authorized_keys has correct permissions (600)"
            else
                check_warn "authorized_keys permissions: $key_perms (should be 600)"
            fi
        else
            check_warn "authorized_keys file not found"
        fi
    else
        check_fail "SSH directory does not exist"
    fi
    
    # Check sudo permissions
    if [[ -f "/etc/sudoers.d/$PREVIEW_USER" ]]; then
        check_pass "Sudoers file exists for $PREVIEW_USER"
        check_info "  Location: /etc/sudoers.d/$PREVIEW_USER"
    else
        check_warn "No sudoers configuration for $PREVIEW_USER"
    fi
    
    # Check preview directory
    if [[ -d "$PREVIEW_DIR" ]]; then
        check_pass "Preview directory exists: $PREVIEW_DIR"
        local dir_owner=$(stat -c %U:%G "$PREVIEW_DIR")
        if [[ "$dir_owner" == "$PREVIEW_USER:www-data" ]]; then
            check_pass "Preview directory ownership correct ($dir_owner)"
        else
            check_warn "Preview directory ownership: $dir_owner (expected: $PREVIEW_USER:www-data)"
        fi
        
        local dir_perms=$(stat -c %a "$PREVIEW_DIR")
        if [[ "$dir_perms" == "755" ]]; then
            check_pass "Preview directory permissions correct (755)"
        else
            check_warn "Preview directory permissions: $dir_perms (expected: 755)"
        fi
    else
        check_fail "Preview directory does not exist: $PREVIEW_DIR"
    fi
}

check_nginx_config() {
    report_section "Nginx Configuration"
    
    # Test configuration
    if nginx -t &>/dev/null; then
        check_pass "Nginx configuration is valid"
    else
        check_fail "Nginx configuration has errors"
        check_info "  Run 'nginx -t' for details"
    fi
    
    # Check main config
    if [[ -f /etc/nginx/nginx.conf ]]; then
        check_pass "Main nginx.conf exists"
        
        # Check important settings
        if grep -q "client_max_body_size" /etc/nginx/nginx.conf; then
            local max_size=$(grep client_max_body_size /etc/nginx/nginx.conf | awk '{print $2}' | sed 's/;//')
            check_info "  Max upload size: $max_size"
        fi
        
        if grep -q "gzip on" /etc/nginx/nginx.conf; then
            check_pass "Gzip compression enabled"
        else
            check_warn "Gzip compression not enabled"
        fi
    else
        check_fail "Main nginx.conf not found"
    fi
    
    # Check preview template
    if [[ -f /etc/nginx/sites-available/preview-template ]]; then
        check_pass "Preview template exists"
        
        # Extract domain from template
        local template_domain=$(grep "server_name" /etc/nginx/sites-available/preview-template | head -n1 | awk '{print $2}' | sed 's/preview-PREVIEW_ID\.//' | sed 's/;//')
        check_info "  Template domain: $template_domain"
    else
        check_fail "Preview template not found"
    fi
    
    # Check security headers
    if [[ -f /etc/nginx/conf.d/security-headers.conf ]]; then
        check_pass "Security headers configured"
    else
        check_warn "Security headers configuration not found (optional)"
    fi
    
    # Check rate limiting
    if grep -q "limit_req_zone" /etc/nginx/nginx.conf; then
        check_pass "Rate limiting configured"
        local rate=$(grep limit_req_zone /etc/nginx/nginx.conf | grep -o 'rate=[^;]*' | cut -d= -f2)
        check_info "  Rate: $rate"
    else
        check_warn "Rate limiting not configured (optional)"
    fi
    
    # Count active preview sites
    local preview_count=$(ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | grep -c "^pr-" || echo "0")
    check_info "Active preview sites: $preview_count"
    
    # List listening ports
    check_info "Nginx listening on:"
    ss -tlnp | grep nginx | awk '{print "  Port "$4}' | sort -u | tee -a "$REPORT_FILE"
}

check_php_config() {
    report_section "PHP Configuration"
    
    local php_ini="/etc/php/${PHP_VERSION}/fpm/php.ini"
    
    if [[ -f "$php_ini" ]]; then
        check_pass "PHP configuration file exists"
        check_info "  Location: $php_ini"
        
        # Extract key settings
        check_info ""
        check_info "PHP Settings:"
        
        local memory_limit=$(grep "^memory_limit" "$php_ini" | awk '{print $3}')
        check_info "  memory_limit: $memory_limit"
        
        local upload_max=$(grep "^upload_max_filesize" "$php_ini" | awk '{print $3}')
        check_info "  upload_max_filesize: $upload_max"
        
        local post_max=$(grep "^post_max_size" "$php_ini" | awk '{print $3}')
        check_info "  post_max_size: $post_max"
        
        local max_execution=$(grep "^max_execution_time" "$php_ini" | awk '{print $3}')
        check_info "  max_execution_time: $max_execution"
        
        # Check if values are adequate for Drupal
        local mem_val=$(echo "$memory_limit" | sed 's/M//')
        if [[ $mem_val -ge 256 ]]; then
            check_pass "Memory limit adequate for Drupal ($memory_limit)"
        else
            check_warn "Memory limit may be low for Drupal ($memory_limit, recommend 256M+)"
        fi
        
        # Check OPcache
        if php -i | grep -q "opcache.enable => On"; then
            check_pass "OPcache enabled"
        else
            check_warn "OPcache not enabled (recommended for performance)"
        fi
    else
        check_fail "PHP configuration file not found"
    fi
    
    # Check PHP-FPM pool config
    local pool_conf="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    if [[ -f "$pool_conf" ]]; then
        check_pass "PHP-FPM pool configuration exists"
        
        local listen=$(grep "^listen = " "$pool_conf" | awk '{print $3}')
        check_info "  Listening on: $listen"
    else
        check_warn "PHP-FPM pool configuration not found"
    fi
}

check_mysql_config() {
    report_section "MySQL Configuration and Database Setup"
    
    # Check if MySQL is accessible
    if mysql -u root -e "SELECT 1;" &>/dev/null; then
        check_pass "MySQL root access configured"
        
        # Get MySQL version
        local mysql_version=$(mysql -u root -e "SELECT VERSION();" -s -N)
        check_info "  MySQL Version: $mysql_version"
        
        # Check preview user
        if mysql -u root -e "SELECT User FROM mysql.user WHERE User='$MYSQL_PREVIEW_USER';" -s -N | grep -q "$MYSQL_PREVIEW_USER"; then
            check_pass "MySQL preview user exists: $MYSQL_PREVIEW_USER"
            
            # Check grants
            check_info "  Grants for $MYSQL_PREVIEW_USER:"
            mysql -u root -e "SHOW GRANTS FOR '$MYSQL_PREVIEW_USER'@'localhost';" -s -N | while read grant; do
                check_info "    $grant"
            done
            
            # Test preview user can connect
            if [[ -f "/root/.preview_mysql_password" ]]; then
                local preview_pass=$(sudo cat /root/.preview_mysql_password)
                if mysql -u "$MYSQL_PREVIEW_USER" -p"$preview_pass" -e "SELECT 1;" &>/dev/null; then
                    check_pass "Preview user can authenticate"
                else
                    check_fail "Preview user cannot authenticate"
                fi
            else
                check_warn "Preview user password file not found (cannot test authentication)"
            fi
        else
            check_fail "MySQL preview user does not exist: $MYSQL_PREVIEW_USER"
        fi
        
        # List preview databases
        local db_count=$(mysql -u root -e "SHOW DATABASES LIKE 'preview_%';" -s -N | wc -l)
        check_info "Preview databases: $db_count"
        if [[ $db_count -gt 0 ]]; then
            mysql -u root -e "SHOW DATABASES LIKE 'preview_%';" -s -N | while read db; do
                check_info "  - $db"
            done
        fi
        
        # Check security settings
        if mysql -u root -e "SELECT User FROM mysql.user WHERE User='';" -s -N | grep -q "^$"; then
            check_pass "No anonymous MySQL users"
        else
            check_warn "Anonymous MySQL users exist (security risk)"
        fi
        
        if mysql -u root -e "SHOW DATABASES LIKE 'test';" -s -N | grep -q "test"; then
            check_warn "Test database exists (should be removed)"
        else
            check_pass "Test database removed"
        fi
        
    else
        check_fail "Cannot access MySQL as root"
        check_info "  Check /root/.my.cnf or /root/.mysql_root_password"
    fi
}

check_ssl_setup() {
    report_section "SSL/TLS Configuration"
    
    # Check certbot
    if command -v certbot &>/dev/null; then
        check_pass "Certbot is installed"
        
        # List certificates
        local cert_count=$(certbot certificates 2>/dev/null | grep -c "Certificate Name:" || echo "0")
        check_info "SSL Certificates: $cert_count"
        
        if [[ $cert_count -gt 0 ]]; then
            certbot certificates 2>/dev/null | grep "Certificate Name:\|Domains:\|Expiry Date:" | tee -a "$REPORT_FILE"
        fi
    else
        check_warn "Certbot not installed"
    fi
    
    # Check SSL automation script
    if [[ -f /usr/local/bin/preview-ssl.sh ]]; then
        check_pass "SSL automation script exists"
        if [[ -x /usr/local/bin/preview-ssl.sh ]]; then
            check_pass "SSL automation script is executable"
        else
            check_warn "SSL automation script not executable"
        fi
    else
        check_warn "SSL automation script not found"
    fi
    
    # Check certbot auto-renewal
    if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        check_pass "Certbot auto-renewal configured"
    else
        check_warn "Certbot auto-renewal not configured"
    fi
}

check_firewall() {
    report_section "Firewall Configuration"
    
    if command -v ufw &>/dev/null; then
        check_pass "UFW is installed"
        
        if ufw status | grep -q "Status: active"; then
            check_pass "UFW is active"
            
            check_info ""
            check_info "Firewall Rules:"
            ufw status numbered | grep -v "Status:" | tee -a "$REPORT_FILE"
        else
            check_fail "UFW is not active"
        fi
    else
        check_fail "UFW is not installed"
    fi
}

check_security_hardening() {
    report_section "Security Hardening Status"
    
    # SSH Configuration
    if [[ -f /etc/ssh/sshd_config.d/99-hardening.conf ]]; then
        check_pass "SSH hardening configuration exists"
        
        # Check specific settings
        if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config* 2>/dev/null; then
            check_pass "Root login disabled"
        else
            check_warn "Root login not disabled"
        fi
        
        if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config* 2>/dev/null; then
            check_pass "Password authentication disabled"
        else
            check_warn "Password authentication not disabled"
        fi
    else
        check_warn "SSH hardening not applied"
    fi
    
    # Fail2ban
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        check_pass "Fail2ban is active"
        
        # Check jails
        if command -v fail2ban-client &>/dev/null; then
            check_info "Active Fail2ban jails:"
            fail2ban-client status | grep "Jail list:" | cut -d: -f2 | tr ',' '\n' | while read jail; do
                jail=$(echo "$jail" | xargs)
                if [[ -n "$jail" ]]; then
                    check_info "  - $jail"
                fi
            done
        fi
    else
        check_warn "Fail2ban not running (recommended)"
    fi
    
    # Automatic updates
    if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
        check_pass "Automatic security updates configured"
    else
        check_warn "Automatic security updates not configured"
    fi
    
    # AIDE (if installed)
    if command -v aide &>/dev/null; then
        check_pass "AIDE file integrity monitoring installed"
    else
        check_warn "AIDE not installed (optional)"
    fi
}

check_helper_scripts() {
    report_section "Helper Scripts"
    
    local scripts=(
        "/usr/local/bin/preview-info"
        "/usr/local/bin/preview-cleanup"
        "/usr/local/bin/preview-cleanup-old"
        "/usr/local/bin/preview-ssl.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if [[ -x "$script" ]]; then
                check_pass "$(basename "$script") - installed and executable"
            else
                check_warn "$(basename "$script") - exists but not executable"
            fi
        else
            check_warn "$(basename "$script") - not found"
        fi
    done
}

check_active_previews() {
    report_section "Active Preview Environments"
    
    if [[ -d "$PREVIEW_DIR" ]]; then
        local preview_dirs=($(find "$PREVIEW_DIR" -maxdepth 1 -type d -name "pr-*" 2>/dev/null || true))
        
        if [[ ${#preview_dirs[@]} -eq 0 ]]; then
            check_info "No active preview environments"
        else
            check_info "Found ${#preview_dirs[@]} preview environment(s):"
            
            for dir in "${preview_dirs[@]}"; do
                local preview_id=$(basename "$dir")
                check_info ""
                check_info "Preview: $preview_id"
                
                # Check directory size
                local size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
                check_info "  Size: $size"
                
                # Check last modified
                local modified=$(stat -c %y "$dir" | cut -d. -f1)
                check_info "  Last modified: $modified"
                
                # Check if nginx config exists
                if [[ -f "/etc/nginx/sites-enabled/$preview_id" ]]; then
                    check_info "  Nginx: ✓ configured"
                else
                    check_info "  Nginx: ✗ not configured"
                fi
                
                # Check database
                local db_name="preview_${preview_id//-/_}"
                if mysql -u root -e "USE $db_name;" &>/dev/null 2>&1; then
                    local db_size=$(mysql -u root -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)' FROM information_schema.TABLES WHERE table_schema='$db_name';" -s -N)
                    check_info "  Database: ✓ exists (${db_size}MB)"
                else
                    check_info "  Database: ✗ not found"
                fi
            done
        fi
    else
        check_warn "Preview directory does not exist"
    fi
}

check_network() {
    report_section "Network Configuration"
    
    # Check listening ports
    check_info "Listening Services:"
    ss -tlnp | grep -E "nginx|mysql|php-fpm" | awk '{print "  "$4" - "$7}' | tee -a "$REPORT_FILE"
    
    # Check DNS
    if [[ -f /root/.preview_domain ]]; then
        local domain=$(sudo cat /root/.preview_domain)
        check_info ""
        check_info "Preview domain: $domain"
        
        # Try to resolve wildcard
        local test_domain="preview-test.$domain"
        if host "$test_domain" &>/dev/null; then
            local resolved_ip=$(host "$test_domain" | grep "has address" | awk '{print $4}')
            check_pass "DNS wildcard resolves: $test_domain -> $resolved_ip"
        else
            check_warn "DNS wildcard not resolving for: $test_domain"
            check_info "  Make sure you have a wildcard DNS record pointing to this server"
        fi
    else
        check_warn "Preview domain not configured"
    fi
}

check_stored_credentials() {
    report_section "Stored Credentials and Configuration"
    
    local cred_files=(
        "/root/.mysql_root_password:MySQL Root Password"
        "/root/.preview_mysql_password:MySQL Preview User Password"
        "/root/.my.cnf:MySQL Root Config"
        "/root/.preview_domain:Preview Domain"
        "/root/.certbot_email:Certbot Email"
    )
    
    for item in "${cred_files[@]}"; do
        local file="${item%%:*}"
        local description="${item##*:}"
        
        if [[ -f "$file" ]]; then
            check_pass "$description stored"
            check_info "  Location: $file"
            
            # Check permissions
            local perms=$(stat -c %a "$file")
            if [[ "$perms" == "600" ]] || [[ "$perms" == "400" ]]; then
                check_pass "  Permissions: $perms (secure)"
            else
                check_warn "  Permissions: $perms (should be 600)"
            fi
            
            # Show value (except passwords)
            if [[ ! "$file" =~ password ]]; then
                local value=$(cat "$file")
                check_info "  Value: $value"
            fi
        else
            check_warn "$description not found"
        fi
    done
}

run_connectivity_test() {
    report_section "Connectivity Tests"
    
    # Test outbound connectivity
    if curl -s --connect-timeout 5 https://www.google.com > /dev/null; then
        check_pass "Outbound HTTPS connectivity working"
    else
        check_fail "Cannot establish outbound HTTPS connection"
    fi
    
    # Test if ports are accessible
    check_info "Testing local service connectivity:"
    
    if nc -z localhost 80 2>/dev/null; then
        check_pass "Port 80 (HTTP) is open"
    else
        check_warn "Port 80 (HTTP) is not accessible"
    fi
    
    if nc -z localhost 443 2>/dev/null; then
        check_pass "Port 443 (HTTPS) is open"
    else
        check_info "Port 443 (HTTPS) not open (normal if no SSL certs yet)"
    fi
    
    if nc -z localhost 3306 2>/dev/null; then
        check_pass "Port 3306 (MySQL) is open locally"
    else
        check_warn "Port 3306 (MySQL) is not accessible"
    fi
}

generate_summary() {
    report_section "Diagnostic Summary"
    
    local score_percentage=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    
    report "Total Checks: $TOTAL_CHECKS"
    report ""
    report "${GREEN}Passed:${NC}   $PASSED_CHECKS"
    report "${YELLOW}Warnings:${NC} $WARNING_CHECKS"
    report "${RED}Failed:${NC}   $FAILED_CHECKS"
    report ""
    
    if [[ $FAILED_CHECKS -eq 0 ]] && [[ $WARNING_CHECKS -eq 0 ]]; then
        report "${GREEN}═══════════════════════════════════════════════════${NC}"
        report "${GREEN}✓ All checks passed! Server is properly configured.${NC}"
        report "${GREEN}═══════════════════════════════════════════════════${NC}"
    elif [[ $FAILED_CHECKS -eq 0 ]]; then
        report "${YELLOW}═══════════════════════════════════════════════════════${NC}"
        report "${YELLOW}⚠ Server is functional but has warnings to address.${NC}"
        report "${YELLOW}═══════════════════════════════════════════════════════${NC}"
    else
        report "${RED}═══════════════════════════════════════════════════${NC}"
        report "${RED}✗ Server has issues that need to be fixed.${NC}"
        report "${RED}═══════════════════════════════════════════════════${NC}"
    fi
    
    report ""
    report "Health Score: $score_percentage%"
    report ""
    report "Full report saved to: $REPORT_FILE"
}

print_next_steps() {
    report_section "Recommended Next Steps"
    
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        report "${RED}Critical Issues to Fix:${NC}"
        report "1. Review failed checks above"
        report "2. Re-run setup script if packages are missing"
        report "3. Check service logs: journalctl -xe"
        report ""
    fi
    
    if [[ $WARNING_CHECKS -gt 0 ]]; then
        report "${YELLOW}Warnings to Address:${NC}"
        
        # Check for common warnings
        if ! systemctl is-active --quiet fail2ban 2>/dev/null; then
            report "• Install Fail2ban for brute force protection"
        fi
        
        if ! grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config* 2>/dev/null; then
            report "• Disable SSH password authentication"
        fi
        
        if [[ ! -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
            report "• Enable automatic security updates"
        fi
        
        if [[ ! -f /root/.preview_domain ]]; then
            report "• Configure preview domain"
        fi
        
        report ""
    fi
    
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        report "${GREEN}Ready for Preview Deployments:${NC}"
        report ""
        report "1. Add SSH key to GitHub Actions:"
        report "   cat your-key.pub | ssh root@your-server \"cat >> /home/$PREVIEW_USER/.ssh/authorized_keys\""
        report ""
        report "2. Configure DNS wildcard record"
        report ""
        report "3. Add GitHub Secrets:"
        report "   • PREVIEW_SSH_KEY"
        report "   • PREVIEW_HOST"
        report "   • PREVIEW_DB_PASSWORD"
        report ""
        report "4. Deploy your first preview with GitHub Actions!"
        report ""
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    # Clear screen and show header
    clear
    
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║              Preview Server Diagnostic & Validation Tool                    ║
║                                                                              ║
║              Checking all components and configurations...                  ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF
    
    # Initialize report
    {
        echo "Preview Server Diagnostic Report"
        echo "Generated: $(date)"
        echo "Hostname: $(hostname)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
    } > "$REPORT_FILE"
    
    # Run all checks
    check_system_info
    check_required_packages
    check_services
    check_user_setup
    check_nginx_config
    check_php_config
    check_mysql_config
    check_ssl_setup
    check_firewall
    check_security_hardening
    check_helper_scripts
    check_stored_credentials
    check_active_previews
    check_network
    run_connectivity_test
    
    # Generate summary
    generate_summary
    print_next_steps
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${CYAN}Full report available at:${NC} $REPORT_FILE"
    echo ""
    echo "To view the report:"
    echo "  cat $REPORT_FILE"
    echo "  less $REPORT_FILE"
    echo ""
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}Warning: Not running as root. Some checks will be limited.${NC}"
    echo "For full diagnostics, run: sudo $0"
    echo ""
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Run main function
main "$@"
