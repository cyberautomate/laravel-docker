# Deployment Guide

This document covers the CI/CD pipeline configuration and production deployment procedures.

## Table of Contents

- [CI/CD Pipeline Overview](#cicd-pipeline-overview)
- [GitHub Actions Workflow](#github-actions-workflow)
- [Production Environment Setup](#production-environment-setup)
- [Secrets Management](#secrets-management)
- [Deployment Process](#deployment-process)
- [Rollback Procedures](#rollback-procedures)
- [Monitoring and Health Checks](#monitoring-and-health-checks)

---

## CI/CD Pipeline Overview

The application uses GitHub Actions for continuous integration and deployment.

### Pipeline Stages

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           GITHUB ACTIONS                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────────┐ │
│  │    TEST     │───▶│    BUILD    │───▶│         DEPLOY              │ │
│  │             │    │             │    │                             │ │
│  │ - PHPUnit   │    │ - PHP-FPM   │    │ - Pull images               │ │
│  │ - Frontend  │    │ - Nginx     │    │ - Run migrations            │ │
│  │ - Coverage  │    │ - Push GHCR │    │ - Clear caches              │ │
│  └─────────────┘    └─────────────┘    │ - Health check              │ │
│                                         └─────────────────────────────┘ │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Triggers

- **Push to `main` branch**: Full pipeline (test → build → deploy)
- **Manual dispatch**: Optional skip_tests flag
- **Excluded files**: `*.md`, `.gitignore`, `LICENSE`

---

## GitHub Actions Workflow

**File**: `.github/workflows/deploy.yml`

### Test Job

```yaml
test:
  runs-on: ubuntu-latest
  services:
    postgres:
      image: postgres:17-alpine
      env:
        POSTGRES_DB: laravel_test
        POSTGRES_USER: laravel
        POSTGRES_PASSWORD: secret
      ports:
        - 5432:5432
      options: >-
        --health-cmd pg_isready
        --health-interval 10s
        --health-timeout 5s
        --health-retries 5
    redis:
      image: redis:7-alpine
      ports:
        - 6379:6379
      options: >-
        --health-cmd "redis-cli ping"
        --health-interval 10s
        --health-timeout 5s
        --health-retries 5

  steps:
    - uses: actions/checkout@v4

    - name: Setup PHP
      uses: shivammathur/setup-php@v2
      with:
        php-version: '8.3'
        extensions: pdo, pdo_pgsql, redis, gd, zip, intl, mbstring, bcmath

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '22'
        cache: 'npm'
        cache-dependency-path: src/package-lock.json

    - name: Install Composer dependencies
      working-directory: src
      run: composer install --prefer-dist --no-progress

    - name: Install NPM dependencies
      working-directory: src
      run: npm ci

    - name: Build frontend assets
      working-directory: src
      run: npm run build

    - name: Prepare environment
      working-directory: src
      run: |
        cp .env.example .env
        php artisan key:generate

    - name: Run database migrations
      working-directory: src
      run: php artisan migrate --force
      env:
        DB_CONNECTION: pgsql
        DB_HOST: 127.0.0.1
        DB_PORT: 5432
        DB_DATABASE: laravel_test
        DB_USERNAME: laravel
        DB_PASSWORD: secret

    - name: Run tests
      working-directory: src
      run: php artisan test --coverage-clover=coverage.xml
      env:
        DB_CONNECTION: pgsql
        DB_HOST: 127.0.0.1
        DB_PORT: 5432
        DB_DATABASE: laravel_test
        DB_USERNAME: laravel
        DB_PASSWORD: secret
        REDIS_HOST: 127.0.0.1
        REDIS_PORT: 6379

    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v4
      with:
        files: src/coverage.xml
        fail_ci_if_error: false
```

### Build Job

```yaml
build:
  needs: test
  runs-on: ubuntu-latest
  permissions:
    contents: read
    packages: write

  steps:
    - uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Login to GitHub Container Registry
      uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ghcr.io/${{ github.repository }}

    - name: Build and push PHP-FPM image
      uses: docker/build-push-action@v5
      with:
        context: .
        file: docker/common/php-fpm/Dockerfile
        target: production
        push: true
        tags: |
          ghcr.io/${{ github.repository }}/php-fpm:${{ github.sha }}
          ghcr.io/${{ github.repository }}/php-fpm:latest
        cache-from: type=gha
        cache-to: type=gha,mode=max

    - name: Build and push Nginx image
      uses: docker/build-push-action@v5
      with:
        context: .
        file: docker/production/nginx/Dockerfile
        push: true
        tags: |
          ghcr.io/${{ github.repository }}/nginx:${{ github.sha }}
          ghcr.io/${{ github.repository }}/nginx:latest
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

### Deploy Job

```yaml
deploy:
  needs: build
  runs-on: ubuntu-latest
  environment: production

  steps:
    - name: Deploy to production
      uses: appleboy/ssh-action@v1.0.0
      with:
        host: ${{ secrets.SERVER_HOST }}
        username: ${{ secrets.SERVER_USER }}
        key: ${{ secrets.SSH_PRIVATE_KEY }}
        script: |
          cd /var/www/laravel

          # Pull latest images
          docker compose -f docker-compose.prod.yml pull

          # Run migrations
          docker compose -f docker-compose.prod.yml run --rm php-fpm \
            php artisan migrate --force

          # Deploy with zero-downtime
          docker compose -f docker-compose.prod.yml up -d --remove-orphans

          # Clear and rebuild caches
          docker compose -f docker-compose.prod.yml exec -T php-fpm \
            php artisan config:cache
          docker compose -f docker-compose.prod.yml exec -T php-fpm \
            php artisan route:cache
          docker compose -f docker-compose.prod.yml exec -T php-fpm \
            php artisan view:cache

          # Restart queue workers to pick up new code
          docker compose -f docker-compose.prod.yml exec -T php-fpm \
            php artisan queue:restart

          # Health check
          sleep 10
          curl -f http://localhost/health || exit 1

    - name: Notify Slack (Success)
      if: success()
      uses: 8398a7/action-slack@v3
      with:
        status: success
        text: 'Deployment to production succeeded!'
      env:
        SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}

    - name: Notify Slack (Failure)
      if: failure()
      uses: 8398a7/action-slack@v3
      with:
        status: failure
        text: 'Deployment to production failed!'
      env:
        SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## Production Environment Setup

### Server Requirements

- **OS**: Ubuntu 22.04 LTS or later
- **Docker**: 24.0+
- **Docker Compose**: 2.20+
- **Memory**: 4GB minimum
- **Storage**: 20GB minimum

### Initial Server Setup

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create application directory
sudo mkdir -p /var/www/laravel
sudo chown $USER:$USER /var/www/laravel

# Clone repository
cd /var/www/laravel
git clone https://github.com/your-org/laravel.git .
```

### Directory Structure on Server

```
/var/www/laravel/
├── docker-compose.prod.yml
├── secrets/
│   ├── app_key.txt
│   ├── db_username.txt
│   ├── db_password.txt
│   ├── redis_password.txt
│   ├── azure_storage_account.txt
│   └── azure_storage_key.txt
├── backups/
└── .env
```

---

## Secrets Management

### Required Secrets

#### GitHub Actions Secrets

| Secret | Description |
|--------|-------------|
| `SSH_PRIVATE_KEY` | SSH key for server access |
| `SSH_KNOWN_HOSTS` | Server SSH fingerprint |
| `SERVER_HOST` | Production server IP/hostname |
| `SERVER_USER` | SSH username |
| `SLACK_WEBHOOK_URL` | Slack notification webhook |

#### Production Server Secrets

Create the `secrets/` directory and populate secret files:

```bash
# Create secrets directory
mkdir -p /var/www/laravel/secrets
chmod 700 /var/www/laravel/secrets

# Generate secure values
# App key (base64 encoded)
echo "base64:$(openssl rand -base64 32)" > secrets/app_key.txt

# Database credentials
echo "laravel" > secrets/db_username.txt
openssl rand -base64 24 > secrets/db_password.txt

# Redis password
openssl rand -base64 24 > secrets/redis_password.txt

# Azure Storage (if using backup)
echo "your_storage_account" > secrets/azure_storage_account.txt
echo "your_storage_key" > secrets/azure_storage_key.txt

# Secure permissions
chmod 600 /var/www/laravel/secrets/*
```

### Secrets in Docker Compose

Secrets are mounted as files in `/run/secrets/`:

```yaml
secrets:
  app_key:
    file: ./secrets/app_key.txt
  db_username:
    file: ./secrets/db_username.txt
  db_password:
    file: ./secrets/db_password.txt

services:
  php-fpm:
    secrets:
      - app_key
      - db_username
      - db_password
```

### Reading Secrets in Entrypoint

```bash
if [ -f /run/secrets/app_key ]; then
    export APP_KEY=$(cat /run/secrets/app_key)
fi
```

---

## Deployment Process

### Manual Deployment

```bash
# SSH to server
ssh user@server

# Navigate to project
cd /var/www/laravel

# Pull latest code
git pull origin main

# Pull latest images
docker compose -f docker-compose.prod.yml pull

# Run migrations
docker compose -f docker-compose.prod.yml run --rm php-fpm \
  php artisan migrate --force

# Deploy containers
docker compose -f docker-compose.prod.yml up -d --remove-orphans

# Clear caches
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan config:cache
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan route:cache
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan view:cache
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan event:cache

# Restart queue workers
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan queue:restart

# Verify deployment
curl -f http://localhost/health
```

### Zero-Downtime Deployment

The deployment achieves zero-downtime through:

1. **Pre-pulled images**: Images are pulled before stopping containers
2. **Health checks**: New containers must be healthy before traffic is routed
3. **Rolling updates**: Docker Compose handles graceful container replacement
4. **Queue restart**: Workers finish current jobs before restarting

### Deployment Checklist

- [ ] All tests pass
- [ ] Docker images built successfully
- [ ] Database migrations reviewed
- [ ] Secrets updated (if needed)
- [ ] Backup completed
- [ ] Team notified

---

## Rollback Procedures

### Quick Rollback (Previous Image)

```bash
# Roll back to previous image tag
export IMAGE_TAG=previous_sha

# Deploy previous version
docker compose -f docker-compose.prod.yml up -d

# Verify rollback
curl -f http://localhost/health
```

### Database Rollback

```bash
# Roll back last migration
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan migrate:rollback --step=1

# Roll back multiple migrations
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan migrate:rollback --step=3
```

### Full Rollback (Including Database)

```bash
# 1. Stop current deployment
docker compose -f docker-compose.prod.yml down

# 2. Restore database from backup
docker compose -f docker-compose.prod.yml run --rm backup \
  pg_restore -h postgres -U $DB_USERNAME -d $DB_DATABASE /backup/backup_YYYYMMDD.sql

# 3. Deploy previous version
export IMAGE_TAG=previous_sha
docker compose -f docker-compose.prod.yml up -d

# 4. Verify
curl -f http://localhost/health
```

---

## Monitoring and Health Checks

### Health Check Endpoints

| Endpoint | Service | Response |
|----------|---------|----------|
| `/health` | Nginx | `healthy\n` (200 OK) |

### Docker Health Status

```bash
# Check all container health
docker compose -f docker-compose.prod.yml ps

# Detailed health check output
docker inspect --format='{{json .State.Health}}' laravel-php
docker inspect --format='{{json .State.Health}}' laravel-nginx
docker inspect --format='{{json .State.Health}}' laravel-postgres
docker inspect --format='{{json .State.Health}}' laravel-redis
```

### Log Monitoring

```bash
# All logs
docker compose -f docker-compose.prod.yml logs -f

# Specific service logs
docker compose -f docker-compose.prod.yml logs -f nginx
docker compose -f docker-compose.prod.yml logs -f php-fpm
docker compose -f docker-compose.prod.yml logs -f postgres
docker compose -f docker-compose.prod.yml logs -f queue

# Laravel application logs
docker compose -f docker-compose.prod.yml exec php-fpm \
  tail -f storage/logs/laravel.log
```

### Resource Monitoring

```bash
# Container resource usage
docker stats

# Specific containers
docker stats laravel-php laravel-nginx laravel-postgres laravel-redis
```

### Database Monitoring

```bash
# Check connections
docker compose -f docker-compose.prod.yml exec postgres \
  psql -U laravel -c "SELECT count(*) FROM pg_stat_activity;"

# Check table sizes
docker compose -f docker-compose.prod.yml exec postgres \
  psql -U laravel -c "SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC;"
```

### Redis Monitoring

```bash
# Redis info
docker compose -f docker-compose.prod.yml exec redis redis-cli info

# Memory usage
docker compose -f docker-compose.prod.yml exec redis redis-cli info memory

# Connected clients
docker compose -f docker-compose.prod.yml exec redis redis-cli client list
```

### Queue Monitoring

```bash
# Queue status
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan queue:monitor redis:default

# Failed jobs
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan queue:failed

# Retry failed jobs
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan queue:retry all
```

---

## Troubleshooting

### Common Issues

#### Container Won't Start

```bash
# Check logs
docker compose -f docker-compose.prod.yml logs php-fpm

# Check container status
docker compose -f docker-compose.prod.yml ps

# Inspect container
docker inspect laravel-php
```

#### Database Connection Failed

```bash
# Check PostgreSQL logs
docker compose -f docker-compose.prod.yml logs postgres

# Test connection manually
docker compose -f docker-compose.prod.yml exec php-fpm \
  php -r "new PDO('pgsql:host=postgres;port=5432;dbname=laravel', 'laravel', file_get_contents('/run/secrets/db_password'));"
```

#### Redis Connection Failed

```bash
# Check Redis logs
docker compose -f docker-compose.prod.yml logs redis

# Test connection
docker compose -f docker-compose.prod.yml exec redis redis-cli ping
```

#### Permission Issues

```bash
# Fix storage permissions
docker compose -f docker-compose.prod.yml exec php-fpm \
  chmod -R 775 storage bootstrap/cache
docker compose -f docker-compose.prod.yml exec php-fpm \
  chown -R laravel:laravel storage bootstrap/cache
```

---

## Related Documentation

- [Architecture Overview](./ARCHITECTURE.md)
- [Docker Configuration](./DOCKER.md)
- [Services Configuration](./SERVICES.md)
- [Development Guide](./DEVELOPMENT.md)
