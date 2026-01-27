# =============================================================================
# Laravel PHP-FPM Docker Image - Multi-Stage Build
# Security-hardened for production use
# =============================================================================

# -----------------------------------------------------------------------------
# Base Stage - Common dependencies for all environments
# -----------------------------------------------------------------------------
FROM php:8.4-fpm-alpine AS base

LABEL maintainer="Your Name <your.email@example.com>"
LABEL description="Laravel 12 PHP-FPM container with PostgreSQL support"

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
        pcntl \
        exif

# Install Redis extension
RUN pecl install redis \
    && docker-php-ext-enable redis

# Create non-root user for security
RUN addgroup -g 1000 -S laravel \
    && adduser -u 1000 -S laravel -G laravel

# Set working directory
WORKDIR /var/www

# -----------------------------------------------------------------------------
# Development Stage - Includes debugging tools
# -----------------------------------------------------------------------------
FROM base AS development

# Install Xdebug for debugging
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug

# Install Node.js and npm for frontend build tools (Vite, etc.)
RUN apk add --no-cache nodejs npm

# Install Composer
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

# Xdebug configuration
RUN echo "xdebug.mode=debug,develop,coverage" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.client_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.start_with_request=yes" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.idekey=DOCKER" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.log_level=0" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Development PHP configuration
RUN echo "display_errors = On" >> /usr/local/etc/php/conf.d/development.ini \
    && echo "display_startup_errors = On" >> /usr/local/etc/php/conf.d/development.ini \
    && echo "error_reporting = E_ALL" >> /usr/local/etc/php/conf.d/development.ini \
    && echo "log_errors = On" >> /usr/local/etc/php/conf.d/development.ini \
    && echo "memory_limit = 512M" >> /usr/local/etc/php/conf.d/development.ini \
    && echo "max_execution_time = 300" >> /usr/local/etc/php/conf.d/development.ini \
    && echo "upload_max_filesize = 64M" >> /usr/local/etc/php/conf.d/development.ini \
    && echo "post_max_size = 68M" >> /usr/local/etc/php/conf.d/development.ini

# PHP-FPM health check script
RUN echo '#!/bin/sh' > /usr/local/bin/php-fpm-healthcheck \
    && echo 'SCRIPT_NAME=/health SCRIPT_FILENAME=/health REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 2>/dev/null | head -n 1 | grep -q "Status: 200" && exit 0 || exit 1' >> /usr/local/bin/php-fpm-healthcheck \
    && chmod +x /usr/local/bin/php-fpm-healthcheck

# Keep as root for development (allows volume permissions to work better on Windows)
# Application code will be mounted as volume

EXPOSE 9000

CMD ["php-fpm"]

# -----------------------------------------------------------------------------
# Production Dependencies Stage - Install dependencies without dev packages
# -----------------------------------------------------------------------------
FROM base AS production-deps

# Remove build dependencies to reduce image size
RUN apk del $PHPIZE_DEPS linux-headers

# Install PostgreSQL client for health checks and entrypoint
RUN apk add --no-cache postgresql-client

# Install Composer
COPY --from=composer:2.7 /usr/bin/composer /usr/bin/composer

# Copy application code
COPY --chown=laravel:laravel src/ /var/www/

# Install production dependencies only
RUN composer install \
    --no-dev \
    --no-interaction \
    --optimize-autoloader \
    --no-scripts \
    --prefer-dist \
    && composer clear-cache \
    && rm -rf /root/.composer

# -----------------------------------------------------------------------------
# Production Stage - Optimized and Hardened
# -----------------------------------------------------------------------------
FROM base AS production

# Remove build dependencies and clean up
RUN apk del $PHPIZE_DEPS linux-headers \
    && rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# Install PostgreSQL client for health checks
RUN apk add --no-cache postgresql-client

# Copy production PHP configuration
COPY docker/production/php/php-production.ini /usr/local/etc/php/conf.d/production.ini

# Copy application from production-deps stage
COPY --from=production-deps --chown=laravel:laravel /var/www /var/www

# Copy entrypoint script
COPY --chmod=755 docker/scripts/entrypoint/php-fpm-entrypoint.sh /usr/local/bin/entrypoint.sh

# PHP-FPM health check script
RUN echo '#!/bin/sh' > /usr/local/bin/php-fpm-healthcheck \
    && echo 'SCRIPT_NAME=/health SCRIPT_FILENAME=/health REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 2>/dev/null | head -n 1 | grep -q "Status: 200" && exit 0 || exit 1' >> /usr/local/bin/php-fpm-healthcheck \
    && chmod +x /usr/local/bin/php-fpm-healthcheck

# Install fcgi for health checks
RUN apk add --no-cache fcgi

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
