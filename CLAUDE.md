# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a DevOps repository containing infrastructure-as-code and Docker configurations for deploying web applications to DigitalOcean Droplets. The repository supports multiple deployment targets and custom Docker images for development environments.

## Key Directories

- **daphnis/**: Production infrastructure for the "Daphnis" droplet (note: the actual droplet may be named "Enceladus" now, but the directory name remains)
  - Contains Docker Compose configurations for deployed web applications
  - Uses Traefik as reverse proxy with automatic HTTPS via Let's Encrypt
  - Managed via Task (go-task/task) - see `Taskfile.yml`
- **docker-images/**: Custom Docker images for local development
  - `node/`: Ubuntu-based Node.js development environment with Volta, PostgreSQL client, zsh, oh-my-zsh
  - `flyway/`: Database migration environment with Flyway, Java, Node.js, and PostgreSQL client
- **documentation/**: Reference documentation for PostgreSQL commands and securing databases
- **enceladus/**: Deployment specifications (currently contains Convex app deployment spec)

## Task Runner Commands

The `daphnis/` directory uses [Task](https://taskfile.dev/) for automation. Commands are run from within `daphnis/`:

```bash
# Core application commands
task up              # Start all services with docker-compose up -d
task down            # Stop all services with docker-compose down --remove-orphans

# Database commands
task db:psql         # Connect to PostgreSQL as application user
task db:psql-admin   # Connect to PostgreSQL as admin user (hidden command)

# Container access
task elc:shell       # Open shell on electric-lounge container

# Dangerous commands
task db:DANGEROUS:initialize  # Initialize PostgreSQL data directory (USE WITH CAUTION)
```

## Environment Variables

- Root/shared environment variables are in `daphnis/.env` (not committed to Git)
- Each web application has its own env file: `daphnis/<application>.env` (not committed to Git)
- Environment variables are referenced in `Taskfile.yml` for database connections and container names

## Docker Compose Architecture

The `daphnis/docker-compose.yml` defines a multi-service architecture:

### Services

1. **database** (postgres:13-alpine)
   - Exposed on host port defined by `$DATABASE_PORT`
   - Data persisted at `$DATABASE_DIRECTORY_POSTGRES`

2. **Web Applications** (dnd-compendium, electric-lounge)
   - Each has Traefik labels for routing and TLS
   - Connected to `webapp-net` network
   - Use env files for configuration

3. **webserver** (traefik:2.4)
   - Reverse proxy handling all HTTP/HTTPS traffic
   - Automatic HTTPS with Let's Encrypt via DNS challenge (DigitalOcean)
   - Configuration in `daphnis/traefik/traefik.yml`
   - Certificate resolver: `daphnis-resolver`

4. **soxy-proxy** (tecnativa/docker-socket-proxy)
   - Secure Docker socket proxy for Traefik
   - Connected to isolated `socker-net` network

### Networks

- **webapp-net**: Bridge network for web applications and Traefik
- **socker-net**: Encrypted bridge network for Docker socket access

### Traefik Configuration

Entry points:
- `web-default` (port 80): Auto-redirects to HTTPS
- `web-secure` (port 443): HTTPS endpoint

Traefik labels pattern for new services:
```yaml
labels:
  - "traefik.http.routers.<service-name>.rule=Host(`<domain>`)"
  - "traefik.http.routers.<service-name>.tls=true"
  - "traefik.http.routers.<service-name>.tls.certresolver=daphnis-resolver"
  - "traefik.http.services.<service-name>.loadbalancer.server.port=<port>"
```

## PostgreSQL Operations

Common database operations are documented in `documentation/postgresql-common-commands.md`:

- **Backup (SQL)**: `pg_dump -U $DATABASE_USER -W $DATABASE_NAME > backup.sql`
- **Backup (binary)**: `pg_dump -U $DATABASE_USER -p $DATABASE_PORT -Fc $DATABASE_NAME > backup.pgsql`
- **Restore**: `PGPASSWORD=$DATABASE_PASSWORD pg_restore -U $DATABASE_USER -h $DATABASE_HOST -p $DATABASE_PORT -d $DATABASE_NAME backup.pgsql`
- **Container access**: `docker exec -it database sh`

## Custom Docker Images

### Node Image

Ubuntu 20.04-based development environment with:
- Volta for Node.js/npm version management
- PostgreSQL 13 client
- Task runner
- Zsh with oh-my-zsh and Spaceship prompt
- Build tools and sudo access
- Default user: `node` (UID/GID 1000)

### Flyway Image

Extends Node image with:
- Java (AdoptOpenJDK 11)
- Flyway 8.0.0-beta1 for database migrations
- Node.js for migration scripting
- PostgreSQL client

## Git Workflow

- Main development branch: `develop`
- Current branch: `deploy-convex-to-enceladus` (feature branch)
- Follow feature branch naming convention: `feature/<description>`

## Adding New Services to Daphnis

When adding a new web application:

1. Add service definition to `docker-compose.yml` following existing patterns
2. Create `<app-name>.env` file (add `.env.example` template if needed)
3. Use `webapp-net` network
4. Add Traefik labels for routing and TLS
5. Ensure DNS A record points to droplet IP
6. Test with `task up` and verify HTTPS certificate generation
7. Add relevant Task commands to `Taskfile.yml` if needed

## Important Notes

- **Never commit** `.env` files or any files in `daphnis/backup/`
- The repository directory on the droplet is `/home/alexgs/devops/daphnis/` (note: still uses old "daphnis" name)
- Logs for electric-lounge are stored in `daphnis/logs/` (bind mount to host)
- Traefik network name in config is `daphnis-net` but docker-compose.yml uses `webapp-net` - verify which is correct when deploying
