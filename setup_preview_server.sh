#!/bin/bash

################################################################################
# Linode Preview Environment Setup Script
# 
# This script sets up a complete preview environment system for Drupal projects
# with error checking, logging, and checkpoint-based resumability.
#
# Usage: sudo bash setup-preview-server.sh
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/preview-server-setup.log"
CHECKPOINT_FILE="/var/log/preview-setup-checkpoint"
PREVIEW_USER="github-actions"
PREVIEW_DIR="/var/www/previews"
NGINX_TEMPLATE_DIR="/etc/nginx/sites-available"
PHP_VERSION="8.3"
MYSQL_PREVIEW_USER="preview"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging and Output Functions
################################################################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "\n${GREEN}========================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${GREEN}$*${NC}" | tee -a "$LOG_FILE"
    echo -e "${GREEN}========================================${NC}\n" | tee -a "$LOG_FILE"
}

################################################################################
# Checkpoint Functions
################################################################################

save_checkpoint() {
    local checkpoint_name="$1"
    echo "$checkpoint_name" > "$CHECKPOINT_FILE"
    log_info "Checkpoint saved: $checkpoint_name"
}

get_checkpoint() {
    if [[ -f "$CHECKPOINT_FILE" ]]; then
        cat "$CHECKPOINT_FILE"
    else
        echo "start"
    fi
}

is_checkpoint_passed() {
    local checkpoint_name="$1"
    local current_checkpoint=$(get_checkpoint)
    
    # List of checkpoints in order
    local checkpoints=(
        "start"
        "system_updated"
        "packages_installed"
        "mysql_secured"
        "mysql_user_created"
        "preview_user_created"
        "directories_created"
        "nginx_configured"
        "php_configured"
        "ssl_setup"
        "firewall_configured"
        "scripts_installed"
        "complete"
    )
    
    # Find indices
    local current_index=-1
    local check_index=-1
    
    for i in "${!checkpoints[@]}"; do
        if [[ "${checkpoints[$i]}" == "$current_checkpoint" ]]; then
            current_index=$i
        fi
        if [[ "${checkpoints[$i]}" == "$checkpoint_name" ]]; then
            check_index=$i
        fi
    done
    
    # If current checkpoint is at or past the check, return true
    if [[ $current_index -ge $check_index ]]; then
        return 0
    else
        return 1
    fi
}

################################################################################
# Error Handling
################################################################################

error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Last command: $BASH_COMMAND"
    log_error "Check $LOG_FILE for details"
    
    echo -e "\n${RED}Installation failed!${NC}"
    echo -e "You can re-run this script to resume from the last successful checkpoint."
    echo -e "Current checkpoint: $(get_checkpoint)"
    echo -e "Log file: $LOG_FILE"
    exit 1
}

trap 'error_handler ${LINENO}' ERR

################################################################################
# Validation Functions
################################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_ubuntu() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script is designed for Ubuntu. Detected: $ID"
        exit 1
    fi
    
    log_info "Detected Ubuntu $VERSION"
}

validate_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command not found: $cmd"
        return 1
    fi
    return 0
}

################################################################################
# Interactive Input Functions
################################################################################

get_mysql_password() {
    if [[ -f "/root/.preview_mysql_password" ]]; then
        cat "/root/.preview_mysql_password"
    else
        while true; do
            read -sp "Enter MySQL password for preview user: " password1
            echo
            read -sp "Confirm password: " password2
            echo
            
            if [[ "$password1" == "$password2" ]]; then
                if [[ ${#password1} -lt 8 ]]; then
                    log_warning "Password should be at least 8 characters"
                    continue
                fi
                echo "$password1" > /root/.preview_mysql_password
                chmod 600 /root/.preview_mysql_password
                echo "$password1"
                break
            else
                log_error "Passwords do not match. Try again."
            fi
        done
    fi
}

get_domain() {
    if [[ -f "/root/.preview_domain" ]]; then
        cat "/root/.preview_domain"
    else
        echo
        log_info "Enter the base domain for preview environments"
        log_info "Example: If you enter 'example.com', previews will be at 'preview-pr-1.example.com'"
        read -p "Domain: " domain
        
        # Validate domain format
        if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_error "Invalid domain format"
            exit 1
        fi
        
        echo "$domain" > /root/.preview_domain
        echo "$domain"
    fi
}

################################################################################
# Installation Steps
################################################################################

update_system() {
    if is_checkpoint_passed "system_updated"; then
        log_info "System already updated, skipping..."
        return 0
    fi
    
    log_step "Updating System Packages"
    
    export DEBIAN_FRONTEND=noninteractive
    
    log "Running apt update..."
    apt update 2>&1 | tee -a "$LOG_FILE"
    
    log "Running apt upgrade..."
    apt upgrade -y 2>&1 | tee -a "$LOG_FILE"
    
    log "Installing basic utilities..."
    apt install -y \
        curl \
        wget \
        git \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release 2>&1 | tee -a "$LOG_FILE"
    
    save_checkpoint "system_updated"
    log "System update complete"
}

install_packages() {
    if is_checkpoint_passed "packages_installed"; then
        log_info "Packages already installed, skipping..."
        return 0
    fi
    
    log_step "Installing Required Packages"
    
    log "Installing Nginx..."
    apt install -y nginx 2>&1 | tee -a "$LOG_FILE"
    
    log "Installing MySQL Server..."
    apt install -y mysql-server 2>&1 | tee -a "$LOG_FILE"
    
    log "Installing PHP $PHP_VERSION and extensions..."
    apt install -y \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-apcu 2>&1 | tee -a "$LOG_FILE"
    
    log "Installing Composer..."
    if [[ ! -f /usr/local/bin/composer ]]; then
        EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
        
        if [[ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]]; then
            log_error "Composer installer corrupt"
            rm composer-setup.php
            exit 1
        fi
        
        php composer-setup.php --quiet
        rm composer-setup.php
        mv composer.phar /usr/local/bin/composer
        chmod +x /usr/local/bin/composer
    fi
    
    log "Installing Certbot for SSL..."
    apt install -y certbot python3-certbot-nginx 2>&1 | tee -a "$LOG_FILE"
    
    # Verify installations
    validate_command nginx
    validate_command mysql
    validate_command php
    validate_command composer
    validate_command certbot
    
    save_checkpoint "packages_installed"
    log "Package installation complete"
}

secure_mysql() {
    if is_checkpoint_passed "mysql_secured"; then
        log_info "MySQL already secured, skipping..."
        return 0
    fi
    
    log_step "Securing MySQL Installation"
    
    # Start MySQL if not running
    systemctl start mysql
    systemctl enable mysql
    
    log "Setting MySQL root password and securing installation..."
    
    # Get or generate root password
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32)
    echo "$MYSQL_ROOT_PASSWORD" > /root/.mysql_root_password
    chmod 600 /root/.mysql_root_password
    
    # Secure MySQL
    mysql -u root <<EOF 2>&1 | tee -a "$LOG_FILE"
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    # Create .my.cnf for root
    cat > /root/.my.cnf <<EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
EOF
    chmod 600 /root/.my.cnf
    
    save_checkpoint "mysql_secured"
    log "MySQL secured successfully"
}

create_mysql_preview_user() {
    if is_checkpoint_passed "mysql_user_created"; then
        log_info "MySQL preview user already created, skipping..."
        return 0
    fi
    
    log_step "Creating MySQL Preview User"
    
    MYSQL_PREVIEW_PASSWORD=$(get_mysql_password)
    
    log "Creating preview database user..."
    mysql -u root <<EOF 2>&1 | tee -a "$LOG_FILE"
CREATE USER IF NOT EXISTS '${MYSQL_PREVIEW_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PREVIEW_PASSWORD}';
GRANT ALL PRIVILEGES ON \`preview\\_%\`.* TO '${MYSQL_PREVIEW_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    
    # Test the connection
    if mysql -u "$MYSQL_PREVIEW_USER" -p"$MYSQL_PREVIEW_PASSWORD" -e "SELECT 1;" &>/dev/null; then
        log "MySQL preview user created and tested successfully"
    else
        log_error "Failed to create or test MySQL preview user"
        exit 1
    fi
    
    save_checkpoint "mysql_user_created"
}

create_preview_user() {
    if is_checkpoint_passed "preview_user_created"; then
        log_info "Preview user already created, skipping..."
        return 0
    fi
    
    log_step "Creating Preview System User"
    
    if id "$PREVIEW_USER" &>/dev/null; then
        log_info "User $PREVIEW_USER already exists"
    else
        log "Creating user $PREVIEW_USER..."
        adduser --disabled-password --gecos "" "$PREVIEW_USER"
        usermod -aG www-data "$PREVIEW_USER"
    fi
    
    # Create SSH directory
    if [[ ! -d "/home/$PREVIEW_USER/.ssh" ]]; then
        mkdir -p "/home/$PREVIEW_USER/.ssh"
        chown "$PREVIEW_USER:$PREVIEW_USER" "/home/$PREVIEW_USER/.ssh"
        chmod 700 "/home/$PREVIEW_USER/.ssh"
        touch "/home/$PREVIEW_USER/.ssh/authorized_keys"
        chmod 600 "/home/$PREVIEW_USER/.ssh/authorized_keys"
        chown "$PREVIEW_USER:$PREVIEW_USER" "/home/$PREVIEW_USER/.ssh/authorized_keys"
    fi
    
    # Add to sudoers for nginx management
    if [[ ! -f "/etc/sudoers.d/$PREVIEW_USER" ]]; then
        cat > "/etc/sudoers.d/$PREVIEW_USER" <<EOF
# Allow $PREVIEW_USER to manage nginx and preview-specific tasks
$PREVIEW_USER ALL=(ALL) NOPASSWD: /usr/sbin/nginx -t
$PREVIEW_USER ALL=(ALL) NOPASSWD: /bin/systemctl reload nginx
$PREVIEW_USER ALL=(ALL) NOPASSWD: /bin/systemctl restart nginx
$PREVIEW_USER ALL=(ALL) NOPASSWD: /bin/ln -sf /etc/nginx/sites-available/* /etc/nginx/sites-enabled/*
$PREVIEW_USER ALL=(ALL) NOPASSWD: /bin/rm -f /etc/nginx/sites-enabled/pr-*
$PREVIEW_USER ALL=(ALL) NOPASSWD: /bin/rm -f /etc/nginx/sites-available/pr-*
$PREVIEW_USER ALL=(ALL) NOPASSWD: /usr/bin/certbot *
$PREVIEW_USER ALL=(ALL) NOPASSWD: /usr/local/bin/preview-ssl.sh *
EOF
        chmod 440 "/etc/sudoers.d/$PREVIEW_USER"
    fi
    
    log "Preview user created: $PREVIEW_USER"
    log_info "SSH public key should be added to: /home/$PREVIEW_USER/.ssh/authorized_keys"
    
    save_checkpoint "preview_user_created"
}

create_directories() {
    if is_checkpoint_passed "directories_created"; then
        log_info "Directories already created, skipping..."
        return 0
    fi
    
    log_step "Creating Directory Structure"
    
    log "Creating preview directories..."
    mkdir -p "$PREVIEW_DIR"
    chown "$PREVIEW_USER:www-data" "$PREVIEW_DIR"
    chmod 755 "$PREVIEW_DIR"
    
    # Create scripts directory
    mkdir -p /usr/local/bin
    
    log "Directory structure created"
    save_checkpoint "directories_created"
}

configure_nginx() {
    if is_checkpoint_passed "nginx_configured"; then
        log_info "Nginx already configured, skipping..."
        return 0
    fi
    
    log_step "Configuring Nginx"
    
    # Backup original nginx.conf
    if [[ ! -f /etc/nginx/nginx.conf.backup ]]; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
    fi
    
    # Optimize nginx.conf for Drupal
    cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    multi_accept on;
}

http {
    ##
    # Basic Settings
    ##
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 100M;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL Settings
    ##
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    ##
    # Gzip Settings
    ##
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss 
               application/rss+xml font/truetype font/opentype 
               application/vnd.ms-fontobject image/svg+xml;
    gzip_disable "msie6";

    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    
    # Create preview template
    DOMAIN=$(get_domain)
    
    cat > "$NGINX_TEMPLATE_DIR/preview-template" <<EOF
server {
    listen 80;
    server_name preview-PREVIEW_ID.${DOMAIN};
    root /var/www/previews/PREVIEW_ID/web;
    
    index index.php index.html;
    
    # Logging
    access_log /var/log/nginx/preview-PREVIEW_ID-access.log;
    error_log /var/log/nginx/preview-PREVIEW_ID-error.log;
    
    # Drupal-specific configurations
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }
    
    # Very rarely should these ever be accessed outside of your lan
    location ~* \.(txt|log)$ {
        deny all;
    }
    
    location ~ \..*/.*\.php$ {
        return 403;
    }
    
    location ~ ^/sites/.*/private/ {
        return 403;
    }
    
    # Block access to scripts in site files directory
    location ~ ^/sites/[^/]+/files/.*\.php$ {
        deny all;
    }
    
    # Allow "Well-Known URIs" as per RFC 5785
    location ~* ^/.well-known/ {
        allow all;
    }
    
    # Block access to "hidden" files and directories
    location ~ (^|/)\. {
        return 403;
    }
    
    location / {
        try_files \$uri /index.php?\$query_string;
    }
    
    location @rewrite {
        rewrite ^ /index.php;
    }
    
    # Don't allow direct access to PHP files in the vendor directory.
    location ~ /vendor/.*\.php$ {
        deny all;
        return 404;
    }
    
    location ~ '\.php$|^/update.php' {
        fastcgi_split_path_info ^(.+?\.php)(|/.*)$;
        include fastcgi_params;
        fastcgi_param HTTP_PROXY "";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param QUERY_STRING \$query_string;
        fastcgi_intercept_errors on;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_read_timeout 300;
    }
    
    # Fighting with Styles? This little gem is amazing.
    location ~ ^/sites/.*/files/styles/ {
        try_files \$uri @rewrite;
    }
    
    # Handle private files through Drupal.
    location ~ ^(/[a-z\-]+)?/system/files/ {
        try_files \$uri /index.php?\$query_string;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        try_files \$uri @rewrite;
        expires max;
        log_not_found off;
    }
}
EOF
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    if nginx -t 2>&1 | tee -a "$LOG_FILE"; then
        systemctl enable nginx
        systemctl restart nginx
        log "Nginx configured and started successfully"
    else
        log_error "Nginx configuration test failed"
        exit 1
    fi
    
    save_checkpoint "nginx_configured"
}

configure_php() {
    if is_checkpoint_passed "php_configured"; then
        log_info "PHP already configured, skipping..."
        return 0
    fi
    
    log_step "Configuring PHP"
    
    PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
    
    if [[ ! -f "${PHP_INI}.backup" ]]; then
        cp "$PHP_INI" "${PHP_INI}.backup"
    fi
    
    # Update PHP settings for Drupal
    log "Updating PHP configuration..."
    sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$PHP_INI"
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' "$PHP_INI"
    sed -i 's/^post_max_size = .*/post_max_size = 100M/' "$PHP_INI"
    sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
    sed -i 's/^max_input_time = .*/max_input_time = 300/' "$PHP_INI"
    
    # Enable opcache
    cat >> "$PHP_INI" <<EOF

; Drupal optimizations
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
EOF
    
    # Restart PHP-FPM
    systemctl enable php${PHP_VERSION}-fpm
    systemctl restart php${PHP_VERSION}-fpm
    
    log "PHP configured successfully"
    save_checkpoint "php_configured"
}

setup_ssl_automation() {
    if is_checkpoint_passed "ssl_setup"; then
        log_info "SSL automation already set up, skipping..."
        return 0
    fi
    
    log_step "Setting up SSL Automation"
    
    DOMAIN=$(get_domain)
    
    # Get email for certbot
    if [[ -f "/root/.certbot_email" ]]; then
        CERTBOT_EMAIL=$(cat /root/.certbot_email)
    else
        read -p "Enter email for Let's Encrypt notifications: " CERTBOT_EMAIL
        echo "$CERTBOT_EMAIL" > /root/.certbot_email
    fi
    
    # Create SSL automation script
    cat > /usr/local/bin/preview-ssl.sh <<'EOF'
#!/bin/bash
set -euo pipefail

PREVIEW_ID="$1"
DOMAIN="$2"
EMAIL="$3"

PREVIEW_DOMAIN="preview-${PREVIEW_ID}.${DOMAIN}"

# Check if cert already exists
if certbot certificates 2>&1 | grep -q "$PREVIEW_DOMAIN"; then
    echo "Certificate already exists for $PREVIEW_DOMAIN"
    exit 0
fi

# Request certificate
certbot --nginx \
    -d "$PREVIEW_DOMAIN" \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --redirect \
    --no-eff-email

echo "SSL certificate obtained for $PREVIEW_DOMAIN"
EOF
    
    chmod +x /usr/local/bin/preview-ssl.sh
    
    # Set up auto-renewal
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
    fi
    
    log "SSL automation configured"
    log_info "SSL certificates will be obtained automatically for each preview"
    log_info "Certbot email: $CERTBOT_EMAIL"
    
    save_checkpoint "ssl_setup"
}

configure_firewall() {
    if is_checkpoint_passed "firewall_configured"; then
        log_info "Firewall already configured, skipping..."
        return 0
    fi
    
    log_step "Configuring Firewall (UFW)"
    
    # Install UFW if not present
    if ! command -v ufw &> /dev/null; then
        apt install -y ufw
    fi
    
    # Configure UFW
    log "Setting up firewall rules..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 'Nginx Full'
    ufw --force enable
    
    log "Firewall configured and enabled"
    save_checkpoint "firewall_configured"
}

install_helper_scripts() {
    if is_checkpoint_passed "scripts_installed"; then
        log_info "Helper scripts already installed, skipping..."
        return 0
    fi
    
    log_step "Installing Helper Scripts"
    
    MYSQL_PREVIEW_PASSWORD=$(cat /root/.preview_mysql_password)
    DOMAIN=$(get_domain)
    
    # Create preview info script
    cat > /usr/local/bin/preview-info <<EOF
#!/bin/bash
# Show information about preview environments

echo "=== Preview Environment Information ==="
echo
echo "Preview Directory: $PREVIEW_DIR"
echo "Preview User: $PREVIEW_USER"
echo "Domain: $DOMAIN"
echo "PHP Version: $PHP_VERSION"
echo
echo "Active Previews:"
if [[ -d "$PREVIEW_DIR" ]]; then
    ls -1 "$PREVIEW_DIR" 2>/dev/null || echo "  No active previews"
else
    echo "  Preview directory not found"
fi
echo
echo "Nginx Sites:"
ls -1 /etc/nginx/sites-enabled/ | grep -E '^pr-' || echo "  No preview sites"
echo
echo "Databases:"
mysql -u root -e "SHOW DATABASES LIKE 'preview_%';" 2>/dev/null | tail -n +2 || echo "  No preview databases"
EOF
    chmod +x /usr/local/bin/preview-info
    
    # Create manual cleanup script
    cat > /usr/local/bin/preview-cleanup <<EOF
#!/bin/bash
# Manually cleanup a specific preview environment

if [[ \$# -ne 1 ]]; then
    echo "Usage: preview-cleanup <preview-id>"
    echo "Example: preview-cleanup pr-123"
    exit 1
fi

PREVIEW_ID="\$1"
PREVIEW_PATH="$PREVIEW_DIR/\$PREVIEW_ID"
DB_NAME="preview_\${PREVIEW_ID//-/_}"

echo "Cleaning up preview: \$PREVIEW_ID"

# Remove directory
if [[ -d "\$PREVIEW_PATH" ]]; then
    echo "Removing directory: \$PREVIEW_PATH"
    rm -rf "\$PREVIEW_PATH"
else
    echo "Directory not found: \$PREVIEW_PATH"
fi

# Remove database
echo "Removing database: \$DB_NAME"
mysql -u root -e "DROP DATABASE IF EXISTS \${DB_NAME};" 2>/dev/null || true

# Remove nginx config
if [[ -f "/etc/nginx/sites-enabled/\$PREVIEW_ID" ]]; then
    echo "Removing nginx config"
    rm -f "/etc/nginx/sites-enabled/\$PREVIEW_ID"
    rm -f "/etc/nginx/sites-available/\$PREVIEW_ID"
    nginx -t && systemctl reload nginx
fi

# Remove SSL cert
certbot delete --cert-name "preview-\${PREVIEW_ID}.${DOMAIN}" --non-interactive 2>/dev/null || true

echo "Cleanup complete for: \$PREVIEW_ID"
EOF
    chmod +x /usr/local/bin/preview-cleanup
    
    # Create old preview cleanup script
    cat > /usr/local/bin/preview-cleanup-old <<'EOF'
#!/bin/bash
# Cleanup preview environments older than specified days (default: 7)

DAYS="${1:-7}"
PREVIEW_DIR="/var/www/previews"

echo "Cleaning up previews older than $DAYS days..."

find "$PREVIEW_DIR" -maxdepth 1 -type d -name "pr-*" -mtime +"$DAYS" | while read -r dir; do
    PREVIEW_ID=$(basename "$dir")
    echo "Found old preview: $PREVIEW_ID"
    /usr/local/bin/preview-cleanup "$PREVIEW_ID"
done

echo "Cleanup complete"
EOF
    chmod +x /usr/local/bin/preview-cleanup-old
    
    log "Helper scripts installed:"
    log "  - preview-info: Show preview environment information"
    log "  - preview-cleanup <id>: Manually cleanup a specific preview"
    log "  - preview-cleanup-old [days]: Cleanup previews older than N days (default: 7)"
    
    save_checkpoint "scripts_installed"
}

################################################################################
# Final Steps
################################################################################

print_summary() {
    log_step "Installation Complete!"
    
    DOMAIN=$(get_domain)
    MYSQL_PREVIEW_PASSWORD=$(cat /root/.preview_mysql_password)
    
    cat <<EOF | tee -a "$LOG_FILE"

${GREEN}╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║       Preview Environment Server Setup Complete! 🎉           ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝${NC}

${BLUE}Server Information:${NC}
  • Preview User: $PREVIEW_USER
  • Preview Directory: $PREVIEW_DIR
  • Base Domain: $DOMAIN
  • PHP Version: $PHP_VERSION

${BLUE}Next Steps:${NC}

1. Add SSH public key for GitHub Actions:
   ${YELLOW}cat your-key.pub | ssh root@your-server "cat >> /home/$PREVIEW_USER/.ssh/authorized_keys"${NC}

2. Set up DNS wildcard record:
   ${YELLOW}Type: A
   Name: *.preview (or preview-*)
   Value: $(hostname -I | awk '{print $1}')${NC}

3. Add these secrets to your GitHub repository:
   ${YELLOW}PREVIEW_SSH_KEY${NC} - Your private SSH key
   ${YELLOW}PREVIEW_HOST${NC} - $PREVIEW_USER@$(hostname -I | awk '{print $1}')
   ${YELLOW}PREVIEW_DB_PASSWORD${NC} - (stored in /root/.preview_mysql_password)

4. MySQL Preview User Password:
   ${YELLOW}$(cat /root/.preview_mysql_password)${NC}
   (Also stored in: /root/.preview_mysql_password)

${BLUE}Useful Commands:${NC}
  • preview-info                    - Show preview environment info
  • preview-cleanup <id>            - Cleanup specific preview
  • preview-cleanup-old [days]      - Cleanup old previews

${BLUE}Important Files:${NC}
  • Log: $LOG_FILE
  • Checkpoint: $CHECKPOINT_FILE
  • MySQL Root Password: /root/.mysql_root_password
  • MySQL Preview Password: /root/.preview_mysql_password
  • Nginx Template: $NGINX_TEMPLATE_DIR/preview-template

${GREEN}Your server is ready to receive preview deployments!${NC}

To test, you can manually create a preview:
  ${YELLOW}sudo -u $PREVIEW_USER bash
  cd $PREVIEW_DIR
  # ... create your preview environment${NC}

EOF
}

################################################################################
# Main Installation Flow
################################################################################

main() {
    # Initialize log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log_step "Starting Preview Environment Server Setup"
    
    # Pre-flight checks
    check_root
    check_ubuntu
    
    CURRENT_CHECKPOINT=$(get_checkpoint)
    if [[ "$CURRENT_CHECKPOINT" != "start" ]]; then
        log_info "Resuming from checkpoint: $CURRENT_CHECKPOINT"
        echo
        read -p "Continue from last checkpoint? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Starting fresh installation..."
            rm -f "$CHECKPOINT_FILE"
        fi
    fi
    
    # Run installation steps
    update_system
    install_packages
    secure_mysql
    create_mysql_preview_user
    create_preview_user
    create_directories
    configure_nginx
    configure_php
    setup_ssl_automation
    configure_firewall
    install_helper_scripts
    
    # Mark as complete
    save_checkpoint "complete"
    
    # Print summary
    print_summary
}

# Run main function
main "$@"
