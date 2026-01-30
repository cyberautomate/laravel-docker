# Laravel Docker

Production-ready Laravel 12 application with Docker, featuring multi-stage builds, security hardening, and multi-application support.

![Laravel](https://img.shields.io/badge/Laravel-12-FF2D20?style=flat&logo=laravel&logoColor=white)
![PHP](https://img.shields.io/badge/PHP-8.4-777BB4?style=flat&logo=php&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=flat&logo=docker&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)

## Features

- **Production-Ready Stack** — Laravel 12 + Nginx + PHP 8.4-FPM + PostgreSQL 17 + Redis 7
- **Multi-Stage Dockerfiles** — Optimized builds for development and production
- **Security Hardened** — Non-root containers, capability dropping, network isolation
- **Multi-Application Support** — Run multiple Laravel apps with isolated queues and databases
- **Xdebug Pre-configured** — Step debugging ready for VS Code and PhpStorm
- **Queue Workers** — Dedicated containers with app isolation
- **Automated Backups** — PostgreSQL backups to Azure Blob Storage (production)

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Laravel 12 |
| Web Server | Nginx 1.27 |
| PHP | 8.4-FPM (Alpine) |
| Database | PostgreSQL 17 |
| Cache/Queue | Redis 7 |
| Frontend | Tailwind CSS 4 + Vite 7 |

## Quick Start

```bash
# Clone and configure
git clone <repo-url> laravel-docker
cd laravel-docker
cp .env.example .env

# Set a secure database password in .env
# DB_PASSWORD=your_secure_password

# Start containers
docker compose up -d

# Install dependencies and setup Laravel
docker compose exec php-fpm composer install
docker compose exec php-fpm php artisan key:generate
docker compose exec php-fpm php artisan migrate
```

Access the application at **http://localhost**

## Project Structure

```
├── src/                     # Laravel 12 application
├── apps/                    # Additional Laravel apps
│   └── app2/                # Secondary application
├── docker/
│   ├── common/php-fpm/      # Multi-stage PHP Dockerfile
│   ├── development/         # Dev configs (Xdebug enabled)
│   │   ├── nginx/           # Dev Nginx configuration
│   │   └── php/             # Dev PHP settings
│   ├── production/          # Prod-hardened configs
│   │   ├── nginx/           # Security headers, rate limiting
│   │   └── php/             # Hardened PHP settings
│   └── scripts/             # Entrypoint and utility scripts
├── docker-compose.yml       # Development environment
├── docker-compose.prod.yml  # Production environment
└── docs/                    # Comprehensive documentation
```

## Services & Ports

| Service | Dev Port | Description |
|---------|----------|-------------|
| Nginx | 80 | Web server (primary app) |
| Nginx | 8081 | Web server (app2) |
| PostgreSQL | 5432 | Database |
| Redis | 6379 | Cache & Queue backend |

## Environment Configuration

This project uses a **two-level .env pattern**:

1. **Root `.env`** — Docker Compose settings (ports, database credentials, container config)
2. **`src/.env`** — Laravel application configuration

> **Important**: After generating `APP_KEY` in `src/.env`, copy it to the root `.env` so containers can access it.

## Common Commands

```bash
# Artisan commands (run inside php-fpm container)
docker compose exec php-fpm php artisan <command>

# Database
docker compose exec php-fpm php artisan migrate
docker compose exec php-fpm php artisan tinker

# Queue management
docker compose logs queue
docker compose restart queue

# Run tests
docker compose exec php-fpm php artisan test

# Rebuild containers
docker compose build --no-cache
docker compose up -d --force-recreate
```

## Adding Applications

Add additional Laravel applications using the automated script:

```bash
./docker/scripts/add-app.sh <app-name>
```

See [Multi-App Setup](docs/MULTI-APP.md) for detailed instructions.

## Production Deployment

The production configuration includes:
- Security-hardened containers (non-root, capability dropping)
- Internal backend network isolation
- Rate limiting (API: 10 req/s, Login: 5 req/min)
- Full security headers (CSP, HSTS, X-Frame-Options)
- Automated daily PostgreSQL backups

```bash
docker compose -f docker-compose.prod.yml up -d
```

See [Deployment Guide](docs/DEPLOYMENT.md) for Azure VM deployment instructions.

## Documentation

| Guide | Description |
|-------|-------------|
| [Development](docs/DEVELOPMENT.md) | Local setup, debugging, testing |
| [Docker](docs/DOCKER.md) | Container configuration details |
| [Deployment](docs/DEPLOYMENT.md) | Production deployment to Azure |
| [Multi-App](docs/MULTI-APP.md) | Adding additional Laravel apps |
| [Architecture](docs/ARCHITECTURE.md) | System design and security |
| [Services](docs/SERVICES.md) | Individual service configuration |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is open-sourced software licensed under the [MIT license](LICENSE).
