#!/bin/sh
set -e

# =============================================================================
# Queue Worker Entrypoint
# Waits for application readiness before starting queue worker
# =============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Queue Worker entrypoint..."

# =============================================================================
# WAIT FOR DEPENDENCIES
# =============================================================================

# Wait for Redis (required for queue)
if [ -n "$REDIS_HOST" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for Redis at $REDIS_HOST:${REDIS_PORT:-6379}..."

    max_attempts=30
    attempt=1

    while ! nc -z "$REDIS_HOST" "${REDIS_PORT:-6379}" 2>/dev/null; do
        if [ $attempt -ge $max_attempts ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Redis not available after $max_attempts attempts"
            exit 1
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempt $attempt/$max_attempts: Redis not ready, waiting 2s..."
        sleep 2
        attempt=$((attempt + 1))
    done

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Redis is ready!"
fi

# Wait for database (if using database for jobs)
if [ -n "$DB_HOST" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for database at $DB_HOST:${DB_PORT:-5432}..."

    max_attempts=30
    attempt=1

    while ! pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "${DB_USERNAME:-laravel}" > /dev/null 2>&1; do
        if [ $attempt -ge $max_attempts ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Database not available after $max_attempts attempts"
            break
        fi

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Attempt $attempt/$max_attempts: Database not ready, waiting 2s..."
        sleep 2
        attempt=$((attempt + 1))
    done
fi

# =============================================================================
# WAIT FOR PHP-FPM TO BE HEALTHY
# =============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for PHP-FPM to be healthy..."
sleep 15

# =============================================================================
# START QUEUE WORKER
# =============================================================================

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting queue worker..."
exec "$@"
