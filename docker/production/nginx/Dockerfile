# =============================================================================
# Production Nginx Docker Image
# Includes application static files and hardened configuration
# =============================================================================

FROM nginx:1.27-alpine

LABEL maintainer="Your Name <your.email@example.com>"
LABEL description="Production Nginx container for Laravel application"

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy hardened nginx configuration
COPY docker/production/nginx/nginx.conf /etc/nginx/nginx.conf

# Copy static files from Laravel (public directory)
COPY --chown=nginx:nginx src/public /var/www/public

# Create required directories
RUN mkdir -p /var/cache/nginx /var/run \
    && chown -R nginx:nginx /var/cache/nginx /var/run /var/log/nginx

# Security: Run as non-root user
USER nginx

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost/health || exit 1

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
