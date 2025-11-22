# Preview Server Setup Guide

Complete step-by-step guide for setting up your preview environment server.

## Prerequisites

Before starting, ensure you have:

- [ ] Ubuntu 22.04 or 24.04 LTS server
- [ ] Root access to the server
- [ ] Domain name with access to DNS settings
- [ ] 2GB+ RAM (4GB recommended)
- [ ] 20GB+ disk space

## Step 1: Provision Server

1. Create a server with your preferred provider (Linode, DigitalOcean, AWS, etc.)
2. Choose Ubuntu 22.04 or 24.04 LTS
3. Select at least 2GB RAM
4. Note your server's IP address

## Step 2: Initial Server Access

```bash
# SSH into your server as root
ssh root@YOUR_SERVER_IP
```

## Step 3: Clone Repository

```bash
# Update system first
apt update && apt upgrade -y

# Install git if needed
apt install -y git

# Clone the repository
cd /root
git clone https://github.com/yourusername/preview_server.git
cd preview_server
```

## Step 4: Run Setup Script

```bash
sudo bash setup_preview_server.sh
```

The script will prompt you for:

1. **MySQL Preview User Password**
   - Choose a strong password (at least 16 characters)
   - Save this password - you'll need it for GitHub Secrets
   - It's stored in `/root/.preview_mysql_password`

2. **Base Domain**
   - Example: `example.com`
   - Previews will be accessible at `preview-pr-123.example.com`

3. **Email for Let's Encrypt**
   - Your email for SSL certificate notifications
   - You'll receive expiration warnings here

The setup process will take 10-20 minutes depending on server speed.

## Step 5: Configure DNS

Set up a wildcard DNS record:

**Option 1: Wildcard subdomain (recommended)**
```
Type: A
Name: *.preview
Value: YOUR_SERVER_IP
```
This allows: `preview-pr-123.example.com`

**Option 2: Full wildcard**
```
Type: A
Name: *
Value: YOUR_SERVER_IP
```
This allows any subdomain.

**DNS Verification:**
```bash
# Wait 5-10 minutes for DNS propagation, then test:
host preview-test.yourdomain.com
# Should return your server IP
```

## Step 6: Generate SSH Keys

On your local machine:

```bash
# Generate SSH key pair for deployments
ssh-keygen -t ed25519 -C "preview-deployments" -f ~/.ssh/preview_deploy

# This creates:
# ~/.ssh/preview_deploy (private key - add to GitHub Secrets)
# ~/.ssh/preview_deploy.pub (public key - add to server)
```

## Step 7: Add Public Key to Server

From your local machine:

```bash
# Copy public key to server
cat ~/.ssh/preview_deploy.pub | ssh root@YOUR_SERVER_IP \
  "cat >> /home/github-actions/.ssh/authorized_keys"

# Test SSH access
ssh -i ~/.ssh/preview_deploy github-actions@YOUR_SERVER_IP
# Should log in without password
```

## Step 8: Secure SSH Access

After confirming SSH key login works:

```bash
# On the server
sudo bash disable-password-auth.sh
```

**Important:** Test SSH key access from a new terminal before closing your current session!

## Step 9: Run Security Audit

```bash
# Run security audit
sudo bash security-audit.sh

# Fix any issues automatically
sudo bash security-audit.sh --fix
```

## Step 10: Verify Installation

```bash
# Run comprehensive diagnostics
sudo bash check.sh

# Quick health check
sudo bash health-check.sh
```

## Step 11: Set Up GitHub Secrets

In your GitHub repository, add these secrets (Settings → Secrets and variables → Actions):

1. **PREVIEW_SSH_KEY**
   ```bash
   # Get private key content:
   cat ~/.ssh/preview_deploy
   # Copy entire output including "-----BEGIN" and "-----END"
   ```

2. **PREVIEW_HOST**
   ```
   github-actions@YOUR_SERVER_IP
   ```

3. **PREVIEW_DB_PASSWORD**
   ```bash
   # Get password from server:
   ssh root@YOUR_SERVER_IP "cat /root/.preview_mysql_password"
   ```

4. **PREVIEW_DOMAIN** (optional)
   ```
   example.com
   ```

## Step 12: Optional - Install Monitoring

```bash
# Option 1: Full monitoring dashboard (Netdata)
sudo bash setup-monitoring.sh netdata
# Access at: http://YOUR_SERVER_IP:19999

# Option 2: Simple cron-based monitoring
sudo bash setup-monitoring.sh simple
```

## Step 13: Schedule Automated Maintenance

```bash
# Schedule automated backups
sudo bash backup-restore.sh schedule

# Add maintenance cron job
(crontab -l 2>/dev/null; echo "0 2 * * 0 /root/preview_server/maintain.sh >> /var/log/maintenance.log 2>&1") | crontab -
```

## Verification Checklist

After setup, verify everything is working:

- [ ] All services running: `sudo bash health-check.sh`
- [ ] DNS resolving: `host preview-test.yourdomain.com`
- [ ] SSH key access: `ssh -i ~/.ssh/preview_deploy github-actions@SERVER_IP`
- [ ] Firewall enabled: `sudo ufw status`
- [ ] SSL automation configured: `sudo certbot certificates`
- [ ] No security issues: `sudo bash security-audit.sh`

## Troubleshooting

### DNS Not Resolving

```bash
# Check DNS settings
dig preview-test.yourdomain.com

# Flush local DNS cache
sudo systemd-resolve --flush-caches
```

### Services Not Starting

```bash
# Check service status
sudo systemctl status nginx mysql php8.3-fpm

# View detailed logs
sudo journalctl -xe

# Test configurations
sudo nginx -t
```

### SSL Issues

```bash
# Test certbot
sudo certbot renew --dry-run

# Check Let's Encrypt logs
sudo tail -f /var/log/letsencrypt/letsencrypt.log
```

## Next Steps

- [Deployment Guide](deployment-guide.md) - Deploy your first preview
- [GitHub Actions Integration](github-actions-guide.md) - Set up CI/CD
- [Security Guide](security-guide.md) - Harden your server

## Support

If you encounter issues:
1. Run `sudo bash check.sh` and review the output
2. Check [Troubleshooting Guide](troubleshooting.md)
3. Open an issue on GitHub with diagnostic output
