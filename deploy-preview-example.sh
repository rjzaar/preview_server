#!/bin/bash

################################################################################
# Preview Deployment Example Script
#
# This script demonstrates how to deploy a Drupal preview environment.
# Use this as a template for GitHub Actions or manual deployments.
#
# Usage: bash deploy-preview-example.sh <pr-number> [branch]
# Note: Run as github-actions user (NOT as root)
#
# Author: Generated for Rob's Drupal preview system
# Version: 1.0.0
################################################################################

set -euo pipefail

################################################################################
# Configuration
################################################################################

PR_NUMBER="${1:-}"
BRANCH="${2:-main}"
PREVIEW_ID="pr-${PR_NUMBER}"
PREVIEW_DIR="/var/www/previews/${PREVIEW_ID}"
DB_NAME="preview_${PREVIEW_ID//-/_}"
DB_USER="preview"

# Read stored configuration
if [[ -f /root/.preview_domain ]]; then
    DOMAIN=$(sudo cat /root/.preview_domain)
elif [[ -f "$HOME/.preview_domain" ]]; then
    DOMAIN=$(cat "$HOME/.preview_domain")
else
    DOMAIN="example.com"
fi

if [[ -f "$HOME/.my.cnf" ]]; then
    # Extract password from .my.cnf
    DB_PASSWORD=$(grep "^password=" "$HOME/.my.cnf" | cut -d'=' -f2)
elif [[ -f /root/.preview_mariadb_password ]]; then
    DB_PASSWORD=$(sudo cat /root/.preview_mariadb_password)
else
    echo "Error: MariaDB preview password not found"
    exit 1
fi

PREVIEW_DOMAIN="preview-${PREVIEW_ID}.${DOMAIN}"

# Git repository (CHANGE THIS to your repository)
GIT_REPO="https://github.com/yourusername/your-drupal-site.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

log_section() {
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}$*${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

################################################################################
# Validation
################################################################################

validate_args() {
    if [[ -z "$PR_NUMBER" ]]; then
        log_error "PR number is required"
        echo "Usage: $0 <pr-number> [branch]"
        echo "Example: $0 123 feature/my-feature"
        exit 1
    fi

    if [[ ! "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
        log_error "PR number must be numeric"
        exit 1
    fi
}

################################################################################
# Deployment Steps
################################################################################

step_1_create_directory() {
    log_section "Step 1: Create Preview Directory"

    if [[ -d "$PREVIEW_DIR" ]]; then
        log "Preview directory exists, cleaning up old deployment..."
        rm -rf "$PREVIEW_DIR"
    fi

    log "Creating preview directory: $PREVIEW_DIR"
    mkdir -p "$PREVIEW_DIR"

    log "Directory created successfully"
}

step_2_clone_repository() {
    log_section "Step 2: Clone Repository"

    log "Cloning repository: $GIT_REPO"
    log_info "Branch: $BRANCH"

    git clone --branch "$BRANCH" --depth 1 "$GIT_REPO" "$PREVIEW_DIR"

    log "Repository cloned successfully"
}

step_3_install_dependencies() {
    log_section "Step 3: Install Dependencies"

    cd "$PREVIEW_DIR"

    if [[ -f "composer.json" ]]; then
        log "Installing Composer dependencies..."
        composer install --no-dev --optimize-autoloader --no-interaction

        log "Dependencies installed successfully"
    else
        log_info "No composer.json found, skipping dependency installation"
    fi
}

step_4_create_database() {
    log_section "Step 4: Create Database"

    log "Creating database: $DB_NAME"

    # Drop database if exists (using preview user's credentials from .my.cnf)
    mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" 2>/dev/null || true

    # Create database
    mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

    log "Database created successfully"
}

step_5_configure_drupal() {
    log_section "Step 5: Configure Drupal"

    cd "$PREVIEW_DIR"

    # Create settings.php if it doesn't exist
    if [[ ! -f "web/sites/default/settings.php" ]]; then
        if [[ -f "web/sites/default/default.settings.php" ]]; then
            cp "web/sites/default/default.settings.php" "web/sites/default/settings.php"
        fi
    fi

    # Make settings.php writable
    chmod 644 "web/sites/default/settings.php" 2>/dev/null || true

    # Add database configuration
    cat >> "web/sites/default/settings.php" <<EOF

/**
 * Preview Environment Database Configuration
 */
\$databases['default']['default'] = [
  'database' => '$DB_NAME',
  'username' => '$DB_USER',
  'password' => '$DB_PASSWORD',
  'host' => 'localhost',
  'port' => '3306',
  'driver' => 'mysql',
  'prefix' => '',
  'collation' => 'utf8mb4_general_ci',
];

/**
 * Trusted host configuration
 */
\$settings['trusted_host_patterns'] = [
  '^preview-pr-[0-9]+\.${DOMAIN//./\\.}$',
];

/**
 * Preview environment settings
 */
\$config['system.performance']['css']['preprocess'] = FALSE;
\$config['system.performance']['js']['preprocess'] = FALSE;
\$settings['skip_permissions_hardening'] = TRUE;
\$settings['config_sync_directory'] = '../config/sync';
EOF

    # Create files directory
    mkdir -p "web/sites/default/files"
    chmod 775 "web/sites/default/files"

    log "Drupal configured successfully"
}

step_6_install_drupal() {
    log_section "Step 6: Install Drupal"

    cd "$PREVIEW_DIR"

    # Option 1: Fresh Drupal installation
    log "Installing Drupal (fresh installation)..."
    ./vendor/bin/drush site:install standard \
        --db-url="mysql://${DB_USER}:${DB_PASSWORD}@localhost/${DB_NAME}" \
        --site-name="Preview PR-${PR_NUMBER}" \
        --account-name=admin \
        --account-pass=admin \
        --yes

    # Option 2: Import configuration (uncomment if you use config sync)
    # log "Importing configuration..."
    # ./vendor/bin/drush config:import --yes
    # ./vendor/bin/drush updatedb --yes

    log "Drupal installed successfully"
    log_info "Admin credentials: admin / admin"
}

step_7_create_nginx_config() {
    log_section "Step 7: Create Nginx Configuration"

    local nginx_config="/etc/nginx/sites-available/${PREVIEW_ID}"

    log "Creating Nginx configuration: $nginx_config"

    # Create config from template
    if [[ -f /etc/nginx/sites-available/preview-template ]]; then
        sed "s/PREVIEW_ID/${PREVIEW_ID}/g" /etc/nginx/sites-available/preview-template > "$nginx_config"
    else
        # Create basic config if template doesn't exist
        cat > "$nginx_config" <<EOF
server {
    listen 80;
    server_name ${PREVIEW_DOMAIN};
    root ${PREVIEW_DIR}/web;

    index index.php index.html;

    access_log /var/log/nginx/${PREVIEW_ID}-access.log;
    error_log /var/log/nginx/${PREVIEW_ID}-error.log;

    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ~* \.(txt|log)$ {
        deny all;
    }

    location / {
        try_files \$uri /index.php?\$query_string;
    }

    location @rewrite {
        rewrite ^ /index.php;
    }

    location ~ '\.php$|^/update.php' {
        fastcgi_split_path_info ^(.+?\.php)(|/.*)$;
        include fastcgi_params;
        fastcgi_param HTTP_PROXY "";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param QUERY_STRING \$query_string;
        fastcgi_intercept_errors on;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_read_timeout 300;
    }

    location ~ ^/sites/.*/files/styles/ {
        try_files \$uri @rewrite;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        try_files \$uri @rewrite;
        expires max;
        log_not_found off;
    }
}
EOF
    fi

    # Enable site
    sudo ln -sf "$nginx_config" "/etc/nginx/sites-enabled/${PREVIEW_ID}"

    # Test nginx config
    if sudo nginx -t; then
        log "Nginx configuration is valid"
        sudo systemctl reload nginx
        log "Nginx reloaded successfully"
    else
        log_error "Nginx configuration test failed"
        exit 1
    fi
}

step_8_setup_ssl() {
    log_section "Step 8: Setup SSL Certificate"

    if [[ -f /usr/local/bin/preview-ssl.sh ]]; then
        log "Requesting SSL certificate for: $PREVIEW_DOMAIN"

        if [[ -f /root/.certbot_email ]]; then
            EMAIL=$(sudo cat /root/.certbot_email)
        elif [[ -f "$HOME/.certbot_email" ]]; then
            EMAIL=$(cat "$HOME/.certbot_email")
        else
            EMAIL="admin@${DOMAIN}"
        fi

        sudo /usr/local/bin/preview-ssl.sh "${PREVIEW_ID}" "$DOMAIN" "$EMAIL" || {
            log_info "SSL certificate request failed (this is OK for testing)"
        }
    else
        log_info "SSL automation script not found, skipping SSL setup"
    fi
}

step_9_set_permissions() {
    log_section "Step 9: Set Permissions"

    log "Setting proper file permissions..."

    # Set ownership
    sudo chown -R github-actions:www-data "$PREVIEW_DIR"

    # Set directory permissions
    find "$PREVIEW_DIR" -type d -exec chmod 755 {} \;

    # Set file permissions
    find "$PREVIEW_DIR" -type f -exec chmod 644 {} \;

    # Make settings.php read-only
    chmod 444 "$PREVIEW_DIR/web/sites/default/settings.php" 2>/dev/null || true

    # Ensure files directory is writable
    chmod 775 "$PREVIEW_DIR/web/sites/default/files"
    find "$PREVIEW_DIR/web/sites/default/files" -type d -exec chmod 775 {} \;
    find "$PREVIEW_DIR/web/sites/default/files" -type f -exec chmod 664 {} \;

    log "Permissions set successfully"
}

step_10_clear_caches() {
    log_section "Step 10: Clear Caches"

    cd "$PREVIEW_DIR"

    if [[ -f "vendor/bin/drush" ]]; then
        log "Clearing Drupal caches..."
        ./vendor/bin/drush cache:rebuild
    fi

    log "Caches cleared successfully"
}

################################################################################
# Deployment Summary
################################################################################

print_summary() {
    log_section "Deployment Complete!"

    cat <<EOF
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}✓ Preview Environment Successfully Deployed${NC}
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${BLUE}Preview Information:${NC}
  Preview ID: ${PREVIEW_ID}
  URL: http://${PREVIEW_DOMAIN}
  Directory: ${PREVIEW_DIR}
  Database: ${DB_NAME}

${BLUE}Admin Access:${NC}
  Username: admin
  Password: admin
  Login URL: http://${PREVIEW_DOMAIN}/user/login

${BLUE}Useful Commands:${NC}
  View site:     curl http://${PREVIEW_DOMAIN}
  Clear cache:   cd ${PREVIEW_DIR} && ./vendor/bin/drush cr
  Check status:  cd ${PREVIEW_DIR} && ./vendor/bin/drush status
  Cleanup:       sudo preview-cleanup ${PREVIEW_ID}

${BLUE}Next Steps:${NC}
  1. Visit http://${PREVIEW_DOMAIN} to test your changes
  2. Log in with the admin credentials above
  3. When done, clean up with: sudo preview-cleanup ${PREVIEW_ID}

EOF
}

################################################################################
# Main
################################################################################

main() {
    echo
    log_section "Deploying Preview Environment for PR #${PR_NUMBER}"

    validate_args

    # Run deployment steps
    step_1_create_directory
    step_2_clone_repository
    step_3_install_dependencies
    step_4_create_database
    step_5_configure_drupal
    step_6_install_drupal
    step_7_create_nginx_config
    step_8_setup_ssl
    step_9_set_permissions
    step_10_clear_caches

    # Print summary
    print_summary
}

main "$@"
