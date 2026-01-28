# Development Guide

This document provides instructions for setting up and working with the local development environment.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Environment Setup](#environment-setup)
- [Development Workflow](#development-workflow)
- [Debugging with Xdebug](#debugging-with-xdebug)
- [Database Operations](#database-operations)
- [Testing](#testing)
- [Common Tasks](#common-tasks)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

| Software | Minimum Version | Recommended |
|----------|-----------------|-------------|
| Docker | 24.0 | Latest |
| Docker Compose | 2.20 | Latest |
| Git | 2.30 | Latest |

### Optional Software

| Software | Purpose |
|----------|---------|
| Node.js 22+ | Local frontend development |
| PHP 8.4+ | Local tooling (optional) |
| IDE with PHP support | PHPStorm, VS Code |

### System Requirements

- **Memory**: 4GB RAM minimum (8GB recommended)
- **Storage**: 5GB free space
- **CPU**: 2 cores minimum (4 recommended)

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/laravel.git
cd laravel
```

### 2. Copy Environment Files

The project uses two environment files:
- **Root `.env`** - Docker Compose settings (ports, credentials for containers)
- **`src/.env`** - Laravel application configuration

```bash
# Root level (Docker Compose)
cp .env.example .env

# Laravel application
cp src/.env.example src/.env
```

Generate and set a secure database password in **both** files:

```bash
# Generate a password
openssl rand -base64 32

# Edit both .env files and set DB_PASSWORD to the same value
```

### 3. Start the Development Environment

```bash
docker compose up -d
```

### 4. Install Dependencies and Setup

```bash
# Install Composer dependencies
docker compose exec php-fpm composer install

# Generate application key (writes to src/.env)
docker compose exec php-fpm php artisan key:generate

# IMPORTANT: Copy the APP_KEY to root .env for Docker Compose
# Get the generated key:
grep APP_KEY src/.env
# Add it to your root .env file (edit .env and set APP_KEY=base64:...)

# Restart to apply APP_KEY from root .env
docker compose down && docker compose up -d

# Run database migrations
docker compose exec php-fpm php artisan migrate

# Install NPM dependencies (optional, for frontend)
docker compose exec php-fpm npm install

# Build frontend assets (optional)
docker compose exec php-fpm npm run build
```

**Note:** The APP_KEY must be in both the root `.env` (for Docker Compose) and `src/.env` (for Laravel). The `key:generate` command only updates `src/.env`, so you need to manually copy it to the root `.env` file.

### 5. Access the Application

- **Application**: http://localhost
- **PostgreSQL**: localhost:5432
- **Redis**: localhost:6379

---

## Environment Setup

### Encrypting Environment Files

Laravel supports encrypting `.env` files for secure storage. After configuring your `.env` with real secrets:

```bash
# Encrypt the .env file
docker compose exec php-fpm php artisan env:encrypt

# This creates .env.encrypted and outputs a decryption key
# SAVE THE KEY SECURELY - you cannot decrypt without it!
```

To decrypt for editing:

```bash
docker compose exec php-fpm php artisan env:decrypt --key=<your-key>
```

The encrypted file (`.env.encrypted`) can be safely committed to version control. Store the decryption key in a secure location (password manager, vault, etc.).

### Environment Variables

The `.env` file controls application configuration. Key variables:

#### Application

```env
APP_NAME=Laravel
APP_ENV=local
APP_KEY=                          # Generated with php artisan key:generate
APP_DEBUG=true
APP_URL=http://localhost
```

#### Database

```env
DB_CONNECTION=pgsql
DB_HOST=postgres                  # Docker service name
DB_PORT=5432
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=secret
```

#### Redis

```env
REDIS_HOST=redis                  # Docker service name
REDIS_PORT=6379
REDIS_PASSWORD=null
```

#### Session and Cache

```env
SESSION_DRIVER=redis
CACHE_STORE=redis
QUEUE_CONNECTION=redis
```

#### Docker-Specific

```env
NGINX_PORT=80
POSTGRES_PORT=5432
REDIS_PORT=6379
UID=1000                          # Your user ID
GID=1000                          # Your group ID
```

### Finding Your UID/GID

```bash
# Linux/macOS
id -u  # UID
id -g  # GID

# Set in .env
UID=1000
GID=1000
```

### IDE Configuration

#### VS Code

Install extensions:
- PHP Intelephense
- Docker
- Laravel Artisan
- Tailwind CSS IntelliSense

`.vscode/launch.json` for Xdebug:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Listen for Xdebug",
      "type": "php",
      "request": "launch",
      "port": 9003,
      "pathMappings": {
        "/var/www": "${workspaceFolder}/src"
      }
    }
  ]
}
```

#### PHPStorm

1. **Configure Docker**: Settings → Build, Execution, Deployment → Docker
2. **Configure PHP Interpreter**: Settings → PHP → CLI Interpreter → Add → From Docker
3. **Configure Xdebug**: Settings → PHP → Debug → Xdebug → Port 9003
4. **Path Mappings**: `/var/www` → `<project>/src`

---

## Development Workflow

### Starting the Environment

```bash
# Start all services in background
docker compose up -d

# Start with logs visible
docker compose up

# Start specific services
docker compose up -d nginx php-fpm postgres redis
```

### Stopping the Environment

```bash
# Stop all services
docker compose stop

# Stop and remove containers
docker compose down

# Stop and remove containers, volumes, and images
docker compose down -v --rmi local
```

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f php-fpm
docker compose logs -f nginx
docker compose logs -f postgres

# Laravel application logs
docker compose exec php-fpm tail -f storage/logs/laravel.log
```

### Running Artisan Commands

```bash
# Basic command
docker compose exec php-fpm php artisan <command>

# Examples
docker compose exec php-fpm php artisan migrate
docker compose exec php-fpm php artisan make:model Post -mfc
docker compose exec php-fpm php artisan tinker
docker compose exec php-fpm php artisan cache:clear
docker compose exec php-fpm php artisan route:list
```

### Running Composer Commands

```bash
docker compose exec php-fpm composer install
docker compose exec php-fpm composer require package/name
docker compose exec php-fpm composer update
docker compose exec php-fpm composer dump-autoload
```

### Running NPM Commands

```bash
docker compose exec php-fpm npm install
docker compose exec php-fpm npm run dev
docker compose exec php-fpm npm run build
docker compose exec php-fpm npm run watch
```

### Using Laravel Sail Alternative Scripts

The project includes Composer scripts for convenience:

```bash
# Full setup (install, key, migrate, npm)
docker compose exec php-fpm composer setup

# Development server with Vite
docker compose exec php-fpm composer dev

# Run tests
docker compose exec php-fpm composer test
```

---

## Debugging with Xdebug

### Configuration

Xdebug is pre-configured in the development image with these settings:

```ini
xdebug.mode=develop,debug
xdebug.client_host=host.docker.internal
xdebug.client_port=9003
xdebug.start_with_request=yes
xdebug.idekey=DOCKER
```

### Environment Variables

Control Xdebug via environment variables in `.env`:

```env
XDEBUG_MODE=develop,debug
XDEBUG_HOST=host.docker.internal
XDEBUG_IDE_KEY=DOCKER
```

### Xdebug Modes

| Mode | Purpose |
|------|---------|
| `off` | Disable Xdebug |
| `develop` | Enhanced error messages |
| `debug` | Step debugging |
| `coverage` | Code coverage |
| `profile` | Profiling |
| `trace` | Function tracing |

Combine modes with comma: `develop,debug,coverage`

### Step Debugging Workflow

1. **Set breakpoint** in your IDE
2. **Enable listening** for Xdebug connections in IDE
3. **Make request** to the application
4. **Debug** - IDE should catch the breakpoint

### Disabling Xdebug

For better performance when not debugging:

```bash
# Disable in .env
XDEBUG_MODE=off

# Restart PHP-FPM
docker compose restart php-fpm
```

---

## Database Operations

### Accessing PostgreSQL

```bash
# Via Docker
docker compose exec postgres psql -U laravel -d laravel

# From host (if port exposed)
psql -h localhost -p 5432 -U laravel -d laravel
```

### Common Database Commands

```bash
# Run migrations
docker compose exec php-fpm php artisan migrate

# Rollback last migration
docker compose exec php-fpm php artisan migrate:rollback

# Fresh database with seeds
docker compose exec php-fpm php artisan migrate:fresh --seed

# Database seed only
docker compose exec php-fpm php artisan db:seed

# Check migration status
docker compose exec php-fpm php artisan migrate:status
```

### Database GUI Tools

Connect with tools like DBeaver, TablePlus, or pgAdmin:

| Setting | Value |
|---------|-------|
| Host | localhost |
| Port | 5432 |
| Database | laravel |
| Username | laravel |
| Password | secret |

### Creating Migrations

```bash
# Create migration
docker compose exec php-fpm php artisan make:migration create_posts_table

# Create migration with model
docker compose exec php-fpm php artisan make:model Post -m
```

---

## Testing

### Running Tests

```bash
# Run all tests
docker compose exec php-fpm php artisan test

# Run with coverage
docker compose exec php-fpm php artisan test --coverage

# Run specific test file
docker compose exec php-fpm php artisan test tests/Feature/ExampleTest.php

# Run specific test method
docker compose exec php-fpm php artisan test --filter test_example

# Using PHPUnit directly
docker compose exec php-fpm ./vendor/bin/phpunit
```

### Test Configuration

**File**: `src/phpunit.xml`

```xml
<phpunit>
    <testsuites>
        <testsuite name="Unit">
            <directory suffix="Test.php">./tests/Unit</directory>
        </testsuite>
        <testsuite name="Feature">
            <directory suffix="Test.php">./tests/Feature</directory>
        </testsuite>
    </testsuites>
    <php>
        <env name="APP_ENV" value="testing"/>
        <env name="DB_CONNECTION" value="pgsql"/>
        <env name="DB_DATABASE" value="laravel"/>
    </php>
</phpunit>
```

### Creating Tests

```bash
# Feature test
docker compose exec php-fpm php artisan make:test UserTest

# Unit test
docker compose exec php-fpm php artisan make:test UserTest --unit
```

### Test Utilities

```php
// RefreshDatabase trait for clean database
use Illuminate\Foundation\Testing\RefreshDatabase;

class ExampleTest extends TestCase
{
    use RefreshDatabase;

    public function test_example(): void
    {
        $response = $this->get('/');
        $response->assertStatus(200);
    }
}
```

---

## Common Tasks

### Creating Models with Relationships

```bash
# Model with migration, factory, controller
docker compose exec php-fpm php artisan make:model Post -mfc

# Model with all (migration, factory, seeder, controller, policy)
docker compose exec php-fpm php artisan make:model Post -a
```

### Creating Controllers

```bash
# Basic controller
docker compose exec php-fpm php artisan make:controller PostController

# Resource controller
docker compose exec php-fpm php artisan make:controller PostController --resource

# API resource controller
docker compose exec php-fpm php artisan make:controller PostController --api
```

### Queue Development

```bash
# Process jobs
docker compose exec php-fpm php artisan queue:work

# Process single job
docker compose exec php-fpm php artisan queue:work --once

# Listen to specific queue
docker compose exec php-fpm php artisan queue:work redis --queue=emails

# View failed jobs
docker compose exec php-fpm php artisan queue:failed

# Retry failed job
docker compose exec php-fpm php artisan queue:retry <job-id>

# Retry all failed
docker compose exec php-fpm php artisan queue:retry all
```

### Cache Management

```bash
# Clear all caches
docker compose exec php-fpm php artisan cache:clear
docker compose exec php-fpm php artisan config:clear
docker compose exec php-fpm php artisan route:clear
docker compose exec php-fpm php artisan view:clear

# Rebuild caches
docker compose exec php-fpm php artisan config:cache
docker compose exec php-fpm php artisan route:cache
docker compose exec php-fpm php artisan view:cache
```

### Redis CLI

```bash
# Access Redis CLI
docker compose exec redis redis-cli

# Common commands
> KEYS *              # List all keys
> GET key             # Get value
> SET key value       # Set value
> DEL key             # Delete key
> FLUSHALL            # Clear all data
> INFO                # Server info
```

### Code Quality

```bash
# Laravel Pint (code style)
docker compose exec php-fpm ./vendor/bin/pint

# Check only (don't fix)
docker compose exec php-fpm ./vendor/bin/pint --test
```

---

## Troubleshooting

### "File Not Found" Error

If you see "file not found" when accessing the application, this typically indicates one of three issues:

#### Issue 1: Nginx Volume Mount Not Working

**Symptom:** `realpath() "/var/www/public" failed (2: No such file or directory)` in nginx logs.

**Fix:** Force-recreate the nginx container:

```bash
docker compose up -d --force-recreate nginx
```

#### Issue 2: Storage Directory Permissions

**Symptom:** `file_put_contents(/var/www/storage/framework/views/...): Failed to open stream: Permission denied`

**Cause:** PHP-FPM worker processes run as `www-data` user, but storage directories may have different ownership.

**Fix:** The development entrypoint script automatically fixes this on container startup. If you still have issues:

```bash
docker compose exec php-fpm chown -R www-data:www-data /var/www/storage
docker compose exec php-fpm chown -R www-data:www-data /var/www/bootstrap/cache
```

Or restart the php-fpm container to trigger the entrypoint fix:

```bash
docker compose restart php-fpm
```

#### Issue 3: Missing APP_KEY

**Symptom:** `MissingAppKeyException - No application encryption key has been specified`

**Cause:** The APP_KEY environment variable is not set. Docker Compose reads environment variables from the root `.env` file, not from `src/.env`.

**Fix:**

```bash
# 1. Generate key (writes to src/.env)
docker compose exec php-fpm php artisan key:generate

# 2. Copy the key to the root .env file
# First, get the key from src/.env:
grep APP_KEY src/.env

# Then add it to the root .env file (replace with actual key):
# APP_KEY=base64:your-generated-key-here

# 3. Restart containers to apply
docker compose down && docker compose up -d
```

**Important:** Both `.env` files need the same APP_KEY value - the root `.env` for Docker Compose environment variables, and `src/.env` for Laravel's direct file reads.

### Container Issues

#### Containers Won't Start

```bash
# Check Docker status
docker info

# Check container logs
docker compose logs

# Rebuild containers
docker compose build --no-cache
docker compose up -d
```

#### Port Already in Use

```bash
# Check what's using the port
# Windows
netstat -ano | findstr :80

# Linux/macOS
lsof -i :80

# Change port in .env
NGINX_PORT=8080
```

### Permission Issues

#### Storage Not Writable

```bash
# Fix permissions inside container
docker compose exec php-fpm chmod -R 775 storage bootstrap/cache
docker compose exec php-fpm chown -R laravel:laravel storage bootstrap/cache
```

#### Host File Ownership

```bash
# On Linux, files created by container may have wrong ownership
# Fix by setting UID/GID in .env to match your user
UID=1000
GID=1000
docker compose down
docker compose up -d
```

### Database Issues

#### Connection Refused

```bash
# Check PostgreSQL is running
docker compose ps postgres

# Check PostgreSQL logs
docker compose logs postgres

# Wait for PostgreSQL to be ready
docker compose exec postgres pg_isready
```

#### Database Doesn't Exist

```bash
# PostgreSQL auto-creates DB from POSTGRES_DB env var
# Restart PostgreSQL if needed
docker compose restart postgres

# Or create manually
docker compose exec postgres createdb -U laravel laravel
```

#### Password Authentication Failed

If you get `FATAL: password authentication failed for user "laravel"` after changing `DB_PASSWORD`:

PostgreSQL only sets the password when the volume is first created. If you started containers before setting `DB_PASSWORD`, or changed it afterward, the database retains the old credentials.

**Solution** - Reset the postgres volume:

```bash
# Stop containers and remove postgres volume
docker compose down
docker volume rm laravel-postgres-data

# Restart (postgres will initialize with current DB_PASSWORD)
docker compose up -d
```

**Warning**: This deletes all database data. For existing databases with data you need to keep, change the password via psql instead:

```bash
docker compose exec postgres psql -U postgres -c "ALTER USER laravel PASSWORD 'your-new-password';"
```

### Redis Issues

#### Connection Refused

```bash
# Check Redis is running
docker compose ps redis

# Check Redis logs
docker compose logs redis

# Test connection
docker compose exec redis redis-cli ping
```

### PHP Issues

#### Memory Limit

Edit `docker/development/php/php.ini`:

```ini
memory_limit = 1024M
```

Then restart:

```bash
docker compose restart php-fpm
```

#### Max Execution Time

Edit `docker/development/php/php.ini`:

```ini
max_execution_time = 600
```

### Xdebug Issues

#### Not Connecting

1. Check IDE is listening on port 9003
2. Verify `host.docker.internal` resolves:

```bash
docker compose exec php-fpm ping host.docker.internal
```

3. Check Xdebug is enabled:

```bash
docker compose exec php-fpm php -v
# Should show "with Xdebug"
```

#### Slow Performance

Disable when not debugging:

```env
XDEBUG_MODE=off
```

### Rebuilding from Scratch

```bash
# Nuclear option - remove everything
docker compose down -v --rmi local
docker system prune -a

# Fresh start
docker compose build --no-cache
docker compose up -d

# Reinstall everything
docker compose exec php-fpm composer install
docker compose exec php-fpm php artisan key:generate
docker compose exec php-fpm php artisan migrate:fresh --seed
docker compose exec php-fpm npm install
docker compose exec php-fpm npm run build
```

---

## Useful Aliases

Add to your shell configuration (`.bashrc`, `.zshrc`):

```bash
# Docker Compose shortcuts
alias dc="docker compose"
alias dcu="docker compose up -d"
alias dcd="docker compose down"
alias dcl="docker compose logs -f"
alias dce="docker compose exec"

# Laravel shortcuts (in Docker)
alias art="docker compose exec php-fpm php artisan"
alias composer="docker compose exec php-fpm composer"
alias npm="docker compose exec php-fpm npm"
alias tinker="docker compose exec php-fpm php artisan tinker"

# Quick commands
alias migrate="docker compose exec php-fpm php artisan migrate"
alias fresh="docker compose exec php-fpm php artisan migrate:fresh --seed"
alias test="docker compose exec php-fpm php artisan test"
```

---

## Related Documentation

- [Architecture Overview](./ARCHITECTURE.md)
- [Docker Configuration](./DOCKER.md)
- [Services Configuration](./SERVICES.md)
- [Deployment Guide](./DEPLOYMENT.md)
