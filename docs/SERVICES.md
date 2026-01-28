# Services Configuration

This document provides detailed configuration information for each service in the application stack.

## Table of Contents

- [Nginx Web Server](#nginx-web-server)
- [PHP-FPM Application Server](#php-fpm-application-server)
- [PostgreSQL Database](#postgresql-database)
- [Redis Cache and Queue](#redis-cache-and-queue)
- [Queue Worker](#queue-worker)
- [Backup Service](#backup-service)

---

## Nginx Web Server

### Overview

Nginx serves as the reverse proxy and static file server for the application.

| Property | Value |
|----------|-------|
| Image | `nginx:1.27-alpine` |
| Container Name | `laravel-nginx` |
| Exposed Port | 80 |
| Networks | frontend, backend |

### Development Configuration

**File**: `docker/development/nginx/nginx.conf`

```nginx
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # Performance settings
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
    gzip_types text/plain text/css text/xml application/json
               application/javascript application/xml+rss
               application/atom+xml image/svg+xml;

    # PHP-FPM upstream
    upstream php-fpm {
        server php-fpm:9000;
    }

    server {
        listen 80;
        server_name _;
        root /var/www/public;
        index index.php index.html;

        # Health check endpoint
        location = /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # Main location
        location / {
            try_files $uri $uri/ /index.php?$query_string;
        }

        # PHP handling
        location ~ \.php$ {
            fastcgi_pass php-fpm;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
            include fastcgi_params;

            # Extended timeouts for Xdebug
            fastcgi_read_timeout 300;
            fastcgi_send_timeout 300;
        }

        # Block hidden files
        location ~ /\. {
            deny all;
            access_log off;
            log_not_found off;
        }

        # Block sensitive files
        location ~* \.(env|git|htaccess|htpasswd)$ {
            deny all;
            access_log off;
            log_not_found off;
        }
    }
}
```

### Production Configuration

**File**: `docker/production/nginx/nginx.conf`

Additional production features:

#### Worker Optimization

```nginx
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}
```

#### Security Headers

```nginx
# Security headers
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=(), usb=(), magnetometer=(), gyroscope=(), accelerometer=()" always;

# Content Security Policy
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'self';" always;
```

#### Rate Limiting

```nginx
# Rate limiting zones
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
limit_conn_zone $binary_remote_addr zone=conn:10m;

# Apply rate limiting
location /api/ {
    limit_req zone=api burst=20 nodelay;
    limit_conn conn 10;
    # ... rest of config
}

location /login {
    limit_req zone=login burst=5 nodelay;
    # ... rest of config
}
```

#### Cloudflare Real IP Restoration

```nginx
# Cloudflare IP ranges
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

# IPv6
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;

real_ip_header CF-Connecting-IP;
```

#### Static File Caching

```nginx
# Images - long cache
location ~* \.(jpg|jpeg|png|gif|ico|webp|svg)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    access_log off;
}

# CSS/JS - long cache with versioning
location ~* \.(css|js)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    access_log off;
}

# Fonts
location ~* \.(woff|woff2|ttf|otf|eot)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    add_header Access-Control-Allow-Origin "*";
    access_log off;
}
```

---

## PHP-FPM Application Server

### Overview

PHP-FPM executes PHP code and runs the Laravel application.

| Property | Value |
|----------|-------|
| Base Image | `php:8.4-fpm-alpine` |
| Container Name | `laravel-php` |
| Internal Port | 9000 |
| Networks | backend |

### PHP Extensions

| Extension | Purpose |
|-----------|---------|
| `pdo` | Database abstraction |
| `pdo_pgsql` | PostgreSQL PDO driver |
| `pgsql` | PostgreSQL functions |
| `gd` | Image manipulation |
| `zip` | ZIP archive support |
| `intl` | Internationalization |
| `mbstring` | Multibyte string handling |
| `bcmath` | Arbitrary precision math |
| `opcache` | Bytecode caching |
| `pcntl` | Process control |
| `exif` | Image metadata |
| `redis` | Redis connectivity |
| `xdebug` | Debugging (dev only) |

### Development PHP Settings

**File**: `docker/development/php/php.ini`

```ini
[PHP]
; Error handling - verbose for development
display_errors = On
display_startup_errors = On
error_reporting = E_ALL
log_errors = On

; Resource limits - generous for development
memory_limit = 512M
max_execution_time = 300
max_input_time = 300

; File uploads
upload_max_filesize = 64M
post_max_size = 68M
max_file_uploads = 20

; Session
session.gc_maxlifetime = 1440
session.cookie_httponly = On

[opcache]
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 1    ; Reload on file changes
opcache.revalidate_freq = 0

[date]
date.timezone = UTC
```

### Production PHP Settings

**File**: `docker/production/php/php-production.ini`

```ini
[PHP]
; Error handling - secure for production
display_errors = Off
display_startup_errors = Off
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
log_errors = On
error_log = /var/log/php/error.log

; Security
expose_php = Off
allow_url_fopen = Off
allow_url_include = Off
cgi.fix_pathinfo = 0

; Disabled dangerous functions
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,highlight_file,phpinfo

; Restricted paths
open_basedir = /var/www:/tmp

; Resource limits - conservative for production
memory_limit = 256M
max_execution_time = 30
max_input_time = 60

; File uploads
upload_max_filesize = 32M
post_max_size = 34M
max_file_uploads = 10

[Session]
session.use_only_cookies = On
session.use_strict_mode = On
session.cookie_httponly = On
session.cookie_secure = On
session.cookie_samesite = Strict
session.name = __Secure_LARAVELSESSID
session.gc_maxlifetime = 1440

[opcache]
opcache.enable = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 20000
opcache.validate_timestamps = 0    ; No reload in production
opcache.save_comments = 1
opcache.fast_shutdown = 1

; JIT compilation (PHP 8.0+)
opcache.jit_buffer_size = 100M
opcache.jit = 1255

[date]
date.timezone = UTC
```

### Entrypoint Script

**File**: `docker/scripts/entrypoint/php-fpm-entrypoint.sh`

```bash
#!/bin/sh
set -e

echo "Starting PHP-FPM container..."

# Secrets are loaded from the .env file which is decrypted during deployment
# using Laravel's env:decrypt command. No need to manually load secrets here.
# All environment variables are passed via Docker Compose env_file directive.

# Wait for PostgreSQL
echo "Waiting for PostgreSQL..."
MAX_ATTEMPTS=30
ATTEMPT=0
until pg_isready -h ${DB_HOST:-postgres} -p ${DB_PORT:-5432} -U ${DB_USERNAME:-laravel} -d ${DB_DATABASE:-laravel} > /dev/null 2>&1; do
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        echo "PostgreSQL not available after $MAX_ATTEMPTS attempts, exiting..."
        exit 1
    fi
    echo "PostgreSQL not ready (attempt $ATTEMPT/$MAX_ATTEMPTS), waiting..."
    sleep 2
done
echo "PostgreSQL is ready!"

# Wait for Redis
echo "Waiting for Redis..."
MAX_ATTEMPTS=15
ATTEMPT=0
until redis-cli -h ${REDIS_HOST:-redis} -p ${REDIS_PORT:-6379} ping > /dev/null 2>&1; do
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        echo "Redis not available after $MAX_ATTEMPTS attempts, continuing anyway..."
        break
    fi
    echo "Redis not ready (attempt $ATTEMPT/$MAX_ATTEMPTS), waiting..."
    sleep 1
done
echo "Redis is ready!"

# Production-specific setup
if [ "$APP_ENV" = "production" ]; then
    echo "Running production optimizations..."

    # Clear and cache configurations
    php artisan config:clear
    php artisan route:clear
    php artisan view:clear
    php artisan event:clear

    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache

    # Run migrations if enabled
    if [ "$MIGRATE_ON_START" = "true" ]; then
        echo "Running database migrations..."
        php artisan migrate --force
    fi
fi

echo "Starting PHP-FPM..."
exec "$@"
```

---

## PostgreSQL Database

### Overview

PostgreSQL serves as the primary relational database.

| Property | Value |
|----------|-------|
| Image | `postgres:17-alpine` |
| Container Name | `laravel-postgres` |
| Internal Port | 5432 |
| Networks | backend |

### Configuration

**Environment Variables**:

```yaml
environment:
  POSTGRES_DB: ${DB_DATABASE:-laravel}
  POSTGRES_USER: ${DB_USERNAME:-laravel}
  POSTGRES_PASSWORD: ${DB_PASSWORD:-secret}
  PGDATA: /var/lib/postgresql/data/pgdata
```

### Laravel Database Configuration

**File**: `src/config/database.php`

```php
'pgsql' => [
    'driver' => 'pgsql',
    'url' => env('DB_URL'),
    'host' => env('DB_HOST', 'postgres'),
    'port' => env('DB_PORT', '5432'),
    'database' => env('DB_DATABASE', 'laravel'),
    'username' => env('DB_USERNAME', 'laravel'),
    'password' => env('DB_PASSWORD', ''),
    'charset' => env('DB_CHARSET', 'utf8'),
    'prefix' => '',
    'prefix_indexes' => true,
    'search_path' => 'public',
    'sslmode' => 'prefer',
],
```

### Database Migrations

Location: `src/database/migrations/`

Default migrations:
1. `0001_01_01_000000_create_users_table.php` - User authentication
2. `0001_01_01_000001_create_cache_table.php` - Database cache driver
3. `0001_01_01_000002_create_jobs_table.php` - Queue jobs storage

### Connection from PHP-FPM

```php
// Using Eloquent
$users = User::all();

// Using Query Builder
$users = DB::table('users')->get();

// Using raw PDO
$pdo = DB::connection()->getPdo();
```

---

## Redis Cache and Queue

### Overview

Redis provides in-memory caching, session storage, and queue backend.

| Property | Value |
|----------|-------|
| Image | `redis:7-alpine` |
| Container Name | `laravel-redis` |
| Internal Port | 6379 |
| Networks | backend |

### Development Command

```bash
redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
```

### Production Command

```bash
redis-server \
  --appendonly yes \
  --requirepass ${REDIS_PASSWORD} \
  --maxmemory 256mb \
  --maxmemory-policy allkeys-lru \
  --tcp-backlog 511 \
  --timeout 0 \
  --tcp-keepalive 300
```

Note: `REDIS_PASSWORD` is loaded from the encrypted `.env` file and passed via Docker Compose environment.

### Configuration Options

| Option | Value | Purpose |
|--------|-------|---------|
| `appendonly` | yes | Enable AOF persistence |
| `maxmemory` | 256mb | Maximum memory usage |
| `maxmemory-policy` | allkeys-lru | Eviction policy |
| `tcp-backlog` | 511 | TCP listen backlog |
| `tcp-keepalive` | 300 | Keep connections alive |

### Laravel Redis Configuration

**File**: `src/config/database.php`

```php
'redis' => [
    'client' => env('REDIS_CLIENT', 'phpredis'),
    'options' => [
        'cluster' => env('REDIS_CLUSTER', 'redis'),
        'prefix' => env('REDIS_PREFIX', Str::slug(env('APP_NAME', 'laravel'), '_').'_database_'),
    ],
    'default' => [
        'url' => env('REDIS_URL'),
        'host' => env('REDIS_HOST', 'redis'),
        'username' => env('REDIS_USERNAME'),
        'password' => env('REDIS_PASSWORD'),
        'port' => env('REDIS_PORT', '6379'),
        'database' => env('REDIS_DB', '0'),
    ],
    'cache' => [
        'url' => env('REDIS_URL'),
        'host' => env('REDIS_HOST', 'redis'),
        'username' => env('REDIS_USERNAME'),
        'password' => env('REDIS_PASSWORD'),
        'port' => env('REDIS_PORT', '6379'),
        'database' => env('REDIS_CACHE_DB', '1'),
    ],
],
```

### Laravel Cache Configuration

**File**: `src/config/cache.php`

```php
'redis' => [
    'driver' => 'redis',
    'connection' => env('REDIS_CACHE_CONNECTION', 'cache'),
    'lock_connection' => env('REDIS_CACHE_LOCK_CONNECTION', 'default'),
],
```

### Laravel Session Configuration

**File**: `src/config/session.php`

```php
'driver' => env('SESSION_DRIVER', 'redis'),
'connection' => env('SESSION_CONNECTION'),
```

### Laravel Queue Configuration

**File**: `src/config/queue.php`

```php
'redis' => [
    'driver' => 'redis',
    'connection' => env('REDIS_QUEUE_CONNECTION', 'default'),
    'queue' => env('REDIS_QUEUE', 'default'),
    'retry_after' => (int) env('REDIS_QUEUE_RETRY_AFTER', 90),
    'block_for' => null,
    'after_commit' => false,
],
```

### Usage Examples

```php
// Caching
Cache::put('key', 'value', now()->addMinutes(10));
$value = Cache::get('key');

// Sessions (automatic)
session(['key' => 'value']);
$value = session('key');

// Queuing jobs
dispatch(new ProcessPodcast($podcast));

// Direct Redis access
Redis::set('key', 'value');
$value = Redis::get('key');
```

---

## Queue Worker

### Overview

The queue worker processes background jobs from Redis.

| Property | Value |
|----------|-------|
| Image | Custom (same as PHP-FPM) |
| Container Name | `laravel-queue` |
| Networks | backend |

### Command

```bash
php artisan queue:work redis --sleep=3 --tries=3 --max-time=3600 --verbose
```

### Command Options

| Option | Value | Purpose |
|--------|-------|---------|
| `redis` | - | Queue connection to use |
| `--sleep=3` | 3 seconds | Wait time when no jobs |
| `--tries=3` | 3 attempts | Max retry attempts |
| `--max-time=3600` | 1 hour | Max worker runtime |
| `--verbose` | - | Detailed output |

### Queue Entrypoint Script

**File**: `docker/scripts/entrypoint/queue-entrypoint.sh`

```bash
#!/bin/sh
set -e

echo "Starting Queue Worker container..."

# Secrets are loaded from the .env file which is decrypted during deployment
# using Laravel's env:decrypt command. No need to manually load secrets here.
# All environment variables are passed via Docker Compose env_file directive.

# Wait for Redis (required for queue)
echo "Waiting for Redis..."
MAX_ATTEMPTS=30
ATTEMPT=0
until redis-cli -h ${REDIS_HOST:-redis} -p ${REDIS_PORT:-6379} ping > /dev/null 2>&1; do
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        echo "Redis not available after $MAX_ATTEMPTS attempts, exiting..."
        exit 1
    fi
    echo "Redis not ready (attempt $ATTEMPT/$MAX_ATTEMPTS), waiting..."
    sleep 2
done
echo "Redis is ready!"

# Wait for PostgreSQL (optional, for database jobs)
echo "Waiting for PostgreSQL..."
MAX_ATTEMPTS=30
ATTEMPT=0
until pg_isready -h ${DB_HOST:-postgres} -p ${DB_PORT:-5432} -U ${DB_USERNAME:-laravel} -d ${DB_DATABASE:-laravel} > /dev/null 2>&1; do
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        echo "PostgreSQL not available after $MAX_ATTEMPTS attempts, continuing..."
        break
    fi
    echo "PostgreSQL not ready (attempt $ATTEMPT/$MAX_ATTEMPTS), waiting..."
    sleep 2
done
echo "PostgreSQL is ready!"

# Wait for PHP-FPM to be healthy
echo "Waiting for PHP-FPM..."
sleep 15

echo "Starting queue worker..."
exec "$@"
```

### Creating Jobs

```php
// app/Jobs/ProcessPodcast.php
namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

class ProcessPodcast implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public $podcast;

    public function __construct(Podcast $podcast)
    {
        $this->podcast = $podcast;
    }

    public function handle(): void
    {
        // Process the podcast...
    }
}

// Dispatching
ProcessPodcast::dispatch($podcast);
```

---

## Backup Service

### Overview

Automated database backups in production using `jkaninda/pg-bkup`.

| Property | Value |
|----------|-------|
| Image | `jkaninda/pg-bkup:latest` |
| Container Name | `laravel-backup` |
| Networks | backend |

### Configuration

```yaml
backup:
  image: jkaninda/pg-bkup:latest
  container_name: laravel-backup
  environment:
    - DB_HOST=postgres
    - DB_PORT=5432
    - DB_NAME=${DB_DATABASE:-laravel}
    - STORAGE_PATH=/backup
    - BACKUP_CRON_EXPRESSION=0 2 * * *    # Daily at 2 AM
    - BACKUP_RETENTION_DAYS=30
    - AWS_S3_ENDPOINT=${AZURE_BLOB_ENDPOINT}
    - AWS_S3_BUCKET_NAME=${AZURE_CONTAINER_NAME}
  volumes:
    - backup_data:/backup
  env_file:
    - .env    # Secrets loaded from encrypted .env file
  networks:
    - backend
  depends_on:
    postgres:
      condition: service_healthy
```

### Backup Schedule

| Frequency | Time | Retention |
|-----------|------|-----------|
| Daily | 2:00 AM UTC | 30 days |

### Manual Backup

```bash
# Enter backup container
docker compose -f docker-compose.prod.yml exec backup sh

# Trigger manual backup
pg_dump -h postgres -U $DB_USERNAME -d $DB_DATABASE > /backup/manual_$(date +%Y%m%d_%H%M%S).sql
```

---

## Related Documentation

- [Architecture Overview](./ARCHITECTURE.md)
- [Docker Configuration](./DOCKER.md)
- [Deployment Guide](./DEPLOYMENT.md)
- [Development Guide](./DEVELOPMENT.md)
