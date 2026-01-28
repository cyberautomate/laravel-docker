#!/bin/sh
set -e

# =============================================================================
# PHP-FPM Development Entrypoint
# Handles permissions and environment setup for local development
# =============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting PHP-FPM development entrypoint..."

# =============================================================================
# FIX STORAGE PERMISSIONS
# PHP-FPM runs as www-data, so storage directories need www-data ownership
# =============================================================================

if [ -d "/var/www/storage" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fixing storage directory permissions..."
    chown -R www-data:www-data /var/www/storage
    chmod -R 775 /var/www/storage
fi

if [ -d "/var/www/bootstrap/cache" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fixing bootstrap/cache directory permissions..."
    chown -R www-data:www-data /var/www/bootstrap/cache
    chmod -R 775 /var/www/bootstrap/cache
fi

# Also fix permissions for app2 if it exists
if [ -d "/var/www/app2/storage" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fixing app2 storage directory permissions..."
    chown -R www-data:www-data /var/www/app2/storage
    chmod -R 775 /var/www/app2/storage
fi

if [ -d "/var/www/app2/bootstrap/cache" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fixing app2 bootstrap/cache directory permissions..."
    chown -R www-data:www-data /var/www/app2/bootstrap/cache
    chmod -R 775 /var/www/app2/bootstrap/cache
fi

# =============================================================================
# WAIT FOR DATABASE (optional, helps with race conditions)
# =============================================================================

if [ -n "$DB_HOST" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for database at $DB_HOST:${DB_PORT:-5432}..."

    max_attempts=30
    attempt=1

    while ! nc -z "$DB_HOST" "${DB_PORT:-5432}" 2>/dev/null; do
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
# WAIT FOR REDIS (optional)
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
# START PHP-FPM
# =============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting PHP-FPM..."
exec "$@"
