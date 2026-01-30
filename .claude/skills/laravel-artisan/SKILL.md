---
name: laravel-artisan
description: Run Laravel artisan commands in the Docker php-fpm container
arguments:
  - name: command
    description: The artisan command to run (e.g., migrate, make:model User, cache:clear)
    required: true
---

# Laravel Artisan Commands

Execute artisan commands in the php-fpm Docker container.

## Usage

Run the command in the container:
```bash
docker compose exec php-fpm php artisan <command>
```

## Common Commands

### Database
- `migrate` - Run pending migrations
- `migrate:fresh --seed` - Drop all tables and re-run migrations with seeders
- `migrate:rollback` - Rollback the last migration batch
- `migrate:status` - Show migration status
- `db:seed` - Run database seeders

### Code Generation
- `make:model ModelName -mfc` - Create model with migration, factory, and controller
- `make:controller ControllerName` - Create a controller
- `make:migration create_table_name` - Create a migration
- `make:livewire ComponentName` - Create a Livewire component
- `make:middleware MiddlewareName` - Create middleware
- `make:request RequestName` - Create a form request
- `make:job JobName` - Create a queued job

### Cache & Config
- `cache:clear` - Clear application cache
- `config:clear` - Clear config cache
- `config:cache` - Cache config (for production)
- `route:clear` - Clear route cache
- `view:clear` - Clear compiled views
- `optimize:clear` - Clear all caches

### Queue
- `queue:work` - Start processing jobs
- `queue:listen` - Listen for jobs (restarts on code changes)
- `queue:restart` - Restart queue workers
- `queue:failed` - List failed jobs
- `queue:retry all` - Retry all failed jobs

### Other
- `tinker` - Interactive REPL
- `route:list` - List all routes
- `schedule:list` - List scheduled tasks
- `key:generate` - Generate application key
