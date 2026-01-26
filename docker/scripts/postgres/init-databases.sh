#!/bin/bash
# =============================================================================
# PostgreSQL Multiple Database Initialization Script
# This script creates additional databases on container startup
# Usage: Mount to /docker-entrypoint-initdb.d/ in the postgres container
# =============================================================================

set -e
set -u

# Function to create a database if it doesn't exist
create_database() {
    local database=$1
    echo "Creating database '$database' if it doesn't exist..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
        SELECT 'CREATE DATABASE "$database"'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$database')\gexec
        GRANT ALL PRIVILEGES ON DATABASE "$database" TO "$POSTGRES_USER";
EOSQL
    echo "Database '$database' is ready."
}

# Check if POSTGRES_MULTIPLE_DATABASES is set
if [ -n "${POSTGRES_MULTIPLE_DATABASES:-}" ]; then
    echo "Multiple database creation requested: $POSTGRES_MULTIPLE_DATABASES"

    # Split the comma-separated list and create each database
    IFS=',' read -ra DATABASES <<< "$POSTGRES_MULTIPLE_DATABASES"
    for db in "${DATABASES[@]}"; do
        # Trim whitespace
        db=$(echo "$db" | xargs)
        if [ -n "$db" ]; then
            create_database "$db"
        fi
    done

    echo "All additional databases have been created."
else
    echo "No additional databases requested (POSTGRES_MULTIPLE_DATABASES not set)."
fi
