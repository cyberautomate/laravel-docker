#!/bin/bash
# =============================================================================
# Add New Laravel Application Script
# Automates adding a new Laravel app to the multi-app Docker setup
#
# Usage: ./add-app.sh <app-name> [port] [redis-db]
# Example: ./add-app.sh app3
# Example: ./add-app.sh admin 8085 5
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# File paths
DOCKER_COMPOSE="$PROJECT_ROOT/docker-compose.yml"
NGINX_CONF="$PROJECT_ROOT/docker/development/nginx/nginx.conf"
APPS_DIR="$PROJECT_ROOT/apps"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo -e "\n${BLUE}=============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=============================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_app_name() {
    local name="$1"

    # Check if name is provided
    if [[ -z "$name" ]]; then
        print_error "App name is required"
        echo "Usage: $0 <app-name> [port] [redis-db]"
        exit 1
    fi

    # Check if name is lowercase alphanumeric with underscores/hyphens
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        print_error "App name must be lowercase alphanumeric (underscores and hyphens allowed)"
        print_error "Examples: app3, admin, my-api, user_service"
        exit 1
    fi

    # Check if directory already exists
    if [[ -d "$APPS_DIR/$name" ]]; then
        print_error "App directory already exists: $APPS_DIR/$name"
        exit 1
    fi
}

validate_port() {
    local port="$1"

    # Check if port is a valid number
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        print_error "Port must be a number: $port"
        exit 1
    fi

    # Check if port is in valid range
    if [[ "$port" -lt 1024 || "$port" -gt 65535 ]]; then
        print_error "Port must be between 1024 and 65535: $port"
        exit 1
    fi

    # Check if port is already used in docker-compose.yml
    if grep -q ":$port\"" "$DOCKER_COMPOSE" 2>/dev/null; then
        print_error "Port $port is already in use in docker-compose.yml"
        exit 1
    fi
}

validate_redis_db() {
    local redis_db="$1"

    # Check if redis_db is a valid number
    if [[ ! "$redis_db" =~ ^[0-9]+$ ]]; then
        print_error "Redis DB must be a number: $redis_db"
        exit 1
    fi

    # Check if redis_db is in valid range (0-15)
    if [[ "$redis_db" -gt 15 ]]; then
        print_error "Redis DB must be between 0 and 15: $redis_db"
        exit 1
    fi

    # Check if redis_db is already used in docker-compose.yml
    if grep -q "REDIS_DB=$redis_db$" "$DOCKER_COMPOSE" 2>/dev/null || \
       grep -q "REDIS_DB=$redis_db\s" "$DOCKER_COMPOSE" 2>/dev/null; then
        print_error "Redis DB $redis_db is already in use in docker-compose.yml"
        exit 1
    fi
}

# =============================================================================
# Detection Functions
# =============================================================================

detect_next_port() {
    # Find highest port in nginx ports section (8081, 8082, etc.)
    # Default starting port is 8081
    local highest_port=8080

    # Extract ports from the nginx ports section
    while IFS= read -r line; do
        if [[ "$line" =~ :([0-9]+)\" ]]; then
            local port="${BASH_REMATCH[1]}"
            if [[ "$port" -gt "$highest_port" && "$port" -lt 9000 ]]; then
                highest_port="$port"
            fi
        fi
    done < <(grep -A 20 "nginx:" "$DOCKER_COMPOSE" | grep -E "^\s*-.*:[0-9]+\"")

    echo $((highest_port + 1))
}

detect_next_redis_db() {
    # Find highest REDIS_DB in use
    # Default is 0 for primary app, so secondary apps start at 1
    local highest_db=0

    while IFS= read -r line; do
        if [[ "$line" =~ REDIS_DB=([0-9]+) ]]; then
            local db="${BASH_REMATCH[1]}"
            if [[ "$db" -gt "$highest_db" ]]; then
                highest_db="$db"
            fi
        fi
    done < <(grep "REDIS_DB=" "$DOCKER_COMPOSE")

    echo $((highest_db + 1))
}

# =============================================================================
# Modification Functions
# =============================================================================

update_docker_compose() {
    local app_name="$1"
    local port="$2"
    local redis_db="$3"

    print_info "Updating docker-compose.yml..."

    # Create a backup
    cp "$DOCKER_COMPOSE" "$DOCKER_COMPOSE.bak"

    # Convert app name for variable naming (replace hyphens with underscores for env vars)
    local app_var_name="${app_name//-/_}"
    local app_upper="${app_var_name^^}"

    # Use temp file for modifications
    local tmp_file="$DOCKER_COMPOSE.tmp"

    # 1. Add port to nginx service
    # Find the last NGINX_PORT line and add new port after it
    local last_nginx_port_line
    last_nginx_port_line=$(grep -n "NGINX_PORT.*:[0-9]\+\"" "$DOCKER_COMPOSE" | tail -1 | cut -d: -f1)
    if [[ -n "$last_nginx_port_line" ]]; then
        head -n "$last_nginx_port_line" "$DOCKER_COMPOSE" > "$tmp_file"
        echo "      - \"\${NGINX_PORT_${app_upper}:-${port}}:${port}\"" >> "$tmp_file"
        tail -n +$((last_nginx_port_line + 1)) "$DOCKER_COMPOSE" >> "$tmp_file"
        mv "$tmp_file" "$DOCKER_COMPOSE"
    fi

    # 2. Add volume to nginx service
    # Find the last apps/ volume in nginx (before nginx.conf mount)
    local last_nginx_apps_line
    last_nginx_apps_line=$(grep -n "./apps/.*:ro" "$DOCKER_COMPOSE" | tail -1 | cut -d: -f1)
    if [[ -n "$last_nginx_apps_line" ]]; then
        head -n "$last_nginx_apps_line" "$DOCKER_COMPOSE" > "$tmp_file"
        echo "      - ./apps/${app_name}:/var/www/${app_name}:ro" >> "$tmp_file"
        tail -n +$((last_nginx_apps_line + 1)) "$DOCKER_COMPOSE" >> "$tmp_file"
        mv "$tmp_file" "$DOCKER_COMPOSE"
    fi

    # 3. Add volume to php-fpm service
    # Find the php-fpm section and its apps/ volume
    local phpfpm_start phpfpm_apps_line
    phpfpm_start=$(grep -n "^  php-fpm:" "$DOCKER_COMPOSE" | cut -d: -f1)
    if [[ -n "$phpfpm_start" ]]; then
        # Find the apps/ volume line in php-fpm section (not :ro)
        phpfpm_apps_line=$(tail -n +$phpfpm_start "$DOCKER_COMPOSE" | grep -n "./apps/.*[^o]$" | head -1 | cut -d: -f1)
        if [[ -n "$phpfpm_apps_line" ]]; then
            local actual_line=$((phpfpm_start + phpfpm_apps_line - 1))
            head -n "$actual_line" "$DOCKER_COMPOSE" > "$tmp_file"
            echo "      - ./apps/${app_name}:/var/www/${app_name}" >> "$tmp_file"
            tail -n +$((actual_line + 1)) "$DOCKER_COMPOSE" >> "$tmp_file"
            mv "$tmp_file" "$DOCKER_COMPOSE"
        fi
    fi

    # 4. Update POSTGRES_MULTIPLE_DATABASES
    sed -i "s/POSTGRES_MULTIPLE_DATABASES: \(.*\)/POSTGRES_MULTIPLE_DATABASES: \1,${app_name}_db/" "$DOCKER_COMPOSE"

    # 5. Add queue worker service block
    # Find the line with "# Networks" comment and insert before it
    local queue_service="
  # ---------------------------------------------------------------------------
  # Queue Worker - ${app_name} (apps/${app_name}/)
  # ---------------------------------------------------------------------------
  queue-${app_name}:
    build:
      context: .
      dockerfile: docker/common/php-fpm/Dockerfile
      target: development
    container_name: laravel-queue-${app_name}
    restart: unless-stopped
    working_dir: /var/www/${app_name}
    command: php artisan queue:work redis --queue=${app_name} --sleep=3 --tries=3 --max-time=3600 --verbose
    volumes:
      - ./apps/${app_name}:/var/www/${app_name}
      - ./docker/development/php/php.ini:/usr/local/etc/php/conf.d/custom.ini:ro
    environment:
      - APP_ENV=\${APP_ENV:-local}
      - APP_DEBUG=\${APP_DEBUG:-true}
      - APP_KEY=\${${app_upper}_KEY:-}
      - DB_CONNECTION=pgsql
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_DATABASE=${app_name}_db
      - DB_USERNAME=\${DB_USERNAME:-laravel}
      - DB_PASSWORD=\${DB_PASSWORD:-secret}
      - REDIS_CLIENT=phpredis
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_PASSWORD=\${REDIS_PASSWORD:-}
      - REDIS_DB=${redis_db}
      - REDIS_PREFIX=${app_name}_
      - CACHE_STORE=redis
      - CACHE_PREFIX=${app_name}_cache_
      - QUEUE_CONNECTION=redis
      - QUEUE_QUEUE=${app_name}
      - LOG_CHANNEL=stack
      - LOG_LEVEL=debug
    depends_on:
      php-fpm:
        condition: service_healthy
    networks:
      - backend
"

    # Insert the queue service before the networks section
    # Find the line "# Networks" header (3 lines before "networks:")
    local networks_line
    networks_line=$(grep -n "^# -\+$" "$DOCKER_COMPOSE" | grep -A1 "" | tail -3 | head -1 | cut -d: -f1)

    # Find the networks comment header (line starting with "# ---" before "Networks")
    local networks_header_line
    networks_header_line=$(grep -n "^# Networks$" "$DOCKER_COMPOSE" | cut -d: -f1)
    if [[ -n "$networks_header_line" ]]; then
        # Insert before the comment block (2 lines before "# Networks")
        local insert_line=$((networks_header_line - 1))
        head -n "$insert_line" "$DOCKER_COMPOSE" > "$tmp_file"
        echo "$queue_service" >> "$tmp_file"
        tail -n +$((insert_line + 1)) "$DOCKER_COMPOSE" >> "$tmp_file"
        mv "$tmp_file" "$DOCKER_COMPOSE"
    fi

    print_success "Updated docker-compose.yml"
}

update_nginx_conf() {
    local app_name="$1"
    local port="$2"
    local redis_db="$3"

    print_info "Updating nginx.conf..."

    # Create a backup
    cp "$NGINX_CONF" "$NGINX_CONF.bak"

    # Server block template
    local server_block="
    # =========================================================================
    # ${app_name} - Port ${port} (apps/${app_name}/)
    # =========================================================================
    server {
        listen ${port};
        server_name localhost;
        root /var/www/${app_name}/public;
        index index.php index.html;

        charset utf-8;

        # Health check endpoint (bypasses PHP)
        location /health {
            access_log off;
            return 200 \"healthy\n\";
            add_header Content-Type text/plain;
        }

        # Laravel routing
        location / {
            try_files \$uri \$uri/ /index.php?\$query_string;
        }

        # Disable logging for common static files
        location = /favicon.ico { access_log off; log_not_found off; }
        location = /robots.txt  { access_log off; log_not_found off; }

        # Custom 404 handling via Laravel
        error_page 404 /index.php;

        # PHP-FPM configuration
        location ~ \.php\$ {
            fastcgi_pass php-fpm:9000;
            fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
            include fastcgi_params;

            # App-specific environment overrides
            fastcgi_param DB_DATABASE ${app_name}_db;
            fastcgi_param REDIS_DB ${redis_db};
            fastcgi_param REDIS_PREFIX ${app_name}_;
            fastcgi_param CACHE_PREFIX ${app_name}_cache_;
            fastcgi_param QUEUE_QUEUE ${app_name};

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
    }"

    # Insert the server block before the final closing brace of http block
    # Find the last } in the file and insert before it
    head -n -1 "$NGINX_CONF" > "$NGINX_CONF.tmp"
    echo "$server_block" >> "$NGINX_CONF.tmp"
    echo "}" >> "$NGINX_CONF.tmp"
    mv "$NGINX_CONF.tmp" "$NGINX_CONF"

    print_success "Updated nginx.conf"
}

create_app_directory() {
    local app_name="$1"
    local port="$2"
    local redis_db="$3"

    print_info "Creating app directory and .env file..."

    # Create the app directory
    mkdir -p "$APPS_DIR/$app_name"

    # Create .env file
    cat > "$APPS_DIR/$app_name/.env" << EOF
# =============================================================================
# Docker Local Development Environment - ${app_name}
# =============================================================================

# -----------------------------------------------------------------------------
# Application Settings
# -----------------------------------------------------------------------------
APP_NAME="Laravel ${app_name}"
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_TIMEZONE=UTC
APP_URL=http://localhost:${port}

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
DB_DATABASE=${app_name}_db
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
CACHE_PREFIX=${app_name}_cache_

# -----------------------------------------------------------------------------
# Queue
# -----------------------------------------------------------------------------
QUEUE_CONNECTION=redis
QUEUE_QUEUE=${app_name}

# -----------------------------------------------------------------------------
# Redis
# -----------------------------------------------------------------------------
REDIS_CLIENT=phpredis
REDIS_HOST=redis
REDIS_PASSWORD=
REDIS_PORT=6379
REDIS_DB=${redis_db}
REDIS_PREFIX=${app_name}_

# -----------------------------------------------------------------------------
# Mail (log for development)
# -----------------------------------------------------------------------------
MAIL_MAILER=log
EOF

    print_success "Created $APPS_DIR/$app_name/.env"
}

print_next_steps() {
    local app_name="$1"
    local port="$2"

    print_header "Next Steps"

    echo -e "1. Install Laravel in the new app directory:"
    echo -e "   ${YELLOW}cd apps/${app_name} && composer create-project laravel/laravel . --prefer-dist${NC}"
    echo ""
    echo -e "2. Recreate the PostgreSQL volume to initialize the new database:"
    echo -e "   ${YELLOW}docker compose down -v${NC}"
    echo -e "   ${RED}   (Warning: This will delete all existing database data!)${NC}"
    echo ""
    echo -e "   Or manually create the database:"
    echo -e "   ${YELLOW}docker compose exec postgres createdb -U laravel ${app_name}_db${NC}"
    echo ""
    echo -e "3. Start the services:"
    echo -e "   ${YELLOW}docker compose up -d${NC}"
    echo ""
    echo -e "4. Generate application key:"
    echo -e "   ${YELLOW}docker compose exec php-fpm php /var/www/${app_name}/artisan key:generate${NC}"
    echo ""
    echo -e "5. Run migrations:"
    echo -e "   ${YELLOW}docker compose exec php-fpm php /var/www/${app_name}/artisan migrate${NC}"
    echo ""
    echo -e "6. Access your application at:"
    echo -e "   ${GREEN}http://localhost:${port}${NC}"
    echo ""
}

# =============================================================================
# Main Script
# =============================================================================

main() {
    print_header "Add New Laravel Application"

    # Get parameters
    local app_name="$1"
    local port="$2"
    local redis_db="$3"

    # Validate app name
    validate_app_name "$app_name"

    # Auto-detect port if not provided
    if [[ -z "$port" ]]; then
        port=$(detect_next_port)
        print_info "Auto-detected port: $port"
    fi
    validate_port "$port"

    # Auto-detect redis_db if not provided
    if [[ -z "$redis_db" ]]; then
        redis_db=$(detect_next_redis_db)
        print_info "Auto-detected Redis DB: $redis_db"
    fi
    validate_redis_db "$redis_db"

    # Show configuration
    echo "Configuration:"
    echo "  App Name:   $app_name"
    echo "  Port:       $port"
    echo "  Redis DB:   $redis_db"
    echo "  Database:   ${app_name}_db"
    echo "  Queue:      $app_name"
    echo "  Directory:  apps/$app_name/"
    echo ""

    # Perform modifications
    update_docker_compose "$app_name" "$port" "$redis_db"
    update_nginx_conf "$app_name" "$port" "$redis_db"
    create_app_directory "$app_name" "$port" "$redis_db"

    print_header "Setup Complete"

    print_success "Added new application: $app_name"
    print_success "Backup files created: docker-compose.yml.bak, nginx.conf.bak"

    print_next_steps "$app_name" "$port"
}

# Run main function with all arguments
main "$@"
