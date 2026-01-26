# Multi-Laravel Application Docker Setup

This guide documents the Docker infrastructure for running multiple Laravel applications with shared services.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Current Setup](#current-setup)
- [Adding a New Application](#adding-a-new-application)
  - [Using the Add-App Script (Recommended)](#using-the-add-app-script-recommended)
  - [Manual Setup](#manual-setup)
- [Configuration Reference](#configuration-reference)
- [Renaming an App Folder](#renaming-an-app-folder)
- [Verification Commands](#verification-commands)
- [Troubleshooting](#troubleshooting)

---

## Overview

This infrastructure allows multiple Laravel applications to run simultaneously, sharing common services (PostgreSQL, Redis, PHP-FPM) while maintaining complete isolation for data and queues.

### Architecture Diagram

```
                                    ┌─────────────────────────────────────────┐
                                    │              Host Machine               │
                                    └─────────────────────────────────────────┘
                                                      │
                           ┌──────────────────────────┼──────────────────────────┐
                           │                          │                          │
                      Port 80                    Port 8081                  Port 8082...
                           │                          │                          │
                           ▼                          ▼                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    Nginx (laravel-nginx)                                │
│  ┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐         │
│  │   Server :80        │    │   Server :8081      │    │   Server :8082      │   ...   │
│  │   root: /var/www/   │    │   root: /var/www/   │    │   root: /var/www/   │         │
│  │         public      │    │         app2/public │    │         app3/public │         │
│  └─────────────────────┘    └─────────────────────┘    └─────────────────────┘         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            ▼ FastCGI :9000
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                  PHP-FPM (laravel-php)                                  │
│  Volumes:   ./src → /var/www       ./apps/app2 → /var/www/app2                          │
│  Environment: Shared connection settings, app-specific via fastcgi_params               │
└─────────────────────────────────────────────────────────────────────────────────────────┘
           │                                                       │
           ▼                                                       ▼
┌─────────────────────────────┐                    ┌─────────────────────────────┐
│   PostgreSQL (laravel-      │                    │     Redis (laravel-redis)   │
│         postgres)           │                    │                             │
│  ┌───────────┬───────────┐  │                    │  ┌─────────┬─────────┐      │
│  │  laravel  │  app2_db  │  │                    │  │  DB 0   │  DB 1   │      │
│  │  (primary)│ (app2)    │  │                    │  │ (primary│  (app2) │ ...  │
│  └───────────┴───────────┘  │                    │  └─────────┴─────────┘      │
└─────────────────────────────┘                    └─────────────────────────────┘
           │                                                       │
           ▼                                                       ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    Queue Workers                                         │
│  ┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐         │
│  │   queue (laravel-   │    │   queue-app2        │    │   queue-app3        │   ...   │
│  │   queue)            │    │   (laravel-queue-   │    │   (laravel-queue-   │         │
│  │   --queue=default   │    │   app2)             │    │   app3)             │         │
│  │   DB: laravel       │    │   --queue=app2      │    │   --queue=app3      │         │
│  │   Redis DB: 0       │    │   DB: app2_db       │    │   DB: app3_db       │         │
│  └─────────────────────┘    │   Redis DB: 1       │    │   Redis DB: 2       │         │
│                             └─────────────────────┘    └─────────────────────┘         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Application Summary

| Application | Directory | Port | Database | Redis DB | Queue Name |
|-------------|-----------|------|----------|----------|------------|
| Primary     | `src/`    | 80   | `laravel` | 0       | `default`  |
| App2        | `apps/app2/` | 8081 | `app2_db` | 1     | `app2`     |

### Benefits

- **Shared Infrastructure**: Single PostgreSQL and Redis instance serves all apps
- **Resource Efficient**: One PHP-FPM pool handles all apps
- **Simple Access**: Each app has its own port (no virtual hosts needed)
- **Complete Isolation**: Separate databases, Redis DBs, and queue names
- **Independent Deployment**: Apps can be updated without affecting others

---

## Architecture

### How Nginx Routes Traffic

Nginx uses port-based routing. Each application has a dedicated server block listening on a unique port:

```nginx
# Primary app - Port 80
server {
    listen 80;
    root /var/www/public;
    # ...
}

# Secondary app - Port 8081
server {
    listen 8081;
    root /var/www/app2/public;
    # Passes app-specific environment via fastcgi_params
    # ...
}
```

App-specific environment variables are passed via `fastcgi_param` directives in the nginx config, overriding the defaults for each application.

### How PostgreSQL Creates Multiple Databases

The `docker/scripts/postgres/init-databases.sh` script runs on container initialization and creates additional databases specified in the `POSTGRES_MULTIPLE_DATABASES` environment variable:

```yaml
# docker-compose.yml
postgres:
  environment:
    POSTGRES_DB: laravel                    # Primary database
    POSTGRES_MULTIPLE_DATABASES: app2_db    # Additional databases (comma-separated)
```

The script:
1. Reads the comma-separated list from `POSTGRES_MULTIPLE_DATABASES`
2. Creates each database if it doesn't exist
3. Grants the default user full privileges

**Important**: This script only runs when the PostgreSQL data volume is first initialized. If you add a new database, you must either:
- Remove the volume and recreate: `docker compose down -v && docker compose up -d`
- Or manually create the database: `docker compose exec postgres createdb -U laravel newdb`

### How Redis Isolation Works

Redis isolation uses two mechanisms:

1. **Database Index**: Redis supports 16 databases (0-15). Each app uses a different DB number:
   - Primary app: DB 0 (default)
   - App2: DB 1
   - App3: DB 2, etc.

2. **Key Prefixes**: All Redis keys are prefixed to prevent collisions:
   - Primary app: No prefix (or `laravel_`)
   - App2: `app2_` prefix

Configuration in `.env`:
```env
REDIS_DB=1           # Database index
REDIS_PREFIX=app2_   # Key prefix
CACHE_PREFIX=app2_cache_
```

### How Queue Workers Are Isolated

Each application has a dedicated queue worker service with:

1. **Separate Container**: Independent worker per app
2. **Unique Queue Name**: `--queue=app2` flag
3. **App-Specific Directory**: `working_dir: /var/www/app2`
4. **Dedicated Environment**: Correct database and Redis settings

```yaml
queue-app2:
  working_dir: /var/www/app2
  command: php artisan queue:work redis --queue=app2 --sleep=3 --tries=3
  environment:
    DB_DATABASE: app2_db
    REDIS_DB: 1
    QUEUE_QUEUE: app2
```

---

## Current Setup

### Primary Application (`src/`)

- **URL**: http://localhost
- **Port**: 80
- **Database**: `laravel`
- **Redis**: DB 0, no prefix
- **Queue**: `default`
- **Queue Worker**: `laravel-queue`

### Secondary Application (`apps/app2/`)

- **URL**: http://localhost:8081
- **Port**: 8081
- **Database**: `app2_db`
- **Redis**: DB 1, prefix `app2_`
- **Queue**: `app2`
- **Queue Worker**: `laravel-queue-app2`

---

## Adding a New Application

There are two ways to add a new application: using the automated script (recommended) or manually configuring the files.

### Using the Add-App Script (Recommended)

The `add-app.sh` script automates all the configuration steps required to add a new application.

#### Script Location

```bash
docker/scripts/add-app.sh
```

#### Usage

```bash
./docker/scripts/add-app.sh <app-name> [port] [redis-db]
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `app-name` | Yes | Name of the app (lowercase, alphanumeric, hyphens/underscores allowed) |
| `port` | No | HTTP port (auto-calculated from existing apps if omitted) |
| `redis-db` | No | Redis database index 0-15 (auto-calculated if omitted) |

#### Examples

```bash
# Add app3 with auto-detected port and Redis DB
./docker/scripts/add-app.sh app3

# Add an admin app on port 8085 with Redis DB 5
./docker/scripts/add-app.sh admin 8085 5

# Add an API service
./docker/scripts/add-app.sh my-api
```

#### What the Script Does

1. **Validates inputs**: Checks app name format, port availability, and Redis DB conflicts
2. **Updates docker-compose.yml**:
   - Adds port mapping to nginx service
   - Adds volume mounts to nginx and php-fpm services
   - Appends database to `POSTGRES_MULTIPLE_DATABASES`
   - Adds queue worker service
3. **Updates nginx.conf**: Inserts a new server block with app-specific configuration
4. **Creates files**:
   - `apps/<app-name>/` directory
   - `apps/<app-name>/.env` with pre-configured settings

#### After Running the Script

The script will display next steps, which include:

1. **Install Laravel**:
   ```bash
   cd apps/<app-name> && composer create-project laravel/laravel . --prefer-dist
   ```

2. **Initialize the database** (choose one):
   ```bash
   # Option A: Recreate volumes (loses all data)
   docker compose down -v && docker compose up -d

   # Option B: Manually create database
   docker compose exec postgres createdb -U laravel <app-name>_db
   ```

3. **Start services**:
   ```bash
   docker compose up -d
   ```

4. **Generate application key**:
   ```bash
   docker compose exec php-fpm php /var/www/<app-name>/artisan key:generate
   ```

5. **Run migrations**:
   ```bash
   docker compose exec php-fpm php /var/www/<app-name>/artisan migrate
   ```

6. **Verify**: Visit `http://localhost:<port>`

#### Backup Files

The script creates backup files before making changes:
- `docker-compose.yml.bak`
- `docker/development/nginx/nginx.conf.bak`

If something goes wrong, restore from these backups.

---

### Manual Setup

Follow these steps if you prefer to manually configure the files, or need to understand what the script does. This example adds `app3`.

#### Step 1: Create the Application Directory

```bash
mkdir -p apps/app3
cd apps/app3
```

#### Step 2: Install Laravel

```bash
composer create-project laravel/laravel . --prefer-dist
```

Or if you're copying an existing app:
```bash
cp -r /path/to/existing/laravel/* .
composer install
```

#### Step 3: Update docker-compose.yml

Make the following changes to `docker-compose.yml`:

##### 3a. Add Port to Nginx Service

```yaml
nginx:
  ports:
    - "${NGINX_PORT:-80}:80"
    - "${NGINX_PORT_APP2:-8081}:8081"
    - "${NGINX_PORT_APP3:-8082}:8082"    # Add this line
```

##### 3b. Add Volume Mount to Nginx

```yaml
nginx:
  volumes:
    - ./src:/var/www:ro
    - ./apps/app2:/var/www/app2:ro
    - ./apps/app3:/var/www/app3:ro       # Add this line
    - ./docker/development/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
```

##### 3c. Add Volume Mount to PHP-FPM

```yaml
php-fpm:
  volumes:
    - ./src:/var/www
    - ./apps/app2:/var/www/app2
    - ./apps/app3:/var/www/app3          # Add this line
    - ./docker/development/php/php.ini:/usr/local/etc/php/conf.d/custom.ini:ro
```

##### 3d. Add Database to PostgreSQL

```yaml
postgres:
  environment:
    POSTGRES_MULTIPLE_DATABASES: app2_db,app3_db    # Add app3_db
```

##### 3e. Add Queue Worker Service

Add this new service at the end of the services section:

```yaml
  # ---------------------------------------------------------------------------
  # Queue Worker - App3 (apps/app3/)
  # ---------------------------------------------------------------------------
  queue-app3:
    build:
      context: .
      dockerfile: docker/common/php-fpm/Dockerfile
      target: development
    container_name: laravel-queue-app3
    restart: unless-stopped
    working_dir: /var/www/app3
    command: php artisan queue:work redis --queue=app3 --sleep=3 --tries=3 --max-time=3600 --verbose
    volumes:
      - ./apps/app3:/var/www/app3
      - ./docker/development/php/php.ini:/usr/local/etc/php/conf.d/custom.ini:ro
    environment:
      - APP_ENV=${APP_ENV:-local}
      - APP_DEBUG=${APP_DEBUG:-true}
      - APP_KEY=${APP3_KEY:-}
      - DB_CONNECTION=pgsql
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=app3_db
      - DB_USERNAME=${DB_USERNAME:-laravel}
      - DB_PASSWORD=${DB_PASSWORD:-secret}
      - REDIS_CLIENT=phpredis
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=${REDIS_PASSWORD:-}
      - REDIS_DB=2
      - REDIS_PREFIX=app3_
      - CACHE_STORE=redis
      - CACHE_PREFIX=app3_cache_
      - QUEUE_CONNECTION=redis
      - QUEUE_QUEUE=app3
      - LOG_CHANNEL=stack
      - LOG_LEVEL=debug
    depends_on:
      php-fpm:
        condition: service_healthy
    networks:
      - backend
```

#### Step 4: Update nginx.conf

Add a new server block in `docker/development/nginx/nginx.conf`:

```nginx
    # =========================================================================
    # App3 - Port 8082 (apps/app3/)
    # =========================================================================
    server {
        listen 8082;
        server_name localhost;
        root /var/www/app3/public;
        index index.php index.html;

        charset utf-8;

        # Health check endpoint (bypasses PHP)
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # Laravel routing
        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }

        # Disable logging for common static files
        location = /favicon.ico { access_log off; log_not_found off; }
        location = /robots.txt  { access_log off; log_not_found off; }

        # Custom 404 handling via Laravel
        error_page 404 /index.php;

        # PHP-FPM configuration
        location ~ \.php$ {
            fastcgi_pass php-fpm:9000;
            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
            include fastcgi_params;

            # App-specific environment overrides
            fastcgi_param DB_DATABASE app3_db;
            fastcgi_param REDIS_DB 2;
            fastcgi_param REDIS_PREFIX app3_;
            fastcgi_param CACHE_PREFIX app3_cache_;
            fastcgi_param QUEUE_QUEUE app3;

            # Hide PHP version
            fastcgi_hide_header X-Powered-By;

            # Development timeouts (longer for debugging with Xdebug)
            fastcgi_connect_timeout 300;
            fastcgi_send_timeout 300;
            fastcgi_read_timeout 300;

            # Buffer settings for larger responses
            fastcgi_buffer_size 128k;
            fastcgi_buffers 256 16k;
            fastcgi_busy_buffers_size 256k;
        }

        # Deny access to hidden files (except .well-known)
        location ~ /\.(?!well-known).* {
            deny all;
        }

        # Deny access to sensitive files
        location ~ /\.(env|git|htaccess|htpasswd) {
            deny all;
        }
    }
```

#### Step 5: Create the .env File

Create `apps/app3/.env` with app-specific settings:

```env
# =============================================================================
# Docker Local Development Environment - App3
# =============================================================================

# -----------------------------------------------------------------------------
# Application Settings
# -----------------------------------------------------------------------------
APP_NAME="Laravel App3"
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_TIMEZONE=UTC
APP_URL=http://localhost:8082

# Locale
APP_LOCALE=en
APP_FALLBACK_LOCALE=en
APP_FAKER_LOCALE=en_US

# Maintenance mode driver
APP_MAINTENANCE_DRIVER=file

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
LOG_CHANNEL=stack
LOG_STACK=single
LOG_DEPRECATIONS_CHANNEL=null
LOG_LEVEL=debug

# -----------------------------------------------------------------------------
# Database (PostgreSQL)
# -----------------------------------------------------------------------------
DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=app3_db
DB_USERNAME=laravel
DB_PASSWORD=secret

# -----------------------------------------------------------------------------
# Session
# -----------------------------------------------------------------------------
SESSION_DRIVER=redis
SESSION_LIFETIME=120
SESSION_ENCRYPT=false
SESSION_PATH=/
SESSION_DOMAIN=null

# -----------------------------------------------------------------------------
# Cache
# -----------------------------------------------------------------------------
CACHE_STORE=redis
CACHE_PREFIX=app3_cache_

# -----------------------------------------------------------------------------
# Queue
# -----------------------------------------------------------------------------
QUEUE_CONNECTION=redis
QUEUE_QUEUE=app3

# -----------------------------------------------------------------------------
# Redis
# -----------------------------------------------------------------------------
REDIS_CLIENT=phpredis
REDIS_HOST=redis
REDIS_PASSWORD=
REDIS_PORT=6379
REDIS_DB=2
REDIS_PREFIX=app3_

# -----------------------------------------------------------------------------
# Mail (log for development)
# -----------------------------------------------------------------------------
MAIL_MAILER=log
```

#### Step 6: Initialize the Database

If this is a fresh setup, recreate volumes to run the init script:

```bash
docker compose down -v
docker compose up -d
```

Or manually create the database:

```bash
docker compose exec postgres createdb -U laravel app3_db
```

#### Step 7: Generate Application Key

```bash
docker compose exec php-fpm php /var/www/app3/artisan key:generate
```

#### Step 8: Run Migrations

```bash
docker compose exec php-fpm php /var/www/app3/artisan migrate
```

#### Step 9: Restart Services

```bash
docker compose up -d
```

#### Step 10: Verify

Visit http://localhost:8082 to confirm the app is running.

---

## Configuration Reference

### Environment Variables Per App

| Variable | Primary (`src/`) | App2 | App3 |
|----------|------------------|------|------|
| `APP_URL` | `http://localhost` | `http://localhost:8081` | `http://localhost:8082` |
| `DB_DATABASE` | `laravel` | `app2_db` | `app3_db` |
| `REDIS_DB` | `0` | `1` | `2` |
| `REDIS_PREFIX` | (none) | `app2_` | `app3_` |
| `CACHE_PREFIX` | (none) | `app2_cache_` | `app3_cache_` |
| `QUEUE_QUEUE` | `default` | `app2` | `app3` |

### Port Assignments

| Port | Application | Environment Variable |
|------|-------------|---------------------|
| 80   | Primary     | `NGINX_PORT` |
| 8081 | App2        | `NGINX_PORT_APP2` |
| 8082 | App3        | `NGINX_PORT_APP3` |
| ...  | ...         | `NGINX_PORT_APPN` |

### Naming Conventions

| Resource | Convention | Example (App3) |
|----------|------------|----------------|
| Directory | `apps/{name}/` | `apps/app3/` |
| Database | `{name}_db` | `app3_db` |
| Redis DB | Sequential (0, 1, 2...) | `2` |
| Redis Prefix | `{name}_` | `app3_` |
| Cache Prefix | `{name}_cache_` | `app3_cache_` |
| Queue Name | `{name}` | `app3` |
| Container (queue) | `laravel-queue-{name}` | `laravel-queue-app3` |

---

## Renaming an App Folder

If you need to rename an app folder (e.g., `app2` to `admin`), update these locations:

### docker-compose.yml (4 locations)

1. **Nginx volumes**: `./apps/app2:/var/www/app2:ro` → `./apps/admin:/var/www/admin:ro`
2. **PHP-FPM volumes**: `./apps/app2:/var/www/app2` → `./apps/admin:/var/www/admin`
3. **Queue worker volumes**: `./apps/app2:/var/www/app2` → `./apps/admin:/var/www/admin`
4. **Queue worker working_dir**: `/var/www/app2` → `/var/www/admin`

### nginx.conf (1 location)

- **Server block root**: `root /var/www/app2/public;` → `root /var/www/admin/public;`

### Optional: Update naming for clarity

- Container name: `laravel-queue-app2` → `laravel-queue-admin`
- Database name: `app2_db` → `admin_db`
- Queue name: `app2` → `admin`
- Redis prefix: `app2_` → `admin_`

---

## Verification Commands

### Check All Services Are Running

```bash
docker compose ps
```

Expected output shows all services as "healthy" or "running".

### Verify Databases Exist

```bash
docker compose exec postgres psql -U laravel -c "\l"
```

Expected output includes `laravel`, `app2_db`, and any other configured databases.

### Test Application URLs

```bash
# Primary app
curl -s http://localhost/health

# App2
curl -s http://localhost:8081/health

# App3 (if configured)
curl -s http://localhost:8082/health
```

Each should return `healthy`.

### Verify Redis Isolation

```bash
# Check keys in DB 0 (primary app)
docker compose exec redis redis-cli -n 0 KEYS "*"

# Check keys in DB 1 (app2)
docker compose exec redis redis-cli -n 1 KEYS "*"
```

Keys should be isolated to their respective databases with appropriate prefixes.

### Check Queue Workers

```bash
# View queue worker logs
docker compose logs queue
docker compose logs queue-app2
```

### Test Queue Processing

From within each app:

```bash
# Primary app
docker compose exec php-fpm php artisan tinker --execute="dispatch(new App\Jobs\TestJob)"

# App2
docker compose exec php-fpm php /var/www/app2/artisan tinker --execute="dispatch(new App\Jobs\TestJob)"
```

---

## Troubleshooting

### Database Not Created

**Symptom**: Application shows "database does not exist" error.

**Cause**: The PostgreSQL init script only runs on first volume initialization.

**Solution**:
```bash
# Option 1: Recreate volumes (loses all data)
docker compose down -v
docker compose up -d

# Option 2: Manually create the database
docker compose exec postgres createdb -U laravel app3_db
```

### Port Conflict

**Symptom**: `Error starting userland proxy: listen tcp 0.0.0.0:8081: bind: address already in use`

**Solution**:
1. Find what's using the port: `netstat -tulpn | grep 8081`
2. Stop the conflicting service, or
3. Use a different port in `docker-compose.yml`

### Permission Issues

**Symptom**: `Permission denied` errors in logs or when accessing files.

**Solution**:
```bash
# Fix permissions on app directory
sudo chown -R $USER:$USER apps/app3
chmod -R 755 apps/app3
chmod -R 775 apps/app3/storage apps/app3/bootstrap/cache
```

### Nginx Configuration Errors

**Symptom**: Nginx container fails to start or returns 502 errors.

**Solution**:
```bash
# Test nginx configuration
docker compose exec nginx nginx -t

# Check nginx logs
docker compose logs nginx
```

Common issues:
- Missing semicolon in config
- Incorrect `root` path
- Duplicate `listen` directives

### App Key Not Set

**Symptom**: `No application encryption key has been specified.`

**Solution**:
```bash
docker compose exec php-fpm php /var/www/app3/artisan key:generate
```

### Queue Jobs Not Processing

**Symptom**: Jobs stay in queue, worker not picking them up.

**Checklist**:
1. Verify queue worker is running: `docker compose ps queue-app3`
2. Check worker logs: `docker compose logs queue-app3`
3. Verify `QUEUE_QUEUE` matches in both `.env` and `docker-compose.yml`
4. Verify Redis connection settings are correct

### Redis Keys Colliding

**Symptom**: Applications seem to share cache or session data unexpectedly.

**Solution**: Verify each app has unique:
- `REDIS_DB` (database index)
- `REDIS_PREFIX`
- `CACHE_PREFIX`

Check current configuration:
```bash
# In app's tinker
config('database.redis.default.database')
config('database.redis.default.prefix')
config('cache.prefix')
```

### Changes to docker-compose.yml Not Taking Effect

**Solution**:
```bash
# Recreate containers with new configuration
docker compose up -d --force-recreate
```

### Changes to nginx.conf Not Taking Effect

**Solution**:
```bash
# Reload nginx configuration
docker compose exec nginx nginx -s reload

# Or restart the container
docker compose restart nginx
```
