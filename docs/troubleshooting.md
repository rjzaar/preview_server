# Troubleshooting Guide

Common issues and their solutions.

## Quick Diagnostics

Always start with:
```bash
sudo bash check.sh          # Comprehensive check
sudo bash health-check.sh   # Quick health check
```

## Common Issues

### 1. Preview Won't Load

**Symptoms:** Preview URL returns 404 or connection refused

**Solutions:**
```bash
# Check DNS
host preview-pr-123.yourdomain.com

# Check Nginx
sudo nginx -t
sudo systemctl status nginx
sudo tail -f /var/log/nginx/error.log

# Check if site is enabled
ls -la /etc/nginx/sites-enabled/pr-*

# Reload Nginx
sudo systemctl reload nginx
```

### 2. Database Connection Errors

**Symptoms:** Drupal shows database errors

**Solutions:**
```bash
# Test database connection
mysql -u preview -p
# Enter password from /root/.preview_mariadb_password

# Check database exists
mysql -u root -e "SHOW DATABASES LIKE 'preview_%';"

# Recreate database
DB_NAME="preview_pr_123"
mysql -u root -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;"
mysql -u root -e "CREATE DATABASE \`${DB_NAME}\`;"
```

### 3. SSL Certificate Fails

**Symptoms:** HTTPS doesn't work, certbot errors

**Solutions:**
```bash
# Verify DNS resolves to your server
dig preview-pr-123.yourdomain.com

# Check port 80 is open
sudo ufw status | grep 80
sudo netstat -tlnp | grep :80

# Test certbot
sudo certbot renew --dry-run

# Manual certificate request
sudo certbot --nginx -d preview-pr-123.yourdomain.com

# Check Let's Encrypt logs
sudo tail -100 /var/log/letsencrypt/letsencrypt.log
```

### 4. Permission Errors

**Symptoms:** 403 errors, file write failures

**Solutions:**
```bash
# Fix preview directory permissions
sudo chown -R github-actions:www-data /var/www/previews/pr-*
sudo chmod -R 755 /var/www/previews/pr-*

# Fix files directory
sudo chmod 775 /var/www/previews/pr-*/web/sites/default/files
find /var/www/previews/pr-*/web/sites/default/files -type d -exec chmod 775 {} \;
find /var/www/previews/pr-*/web/sites/default/files -type f -exec chmod 664 {} \;
```

### 5. Out of Disk Space

**Symptoms:** Deployments fail, services crash

**Solutions:**
```bash
# Check disk usage
df -h
du -sh /var/www/previews/* | sort -hr | head

# Clean up old previews
sudo bash maintain.sh --clean

# Manual cleanup
sudo preview-cleanup-old 7

# Clean logs
sudo bash manage-logs.sh clean

# Clear package cache
sudo apt clean
sudo apt autoclean
```

### 6. High Memory Usage

**Symptoms:** Server slow, OOM errors

**Solutions:**
```bash
# Check memory
free -h

# Find memory hogs
ps aux --sort=-%mem | head

# Optimize PHP-FPM
sudo bash tune-performance.sh --apply

# Restart services
sudo systemctl restart php8.3-fpm
sudo systemctl restart mariadb
```

### 7. Composer Install Fails

**Symptoms:** Deployment fails during composer install

**Solutions:**
```bash
# Clear composer cache
composer clear-cache

# Increase memory limit
php -d memory_limit=-1 /usr/local/bin/composer install

# Check composer.lock is committed
ls -la composer.lock

# Manual install
cd /var/www/previews/pr-123
sudo -u github-actions composer install --no-dev
```

### 8. Nginx Configuration Errors

**Symptoms:** nginx -t fails

**Solutions:**
```bash
# Test configuration
sudo nginx -t

# Check syntax of specific file
sudo nginx -t -c /etc/nginx/sites-available/pr-123

# View error details
sudo nginx -t 2>&1

# Restore from backup
sudo cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
```

### 9. SSH Connection Issues

**Symptoms:** Can't connect with SSH key

**Solutions:**
```bash
# Verify key is added
cat /home/github-actions/.ssh/authorized_keys

# Check permissions
ls -la /home/github-actions/.ssh/
# Should be: drwx------ (700) for .ssh
# Should be: -rw------- (600) for authorized_keys

# Fix permissions
sudo chmod 700 /home/github-actions/.ssh
sudo chmod 600 /home/github-actions/.ssh/authorized_keys
sudo chown -R github-actions:github-actions /home/github-actions/.ssh

# Test from client
ssh -v -i ~/.ssh/preview_deploy github-actions@SERVER_IP
```

### 10. Services Won't Start

**Symptoms:** nginx/mariadb/php-fpm won't start

**Solutions:**
```bash
# Check service status
sudo systemctl status nginx
sudo systemctl status mariadb
sudo systemctl status php8.3-fpm

# View detailed errors
sudo journalctl -xe -u nginx
sudo journalctl -xe -u mariadb
sudo journalctl -xe -u php8.3-fpm

# Check ports aren't in use
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :3306

# Restart services
sudo systemctl restart nginx mariadb php8.3-fpm
```

## Advanced Troubleshooting

### Enable Debug Mode

```bash
# Nginx debug logging
sudo sed -i 's/error_log.*/error_log \/var\/log\/nginx\/error.log debug;/' /etc/nginx/nginx.conf
sudo systemctl reload nginx

# PHP error logging
sudo sed -i 's/display_errors = Off/display_errors = On/' /etc/php/8.3/fpm/php.ini
sudo systemctl restart php8.3-fpm
```

### Monitor in Real-Time

```bash
# Watch all logs
sudo tail -f /var/log/nginx/*.log /var/log/php8.3-fpm.log

# Watch specific preview
sudo tail -f /var/log/nginx/preview-pr-123-*.log

# Watch system logs
sudo journalctl -f
```

### Network Issues

```bash
# Test connectivity
curl -I http://localhost
curl -I http://127.0.0.1

# Check firewall
sudo ufw status verbose

# Check if port is listening
sudo ss -tlnp | grep :80

# Test DNS resolution
dig @8.8.8.8 preview-pr-123.yourdomain.com
```

## Recovery Procedures

### Restore from Backup

```bash
# List backups
sudo bash backup-restore.sh list

# Restore
sudo bash backup-restore.sh restore /var/backups/preview-server/backup-file.tar.gz
```

### Reset Preview Environment

```bash
# Clean up specific preview
sudo preview-cleanup pr-123

# Redeploy
sudo -u github-actions bash deploy-preview-example.sh 123
```

### Full Server Reset

```bash
# Nuclear option - reinstall everything
cd /root/preview_server
sudo bash setup_preview_server.sh
```

## Getting Help

If none of these solutions work:

1. Run full diagnostics:
   ```bash
   sudo bash check.sh > diagnostic-report.txt
   ```

2. Gather logs:
   ```bash
   sudo tail -100 /var/log/nginx/error.log > nginx-errors.txt
   sudo journalctl -xe > system-log.txt
   ```

3. Open GitHub issue with:
   - Diagnostic report
   - Error logs
   - Steps to reproduce
   - What you've already tried

## Prevention

Prevent issues before they happen:

```bash
# Regular maintenance
sudo bash maintain.sh

# Weekly security audit
sudo bash security-audit.sh --fix

# Monitor disk space
df -h

# Check for issues
sudo bash health-check.sh
```
