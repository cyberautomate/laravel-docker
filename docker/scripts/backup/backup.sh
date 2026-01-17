#!/bin/bash
# =============================================================================
# PostgreSQL Backup Script
# Backs up database to local storage and Azure Blob Storage
#
# Usage:
#   ./backup.sh                    # Run backup
#   ./backup.sh --restore <file>   # Restore from backup file
#
# Environment Variables:
#   DB_HOST          - PostgreSQL host
#   DB_PORT          - PostgreSQL port (default: 5432)
#   DB_NAME          - Database name
#   DB_USER          - Database username (or via secret)
#   PGPASSWORD       - Database password (or via secret)
#   BACKUP_DIR       - Backup directory (default: /backup)
#   RETENTION_DAYS   - Days to keep backups (default: 30)
#   AZURE_STORAGE_ACCOUNT      - Azure storage account name
#   AZURE_STORAGE_KEY          - Azure storage account key
#   AZURE_STORAGE_CONTAINER    - Azure blob container name
# =============================================================================

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================

BACKUP_DIR="${BACKUP_DIR:-/backup}"
LOCAL_BACKUP_DIR="${BACKUP_DIR}/local"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_DIR=$(date +%Y/%m)
BACKUP_FILE="laravel_${TIMESTAMP}.sql.gz"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =============================================================================
# FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Load credentials from Docker secrets if available
load_secrets() {
    if [ -f "/run/secrets/db_username" ]; then
        DB_USER=$(cat /run/secrets/db_username)
        log_info "Loaded DB_USER from Docker secret"
    fi

    if [ -f "/run/secrets/db_password" ]; then
        export PGPASSWORD=$(cat /run/secrets/db_password)
        log_info "Loaded PGPASSWORD from Docker secret"
    fi

    if [ -f "/run/secrets/azure_storage_account" ]; then
        AZURE_STORAGE_ACCOUNT=$(cat /run/secrets/azure_storage_account)
        log_info "Loaded AZURE_STORAGE_ACCOUNT from Docker secret"
    fi

    if [ -f "/run/secrets/azure_storage_key" ]; then
        AZURE_STORAGE_KEY=$(cat /run/secrets/azure_storage_key)
        log_info "Loaded AZURE_STORAGE_KEY from Docker secret"
    fi
}

# Validate required environment variables
validate_env() {
    local missing=()

    [ -z "$DB_HOST" ] && missing+=("DB_HOST")
    [ -z "$DB_NAME" ] && missing+=("DB_NAME")
    [ -z "$DB_USER" ] && missing+=("DB_USER")
    [ -z "$PGPASSWORD" ] && missing+=("PGPASSWORD")

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required environment variables: ${missing[*]}"
        exit 1
    fi
}

# Create backup directories
setup_directories() {
    mkdir -p "$LOCAL_BACKUP_DIR/$DATE_DIR"
    log_info "Backup directory: $LOCAL_BACKUP_DIR/$DATE_DIR"
}

# Perform database backup
backup_database() {
    log_info "Starting PostgreSQL backup..."
    log_info "Database: $DB_NAME @ $DB_HOST:${DB_PORT:-5432}"

    # Create backup using pg_dump
    pg_dump \
        -h "$DB_HOST" \
        -p "${DB_PORT:-5432}" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists \
        | gzip > "$LOCAL_BACKUP_DIR/$DATE_DIR/$BACKUP_FILE"

    local backup_size=$(du -h "$LOCAL_BACKUP_DIR/$DATE_DIR/$BACKUP_FILE" | cut -f1)
    log_info "Local backup created: $BACKUP_FILE ($backup_size)"
}

# Upload backup to Azure Blob Storage
upload_to_azure() {
    if [ -z "$AZURE_STORAGE_ACCOUNT" ] || [ -z "$AZURE_STORAGE_KEY" ]; then
        log_warn "Azure credentials not configured, skipping cloud upload"
        return 0
    fi

    log_info "Uploading to Azure Blob Storage..."
    log_info "Container: ${AZURE_STORAGE_CONTAINER:-backups}"

    # Check if az CLI is available
    if ! command -v az &> /dev/null; then
        log_warn "Azure CLI not found, skipping cloud upload"
        return 0
    fi

    az storage blob upload \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --account-key "$AZURE_STORAGE_KEY" \
        --container-name "${AZURE_STORAGE_CONTAINER:-backups}" \
        --file "$LOCAL_BACKUP_DIR/$DATE_DIR/$BACKUP_FILE" \
        --name "postgresql/$DATE_DIR/$BACKUP_FILE" \
        --overwrite \
        --only-show-errors

    log_info "Azure upload complete: postgresql/$DATE_DIR/$BACKUP_FILE"
}

# Clean up old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than $RETENTION_DAYS days..."

    # Clean local backups
    local deleted_count=$(find "$LOCAL_BACKUP_DIR" -name "*.sql.gz" -type f -mtime +$RETENTION_DAYS -delete -print | wc -l)
    log_info "Deleted $deleted_count local backup(s)"

    # Clean empty directories
    find "$LOCAL_BACKUP_DIR" -type d -empty -delete 2>/dev/null || true

    # Clean Azure blobs if configured
    if [ -n "$AZURE_STORAGE_ACCOUNT" ] && [ -n "$AZURE_STORAGE_KEY" ] && command -v az &> /dev/null; then
        log_info "Cleaning old Azure backups..."

        # Calculate cutoff date
        local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y-%m-%dT00:00:00Z 2>/dev/null || \
                          date -v-${RETENTION_DAYS}d +%Y-%m-%dT00:00:00Z)

        # List and delete old blobs
        az storage blob list \
            --account-name "$AZURE_STORAGE_ACCOUNT" \
            --account-key "$AZURE_STORAGE_KEY" \
            --container-name "${AZURE_STORAGE_CONTAINER:-backups}" \
            --prefix "postgresql/" \
            --query "[?properties.lastModified<='$cutoff_date'].name" \
            --output tsv \
            | while read blob_name; do
                if [ -n "$blob_name" ]; then
                    az storage blob delete \
                        --account-name "$AZURE_STORAGE_ACCOUNT" \
                        --account-key "$AZURE_STORAGE_KEY" \
                        --container-name "${AZURE_STORAGE_CONTAINER:-backups}" \
                        --name "$blob_name" \
                        --only-show-errors
                    log_info "Deleted Azure blob: $blob_name"
                fi
            done
    fi
}

# Restore database from backup
restore_database() {
    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi

    log_warn "This will OVERWRITE the database '$DB_NAME'"
    log_warn "Press Ctrl+C within 5 seconds to cancel..."
    sleep 5

    log_info "Restoring database from: $backup_file"

    # Decompress and restore
    gunzip -c "$backup_file" | psql \
        -h "$DB_HOST" \
        -p "${DB_PORT:-5432}" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --quiet

    log_info "Database restore completed!"
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --restore <file>    Restore database from backup file"
    echo "  --cleanup           Only run cleanup (no new backup)"
    echo "  --help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  DB_HOST             PostgreSQL host"
    echo "  DB_PORT             PostgreSQL port (default: 5432)"
    echo "  DB_NAME             Database name"
    echo "  DB_USER             Database username"
    echo "  PGPASSWORD          Database password"
    echo "  BACKUP_DIR          Backup directory (default: /backup)"
    echo "  RETENTION_DAYS      Days to keep backups (default: 30)"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log_info "=== PostgreSQL Backup Script ==="

    # Load Docker secrets
    load_secrets

    # Parse arguments
    case "${1:-}" in
        --restore)
            validate_env
            restore_database "$2"
            exit 0
            ;;
        --cleanup)
            cleanup_old_backups
            exit 0
            ;;
        --help)
            show_usage
            exit 0
            ;;
    esac

    # Validate environment
    validate_env

    # Run backup process
    setup_directories
    backup_database
    upload_to_azure
    cleanup_old_backups

    log_info "=== Backup completed successfully ==="
}

# Run main function
main "$@"
