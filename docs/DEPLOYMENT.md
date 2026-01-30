# Production Deployment Guide

This guide walks you through deploying the Laravel application to an **Azure Virtual Machine running Ubuntu Linux**. The guide assumes your VM has no public IP address and you connect via VPN.

## Table of Contents

1. [Before You Begin](#before-you-begin)
2. [Step 1: Prepare Your Azure VM](#step-1-prepare-your-azure-vm)
3. [Step 2: Install Docker](#step-2-install-docker)
4. [Step 3: Get the Application Code](#step-3-get-the-application-code)
5. [Step 4: Configure Secrets](#step-4-configure-secrets)
6. [Step 5: Deploy the Application](#step-5-deploy-the-application)
7. [Step 6: Verify Everything Works](#step-6-verify-everything-works)
8. [Updating the Application](#updating-the-application)
9. [Rolling Back if Something Goes Wrong](#rolling-back-if-something-goes-wrong)
10. [Monitoring Your Application](#monitoring-your-application)
11. [Troubleshooting](#troubleshooting)
12. [CI/CD Reference](#cicd-reference)

---

## Before You Begin

### What You'll Need

| Item | Description |
|------|-------------|
| Azure VM | Ubuntu 22.04 LTS (or newer) with at least 4GB RAM and 20GB storage |
| VPN Access | Connection to your Azure virtual network to reach the VM |
| SSH Client | Terminal (macOS/Linux) or PuTTY/Windows Terminal (Windows) |
| GitHub Account | Access to the repository containing your Laravel code |

### Architecture Overview

Your production environment will run these services inside Docker containers:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure VM (Ubuntu)                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     Docker Containers                      │  │
│  │  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌─────────────┐  │  │
│  │  │  Nginx  │  │ PHP-FPM │  │ PostgreSQL│  │    Redis    │  │  │
│  │  │  :80    │──│  App    │──│  Database │  │ Cache/Queue │  │  │
│  │  └─────────┘  └─────────┘  └──────────┘  └─────────────┘  │  │
│  │                      │                                      │  │
│  │               ┌──────────────┐    ┌────────────────────┐   │  │
│  │               │ Queue Worker │    │ Backup Service     │   │  │
│  │               │ (Background) │    │ (Daily to Azure)   │   │  │
│  │               └──────────────┘    └────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
            ↑
            │ VPN Connection
            │
        Your Computer
```

---

## Step 1: Prepare Your Azure VM

### Connect to Your VM

1. Connect to your VPN
2. Open your terminal and SSH into the VM:

```bash
ssh your-username@10.x.x.x    # Use your VM's private IP address
```

### Update the System

```bash
# Update package lists and upgrade existing packages
sudo apt update && sudo apt upgrade -y

# Install essential utilities
sudo apt install -y curl git unzip
```

---

## Step 2: Install Docker

### Install Docker Engine

```bash
# Download and run Docker's official install script
curl -fsSL https://get.docker.com | sudo sh

# Add your user to the docker group (so you don't need sudo)
sudo usermod -aG docker $USER
```

### Apply Group Changes

Log out and back in for the group change to take effect:

```bash
exit
```

Then SSH back in:

```bash
ssh your-username@10.x.x.x
```

### Verify Docker is Working

```bash
docker --version
# Expected output: Docker version 24.x.x or higher

docker compose version
# Expected output: Docker Compose version v2.x.x or higher

# Test that Docker runs without sudo
docker run hello-world
```

---

## Step 3: Get the Application Code

### Create the Application Directory

```bash
# Create the directory where the application will live
sudo mkdir -p /var/www/laravel

# Make your user the owner
sudo chown $USER:$USER /var/www/laravel

# Navigate to the directory
cd /var/www/laravel
```

### Clone the Repository

```bash
# Clone your repository (replace with your actual repo URL)
git clone https://github.com/your-org/your-laravel-app.git .

# The . at the end clones into the current directory
```

If your repository is private, you'll need to authenticate. You can either:
- Use a GitHub Personal Access Token
- Set up SSH keys on the VM

---

## Step 4: Configure Secrets

The application uses Docker secrets stored in text files. This keeps sensitive data out of environment variables and logs.

### Create the Secrets Directory

```bash
cd /var/www/laravel
mkdir -p secrets
```

### Generate Your Secrets

You'll need to create 6 secret files. Use these commands to generate secure values:

#### 1. Application Key

```bash
# Generate a random Laravel application key
echo "base64:$(openssl rand -base64 32)" > secrets/app_key.txt
```

#### 2. Database Username

```bash
# Set your database username
echo "laravel" > secrets/db_username.txt
```

#### 3. Database Password

```bash
# Generate a secure database password
openssl rand -base64 24 > secrets/db_password.txt

# View it so you can save it somewhere safe
cat secrets/db_password.txt
```

#### 4. Redis Password

```bash
# Generate a secure Redis password
openssl rand -base64 24 > secrets/redis_password.txt
```

#### 5. Azure Storage Account (for backups)

```bash
# Enter your Azure Storage Account name
echo "your_storage_account_name" > secrets/azure_storage_account.txt
```

#### 6. Azure Storage Key (for backups)

```bash
# Enter your Azure Storage Account key
echo "your_storage_account_key_here" > secrets/azure_storage_key.txt
```

> **Finding your Azure Storage credentials:**
> 1. Go to the Azure Portal
> 2. Navigate to your Storage Account
> 3. Click "Access keys" in the left sidebar
> 4. Copy the "Storage account name" and one of the "Key" values

### Secure the Secrets Directory

```bash
# Make secrets readable only by your user
chmod 700 secrets
chmod 600 secrets/*
```

### Verify Your Secrets

```bash
# List all secret files (should show 6 files)
ls -la secrets/

# Output should look like:
# -rw------- 1 user user   xx Jan 30 12:00 app_key.txt
# -rw------- 1 user user   xx Jan 30 12:00 azure_storage_account.txt
# -rw------- 1 user user   xx Jan 30 12:00 azure_storage_key.txt
# -rw------- 1 user user   xx Jan 30 12:00 db_password.txt
# -rw------- 1 user user   xx Jan 30 12:00 db_username.txt
# -rw------- 1 user user   xx Jan 30 12:00 redis_password.txt
```

---

## Step 5: Deploy the Application

### Pull the Docker Images

```bash
cd /var/www/laravel

# Pull all required images (this may take a few minutes the first time)
docker compose -f docker-compose.prod.yml pull
```

### Start the Containers

```bash
# Start all services in the background
docker compose -f docker-compose.prod.yml up -d
```

You'll see output like:
```
[+] Running 6/6
 ✔ Network laravel-frontend-prod  Created
 ✔ Network laravel-backend-prod   Created
 ✔ Container laravel-redis        Started
 ✔ Container laravel-postgres     Started
 ✔ Container laravel-php          Started
 ✔ Container laravel-nginx        Started
 ✔ Container laravel-queue        Started
 ✔ Container laravel-backup       Started
```

### Run Database Migrations

```bash
# Run Laravel migrations to set up the database tables
docker compose -f docker-compose.prod.yml exec php-fpm php artisan migrate --force
```

Type `yes` if prompted to confirm running in production.

### Build the Caches

```bash
# Cache configuration for better performance
docker compose -f docker-compose.prod.yml exec php-fpm php artisan config:cache
docker compose -f docker-compose.prod.yml exec php-fpm php artisan route:cache
docker compose -f docker-compose.prod.yml exec php-fpm php artisan view:cache
docker compose -f docker-compose.prod.yml exec php-fpm php artisan event:cache
```

---

## Step 6: Verify Everything Works

### Check Container Status

```bash
docker compose -f docker-compose.prod.yml ps
```

All containers should show `Up` and `(healthy)`:
```
NAME               STATUS                   PORTS
laravel-nginx      Up 2 minutes (healthy)   0.0.0.0:80->80/tcp
laravel-php        Up 2 minutes (healthy)   9000/tcp
laravel-postgres   Up 2 minutes (healthy)   5432/tcp
laravel-redis      Up 2 minutes (healthy)   6379/tcp
laravel-queue      Up 2 minutes
laravel-backup     Up 2 minutes
```

### Test the Health Endpoint

```bash
curl http://localhost/health
```

Expected output:
```
healthy
```

### Test the Application

Open a browser and navigate to your VM's private IP address:
```
http://10.x.x.x/
```

You should see your Laravel application's homepage.

---

## Updating the Application

When you need to deploy new code changes:

### Quick Update (No Database Changes)

```bash
cd /var/www/laravel

# Pull latest code
git pull origin main

# Pull latest Docker images
docker compose -f docker-compose.prod.yml pull

# Restart containers with new images
docker compose -f docker-compose.prod.yml up -d --remove-orphans

# Clear and rebuild caches
docker compose -f docker-compose.prod.yml exec php-fpm php artisan config:cache
docker compose -f docker-compose.prod.yml exec php-fpm php artisan route:cache
docker compose -f docker-compose.prod.yml exec php-fpm php artisan view:cache

# Tell queue workers to restart after their current job
docker compose -f docker-compose.prod.yml exec php-fpm php artisan queue:restart

# Verify the update
curl http://localhost/health
```

### Full Update (With Database Changes)

```bash
cd /var/www/laravel

# Pull latest code
git pull origin main

# Pull latest Docker images
docker compose -f docker-compose.prod.yml pull

# Run database migrations BEFORE restarting containers
docker compose -f docker-compose.prod.yml exec php-fpm php artisan migrate --force

# Restart containers
docker compose -f docker-compose.prod.yml up -d --remove-orphans

# Rebuild caches
docker compose -f docker-compose.prod.yml exec php-fpm php artisan config:cache
docker compose -f docker-compose.prod.yml exec php-fpm php artisan route:cache
docker compose -f docker-compose.prod.yml exec php-fpm php artisan view:cache

# Restart queue workers
docker compose -f docker-compose.prod.yml exec php-fpm php artisan queue:restart

# Verify
curl http://localhost/health
```

---

## Rolling Back if Something Goes Wrong

### Roll Back to Previous Code

If an update causes problems, you can quickly revert:

```bash
cd /var/www/laravel

# See recent commits to find the one you want
git log --oneline -10

# Roll back to a specific commit
git checkout <commit-hash>

# Restart containers
docker compose -f docker-compose.prod.yml up -d

# Verify
curl http://localhost/health
```

### Roll Back Database Migrations

If a migration caused issues:

```bash
# Undo the last migration
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan migrate:rollback --step=1

# Undo multiple migrations (e.g., last 3)
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan migrate:rollback --step=3
```

### Complete Restore from Backup

For major issues, restore from a database backup:

```bash
# Stop the application
docker compose -f docker-compose.prod.yml down

# List available backups
ls -la /var/lib/docker/volumes/laravel-backup-data-prod/_data/

# Restore a specific backup (replace YYYYMMDD with the date)
docker compose -f docker-compose.prod.yml run --rm backup \
  pg_restore -h postgres -U laravel -d laravel /backup/backup_YYYYMMDD.sql

# Start the application
docker compose -f docker-compose.prod.yml up -d
```

---

## Monitoring Your Application

### View Container Status

```bash
# Quick status check
docker compose -f docker-compose.prod.yml ps

# Detailed resource usage (CPU, memory)
docker stats
```

### View Logs

```bash
# All logs (follow mode - press Ctrl+C to exit)
docker compose -f docker-compose.prod.yml logs -f

# Logs from a specific service
docker compose -f docker-compose.prod.yml logs -f nginx
docker compose -f docker-compose.prod.yml logs -f php-fpm
docker compose -f docker-compose.prod.yml logs -f postgres
docker compose -f docker-compose.prod.yml logs -f queue

# Laravel application logs
docker compose -f docker-compose.prod.yml exec php-fpm \
  tail -100 storage/logs/laravel.log
```

### Check Queue Jobs

```bash
# See failed jobs
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan queue:failed

# Retry all failed jobs
docker compose -f docker-compose.prod.yml exec php-fpm \
  php artisan queue:retry all
```

### Database Information

```bash
# Connect to PostgreSQL
docker compose -f docker-compose.prod.yml exec postgres \
  psql -U laravel

# Check active connections
docker compose -f docker-compose.prod.yml exec postgres \
  psql -U laravel -c "SELECT count(*) FROM pg_stat_activity;"
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check what's wrong
docker compose -f docker-compose.prod.yml logs php-fpm

# Common fixes:
# 1. Secrets files missing or wrong permissions
ls -la secrets/

# 2. Port 80 already in use
sudo lsof -i :80
```

### "Permission Denied" Errors

```bash
# Fix storage permissions
docker compose -f docker-compose.prod.yml exec php-fpm \
  chmod -R 775 storage bootstrap/cache
```

### Database Connection Failed

```bash
# Check PostgreSQL is running
docker compose -f docker-compose.prod.yml logs postgres

# Verify the password file exists and is readable
cat secrets/db_password.txt
```

### Application Shows Error Page

```bash
# Check Laravel logs for details
docker compose -f docker-compose.prod.yml exec php-fpm \
  tail -50 storage/logs/laravel.log

# Clear all caches and try again
docker compose -f docker-compose.prod.yml exec php-fpm php artisan cache:clear
docker compose -f docker-compose.prod.yml exec php-fpm php artisan config:clear
```

### Redis Connection Failed

```bash
# Check Redis is running
docker compose -f docker-compose.prod.yml exec redis redis-cli ping
# Should return: PONG
```

---

## CI/CD Reference

If you want to automate deployments using GitHub Actions, the workflow file is located at `.github/workflows/deploy.yml`.

### Required GitHub Secrets

Configure these in your GitHub repository under Settings → Secrets and variables → Actions:

| Secret | Description | Example |
|--------|-------------|---------|
| `SSH_PRIVATE_KEY` | Private SSH key for connecting to your VM | Contents of `~/.ssh/id_rsa` |
| `SERVER_HOST` | Your VM's private IP address | `10.0.1.50` |
| `SERVER_USER` | SSH username | `azureuser` |
| `SLACK_WEBHOOK_URL` | (Optional) For deployment notifications | `https://hooks.slack.com/...` |

### How the Pipeline Works

```
Push to main branch
        │
        ▼
   ┌─────────┐     ┌─────────┐     ┌─────────┐
   │  TEST   │ ──▶ │  BUILD  │ ──▶ │ DEPLOY  │
   │         │     │         │     │         │
   │ PHPUnit │     │ Docker  │     │ SSH to  │
   │ Tests   │     │ Images  │     │ Server  │
   └─────────┘     └─────────┘     └─────────┘
```

1. **Test**: Runs PHPUnit tests against a temporary database
2. **Build**: Creates production Docker images and pushes to GitHub Container Registry
3. **Deploy**: Connects via SSH and runs the update commands

---

## Related Documentation

- [Architecture Overview](./ARCHITECTURE.md) - System design and component relationships
- [Docker Configuration](./DOCKER.md) - Detailed Docker setup information
- [Services Configuration](./SERVICES.md) - Individual service settings
- [Development Guide](./DEVELOPMENT.md) - Local development setup
