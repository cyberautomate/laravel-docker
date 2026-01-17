# Application Architecture

This document provides a comprehensive overview of the Laravel Docker application architecture, including system design, component relationships, and data flow.

## Table of Contents

- [System Overview](#system-overview)
- [Directory Structure](#directory-structure)
- [Architecture Diagram](#architecture-diagram)
- [Component Overview](#component-overview)
- [Network Architecture](#network-architecture)
- [Data Flow](#data-flow)
- [Security Architecture](#security-architecture)

---

## System Overview

This application is a **Laravel 12** web application containerized using **Docker** with a multi-service architecture designed for both development and production environments.

### Technology Stack

| Layer | Technology | Version |
|-------|------------|---------|
| Web Server | Nginx | 1.27-alpine |
| Application | PHP-FPM | 8.4-alpine |
| Framework | Laravel | 12.0 |
| Database | PostgreSQL | 17-alpine |
| Cache/Queue | Redis | 7-alpine |
| Frontend | Tailwind CSS | 4.x |
| Build Tool | Vite | 7.x |

### Key Features

- **Containerized Architecture**: All services run in isolated Docker containers
- **Environment Parity**: Development and production use identical base configurations
- **Horizontal Scalability**: Stateless application design with external session/cache storage
- **Security Hardened**: Production containers run as non-root with minimal capabilities
- **Zero-Downtime Deployments**: CI/CD pipeline supports rolling updates

---

## Directory Structure

```
laravel/
├── src/                          # Laravel application source code
│   ├── app/                      # Application logic
│   │   ├── Http/Controllers/     # HTTP request handlers
│   │   ├── Models/               # Eloquent ORM models
│   │   └── Providers/            # Service providers
│   ├── bootstrap/                # Framework bootstrap files
│   ├── config/                   # Configuration files
│   ├── database/                 # Migrations, factories, seeders
│   ├── public/                   # Web root (index.php, assets)
│   ├── resources/                # Views, CSS, JavaScript
│   ├── routes/                   # Route definitions
│   ├── storage/                  # Logs, cache, sessions
│   ├── tests/                    # Test suites
│   └── vendor/                   # Composer dependencies
│
├── docker/                       # Docker configuration
│   ├── common/php-fpm/           # Multi-stage PHP Dockerfile
│   ├── development/              # Development-specific configs
│   │   ├── nginx/                # Dev Nginx configuration
│   │   └── php/                  # Dev PHP settings
│   ├── production/               # Production-specific configs
│   │   ├── nginx/                # Prod Nginx with security headers
│   │   └── php/                  # Hardened PHP settings
│   └── scripts/                  # Entrypoint and utility scripts
│       ├── entrypoint/           # Container startup scripts
│       └── backup/               # Database backup scripts
│
├── secrets/                      # Production secrets (git-ignored)
├── backups/                      # Database backup storage
├── .github/workflows/            # CI/CD pipeline definitions
│
├── docker-compose.yml            # Development environment
├── docker-compose.prod.yml       # Production environment
├── .env                          # Environment configuration
└── docs/                         # This documentation
```

---

## Architecture Diagram

```
                                    ┌─────────────────────────────────────────────────────────────┐
                                    │                     EXTERNAL TRAFFIC                        │
                                    │                    (Cloudflare CDN)                         │
                                    └─────────────────────────┬───────────────────────────────────┘
                                                              │
                                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                        FRONTEND NETWORK                                             │
│  ┌────────────────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                                                                                                │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────────────────┐  │ │
│  │  │                              NGINX (Port 80/443)                                        │  │ │
│  │  │  ┌─────────────────┐  ┌──────────────────┐  ┌─────────────────────────────────────┐    │  │ │
│  │  │  │  Static Files   │  │   Rate Limiting  │  │       Security Headers              │    │  │ │
│  │  │  │  (CSS/JS/IMG)   │  │   (10 req/s API) │  │  (CSP, HSTS, X-Frame-Options)       │    │  │ │
│  │  │  └─────────────────┘  └──────────────────┘  └─────────────────────────────────────┘    │  │ │
│  │  │                              │                                                          │  │ │
│  │  │                              ▼ FastCGI (port 9000)                                      │  │ │
│  │  └──────────────────────────────┼──────────────────────────────────────────────────────────┘  │ │
│  │                                 │                                                              │ │
│  └─────────────────────────────────┼──────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────┼────────────────────────────────────────────────────────────────┘
                                     │
                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                        BACKEND NETWORK (Internal)                                   │
│                                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                                     PHP-FPM (Port 9000)                                     │   │
│  │  ┌────────────────────────────────────────────────────────────────────────────────────────┐│   │
│  │  │                              LARAVEL 12 APPLICATION                                    ││   │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐   ││   │
│  │  │  │  Controllers │  │    Models    │  │   Services   │  │      Middleware          │   ││   │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────────────────┘   ││   │
│  │  └────────────────────────────────────────────────────────────────────────────────────────┘│   │
│  │                    │                              │                         │              │   │
│  └────────────────────┼──────────────────────────────┼─────────────────────────┼──────────────┘   │
│                       │                              │                         │                  │
│                       ▼                              ▼                         ▼                  │
│  ┌────────────────────────────────┐  ┌───────────────────────────┐  ┌─────────────────────────┐   │
│  │      PostgreSQL (Port 5432)   │  │     Redis (Port 6379)     │  │    Queue Worker         │   │
│  │  ┌──────────────────────────┐ │  │  ┌─────────────────────┐  │  │  ┌───────────────────┐  │   │
│  │  │    laravel database      │ │  │  │  Session Storage    │  │  │  │  php artisan      │  │   │
│  │  │  ┌────────┐ ┌─────────┐  │ │  │  │  Cache Storage      │  │  │  │  queue:work       │  │   │
│  │  │  │ users  │ │  jobs   │  │ │  │  │  Queue Backend      │  │  │  │                   │  │   │
│  │  │  └────────┘ └─────────┘  │ │  │  └─────────────────────┘  │  │  └───────────────────┘  │   │
│  │  └──────────────────────────┘ │  └───────────────────────────┘  └─────────────────────────┘   │
│  │                               │                                                               │
│  │  Volume: postgres_data        │  Volume: redis_data                                           │
│  └───────────────────────────────┘                                                               │
│                                                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              Backup Service (Production Only)                               │   │
│  │                         Daily PostgreSQL backups to Azure Blob Storage                      │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Overview

### Nginx (Web Server)

**Purpose**: Reverse proxy, static file serving, SSL termination, security headers

**Responsibilities**:
- Routes HTTP requests to PHP-FPM via FastCGI
- Serves static assets directly (CSS, JS, images)
- Applies security headers and rate limiting
- Handles gzip compression
- Provides health check endpoint at `/health`

**Configuration Differences**:

| Aspect | Development | Production |
|--------|-------------|------------|
| Timeout | 300s (for Xdebug) | 30s |
| Rate Limiting | Disabled | 10 req/s API, 5 req/min login |
| Security Headers | Basic | Full CSP, HSTS, etc. |
| Cloudflare IPs | Not configured | Real IP restoration |

### PHP-FPM (Application Server)

**Purpose**: Execute PHP code, run Laravel application

**Responsibilities**:
- Process PHP requests from Nginx
- Manage Laravel application lifecycle
- Handle database connections via PDO
- Communicate with Redis for cache/sessions
- Execute Artisan commands

**Key Extensions**:
- `pdo_pgsql`, `pgsql` - PostgreSQL connectivity
- `redis` - Redis connectivity
- `opcache` - Bytecode caching
- `gd` - Image manipulation
- `intl`, `mbstring` - Internationalization

### PostgreSQL (Database)

**Purpose**: Persistent data storage

**Responsibilities**:
- Store application data (users, jobs, etc.)
- Handle ACID transactions
- Manage migrations via Laravel

**Configuration**:
- Character set: UTF-8
- SSL mode: prefer
- Search path: public

### Redis (Cache/Queue)

**Purpose**: In-memory data store for caching, sessions, and queues

**Responsibilities**:
- **Session Storage**: User session data
- **Cache Storage**: Application cache (queries, views, routes)
- **Queue Backend**: Background job queue
- **Rate Limiting**: Request throttling data

**Configuration**:
- Persistence: AOF (append-only file)
- Max memory: 256MB
- Eviction policy: allkeys-lru

### Queue Worker

**Purpose**: Process background jobs asynchronously

**Responsibilities**:
- Execute queued jobs from Redis
- Retry failed jobs (up to 3 attempts)
- Handle long-running tasks outside request cycle

**Command**: `php artisan queue:work redis --sleep=3 --tries=3 --max-time=3600`

---

## Network Architecture

### Development Networks

```yaml
networks:
  frontend:
    driver: bridge    # Nginx accessible externally
  backend:
    driver: bridge    # Internal services only
```

### Production Networks

```yaml
networks:
  frontend:
    driver: bridge    # Nginx accessible externally
  backend:
    driver: bridge
    internal: true    # No external access (security)
```

### Service Network Placement

| Service | Frontend | Backend |
|---------|----------|---------|
| Nginx | ✓ | ✓ |
| PHP-FPM | | ✓ |
| PostgreSQL | | ✓ |
| Redis | | ✓ |
| Queue | | ✓ |
| Backup | | ✓ |

### Port Mappings

| Service | Container Port | Host Port (Dev) | Host Port (Prod) |
|---------|---------------|-----------------|------------------|
| Nginx | 80 | 80 | 80 |
| PostgreSQL | 5432 | 5432 | Not exposed |
| Redis | 6379 | 6379 | Not exposed |

---

## Data Flow

### HTTP Request Flow

```
1. Client Request
       ↓
2. Cloudflare (CDN/WAF) [Production]
       ↓
3. Nginx
   ├── Static file? → Serve directly
   └── PHP request? → FastCGI to PHP-FPM
       ↓
4. PHP-FPM
   ├── Laravel bootstraps
   ├── Middleware executes
   ├── Route matches
   └── Controller handles
       ↓
5. Controller Logic
   ├── Cache hit? → Return from Redis
   ├── Database query → PostgreSQL
   └── Queue job? → Push to Redis
       ↓
6. Response Generation
   ├── View rendering
   └── JSON serialization
       ↓
7. Response to Client
```

### Background Job Flow

```
1. Application dispatches job
       ↓
2. Job serialized to Redis queue
       ↓
3. Queue Worker picks up job
       ↓
4. Job executes
   ├── Database operations
   ├── External API calls
   └── File operations
       ↓
5. Job completes or fails
   ├── Success → Remove from queue
   └── Failure → Retry or fail permanently
```

### Session/Cache Flow

```
Read:
1. Request arrives
2. Session ID from cookie
3. Fetch from Redis
4. Deserialize session data

Write:
1. Session modified
2. Serialize data
3. Store in Redis
4. Set cookie if new
```

---

## Security Architecture

### Defense in Depth

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: Cloudflare                                            │
│  - DDoS protection                                              │
│  - WAF rules                                                    │
│  - SSL termination                                              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Layer 2: Nginx                                                 │
│  - Rate limiting                                                │
│  - Security headers (CSP, HSTS, X-Frame-Options)                │
│  - Request filtering                                            │
│  - Hidden sensitive files (.env, .git)                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3: PHP-FPM                                               │
│  - Disabled dangerous functions                                 │
│  - open_basedir restriction                                     │
│  - Session security (httponly, secure, samesite)                │
│  - Non-root user                                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Layer 4: Laravel                                               │
│  - CSRF protection                                              │
│  - XSS prevention (Blade escaping)                              │
│  - SQL injection prevention (Eloquent/Query Builder)            │
│  - Authentication/Authorization                                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Layer 5: Network Isolation                                     │
│  - Backend network internal-only                                │
│  - Database not exposed externally                              │
│  - Redis password protected                                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Layer 6: Container Security                                    │
│  - Non-root users                                               │
│  - Capability dropping (CAP_DROP: ALL)                          │
│  - Read-only filesystems                                        │
│  - Resource limits                                              │
│  - Docker secrets for credentials                               │
└─────────────────────────────────────────────────────────────────┘
```

### Secrets Management

**Development**: Environment variables in `.env` file

**Production**: Docker secrets mounted at runtime
- `/run/secrets/app_key`
- `/run/secrets/db_username`
- `/run/secrets/db_password`
- `/run/secrets/redis_password`
- `/run/secrets/azure_storage_account`
- `/run/secrets/azure_storage_key`

---

## Related Documentation

- [Docker Configuration](./DOCKER.md) - Detailed Docker setup
- [Services Configuration](./SERVICES.md) - Individual service details
- [Deployment Guide](./DEPLOYMENT.md) - CI/CD and deployment
- [Development Guide](./DEVELOPMENT.md) - Local development setup
