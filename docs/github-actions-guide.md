# GitHub Actions Integration Guide

Set up automated preview deployments with GitHub Actions.

## Overview

This guide shows you how to automatically deploy preview environments when pull requests are opened, updated, or closed.

## Prerequisites

- Preview server set up and running
- SSH key added to server
- GitHub Secrets configured
- DNS configured

## Workflow File

Create `.github/workflows/preview-deploy.yml`:

```yaml
name: Deploy Preview Environment

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]

env:
  PREVIEW_ID: pr-${{ github.event.pull_request.number }}
  PREVIEW_DOMAIN: preview-pr-${{ github.event.pull_request.number }}.${{ secrets.PREVIEW_DOMAIN }}

jobs:
  deploy:
    runs-on: ubuntu-latest
    if: github.event.action != 'closed'
    steps:
      - name: Deploy Preview
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.PREVIEW_HOST }}
          username: github-actions
          key: ${{ secrets.PREVIEW_SSH_KEY }}
          script: |
            cd /var/www/previews

            # Create or update preview
            if [ ! -d "${{ env.PREVIEW_ID }}" ]; then
              echo "Creating new preview environment..."
            else
              echo "Updating existing preview..."
              rm -rf "${{ env.PREVIEW_ID }}"
            fi

            # Clone repository
            git clone --depth 1 --branch ${{ github.head_ref }} \
              https://github.com/${{ github.repository }}.git \
              ${{ env.PREVIEW_ID }}

            cd ${{ env.PREVIEW_ID }}

            # Install dependencies
            composer install --no-dev --optimize-autoloader

            # Create database if needed
            DB_NAME="preview_pr_${{ github.event.pull_request.number }}"
            mysql -u root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`"

            # Configure Drupal
            cp web/sites/default/default.settings.php web/sites/default/settings.php
            cat >> web/sites/default/settings.php <<'EOF'
            \$databases['default']['default'] = [
              'database' => '${DB_NAME}',
              'username' => 'preview',
              'password' => '${{ secrets.PREVIEW_DB_PASSWORD }}',
              'host' => 'localhost',
              'driver' => 'mysql',
              'prefix' => '',
            ];
            EOF

            # Install Drupal
            ./vendor/bin/drush site:install --yes \
              --db-url="mysql://preview:${{ secrets.PREVIEW_DB_PASSWORD }}@localhost/${DB_NAME}" \
              --site-name="Preview PR-${{ github.event.pull_request.number }}" \
              --account-pass=admin

            # Create Nginx config
            sudo sed "s/PREVIEW_ID/${{ env.PREVIEW_ID }}/g" \
              /etc/nginx/sites-available/preview-template > \
              /etc/nginx/sites-available/${{ env.PREVIEW_ID }}

            sudo ln -sf /etc/nginx/sites-available/${{ env.PREVIEW_ID }} \
              /etc/nginx/sites-enabled/${{ env.PREVIEW_ID }}

            sudo nginx -t && sudo systemctl reload nginx

            # Request SSL
            sudo /usr/local/bin/preview-ssl.sh \
              ${{ env.PREVIEW_ID }} \
              ${{ secrets.PREVIEW_DOMAIN }} \
              admin@${{ secrets.PREVIEW_DOMAIN }} || true

            # Set permissions
            sudo chown -R github-actions:www-data /var/www/previews/${{ env.PREVIEW_ID }}

            echo "Preview deployed at: https://${{ env.PREVIEW_DOMAIN }}"

      - name: Comment Preview URL
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '🚀 Preview environment deployed!\n\n**URL**: https://${{ env.PREVIEW_DOMAIN }}\n**Login**: admin / admin\n\nThe preview will be automatically cleaned up when this PR is closed.'
            })

  cleanup:
    runs-on: ubuntu-latest
    if: github.event.action == 'closed'
    steps:
      - name: Cleanup Preview
        uses: appleboy/ssh-action@v1.0.0
        with:
          host: ${{ secrets.PREVIEW_HOST }}
          username: github-actions
          key: ${{ secrets.PREVIEW_SSH_KEY }}
          script: |
            sudo /usr/local/bin/preview-cleanup ${{ env.PREVIEW_ID }}
            echo "Preview environment cleaned up"

      - name: Comment Cleanup
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '🧹 Preview environment has been cleaned up.'
            })
```

## Advanced Configuration

### Database Seeding

Add database seeding to your workflow:

```yaml
- name: Seed Database
  script: |
    cd /var/www/previews/${{ env.PREVIEW_ID }}

    # Import production database dump
    curl https://example.com/db-snapshot.sql.gz | \
      gunzip | mysql -u preview -p${{ secrets.PREVIEW_DB_PASSWORD }} ${DB_NAME}

    # Or import config
    ./vendor/bin/drush config:import --yes
    ./vendor/bin/drush updatedb --yes
```

### File Sync

Sync files from production:

```yaml
- name: Sync Files
  script: |
    cd /var/www/previews/${{ env.PREVIEW_ID }}
    rsync -avz production@server:/path/to/files/ web/sites/default/files/
```

### Performance Testing

Add Lighthouse or performance testing:

```yaml
- name: Run Lighthouse
  uses: treosh/lighthouse-ci-action@v9
  with:
    urls: |
      https://${{ env.PREVIEW_DOMAIN }}
    uploadArtifacts: true
```

### Security Scanning

Add security scanning:

```yaml
- name: Security Scan
  script: |
    cd /var/www/previews/${{ env.PREVIEW_ID }}
    ./vendor/bin/drush pm:security
```

## Testing Locally

Test deployment script locally:

```bash
# Set environment variables
export PREVIEW_ID="pr-test"
export BRANCH="main"

# Run deployment
sudo -u github-actions bash deploy-preview-example.sh test main
```

## Monitoring Deployments

### View Deployment Logs

```bash
# On the server
tail -f /var/log/nginx/preview-pr-*-access.log
```

### Check Deployment Status

```bash
# List all previews
preview-info

# Check specific preview
curl -I https://preview-pr-123.example.com
```

## Troubleshooting

### Deployment Fails

Check GitHub Actions logs and server logs:

```bash
# Server logs
sudo tail -f /var/log/nginx/error.log
sudo journalctl -u php8.3-fpm -f
```

### Permission Errors

```bash
# Fix permissions
sudo chown -R github-actions:www-data /var/www/previews/pr-*
```

### SSL Certificate Fails

```bash
# Check DNS first
host preview-pr-123.example.com

# Manual SSL request
sudo /usr/local/bin/preview-ssl.sh pr-123 example.com admin@example.com
```

## Best Practices

1. **Limit Preview Duration**: Set up automatic cleanup of old previews
   ```bash
   # Cron job to clean previews older than 7 days
   0 2 * * * /usr/local/bin/preview-cleanup-old 7
   ```

2. **Resource Limits**: Monitor resource usage
   ```bash
   # Check resource usage
   sudo bash health-check.sh
   ```

3. **Security**: Use environment variables for secrets, never commit passwords

4. **Testing**: Test deployment scripts in a staging environment first

5. **Notifications**: Set up Slack/Discord notifications for deployments

## Example: Slack Notifications

Add to your workflow:

```yaml
- name: Notify Slack
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    text: 'Preview deployed: https://${{ env.PREVIEW_DOMAIN }}'
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
  if: always()
```

## Next Steps

- [Deployment Guide](deployment-guide.md)
- [Maintenance Guide](maintenance-guide.md)
- [Troubleshooting](troubleshooting.md)
