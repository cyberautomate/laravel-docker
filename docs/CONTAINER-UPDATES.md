# Container Update Guide

Your project uses **minor version pinning** (e.g., `8.4`, `1.27`, `17`, `7`), which is a good balance between stability and receiving patch updates.

## Current Versions

| Service | Image | Current Version |
|---------|-------|-----------------|
| PHP-FPM | `php:8.4-fpm-alpine` | 8.4.x |
| Nginx | `nginx:1.27-alpine` | 1.27.x |
| PostgreSQL | `postgres:17-alpine` | 17.x |
| Redis | `redis:7-alpine` | 7.x |
| Composer | (in Dockerfile) | 2.7 |

## Updating Within Pinned Versions (Patch Updates)

To pull the latest patch versions without changing your configuration:

```bash
# Pull latest images for all services
docker compose pull

# Rebuild custom images (php-fpm, queue)
docker compose build --no-cache

# Restart with new images
docker compose down && docker compose up -d
```

## Upgrading to New Minor/Major Versions

### 1. Update `docker-compose.yml`

For services using stock images (nginx, postgres, redis):

```yaml
# Example: Upgrade PostgreSQL from 17 to 18
postgres:
  image: postgres:18-alpine  # was 17-alpine
```

### 2. Update `docker/common/php-fpm/Dockerfile`

For PHP and Composer versions:

```dockerfile
# Line 1: Change PHP version
FROM php:8.5-fpm-alpine AS base  # was 8.4

# Lines 54 & 80: Update Composer version
COPY --from=composer:2.8 /usr/bin/composer /usr/bin/composer
```

### 3. Update `docker/production/nginx/Dockerfile`

For production Nginx:

```dockerfile
FROM nginx:1.28-alpine  # was 1.27
```

## Version Upgrade Checklist

Before upgrading major versions:

### Check Compatibility

- **PHP**: Review [migration guides](https://www.php.net/manual/en/appendices.php)
- **PostgreSQL**: Check [release notes](https://www.postgresql.org/docs/release/)
- **Laravel**: Verify PHP version requirements in `composer.json`

### Test Locally First

```bash
docker compose build --no-cache
docker compose up -d
docker compose exec php-fpm php artisan test
```

### Database Migrations (PostgreSQL Major Upgrades)

```bash
# Export data before upgrade
docker compose exec postgres pg_dumpall -U laravel > backup.sql

# After upgrade, restore if needed
docker compose exec -T postgres psql -U laravel < backup.sql
```

## Checking for Available Updates

```bash
# Check current image digests
docker compose images

# Pull and compare (won't restart containers)
docker compose pull --dry-run 2>/dev/null || docker compose pull
```

## Recommended Update Schedule

| Component | Frequency | Notes |
|-----------|-----------|-------|
| Patch updates | Monthly | Low risk, security fixes |
| Minor versions | Quarterly | Test in dev first |
| Major versions | As needed | Full regression testing |

## Files to Modify When Updating

| Version Change | Files |
|----------------|-------|
| PHP | `docker/common/php-fpm/Dockerfile` (line 1) |
| Composer | `docker/common/php-fpm/Dockerfile` (lines 54, 80) |
| Nginx (dev) | `docker-compose.yml` |
| Nginx (prod) | `docker/production/nginx/Dockerfile` |
| PostgreSQL | `docker-compose.yml` |
| Redis | `docker-compose.yml` |
