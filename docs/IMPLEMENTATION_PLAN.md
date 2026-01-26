# Laravel 12 + PostgreSQL 18 Docker Boilerplate

## Complete Implementation Plan

A secure, portable Docker-based Laravel application designed as a reusable boilerplate for future web applications.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Directory Structure](#directory-structure)
3. [Docker Configuration Files](#docker-configuration-files)
4. [Environment Files](#environment-files)
5. [Nginx Configuration](#nginx-configuration)
6. [PHP Configuration](#php-configuration)
7. [Entrypoint Scripts](#entrypoint-scripts)
8. [Backup Scripts](#backup-scripts)
9. [GitHub Actions CI/CD](#github-actions-cicd)
10. [Security Hardening Checklist](#security-hardening-checklist)
11. [Implementation Steps](#implementation-steps)
12. [Verification Plan](#verification-plan)

---

## Architecture Overview

```
                    [Cloudflare CDN/SSL]
                           |
                    [Azure VM - Ubuntu]
                           |
    ┌──────────────────────┴──────────────────────┐
    │                   FRONTEND NETWORK          │
    │  ┌─────────┐                                │
    │  │  Nginx  │◄── Port 80                     │
    │  └────┬────┘                                │
    └───────┼─────────────────────────────────────┘
            │
    ┌───────┼─────────────────────────────────────┐
    │       │         BACKEND NETWORK (internal)  │
    │  ┌────▼────┐   ┌─────────┐   ┌─────────┐   │
    │  │ PHP-FPM │◄──│  Redis  │   │ Queue   │   │
    │  └────┬────┘   └─────────┘   └────┬────┘   │
    │       │                           │        │
    │  ┌────▼──────────────────────────▼────┐   │
    │  │           PostgreSQL 18            │   │
    │  │         (persistent volume)        │   │
    │  └────────────────────────────────────┘   │
    └─────────────────────────────────────────────┘
```

### Components

| Service | Image | Purpose |
|---------|-------|---------|
| Nginx | nginx:1.27-alpine | Reverse proxy, static file serving |
| PHP-FPM | Custom (PHP 8.3-fpm-alpine) | Laravel application |
| PostgreSQL | postgres:18-alpine | Database |
| Redis | redis:7-alpine | Cache, sessions, queue backend |
| Queue | Same as PHP-FPM | Background job processing |

### Networks

| Network | Type | Services | Purpose |
|---------|------|----------|---------|
| frontend | bridge | nginx, php-fpm | External-facing |
| backend | internal | php-fpm, postgres, redis, queue | Database/cache isolation |

---

## Directory Structure

```
D:\_repos\docker\laravel\
├── src/                              # Laravel 12 application
│   ├── app/
│   ├── bootstrap/
│   ├── config/
│   ├── database/
│   ├── public/
│   ├── resources/
│   ├── routes/
│   ├── storage/
│   ├── tests/
│   ├── composer.json
│   └── .env.example
├── docker/
│   ├── common/
│   │   └── php-fpm/
│   │       └── Dockerfile            # Multi-stage build (dev + prod)
│   ├── development/
│   │   ├── nginx/
│   │   │   └── nginx.conf
│   │   └── workspace/
│   │       └── Dockerfile            # Dev tools + Xdebug
│   ├── production/
│   │   ├── nginx/
│   │   │   ├── Dockerfile
│   │   │   └── nginx.conf            # Hardened config
│   │   └── php/
│   │       └── php-production.ini
│   └── scripts/
│       ├── entrypoint/
│       │   ├── php-fpm-entrypoint.sh
│       │   └── queue-entrypoint.sh
│       └── backup/
│           └── backup.sh
├── secrets/                          # Git-ignored production secrets
│   ├── app_key.txt
│   ├── db_username.txt
│   ├── db_password.txt
│   └── redis_password.txt
├── backups/                          # Local backup storage
├── docker-compose.yml                # Local development
├── docker-compose.prod.yml           # Production with secrets
├── .env.docker                       # Local dev environment
├── .env.example                      # Template
├── .dockerignore
├── .gitignore
└── .github/
    └── workflows/
        └── deploy.yml                # CI/CD pipeline
```

---

## Docker Configuration Files

### PHP-FPM Dockerfile (Multi-Stage)

**File: `docker/common/php-fpm/Dockerfile`**

```dockerfile
# =============================================================================
# Laravel PHP-FPM Docker Image - Multi-Stage Build
# Security-hardened for production use
# =============================================================================

# -----------------------------------------------------------------------------
# Base Stage - Common dependencies
# -----------------------------------------------------------------------------
FROM php:8.3-fpm-alpine AS base

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
    libpq \
    linux-headers \
    $PHPIZE_DEPS

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
        pcntl

# Install Redis extension
RUN pecl install redis && docker-php-ext-enable redis

# Create non-root user for security
RUN addgroup -g 1000 -S laravel \
    && adduser -u 1000 -S laravel -G laravel

# Set working directory
WORKDIR /var/www

# -----------------------------------------------------------------------------
# Development Stage
# -----------------------------------------------------------------------------
FROM base AS development

# Install Xdebug for debugging
RUN pecl install xdebug && docker-php-ext-enable xdebug

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Development PHP configuration
RUN echo "xdebug.mode=debug,develop" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.client_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.start_with_request=yes" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Copy development PHP config
COPY docker/development/php/php.ini /usr/local/etc/php/conf.d/custom.ini

USER laravel

EXPOSE 9000

CMD ["php-fpm"]

# -----------------------------------------------------------------------------
# Production Stage - Optimized and Hardened
# -----------------------------------------------------------------------------
FROM base AS production

# Remove dev dependencies and clean up
RUN apk del $PHPIZE_DEPS linux-headers \
    && rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# Install PostgreSQL client for health checks
RUN apk add --no-cache postgresql-client

# Copy production PHP configuration
COPY docker/production/php/php-production.ini /usr/local/etc/php/conf.d/custom.ini

# Copy application code
COPY --chown=laravel:laravel src/ /var/www/

# Install Composer and dependencies (production only)
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
RUN composer install --no-dev --no-interaction --optimize-autoloader --no-scripts \
    && composer clear-cache \
    && rm -rf /root/.composer

# Copy entrypoint script
COPY --chmod=755 docker/scripts/entrypoint/php-fpm-entrypoint.sh /usr/local/bin/entrypoint.sh

# Set proper permissions
RUN chown -R laravel:laravel /var/www \
    && chmod -R 755 /var/www/storage /var/www/bootstrap/cache

# Security: Run as non-root user
USER laravel

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD php-fpm-healthcheck || exit 1

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm"]
```

---

### Local Development Docker Compose

**File: `docker-compose.yml`**

```yaml
# =============================================================================
# Docker Compose - Local Development Environment
# =============================================================================

services:
  # ---------------------------------------------------------------------------
  # Nginx Web Server
  # ---------------------------------------------------------------------------
  nginx:
    image: nginx:1.27-alpine
    container_name: laravel-nginx
    restart: unless-stopped
    ports:
      - "${NGINX_PORT:-80}:80"
    volumes:
      - ./src:/var/www:ro
      - ./docker/development/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      php-fpm:
        condition: service_healthy
    networks:
      - frontend
      - backend
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # ---------------------------------------------------------------------------
  # PHP-FPM Application Server
  # ---------------------------------------------------------------------------
  php-fpm:
    build:
      context: .
      dockerfile: docker/common/php-fpm/Dockerfile
      target: development
    container_name: laravel-php
    restart: unless-stopped
    volumes:
      - ./src:/var/www
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
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "php-fpm-healthcheck || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  # ---------------------------------------------------------------------------
  # PostgreSQL Database
  # ---------------------------------------------------------------------------
  postgres:
    image: postgres:18-alpine
    container_name: laravel-postgres
    restart: unless-stopped
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    environment:
      POSTGRES_DB: ${DB_DATABASE:-laravel}
      POSTGRES_USER: ${DB_USERNAME:-laravel}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-secret}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USERNAME:-laravel} -d ${DB_DATABASE:-laravel}"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ---------------------------------------------------------------------------
  # Redis Cache
  # ---------------------------------------------------------------------------
  redis:
    image: redis:7-alpine
    container_name: laravel-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ---------------------------------------------------------------------------
  # Queue Worker
  # ---------------------------------------------------------------------------
  queue:
    build:
      context: .
      dockerfile: docker/common/php-fpm/Dockerfile
      target: development
    container_name: laravel-queue
    restart: unless-stopped
    command: php artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
    volumes:
      - ./src:/var/www
    environment:
      - APP_ENV=${APP_ENV:-local}
      - DB_CONNECTION=pgsql
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=${DB_DATABASE:-laravel}
      - DB_USERNAME=${DB_USERNAME:-laravel}
      - DB_PASSWORD=${DB_PASSWORD:-secret}
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - QUEUE_CONNECTION=redis
    depends_on:
      php-fpm:
        condition: service_healthy
    networks:
      - backend

# -----------------------------------------------------------------------------
# Networks
# -----------------------------------------------------------------------------
networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge

# -----------------------------------------------------------------------------
# Volumes
# -----------------------------------------------------------------------------
volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
```

---

### Production Docker Compose

**File: `docker-compose.prod.yml`**

```yaml
# =============================================================================
# Docker Compose - Production Environment
# Security-hardened with Docker secrets and network isolation
# =============================================================================

services:
  # ---------------------------------------------------------------------------
  # Nginx Web Server (Hardened)
  # ---------------------------------------------------------------------------
  nginx:
    image: ghcr.io/${GITHUB_REPOSITORY:-laravel}/nginx:latest
    container_name: laravel-nginx
    restart: always
    ports:
      - "80:80"
    depends_on:
      php-fpm:
        condition: service_healthy
    networks:
      - frontend
      - backend
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /var/cache/nginx:uid=101,gid=101
      - /var/run:uid=101,gid=101
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
        reservations:
          cpus: '0.1'
          memory: 64M
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ---------------------------------------------------------------------------
  # PHP-FPM Application Server (Hardened)
  # ---------------------------------------------------------------------------
  php-fpm:
    image: ghcr.io/${GITHUB_REPOSITORY:-laravel}/php-fpm:latest
    container_name: laravel-php
    restart: always
    environment:
      - APP_ENV=production
      - APP_DEBUG=false
      - DB_CONNECTION=pgsql
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=laravel
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - CACHE_STORE=redis
      - SESSION_DRIVER=redis
      - QUEUE_CONNECTION=redis
      - MIGRATE_ON_START=false
    secrets:
      - app_key
      - db_username
      - db_password
      - redis_password
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - backend
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
    healthcheck:
      test: ["CMD-SHELL", "php-fpm-healthcheck || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

  # ---------------------------------------------------------------------------
  # PostgreSQL Database (Hardened)
  # ---------------------------------------------------------------------------
  postgres:
    image: postgres:18-alpine
    container_name: laravel-postgres
    restart: always
    environment:
      POSTGRES_DB: laravel
      POSTGRES_USER_FILE: /run/secrets/db_username
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_username
      - db_password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 256M
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$(cat /run/secrets/db_username) -d laravel"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

  # ---------------------------------------------------------------------------
  # Redis Cache (Hardened)
  # ---------------------------------------------------------------------------
  redis:
    image: redis:7-alpine
    container_name: laravel-redis
    restart: always
    command: >
      sh -c "redis-server
      --appendonly yes
      --requirepass $$(cat /run/secrets/redis_password)
      --maxmemory 256mb
      --maxmemory-policy allkeys-lru"
    secrets:
      - redis_password
    volumes:
      - redis_data:/data
    networks:
      - backend
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.1'
          memory: 128M
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a $$(cat /run/secrets/redis_password) ping | grep PONG"]
      interval: 10s
      timeout: 5s
      retries: 5
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ---------------------------------------------------------------------------
  # Queue Worker (Hardened)
  # ---------------------------------------------------------------------------
  queue:
    image: ghcr.io/${GITHUB_REPOSITORY:-laravel}/php-fpm:latest
    container_name: laravel-queue
    restart: always
    entrypoint: ["/usr/local/bin/queue-entrypoint.sh"]
    command: php artisan queue:work redis --sleep=3 --tries=3 --max-time=3600 --memory=256
    environment:
      - APP_ENV=production
      - APP_DEBUG=false
      - DB_CONNECTION=pgsql
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=laravel
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - QUEUE_CONNECTION=redis
    secrets:
      - app_key
      - db_username
      - db_password
      - redis_password
    depends_on:
      php-fpm:
        condition: service_healthy
    networks:
      - backend
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"

  # ---------------------------------------------------------------------------
  # Database Backup Service
  # ---------------------------------------------------------------------------
  backup:
    image: jkaninda/pg-bkup:latest
    container_name: laravel-backup
    restart: always
    environment:
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_NAME=laravel
      - CRON_EXPRESSION=0 2 * * *
      - BACKUP_RETENTION_DAYS=30
      - AZURE_STORAGE_CONTAINER_NAME=backups
    secrets:
      - db_username
      - db_password
      - azure_storage_account
      - azure_storage_key
    volumes:
      - backup_data:/backup
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - backend
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

# -----------------------------------------------------------------------------
# Networks
# -----------------------------------------------------------------------------
networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true  # No external access - security critical!

# -----------------------------------------------------------------------------
# Volumes
# -----------------------------------------------------------------------------
volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  backup_data:
    driver: local

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------
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
```

---

## Environment Files

### `.env.example`

```bash
# =============================================================================
# Laravel Environment Configuration Template
# Copy to .env.docker for local development
# =============================================================================

APP_NAME=Laravel
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_TIMEZONE=UTC
APP_URL=http://localhost

# Logging
LOG_CHANNEL=stack
LOG_STACK=single
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

# Database
DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret

# Session
SESSION_DRIVER=redis
SESSION_LIFETIME=120
SESSION_ENCRYPT=false

# Cache
CACHE_STORE=redis

# Queue
QUEUE_CONNECTION=redis

# Redis
REDIS_CLIENT=phpredis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

# Docker specific
NGINX_PORT=80
POSTGRES_PORT=5432
UID=1000
GID=1000

# Xdebug (development only)
XDEBUG_ENABLED=true
XDEBUG_HOST=host.docker.internal
XDEBUG_IDE_KEY=DOCKER
```

### `.env.docker` (Local Development)

```bash
# =============================================================================
# Docker Local Development Environment
# =============================================================================

APP_NAME=Laravel
APP_ENV=local
APP_KEY=base64:your-generated-key-here
APP_DEBUG=true
APP_TIMEZONE=UTC
APP_URL=http://localhost

LOG_CHANNEL=stack
LOG_STACK=single
LOG_LEVEL=debug

DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret

SESSION_DRIVER=redis
SESSION_LIFETIME=120
CACHE_STORE=redis
QUEUE_CONNECTION=redis

REDIS_CLIENT=phpredis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

NGINX_PORT=80
POSTGRES_PORT=5432
UID=1000
GID=1000

XDEBUG_ENABLED=true
XDEBUG_HOST=host.docker.internal
XDEBUG_IDE_KEY=DOCKER
```

---

## Nginx Configuration

### Development: `docker/development/nginx/nginx.conf`

```nginx
# =============================================================================
# Nginx Configuration - Local Development Environment
# =============================================================================

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Hide Nginx version
    server_tokens off;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 64m;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript
               application/xml application/xml+rss text/javascript application/x-font-ttf
               font/opentype image/svg+xml;

    server {
        listen 80;
        server_name localhost;
        root /var/www/public;
        index index.php index.html;

        charset utf-8;

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }

        location = /favicon.ico { access_log off; log_not_found off; }
        location = /robots.txt  { access_log off; log_not_found off; }

        error_page 404 /index.php;

        location ~ \.php$ {
            fastcgi_pass php-fpm:9000;
            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
            include fastcgi_params;
            fastcgi_hide_header X-Powered-By;

            # Development timeouts (longer for debugging)
            fastcgi_connect_timeout 300;
            fastcgi_send_timeout 300;
            fastcgi_read_timeout 300;
        }

        location ~ /\.(?!well-known).* {
            deny all;
        }
    }
}
```

### Production: `docker/production/nginx/nginx.conf`

```nginx
# =============================================================================
# Nginx Configuration - Production Environment (Hardened)
# SSL termination handled by Cloudflare
# =============================================================================

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log error;
pid /var/run/nginx.pid;

# Security: Limit worker file descriptors
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Hide Nginx version
    server_tokens off;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main buffer=16k flush=2m;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 30;
    types_hash_max_size 2048;
    client_max_body_size 32m;

    # Security: Limit request body and buffers
    client_body_buffer_size 16k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 8k;

    # Rate limiting zone
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_types text/plain text/css text/xml application/json application/javascript
               application/xml application/xml+rss text/javascript application/x-font-ttf
               font/opentype image/svg+xml;

    # Upstream PHP-FPM pool
    upstream php-fpm {
        server php-fpm:9000;
        keepalive 32;
    }

    server {
        listen 80;
        server_name _;
        root /var/www/public;
        index index.php;

        charset utf-8;

        # Security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

        # CSP header (adjust as needed for your application)
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self';" always;

        # Health check (no rate limiting)
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # Cloudflare real IP restoration
        set_real_ip_from 173.245.48.0/20;
        set_real_ip_from 103.21.244.0/22;
        set_real_ip_from 103.22.200.0/22;
        set_real_ip_from 103.31.4.0/22;
        set_real_ip_from 141.101.64.0/18;
        set_real_ip_from 108.162.192.0/18;
        set_real_ip_from 190.93.240.0/20;
        set_real_ip_from 188.114.96.0/20;
        set_real_ip_from 197.234.240.0/22;
        set_real_ip_from 198.41.128.0/17;
        set_real_ip_from 162.158.0.0/15;
        set_real_ip_from 104.16.0.0/13;
        set_real_ip_from 104.24.0.0/14;
        set_real_ip_from 172.64.0.0/13;
        set_real_ip_from 131.0.72.0/22;
        real_ip_header CF-Connecting-IP;

        # Static files caching
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            access_log off;
            try_files $uri =404;
        }

        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }

        location = /favicon.ico { access_log off; log_not_found off; }
        location = /robots.txt  { access_log off; log_not_found off; }

        error_page 404 /index.php;

        # PHP handling with rate limiting
        location ~ \.php$ {
            # Rate limiting
            limit_req zone=api burst=20 nodelay;
            limit_conn conn_limit 10;

            fastcgi_pass php-fpm;
            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
            include fastcgi_params;

            # Security: Hide PHP version
            fastcgi_hide_header X-Powered-By;

            # Production timeouts
            fastcgi_connect_timeout 60;
            fastcgi_send_timeout 60;
            fastcgi_read_timeout 60;

            # Buffer settings
            fastcgi_buffer_size 128k;
            fastcgi_buffers 256 16k;
            fastcgi_busy_buffers_size 256k;
            fastcgi_temp_file_write_size 256k;

            # Keepalive
            fastcgi_keep_conn on;
        }

        # Block access to sensitive files
        location ~ /\.(?!well-known).* {
            deny all;
        }

        location ~ /\.(env|git|htaccess|htpasswd) {
            deny all;
        }

        # Block access to storage and bootstrap directories
        location ~ ^/(storage|bootstrap)/ {
            deny all;
        }
    }
}
```

---

## PHP Configuration

### `docker/production/php/php-production.ini`

```ini
; =============================================================================
; PHP Production Configuration - Security Hardened
; =============================================================================

[PHP]
; Error handling - disable display, enable logging
display_errors = Off
display_startup_errors = Off
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
log_errors = On
error_log = /dev/stderr

; Security settings
expose_php = Off
allow_url_fopen = Off
allow_url_include = Off

; Disable dangerous functions
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,highlight_file,phpinfo

; File uploads
file_uploads = On
upload_max_filesize = 32M
max_file_uploads = 10
post_max_size = 34M

; Memory and execution limits
memory_limit = 256M
max_execution_time = 30
max_input_time = 30
max_input_vars = 5000

; Session security
session.cookie_httponly = On
session.cookie_secure = On
session.cookie_samesite = Strict
session.use_strict_mode = On
session.use_only_cookies = On
session.name = __Secure_LARAVELSESSID
session.gc_maxlifetime = 7200

; Other security settings
cgi.fix_pathinfo = 0
open_basedir = /var/www:/tmp

[opcache]
; OPcache settings for production
opcache.enable = 1
opcache.enable_cli = 0
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0
opcache.revalidate_freq = 0
opcache.save_comments = 1
opcache.jit_buffer_size = 100M
opcache.jit = 1255

[Date]
date.timezone = UTC

[Realpath Cache]
realpath_cache_size = 4096K
realpath_cache_ttl = 600
```

---

## Entrypoint Scripts

### `docker/scripts/entrypoint/php-fpm-entrypoint.sh`

```bash
#!/bin/sh
set -e

# =============================================================================
# PHP-FPM Production Entrypoint
# Handles Docker secrets and Laravel optimization
# =============================================================================

echo "Starting PHP-FPM entrypoint..."

# Function to read secret from file
read_secret() {
    local secret_file="$1"
    local env_var="$2"

    if [ -f "$secret_file" ]; then
        export "$env_var"="$(cat "$secret_file")"
        echo "Loaded secret for $env_var"
    fi
}

# Load secrets from Docker secrets
if [ -d "/run/secrets" ]; then
    echo "Loading Docker secrets..."

    [ -f "/run/secrets/app_key" ] && export APP_KEY="$(cat /run/secrets/app_key)"
    [ -f "/run/secrets/db_username" ] && export DB_USERNAME="$(cat /run/secrets/db_username)"
    [ -f "/run/secrets/db_password" ] && export DB_PASSWORD="$(cat /run/secrets/db_password)"
    [ -f "/run/secrets/redis_password" ] && export REDIS_PASSWORD="$(cat /run/secrets/redis_password)"
fi

# Wait for database to be ready
if [ -n "$DB_HOST" ]; then
    echo "Waiting for database connection..."
    max_attempts=30
    attempt=1

    while ! pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "${DB_USERNAME:-laravel}" > /dev/null 2>&1; do
        if [ $attempt -ge $max_attempts ]; then
            echo "Database not available after $max_attempts attempts, starting anyway..."
            break
        fi
        echo "Attempt $attempt/$max_attempts: Database not ready, waiting..."
        sleep 2
        attempt=$((attempt + 1))
    done
fi

# Laravel optimization for production
if [ "$APP_ENV" = "production" ]; then
    echo "Running Laravel production optimizations..."

    # Cache configuration
    php artisan config:cache

    # Cache routes
    php artisan route:cache

    # Cache views
    php artisan view:cache

    # Run migrations if MIGRATE_ON_START is set
    if [ "$MIGRATE_ON_START" = "true" ]; then
        echo "Running database migrations..."
        php artisan migrate --force
    fi
fi

echo "Starting PHP-FPM..."
exec "$@"
```

### `docker/scripts/entrypoint/queue-entrypoint.sh`

```bash
#!/bin/sh
set -e

# =============================================================================
# Queue Worker Entrypoint
# =============================================================================

echo "Starting Queue Worker entrypoint..."

# Load secrets
if [ -d "/run/secrets" ]; then
    echo "Loading Docker secrets..."
    [ -f "/run/secrets/app_key" ] && export APP_KEY="$(cat /run/secrets/app_key)"
    [ -f "/run/secrets/db_username" ] && export DB_USERNAME="$(cat /run/secrets/db_username)"
    [ -f "/run/secrets/db_password" ] && export DB_PASSWORD="$(cat /run/secrets/db_password)"
    [ -f "/run/secrets/redis_password" ] && export REDIS_PASSWORD="$(cat /run/secrets/redis_password)"
fi

# Wait for PHP-FPM to be healthy
echo "Waiting for application to be ready..."
sleep 10

echo "Starting queue worker..."
exec "$@"
```

---

## Backup Scripts

### `docker/scripts/backup/backup.sh`

```bash
#!/bin/bash
# =============================================================================
# PostgreSQL Backup Script
# Backs up to local storage and Azure Blob Storage
# =============================================================================

set -e

# Configuration
BACKUP_DIR="/backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="laravel_${TIMESTAMP}.sql.gz"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}

# Load secrets
if [ -f "/run/secrets/db_username" ]; then
    DB_USER=$(cat /run/secrets/db_username)
fi
if [ -f "/run/secrets/db_password" ]; then
    export PGPASSWORD=$(cat /run/secrets/db_password)
fi

echo "[$(date)] Starting PostgreSQL backup..."

# Create backup directory if not exists
mkdir -p "$BACKUP_DIR/local"

# Perform database dump
echo "[$(date)] Dumping database..."
pg_dump -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" | gzip > "$BACKUP_DIR/local/$BACKUP_FILE"

echo "[$(date)] Local backup created: $BACKUP_FILE"

# Upload to Azure Blob Storage
if [ -n "$AZURE_STORAGE_ACCOUNT" ] && [ -n "$AZURE_STORAGE_KEY" ]; then
    echo "[$(date)] Uploading to Azure Blob Storage..."

    az storage blob upload \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --account-key "$AZURE_STORAGE_KEY" \
        --container-name "$AZURE_STORAGE_CONTAINER_NAME" \
        --file "$BACKUP_DIR/local/$BACKUP_FILE" \
        --name "backups/$BACKUP_FILE"

    echo "[$(date)] Azure upload complete."
fi

# Clean up old backups
echo "[$(date)] Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR/local" -name "*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete

echo "[$(date)] Backup completed successfully."
```

---

## GitHub Actions CI/CD

### `.github/workflows/deploy.yml`

```yaml
# =============================================================================
# GitHub Actions - CI/CD Pipeline for Laravel Docker Application
# Triggered on push to main branch
# =============================================================================

name: Deploy Laravel Application

on:
  push:
    branches:
      - main
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  # ---------------------------------------------------------------------------
  # Build and Test
  # ---------------------------------------------------------------------------
  test:
    name: Test Application
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:18
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
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup PHP
        uses: shivammathur/setup-php@v2
        with:
          php-version: '8.3'
          extensions: pdo_pgsql, redis, bcmath, gd, intl, zip
          coverage: xdebug

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'
          cache-dependency-path: src/package-lock.json

      - name: Get Composer cache directory
        id: composer-cache
        run: echo "dir=$(composer config cache-files-dir)" >> $GITHUB_OUTPUT
        working-directory: src

      - name: Cache Composer dependencies
        uses: actions/cache@v4
        with:
          path: ${{ steps.composer-cache.outputs.dir }}
          key: ${{ runner.os }}-composer-${{ hashFiles('src/composer.lock') }}
          restore-keys: ${{ runner.os }}-composer-

      - name: Install Composer dependencies
        run: composer install --no-interaction --prefer-dist --optimize-autoloader
        working-directory: src

      - name: Install NPM dependencies
        run: npm ci
        working-directory: src

      - name: Build assets
        run: npm run build
        working-directory: src

      - name: Copy environment file
        run: cp .env.example .env
        working-directory: src

      - name: Generate application key
        run: php artisan key:generate
        working-directory: src

      - name: Run tests
        run: php artisan test --parallel
        working-directory: src
        env:
          DB_CONNECTION: pgsql
          DB_HOST: localhost
          DB_PORT: 5432
          DB_DATABASE: laravel_test
          DB_USERNAME: laravel
          DB_PASSWORD: secret
          REDIS_HOST: localhost
          REDIS_PORT: 6379

  # ---------------------------------------------------------------------------
  # Build Docker Images
  # ---------------------------------------------------------------------------
  build:
    name: Build Docker Images
    runs-on: ubuntu-latest
    needs: test
    permissions:
      contents: read
      packages: write

    outputs:
      image-tag: ${{ steps.meta.outputs.version }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata for PHP-FPM image
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}/php-fpm
          tags: |
            type=sha,prefix=
            type=ref,event=branch
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

      - name: Build and push PHP-FPM image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: docker/common/php-fpm/Dockerfile
          target: production
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Extract metadata for Nginx image
        id: nginx-meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}/nginx
          tags: |
            type=sha,prefix=
            type=ref,event=branch
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

      - name: Build and push Nginx image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: docker/production/nginx/Dockerfile
          push: true
          tags: ${{ steps.nginx-meta.outputs.tags }}
          labels: ${{ steps.nginx-meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ---------------------------------------------------------------------------
  # Deploy to Azure VM
  # ---------------------------------------------------------------------------
  deploy:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: build
    environment: production
    concurrency:
      group: production-deploy
      cancel-in-progress: false

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install SSH key
        uses: shimataro/ssh-key-action@v2
        with:
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          known_hosts: ${{ secrets.SSH_KNOWN_HOSTS }}

      - name: Deploy to server
        env:
          SERVER_HOST: ${{ secrets.SERVER_HOST }}
          SERVER_USER: ${{ secrets.SERVER_USER }}
          IMAGE_TAG: ${{ needs.build.outputs.image-tag }}
        run: |
          ssh $SERVER_USER@$SERVER_HOST << 'ENDSSH'
            set -e

            cd /opt/laravel

            # Pull latest images
            docker compose -f docker-compose.prod.yml pull

            # Run database migrations
            docker compose -f docker-compose.prod.yml run --rm php-fpm php artisan migrate --force

            # Deploy with zero-downtime
            docker compose -f docker-compose.prod.yml up -d --remove-orphans

            # Clear caches and optimize
            docker compose -f docker-compose.prod.yml exec php-fpm php artisan optimize:clear
            docker compose -f docker-compose.prod.yml exec php-fpm php artisan config:cache
            docker compose -f docker-compose.prod.yml exec php-fpm php artisan route:cache
            docker compose -f docker-compose.prod.yml exec php-fpm php artisan view:cache

            # Restart queue workers to pick up new code
            docker compose -f docker-compose.prod.yml restart queue

            # Health check
            sleep 10
            curl -f http://localhost/health || exit 1

            # Clean up old images
            docker image prune -af --filter "until=168h"

            echo "Deployment completed successfully!"
          ENDSSH

      - name: Notify on failure
        if: failure()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "Deployment failed for ${{ github.repository }}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Deployment Failed* :x:\nRepository: ${{ github.repository }}\nCommit: ${{ github.sha }}\nBranch: ${{ github.ref_name }}"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
```

---

## Security Hardening Checklist

### Container Security
- [ ] All containers run as non-root users
- [ ] No containers have `privileged: true`
- [ ] `security_opt: no-new-privileges:true` enabled
- [ ] Capabilities dropped with `cap_drop: ALL`
- [ ] Read-only root filesystem where possible (`read_only: true`)
- [ ] Resource limits defined for all containers

### Network Security
- [ ] Backend network marked as `internal: true`
- [ ] Database and Redis not exposed to host in production
- [ ] Rate limiting configured in Nginx
- [ ] Cloudflare IP restoration configured

### Secrets Management
- [ ] No secrets in environment variables in production
- [ ] Docker secrets used for all sensitive data
- [ ] Secrets files excluded from git (`.gitignore`)
- [ ] Backup encryption key stored securely

### PHP Security
- [ ] `display_errors = Off` in production
- [ ] `expose_php = Off`
- [ ] `allow_url_fopen = Off`
- [ ] `allow_url_include = Off`
- [ ] Dangerous functions disabled
- [ ] `open_basedir` restriction set
- [ ] Session cookies: `httponly`, `secure`, `samesite=Strict`

### Nginx Security
- [ ] `server_tokens off` to hide version
- [ ] Security headers configured (X-Frame-Options, X-Content-Type-Options, etc.)
- [ ] CSP header configured
- [ ] Sensitive file/directory access blocked
- [ ] Rate limiting zones configured
- [ ] Request body size limits set

### Application Security
- [ ] `.env` files excluded from git
- [ ] APP_DEBUG=false in production
- [ ] HTTPS enforced (via Cloudflare)
- [ ] Database credentials use Docker secrets
- [ ] Redis requires authentication in production

### Backup Security
- [ ] Backups stored in Azure Blob Storage
- [ ] Azure Blob Storage access via managed keys
- [ ] Backup retention policy enforced
- [ ] Local backup directory permissions restricted

---

## Implementation Steps

### Phase 1: Project Setup
1. Create directory structure as outlined above
2. Initialize git repository with proper `.gitignore`
3. Create Laravel 12 boilerplate in `src/` directory:
   ```bash
   composer create-project laravel/laravel src
   ```

### Phase 2: Docker Configuration
4. Create `docker/common/php-fpm/Dockerfile` (multi-stage)
5. Create `docker/development/nginx/nginx.conf`
6. Create `docker/development/workspace/Dockerfile`
7. Create `docker-compose.yml` for local development
8. Test local development environment

### Phase 3: Production Hardening
9. Create `docker/production/nginx/nginx.conf` (hardened)
10. Create `docker/production/nginx/Dockerfile`
11. Create `docker/production/php/php-production.ini`
12. Create entrypoint scripts
13. Create `docker-compose.prod.yml` with secrets

### Phase 4: Secrets and Backup
14. Create secrets directory structure
15. Generate production secrets
16. Create backup scripts
17. Configure Azure Blob Storage connection

### Phase 5: CI/CD Pipeline
18. Create GitHub Actions workflow
19. Configure GitHub repository secrets
20. Set up deployment environment
21. Test deployment pipeline

### Phase 6: Azure VM Preparation
22. Provision Ubuntu VM in Azure
23. Install Docker and Docker Compose
24. Configure firewall (allow ports 80, 443, 22)
25. Set up DNS and Cloudflare proxy
26. Deploy secrets to production server
27. First deployment

---

## Verification Plan

### 1. Local Development Verification
```bash
# Start all services
docker compose up -d

# Check all containers are running
docker compose ps

# Verify health endpoint
curl http://localhost/health

# Run Laravel tests
docker compose exec php-fpm php artisan test

# Check database connection
docker compose exec php-fpm php artisan db:show

# Verify Redis connection
docker compose exec php-fpm php artisan tinker --execute="Redis::ping()"
```

### 2. Production Build Verification
```bash
# Build production images locally
docker compose -f docker-compose.prod.yml build

# Start production stack
docker compose -f docker-compose.prod.yml up -d

# Verify all services healthy
docker compose -f docker-compose.prod.yml ps
```

### 3. CI/CD Pipeline Verification
- Push to `main` branch
- Monitor GitHub Actions workflow
- Verify test job passes
- Verify build job creates and pushes images
- Verify deploy job succeeds
- Check production site responds to health check

### 4. Backup Verification
```bash
# Trigger manual backup
docker compose -f docker-compose.prod.yml exec backup /backup.sh

# Verify local backup file exists
ls -la /opt/laravel/backups/

# Verify Azure Blob upload (using Azure CLI)
az storage blob list --account-name <account> --container-name backups
```

---

## GitHub Repository Secrets Required

| Secret Name | Description |
|-------------|-------------|
| `SSH_PRIVATE_KEY` | SSH private key for Azure VM access |
| `SSH_KNOWN_HOSTS` | SSH host verification |
| `SERVER_HOST` | Azure VM IP address or hostname |
| `SERVER_USER` | SSH username for deployment |
| `SLACK_WEBHOOK_URL` | (Optional) Slack notification webhook |

---

## Production Server Setup Commands

```bash
# Install Docker on Ubuntu
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create application directory
sudo mkdir -p /opt/laravel
sudo chown $USER:$USER /opt/laravel

# Configure firewall
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# Create secrets directory
mkdir -p /opt/laravel/secrets
chmod 700 /opt/laravel/secrets

# Generate secrets (run these and save output to secret files)
php artisan key:generate --show > /opt/laravel/secrets/app_key.txt
openssl rand -base64 32 > /opt/laravel/secrets/db_password.txt
openssl rand -base64 32 > /opt/laravel/secrets/redis_password.txt
echo "laravel" > /opt/laravel/secrets/db_username.txt
```

---

## References

- [Laravel 12 Documentation](https://laravel.com/docs/12.x)
- [PostgreSQL 18 Release Notes](https://www.postgresql.org/about/news/postgresql-18-beta-1-released-3070/)
- [Docker Compose Networking](https://docs.docker.com/compose/how-tos/networking/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Nginx Security Hardening](https://www.digitalocean.com/community/tutorials/php-fpm-nginx)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
