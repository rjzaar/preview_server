# Architecture Overview

System design and component overview for the preview server infrastructure.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└────────────────┬────────────────────────────────────────────┘
                 │
            Port 80/443
                 │
        ┌────────▼────────┐
        │   UFW Firewall  │
        │   (iptables)    │
        └────────┬────────┘
                 │
        ┌────────▼────────┐
        │      Nginx      │
        │  Reverse Proxy  │
        │   + SSL/TLS     │
        └─────────────────┘
                 │
    ┌────────────┼────────────┐
    │            │            │
┌───▼───┐   ┌───▼───┐   ┌───▼───┐
│ PR-1  │   │ PR-2  │   │ PR-N  │
│       │   │       │   │       │
│ PHP   │   │ PHP   │   │ PHP   │
│ FPM   │   │ FPM   │   │ FPM   │
└───┬───┘   └───┬───┘   └───┬───┘
    │           │           │
    └───────────┼───────────┘
                │
        ┌───────▼───────┐
        │     MariaDB     │
        │   (preview_*  │
        │   databases)  │
        └───────────────┘
```

## Components

### Web Server (Nginx)

**Role:** Reverse proxy and static file server

**Configuration:**
- Location: `/etc/nginx/`
- Virtual hosts: `/etc/nginx/sites-available/`
- Active sites: `/etc/nginx/sites-enabled/`

**Features:**
- Dynamic virtual host creation per PR
- SSL/TLS termination
- Static file caching
- Gzip compression
- Security headers

**Preview URL Pattern:**
```
https://preview-pr-{NUMBER}.{DOMAIN}
```

### Application Server (PHP-FPM)

**Role:** PHP execution environment

**Configuration:**
- Version: PHP 8.3
- Config: `/etc/php/8.3/fpm/`
- Pool config: `/etc/php/8.3/fpm/pool.d/www.conf`

**Optimizations:**
- OPcache enabled
- Process manager: dynamic
- Memory limit: 256MB
- Max execution time: 300s

### Database (MariaDB)

**Role:** Data persistence

**Configuration:**
- Location: `/etc/mariadb/`
- Data directory: `/var/lib/mariadb/`

**Database naming:**
```
preview_pr_{NUMBER}
```

**Security:**
- Preview user with limited permissions
- Only localhost access
- Per-database isolation

### File System Structure

```
/var/www/previews/
├── pr-1/
│   ├── web/                 # Drupal docroot
│   │   ├── index.php
│   │   ├── sites/
│   │   │   └── default/
│   │   │       ├── files/  # User-uploaded files
│   │   │       └── settings.php
│   │   └── ...
│   ├── vendor/              # Composer dependencies
│   └── composer.json
├── pr-2/
│   └── ...
└── pr-N/
    └── ...
```

### SSL/TLS (Let's Encrypt)

**Role:** HTTPS encryption

**Configuration:**
- Certbot for certificate management
- Auto-renewal via cron
- Per-preview certificates

**Certificate locations:**
```
/etc/letsencrypt/live/preview-pr-{NUMBER}.{DOMAIN}/
```

### Firewall (UFW)

**Role:** Network security

**Rules:**
- Allow SSH (22)
- Allow HTTP (80)
- Allow HTTPS (443)
- Deny all other incoming
- Allow all outgoing

## Data Flow

### Deployment Flow

```
1. GitHub Actions triggers
2. SSH connection to server
3. Clone repository to /var/www/previews/pr-{N}
4. Composer install
5. Create MariaDB database
6. Configure Drupal
7. Install Drupal
8. Create Nginx virtual host
9. Reload Nginx
10. Request SSL certificate
11. Set file permissions
```

### Request Flow

```
1. DNS: preview-pr-123.example.com → Server IP
2. Firewall: Allow port 443
3. Nginx:
   - SSL termination
   - Match virtual host
   - Route to preview directory
4. PHP-FPM: Execute PHP
5. Drupal: Process request
6. MariaDB: Query database
7. Response: HTML/JSON/etc.
```

## Security Layers

### Layer 1: Network (UFW)
- Port-level access control
- Rate limiting (future)

### Layer 2: SSH
- Key-only authentication
- No password login
- No root password login

### Layer 3: Application
- Preview user with limited sudo
- Separate MariaDB user per environment
- File permission isolation

### Layer 4: Web Server
- Security headers
- Request size limits
- SSL/TLS only (HTTPS)

### Layer 5: Application
- Drupal security best practices
- Trusted host patterns
- Database credentials in settings.php

## Resource Management

### CPU
- PHP-FPM workers: Dynamic based on load
- Nginx workers: One per CPU core

### Memory
- PHP memory limit: 256MB per request
- MariaDB buffer pool: 50% of RAM
- File cache: Automatic

### Disk
- Preview environments: ~500MB each
- Databases: ~50-500MB each
- Logs: Rotated after 90 days

### Network
- Bandwidth: Depends on provider
- Concurrent connections: 768 (Nginx)

## Scaling Considerations

### Vertical Scaling
Increase server resources:
- More RAM → More PHP workers
- More CPU → Better performance
- More disk → More previews

### Horizontal Scaling
Multiple preview servers:
- Load balancer in front
- Shared MariaDB (RDS)
- Shared file storage (NFS/S3)
- Redis for cache

### Optimization
- Enable Redis/Memcached
- Add Varnish cache
- Use CDN for static files
- Implement queue system

## Backup Strategy

### What's Backed Up
- All preview environments
- All databases
- All configurations
- SSL certificates
- Credentials

### Backup Frequency
- Manual: On demand
- Automated: Daily/Weekly/Monthly

### Backup Location
- Local: `/var/backups/preview-server/`
- External: Optional (S3, external drive)

## Monitoring Points

### System Level
- CPU usage
- Memory usage
- Disk space
- Load average

### Application Level
- Service status (Nginx, MariaDB, PHP-FPM)
- Preview count
- Database count
- SSL certificate expiration

### Security
- Failed login attempts
- Open ports
- Security updates
- File integrity

## Integration Points

### GitHub Actions
- SSH for deployment
- Secrets for credentials
- Webhooks for events

### DNS Provider
- Wildcard A record
- API for dynamic updates (optional)

### Let's Encrypt
- HTTP-01 challenge
- Auto-renewal hooks

### Monitoring (Optional)
- Netdata for metrics
- Cron for health checks
- Email for alerts

## Limitations

### Current Implementation
- Single server (no HA)
- No automatic scaling
- Manual DNS configuration
- Limited to one Drupal site

### Resource Constraints
- Max previews: Depends on server resources
- Max concurrent users: Depends on server resources
- Database size: No hard limit (disk-dependent)

## Future Enhancements

### Planned
- Multi-site support
- Automated DNS management
- Container-based isolation
- Database snapshot/restore
- Performance profiling

### Possible
- Kubernetes deployment
- Multi-region support
- Advanced monitoring
- Cost tracking per preview
- Preview environment templates
