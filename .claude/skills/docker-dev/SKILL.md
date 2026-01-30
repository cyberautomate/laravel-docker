---
name: docker-dev
description: Docker development workflow commands for Laravel
arguments:
  - name: action
    description: The action to perform (up, down, rebuild, shell, logs, restart)
    required: true
---

# Docker Development Workflow

Manage the Laravel Docker development environment.

## Container Management

### Start containers
```bash
docker compose up -d
```

### Stop containers
```bash
docker compose down
```

### Restart all containers
```bash
docker compose restart
```

### Restart specific service
```bash
docker compose restart <service>
```
Services: nginx, php-fpm, postgres, redis, queue, queue-app2

## Building

### Rebuild all containers
```bash
docker compose build --no-cache
```

### Rebuild specific service
```bash
docker compose build --no-cache <service>
```

### Rebuild and restart
```bash
docker compose up -d --build
```

## Shell Access

### PHP container shell
```bash
docker compose exec php-fpm bash
```

### PostgreSQL shell
```bash
docker compose exec postgres psql -U laravel -d laravel
```

### Redis CLI
```bash
docker compose exec redis redis-cli
```

## Logs

### Follow all logs
```bash
docker compose logs -f
```

### Follow specific service logs
```bash
docker compose logs -f <service>
```

### Tail recent logs
```bash
docker compose logs --tail=100 <service>
```

## Status

### List running containers
```bash
docker compose ps
```

### Check container health
```bash
docker compose ps --format "table {{.Name}}\t{{.Status}}"
```

## Cleanup

### Remove containers and volumes
```bash
docker compose down -v
```

### Prune unused Docker resources
```bash
docker system prune -f
```

## Common Workflows

### Fresh start (reset everything)
```bash
docker compose down -v && docker compose up -d --build
```

### Update after pulling changes
```bash
docker compose build --no-cache php-fpm && docker compose up -d
```
