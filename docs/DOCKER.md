# Docker Configuration

This document details the Docker configuration for both development and production environments.

## Table of Contents

- [Overview](#overview)
- [Docker Compose Files](#docker-compose-files)
- [Dockerfile Structure](#dockerfile-structure)
- [Environment Variables](#environment-variables)
- [Volumes and Persistence](#volumes-and-persistence)
- [Networks](#networks)
- [Health Checks](#health-checks)
- [Production Security](#production-security)

---

## Overview

The application uses Docker Compose to orchestrate multiple containers. Two compose files are provided:

| File | Purpose | Use Case |
|------|---------|----------|
| `docker-compose.yml` | Development environment | Local development |
| `docker-compose.prod.yml` | Production environment | Production deployment |

---

## Docker Compose Files

### Development (docker-compose.yml)

```yaml
services:
  nginx:
    image: nginx:1.27-alpine
    container_name: laravel-nginx
    ports:
      - "${NGINX_PORT:-80}:80"
    volumes:
      - ./src:/var/www:ro
      - ./docker/development/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - frontend
      - backend
    depends_on:
      php-fpm:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  php-fpm:
    build:
      context: .
      dockerfile: docker/common/php-fpm/Dockerfile
      target: development
      args:
        UID: ${UID:-1000}
        GID: ${GID:-1000}
    container_name: laravel-php
    volumes:
      - ./src:/var/www
      - ./docker/development/php/php.ini:/usr/local/etc/php/conf.d/custom.ini:ro
    networks:
      - backend
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - APP_ENV=${APP_ENV:-local}
      - APP_DEBUG=${APP_DEBUG:-true}
      - DB_CONNECTION=pgsql
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=${DB_DATABASE:-laravel}
      - DB_USERNAME=${DB_USERNAME:-laravel}
      - DB_PASSWORD=${DB_PASSWORD:-secret}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - CACHE_STORE=redis
      - SESSION_DRIVER=redis
      - QUEUE_CONNECTION=redis
      - XDEBUG_MODE=${XDEBUG_MODE:-develop,debug}
      - XDEBUG_CONFIG=client_host=${XDEBUG_HOST:-host.docker.internal}
    healthcheck:
      test: ["CMD-SHELL", "php-fpm-healthcheck || php -r 'exit(0);'"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  postgres:
    image: postgres:17-alpine
    container_name: laravel-postgres
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    environment:
      POSTGRES_DB: ${DB_DATABASE:-laravel}
      POSTGRES_USER: ${DB_USERNAME:-laravel}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-secret}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USERNAME:-laravel} -d ${DB_DATABASE:-laravel}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: laravel-redis
    ports:
      - "${REDIS_PORT:-6379}:6379"
    command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  queue:
    build:
      context: .
      dockerfile: docker/common/php-fpm/Dockerfile
      target: development
    container_name: laravel-queue
    volumes:
      - ./src:/var/www
    command: php artisan queue:work redis --sleep=3 --tries=3 --max-time=3600 --verbose
    networks:
      - backend
    depends_on:
      php-fpm:
        condition: service_healthy

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge

volumes:
  postgres_data:
  redis_data:
```

### Production (docker-compose.prod.yml)

Key differences from development:

```yaml
services:
  nginx:
    image: ghcr.io/${GITHUB_REPOSITORY:-your-org/laravel}/nginx:${IMAGE_TAG:-latest}
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - CHOWN
      - SETUID
      - SETGID
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

  php-fpm:
    image: ghcr.io/${GITHUB_REPOSITORY:-your-org/laravel}/php-fpm:${IMAGE_TAG:-latest}
    entrypoint: ["/usr/local/bin/entrypoint.sh"]
    command: ["php-fpm"]
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 512M
    read_only: true
    tmpfs:
      - /tmp:mode=1777,size=64M
      - /var/run:mode=1777,size=16M
    secrets:
      - app_key
      - db_username
      - db_password
      - redis_password

  postgres:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
    secrets:
      - db_username
      - db_password

  redis:
    command: >
      redis-server
      --appendonly yes
      --requirepass_file /run/secrets/redis_password
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru
    secrets:
      - redis_password

  backup:
    image: jkaninda/pg-bkup:latest
    environment:
      - DB_HOST=postgres
      - DB_NAME=${DB_DATABASE:-laravel}
      - STORAGE_PATH=/backup
      - BACKUP_CRON_EXPRESSION=0 2 * * *
      - BACKUP_RETENTION_DAYS=30
      - AWS_S3_ENDPOINT=${AZURE_BLOB_ENDPOINT}
      - AWS_S3_BUCKET_NAME=${AZURE_CONTAINER_NAME}
    secrets:
      - db_username
      - db_password
      - azure_storage_account
      - azure_storage_key

secrets:
  app_key:
    file: ./secrets/app_key.txt
  db_username:
    file: ./secrets/db_username.txt
  db_password:
    file: ./secrets/db_password.txt
  redis_password:
    file: ./secrets/redis_password.txt
  azure_storage_account:
    file: ./secrets/azure_storage_account.txt
  azure_storage_key:
    file: ./secrets/azure_storage_key.txt

networks:
  backend:
    internal: true  # No external access in production
```

---

## Dockerfile Structure

### Multi-Stage Build (docker/common/php-fpm/Dockerfile)

The Dockerfile uses multi-stage builds to create optimized images for different environments.

#### Base Stage

```dockerfile
FROM php:8.4-fpm-alpine AS base

# Install system dependencies
RUN apk add --no-cache \
    curl \
    git \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libzip-dev \
    icu-dev \
    oniguruma-dev \
    postgresql-dev \
    libpq

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo \
        pdo_pgsql \
        pgsql \
        gd \
        zip \
        intl \
        mbstring \
        bcmath \
        opcache \
        pcntl \
        exif

# Install Redis extension
RUN pecl install redis && docker-php-ext-enable redis

# Create non-root user
ARG UID=1000
ARG GID=1000
RUN addgroup -g ${GID} laravel \
    && adduser -u ${UID} -G laravel -D -s /bin/sh laravel

WORKDIR /var/www
```

#### Development Stage

```dockerfile
FROM base AS development

# Install Xdebug for debugging
RUN pecl install xdebug && docker-php-ext-enable xdebug

# Install Composer
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

# Configure Xdebug
RUN echo "xdebug.mode=develop,debug" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.client_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.start_with_request=yes" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.idekey=DOCKER" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Development PHP settings
RUN echo "memory_limit = 512M" >> /usr/local/etc/php/conf.d/custom.ini \
    && echo "max_execution_time = 300" >> /usr/local/etc/php/conf.d/custom.ini \
    && echo "upload_max_filesize = 64M" >> /usr/local/etc/php/conf.d/custom.ini \
    && echo "post_max_size = 68M" >> /usr/local/etc/php/conf.d/custom.ini

# Install healthcheck script
RUN curl -o /usr/local/bin/php-fpm-healthcheck \
    https://raw.githubusercontent.com/renatomefi/php-fpm-healthcheck/master/php-fpm-healthcheck \
    && chmod +x /usr/local/bin/php-fpm-healthcheck

USER laravel
```

#### Production Stage

```dockerfile
FROM base AS production

# Remove build dependencies for smaller image
RUN apk del --no-cache $PHPIZE_DEPS

# Install only runtime dependencies
RUN apk add --no-cache postgresql-client fcgi

# Copy production PHP configuration
COPY docker/production/php/php-production.ini /usr/local/etc/php/conf.d/production.ini

# Install Composer
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

# Copy application code
COPY --chown=laravel:laravel src /var/www

# Install production dependencies only
RUN composer install --no-dev --optimize-autoloader --no-interaction

# Copy entrypoint script
COPY --chmod=755 docker/scripts/entrypoint/php-fpm-entrypoint.sh /usr/local/bin/entrypoint.sh

# Install healthcheck script
RUN curl -o /usr/local/bin/php-fpm-healthcheck \
    https://raw.githubusercontent.com/renatomefi/php-fpm-healthcheck/master/php-fpm-healthcheck \
    && chmod +x /usr/local/bin/php-fpm-healthcheck

USER laravel

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD php-fpm-healthcheck || php -r 'exit(0);'

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm"]
```

### Nginx Production Dockerfile

```dockerfile
FROM nginx:1.27-alpine

# Remove default configuration
RUN rm /etc/nginx/conf.d/default.conf

# Copy production configuration
COPY docker/production/nginx/nginx.conf /etc/nginx/nginx.conf

# Copy static files
COPY src/public /var/www/public

# Create required directories
RUN mkdir -p /var/cache/nginx /var/run/nginx \
    && chown -R nginx:nginx /var/cache/nginx /var/run/nginx /var/www/public

USER nginx

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD wget -q --spider http://localhost/health || exit 1

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## Environment Variables

### Application Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `APP_NAME` | Application name | Laravel | No |
| `APP_ENV` | Environment (local/production) | local | Yes |
| `APP_KEY` | Encryption key | - | Yes |
| `APP_DEBUG` | Debug mode | true | No |
| `APP_URL` | Application URL | http://localhost | Yes |

### Database Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `DB_CONNECTION` | Database driver | pgsql | No |
| `DB_HOST` | Database host | postgres | Yes |
| `DB_PORT` | Database port | 5432 | No |
| `DB_DATABASE` | Database name | laravel | Yes |
| `DB_USERNAME` | Database user | laravel | Yes |
| `DB_PASSWORD` | Database password | secret | Yes |

### Redis Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `REDIS_HOST` | Redis host | redis | Yes |
| `REDIS_PORT` | Redis port | 6379 | No |
| `REDIS_PASSWORD` | Redis password | null | Prod only |

### Docker Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `UID` | User ID for container | 1000 | No |
| `GID` | Group ID for container | 1000 | No |
| `NGINX_PORT` | Host port for Nginx | 80 | No |
| `POSTGRES_PORT` | Host port for PostgreSQL | 5432 | No |
| `REDIS_PORT` | Host port for Redis | 6379 | No |

### Xdebug Variables (Development)

| Variable | Description | Default |
|----------|-------------|---------|
| `XDEBUG_MODE` | Xdebug mode | develop,debug |
| `XDEBUG_HOST` | IDE host | host.docker.internal |
| `XDEBUG_IDE_KEY` | IDE key | DOCKER |

---

## Volumes and Persistence

### Named Volumes

| Volume | Service | Mount Point | Purpose |
|--------|---------|-------------|---------|
| `postgres_data` | PostgreSQL | `/var/lib/postgresql/data` | Database files |
| `redis_data` | Redis | `/data` | Redis persistence |
| `backup_data` | Backup | `/backup` | Backup storage |

### Bind Mounts (Development)

| Host Path | Container Path | Service | Mode |
|-----------|---------------|---------|------|
| `./src` | `/var/www` | PHP-FPM | rw |
| `./src` | `/var/www` | Nginx | ro |
| `./docker/development/nginx/nginx.conf` | `/etc/nginx/nginx.conf` | Nginx | ro |
| `./docker/development/php/php.ini` | `/usr/local/etc/php/conf.d/custom.ini` | PHP-FPM | ro |

### tmpfs Mounts (Production)

| Mount Point | Size | Purpose |
|-------------|------|---------|
| `/tmp` | 64M | Temporary files |
| `/var/run` | 16M | Runtime files |

---

## Networks

### Development Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    frontend (bridge)                        │
│                                                             │
│  ┌─────────────┐                                            │
│  │   nginx     │ ←── Port 80 exposed                        │
│  └──────┬──────┘                                            │
└─────────┼───────────────────────────────────────────────────┘
          │
          │ FastCGI (9000)
          │
┌─────────┼───────────────────────────────────────────────────┐
│         │              backend (bridge)                     │
│         ▼                                                   │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  php-fpm    │───▶│  postgres   │    │   redis     │     │
│  └──────┬──────┘    └─────────────┘    └─────────────┘     │
│         │                │                   │              │
│         │                │ Port 5432         │ Port 6379    │
│         │                │ exposed           │ exposed      │
│         ▼                                                   │
│  ┌─────────────┐                                            │
│  │   queue     │                                            │
│  └─────────────┘                                            │
└─────────────────────────────────────────────────────────────┘
```

### Production Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    frontend (bridge)                        │
│                                                             │
│  ┌─────────────┐                                            │
│  │   nginx     │ ←── Port 80 exposed                        │
│  └──────┬──────┘                                            │
└─────────┼───────────────────────────────────────────────────┘
          │
          │ FastCGI (9000)
          │
┌─────────┼───────────────────────────────────────────────────┐
│         │         backend (bridge, INTERNAL)                │
│         │         ════════════════════════                  │
│         │         No external access                        │
│         ▼                                                   │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │  php-fpm    │───▶│  postgres   │    │   redis     │     │
│  └──────┬──────┘    └─────────────┘    └─────────────┘     │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────┐    ┌─────────────┐                        │
│  │   queue     │    │   backup    │                        │
│  └─────────────┘    └─────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Health Checks

### Nginx Health Check

```yaml
healthcheck:
  test: ["CMD", "wget", "-q", "--spider", "http://localhost/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

The `/health` endpoint in Nginx configuration:

```nginx
location = /health {
    access_log off;
    return 200 "healthy\n";
    add_header Content-Type text/plain;
}
```

### PHP-FPM Health Check

```yaml
healthcheck:
  test: ["CMD-SHELL", "php-fpm-healthcheck || php -r 'exit(0);'"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

Uses the `php-fpm-healthcheck` script that queries PHP-FPM status.

### PostgreSQL Health Check

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${DB_USERNAME:-laravel} -d ${DB_DATABASE:-laravel}"]
  interval: 10s
  timeout: 5s
  retries: 5
```

### Redis Health Check

```yaml
healthcheck:
  test: ["CMD", "redis-cli", "ping"]
  interval: 10s
  timeout: 5s
  retries: 5
```

---

## Production Security

### Container Security Options

```yaml
security_opt:
  - no-new-privileges:true  # Prevent privilege escalation

cap_drop:
  - ALL                      # Drop all capabilities

cap_add:
  - NET_BIND_SERVICE        # Only allow binding to ports < 1024 (Nginx)
```

### Read-Only Root Filesystem

```yaml
read_only: true
tmpfs:
  - /tmp:mode=1777,size=64M
  - /var/run:mode=1777,size=16M
```

### Resource Limits

```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 512M
    reservations:
      cpus: '0.5'
      memory: 256M
```

### Logging Configuration

```yaml
logging:
  driver: json-file
  options:
    max-size: "50m"
    max-file: "5"
```

### Non-Root Users

All containers run as non-root users:
- Nginx: `nginx` user
- PHP-FPM: `laravel` user (UID 1000)
- PostgreSQL: `postgres` user
- Redis: `redis` user

---

## Related Documentation

- [Architecture Overview](./ARCHITECTURE.md)
- [Services Configuration](./SERVICES.md)
- [Deployment Guide](./DEPLOYMENT.md)
- [Development Guide](./DEVELOPMENT.md)
