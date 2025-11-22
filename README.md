# Preview Server Management Scripts

A comprehensive collection of scripts for managing a Drupal preview environment server. This toolset provides everything you need to set up, maintain, monitor, and secure your preview deployment infrastructure.

## 📚 Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Scripts Reference](#scripts-reference)
- [Documentation](#documentation)
- [Requirements](#requirements)
- [Installation](#installation)

## Overview

This repository contains a complete suite of tools for managing a production-ready preview environment server for Drupal projects. The system allows you to automatically deploy pull request previews with their own isolated environments, databases, and domains.

### Features

- **Automated Setup**: Complete server setup with one command
- **Preview Deployment**: Easy deployment of isolated preview environments
- **Health Monitoring**: Comprehensive health checks and monitoring
- **Security Auditing**: Automated security scans and hardening
- **Backup & Restore**: Full system backup and disaster recovery
- **Performance Tuning**: Optimize PHP, MySQL, and Nginx
- **Log Management**: Centralized log rotation and analysis
- **SSL Automation**: Automatic Let's Encrypt SSL certificates

## Quick Start

### Initial Server Setup

```bash
# Clone this repository
git clone https://github.com/yourusername/preview_server.git
cd preview_server

# Run the initial setup (requires sudo)
sudo bash setup_preview_server.sh
```

The setup script will:
- Install and configure Nginx, PHP 8.3, MySQL
- Create preview user and directories
- Configure SSL automation
- Set up firewall rules
- Install helper scripts

### Verify Installation

```bash
# Run diagnostic check
sudo bash check.sh

# Run health check
sudo bash health-check.sh
```

### Deploy Your First Preview

```bash
# Deploy preview for PR #123
sudo -u github-actions bash deploy-preview-example.sh 123
```

## Scripts Reference

### Setup & Installation

#### `setup_preview_server.sh`
Complete server setup and configuration with checkpoint-based resumability.

```bash
sudo bash setup_preview_server.sh
```

**Features:**
- Installs all required packages (Nginx, PHP, MySQL, Composer, Certbot)
- Configures services with Drupal-optimized settings
- Creates preview user with proper permissions
- Sets up SSL automation
- Configures firewall (UFW)
- Installs helper scripts

**Configuration:**
- Preview user: `github-actions`
- Preview directory: `/var/www/previews`
- PHP version: 8.3
- MySQL user: `preview`

---

### Diagnostics & Monitoring

#### `check.sh`
Comprehensive diagnostic and validation tool that checks all server components.

```bash
sudo bash check.sh
```

**What it checks:**
- System information and resources
- Package installation status
- Service health (Nginx, MySQL, PHP-FPM)
- User and permission setup
- Nginx and PHP configuration
- Database connectivity
- SSL certificates
- Firewall rules
- Active preview environments
- Network configuration

**Output:**
- Detailed report with pass/fail/warning status
- Saves report to `/var/log/preview-server-diagnostic-*.txt`
- Provides recommendations for fixes

#### `health-check.sh`
Quick lightweight health check for monitoring integrations.

```bash
# Human-readable output
sudo bash health-check.sh

# JSON output for monitoring tools
sudo bash health-check.sh --json
```

**Checks:**
- Service status (Nginx, MySQL, PHP-FPM)
- Resource usage (disk, memory, CPU load)
- Configuration validity
- Database connectivity
- Preview environment count
- SSL certificates
- Network connectivity
- Recent errors

**Exit codes:**
- `0` = Healthy
- `1` = Warning
- `2` = Critical

---

### Deployment

#### `deploy-preview-example.sh`
Example/template script for deploying preview environments.

```bash
sudo -u github-actions bash deploy-preview-example.sh <pr-number> [branch]

# Examples:
sudo -u github-actions bash deploy-preview-example.sh 123
sudo -u github-actions bash deploy-preview-example.sh 456 feature/my-feature
```

**What it does:**
1. Creates preview directory structure
2. Clones repository and checks out branch
3. Installs Composer dependencies
4. Creates isolated MySQL database
5. Configures Drupal settings
6. Installs Drupal (or imports configuration)
7. Creates Nginx virtual host
8. Requests SSL certificate
9. Sets proper file permissions
10. Clears caches

**Customize for your project:**
- Edit `GIT_REPO` variable to your repository
- Adjust Drupal installation method (fresh vs config import)
- Modify database seeding if needed

---

### Backup & Recovery

#### `backup-restore.sh`
Complete backup and restore solution.

```bash
# Create backup
sudo bash backup-restore.sh backup
sudo bash backup-restore.sh backup /path/to/external/drive

# List backups
sudo bash backup-restore.sh list

# Restore from backup
sudo bash backup-restore.sh restore /var/backups/preview-server/backup-file.tar.gz

# Schedule automated backups
sudo bash backup-restore.sh schedule
```

**What gets backed up:**
- All MySQL databases (preview_* databases)
- Nginx configurations
- PHP configurations
- MySQL configurations
- SSL certificates (Let's Encrypt)
- Firewall rules
- Crontabs
- Helper scripts
- Stored credentials
- Preview environment files

**Backup location:** `/var/backups/preview-server/`

---

### Maintenance

#### `maintain.sh`
Automated maintenance tasks for keeping the server healthy.

```bash
# Run all maintenance tasks
sudo bash maintain.sh

# Run specific tasks
sudo bash maintain.sh --update     # Update packages
sudo bash maintain.sh --optimize   # Optimize databases and services
sudo bash maintain.sh --clean      # Clean up old data
sudo bash maintain.sh --ssl        # Renew SSL certificates
sudo bash maintain.sh --status     # Show system status
```

**Maintenance tasks:**
- System package updates
- Composer updates
- SSL certificate renewal
- Database optimization (ANALYZE, OPTIMIZE)
- PHP-FPM OPcache clearing
- Nginx reload
- Old preview cleanup (30+ days)
- Log rotation and cleanup (90+ days)
- Temporary file cleanup
- Package cache cleanup
- Old kernel removal

---

### Security

#### `disable-password-auth.sh`
Disables SSH password authentication to enforce key-only access.

```bash
sudo bash disable-password-auth.sh
```

**Security measures:**
- Disables password authentication
- Disables root password login
- Configures strong SSH ciphers
- Sets MaxAuthTries to 3
- Enforces SSH Protocol 2

**Prerequisites:**
- SSH key must be added to `github-actions` user before running
- Test SSH key access in a separate terminal before closing your session

#### `security-audit.sh`
Comprehensive security audit with optional auto-fix.

```bash
# Run security audit
sudo bash security-audit.sh

# Run audit and fix issues
sudo bash security-audit.sh --fix
```

**Security checks:**
- SSH configuration hardening
- Firewall status and rules
- Automatic security updates
- Fail2ban intrusion prevention
- File permissions
- User account security
- Service security (MySQL exposure, unnecessary services)
- Kernel security parameters
- Outdated packages
- Web server security (Nginx headers, SSL/TLS)
- File integrity monitoring
- Logging and auditing

**Output:**
- Security score (0-100) and grade (A-F)
- Critical, warning, and informational findings
- Recommendations for improvements

---

### Logging

#### `manage-logs.sh`
Centralized log management tool.

```bash
# Run all log tasks
sudo bash manage-logs.sh all

# Specific tasks
sudo bash manage-logs.sh rotate    # Rotate logs
sudo bash manage-logs.sh archive   # Archive compressed logs
sudo bash manage-logs.sh clean     # Remove old logs (90+ days)
sudo bash manage-logs.sh analyze   # Analyze log patterns
sudo bash manage-logs.sh tail      # Follow logs in real-time
```

**Features:**
- Log rotation using logrotate
- Archive management
- Automatic cleanup of old logs
- Log analysis (top URLs, IPs, status codes, errors)
- Real-time log monitoring

**Logs managed:**
- Nginx access and error logs
- PHP-FPM logs
- System journal logs
- Preview-specific logs

---

### Performance

#### `tune-performance.sh`
Optimizes server performance based on available resources.

```bash
# Analyze current configuration
sudo bash tune-performance.sh

# Apply recommended optimizations
sudo bash tune-performance.sh --apply
```

**Optimizations:**
- **PHP-FPM:** Calculates optimal pm.max_children based on available memory
- **MySQL:** Sets innodb_buffer_pool_size, connection limits
- **Nginx:** Configures worker_processes based on CPU cores

**Safe to run:** Analyzes first, only applies with `--apply` flag

---

### Monitoring

#### `setup-monitoring.sh`
Sets up monitoring and alerting systems.

```bash
# Install Netdata (full monitoring dashboard)
sudo bash setup-monitoring.sh netdata

# Simple cron-based monitoring
sudo bash setup-monitoring.sh simple

# Set up email alerts
sudo bash setup-monitoring.sh alerts
```

**Monitoring options:**
1. **Netdata**: Full-featured real-time monitoring dashboard
   - Access at: `http://your-server:19999`
   - Real-time metrics, historical data, alarms

2. **Simple Monitoring**: Cron-based system checks every 5 minutes
   - Logs to `/var/log/monitoring/`
   - Checks services, disk, memory, load

3. **Email Alerts**: Sends email on critical conditions
   - High disk usage alerts
   - Service failures

---

## Documentation

Detailed guides are available in the `docs/` folder:

- [Setup Guide](docs/setup-guide.md) - Step-by-step installation instructions
- [Deployment Guide](docs/deployment-guide.md) - How to deploy previews
- [GitHub Actions Integration](docs/github-actions-guide.md) - CI/CD setup
- [Maintenance Guide](docs/maintenance-guide.md) - Routine maintenance tasks
- [Security Best Practices](docs/security-guide.md) - Security recommendations
- [Troubleshooting](docs/troubleshooting.md) - Common issues and solutions
- [Architecture Overview](docs/architecture.md) - System design and components

## Requirements

### Server Requirements

- **OS**: Ubuntu 22.04 LTS or 24.04 LTS
- **RAM**: Minimum 2GB (4GB+ recommended)
- **Disk**: 20GB+ available space
- **Network**: Public IP with ports 80, 443, and 22 accessible

### Software Installed by Setup Script

- Nginx (latest stable)
- PHP 8.3 with extensions (FPM, CLI, MySQL, GD, XML, etc.)
- MySQL 8.0+
- Composer (latest)
- Certbot for Let's Encrypt
- UFW firewall
- Git, curl, wget, unzip

### DNS Requirements

A wildcard DNS record pointing to your server:
```
Type: A
Name: *.preview  (or preview-*)
Value: <your-server-ip>
```

This allows `preview-pr-123.yourdomain.com` to resolve automatically.

## Installation

### 1. Provision Server

Provision an Ubuntu server (Linode, DigitalOcean, AWS, etc.) with:
- Ubuntu 22.04 or 24.04 LTS
- At least 2GB RAM
- Public IP address

### 2. Clone Repository

```bash
git clone https://github.com/yourusername/preview_server.git
cd preview_server
```

### 3. Run Setup

```bash
sudo bash setup_preview_server.sh
```

Follow the prompts to enter:
- MySQL preview user password
- Base domain for previews
- Email for Let's Encrypt notifications

### 4. Add SSH Key

Add your deployment SSH key to the preview user:

```bash
# From your local machine
cat ~/.ssh/id_rsa.pub | ssh root@your-server \
  "cat >> /home/github-actions/.ssh/authorized_keys"
```

### 5. Configure DNS

Add a wildcard DNS record:
- **Type**: A
- **Name**: `*.preview` or `preview-*`
- **Value**: Your server IP

### 6. Set Up GitHub Secrets

Add these secrets to your GitHub repository:

- `PREVIEW_SSH_KEY` - Your private SSH key
- `PREVIEW_HOST` - `github-actions@your-server-ip`
- `PREVIEW_DB_PASSWORD` - MySQL preview user password

### 7. Verify Installation

```bash
sudo bash check.sh
```

## Helper Scripts (Auto-Installed)

These scripts are automatically installed to `/usr/local/bin/`:

### `preview-info`
Shows information about preview environments

```bash
preview-info
```

### `preview-cleanup <preview-id>`
Manually clean up a specific preview environment

```bash
sudo preview-cleanup pr-123
```

Removes:
- Preview directory
- Database
- Nginx configuration
- SSL certificate

### `preview-cleanup-old [days]`
Automatically clean up previews older than N days (default: 7)

```bash
sudo preview-cleanup-old 30
```

### `preview-ssl.sh <preview-id> <domain> <email>`
Request SSL certificate for a preview (used by deployment scripts)

```bash
sudo preview-ssl.sh pr-123 example.com admin@example.com
```

## File Structure

```
preview_server/
├── setup_preview_server.sh      # Initial server setup
├── check.sh                      # Comprehensive diagnostics
├── health-check.sh               # Quick health check
├── deploy-preview-example.sh    # Deployment template
├── backup-restore.sh             # Backup and restore
├── maintain.sh                   # Maintenance tasks
├── disable-password-auth.sh      # SSH hardening
├── security-audit.sh             # Security scanning
├── manage-logs.sh                # Log management
├── tune-performance.sh           # Performance optimization
├── setup-monitoring.sh           # Monitoring setup
├── LICENSE                       # MIT License
├── README.md                     # This file
└── docs/                         # Documentation
    ├── setup-guide.md
    ├── deployment-guide.md
    ├── github-actions-guide.md
    ├── maintenance-guide.md
    ├── security-guide.md
    ├── troubleshooting.md
    └── architecture.md
```

## Common Tasks

### Deploy a New Preview

```bash
sudo -u github-actions bash deploy-preview-example.sh 123
```

### Check Server Health

```bash
sudo bash health-check.sh
```

### Run Weekly Maintenance

```bash
sudo bash maintain.sh
```

### Backup Server

```bash
sudo bash backup-restore.sh backup
```

### Security Audit

```bash
sudo bash security-audit.sh
```

### Clean Up Old Previews

```bash
sudo bash maintain.sh --clean
```

## Monitoring & Alerts

### Health Check Monitoring

Integrate `health-check.sh --json` with your monitoring system:

```bash
# Check every 5 minutes
*/5 * * * * /usr/local/bin/health-check.sh --json > /var/log/health-status.json
```

### Automated Backups

Schedule daily backups:

```bash
sudo bash backup-restore.sh schedule
```

### Log Monitoring

Set up log analysis cron job:

```bash
0 2 * * * /usr/local/bin/manage-logs.sh all >> /var/log/log-management.log
```

## Security Best Practices

1. **Disable Password Authentication**: Run `disable-password-auth.sh` after setting up SSH keys
2. **Regular Security Audits**: Run `security-audit.sh --fix` weekly
3. **Keep System Updated**: Run `maintain.sh --update` regularly
4. **Enable Fail2ban**: Protect against brute force attacks
5. **Use Strong Passwords**: For MySQL and any admin accounts
6. **Regular Backups**: Schedule automated backups with `backup-restore.sh schedule`
7. **Monitor Logs**: Check for suspicious activity with `manage-logs.sh analyze`
8. **SSL Everywhere**: All previews should use HTTPS
9. **Minimal Permissions**: Preview user has only necessary sudo permissions
10. **Firewall**: Keep UFW enabled and configured properly

## Troubleshooting

### Preview Won't Deploy

1. Check DNS resolution: `host preview-pr-123.yourdomain.com`
2. Verify preview user permissions: `sudo -u github-actions ls /var/www/previews`
3. Check Nginx logs: `sudo tail -f /var/log/nginx/error.log`
4. Verify database connection: `mysql -u preview -p`

### SSL Certificate Fails

1. Verify DNS is resolving: `nslookup preview-pr-123.yourdomain.com`
2. Check Certbot logs: `sudo tail -f /var/log/letsencrypt/letsencrypt.log`
3. Ensure port 80 is accessible: `sudo ufw status`
4. Test Certbot: `sudo certbot renew --dry-run`

### High Resource Usage

1. Run health check: `sudo bash health-check.sh`
2. Optimize performance: `sudo bash tune-performance.sh --apply`
3. Clean up old previews: `sudo bash maintain.sh --clean`
4. Check for database issues: `sudo bash maintain.sh --optimize`

### Service Won't Start

1. Check service status: `sudo systemctl status nginx mysql php8.3-fpm`
2. View detailed logs: `sudo journalctl -xe`
3. Run diagnostics: `sudo bash check.sh`
4. Verify configurations: `sudo nginx -t`, `sudo php-fpm8.3 -t`

For more detailed troubleshooting, see [docs/troubleshooting.md](docs/troubleshooting.md)

## Support & Contributing

### Reporting Issues

Please report issues on GitHub with:
- Output of `sudo bash check.sh`
- Relevant log excerpts
- Steps to reproduce

### Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details

## Credits

Created for Drupal preview environment deployments with GitHub Actions integration.

---

**Need help?** Check the [documentation](docs/) or open an issue on GitHub.
