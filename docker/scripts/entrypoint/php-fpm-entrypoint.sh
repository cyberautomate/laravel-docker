#!/bin/sh
set -e

# =============================================================================
# PHP-FPM Production Entrypoint
# Handles database readiness and Laravel optimization
# =============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting PHP-FPM entrypoint..."

# =============================================================================
# WAIT FOR DATABASE
# =============================================================================

if [ -n "$DB_HOST" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for database at $DB_HOST:${DB_PORT:-5432}..."

    max_attempts=30
    attempt=1

    while ! pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "${DB_USERNAME:-laravel}" > /dev/null 2>&1; do
        if [ $attempt -ge $max_attempts ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Database not available after $max_attempts attempts"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Continuing startup anyway..."
            break
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempt $attempt/$max_attempts: Database not ready, waiting 2s..."
        sleep 2
        attempt=$((attempt + 1))
    done

    if [ $attempt -lt $max_attempts ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Database is ready!"
    fi
fi

# =============================================================================
# WAIT FOR REDIS
# =============================================================================

if [ -n "$REDIS_HOST" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for Redis at $REDIS_HOST:${REDIS_PORT:-6379}..."

    max_attempts=15
    attempt=1

    while ! nc -z "$REDIS_HOST" "${REDIS_PORT:-6379}" 2>/dev/null; do
        if [ $attempt -ge $max_attempts ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Redis not available after $max_attempts attempts"
            break
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempt $attempt/$max_attempts: Redis not ready, waiting 1s..."
        sleep 1
        attempt=$((attempt + 1))
    done
fi

# =============================================================================
# LARAVEL PRODUCTION OPTIMIZATION
# =============================================================================

if [ "$APP_ENV" = "production" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running Laravel production optimizations..."

    # Clear any existing cache first
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Clearing existing caches..."
    php artisan optimize:clear 2>/dev/null || true

    # Cache configuration
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Caching configuration..."
    php artisan config:cache

    # Cache routes
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Caching routes..."
    php artisan route:cache

    # Cache views
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Caching views..."
    php artisan view:cache

    # Cache events (Laravel 11+)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Caching events..."
    php artisan event:cache 2>/dev/null || true

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Laravel optimization complete!"

    # Run migrations if enabled
    if [ "$MIGRATE_ON_START" = "true" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running database migrations..."
        php artisan migrate --force
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Migrations complete!"
    fi
fi

# =============================================================================
# START PHP-FPM
# =============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting PHP-FPM..."
exec "$@"
