# Enceladus

Deployment and infrastructure-as-code for Enceladus (DigitalOcean Droplet).

## Overview

Enceladus hosts personal web applications using Docker Compose with Traefik as a reverse proxy for automatic HTTPS via Let's Encrypt.

**Current services:**
- **Convex**: Conversation archive application (`convex.alexgs.me`)
- **Skyreach**: D&D campaign website (`skyreach.alexgs.me`)
- **Traefik**: Reverse proxy with automatic HTTPS

## Prerequisites

- DigitalOcean Droplet running Ubuntu 24.04
- Docker and Docker Compose installed on the droplet
- DNS records configured (A or CNAME records pointing to droplet IP)
- [Task](https://taskfile.dev) installed for task automation

## First-Time Setup

### 1. Clone Repository on Server

```bash
ssh alexgs@enceladus
cd ~
mkdir -p devops
cd devops
git clone <repo-url> .
cd enceladus
```

### 2. Configure Environment Variables

```bash
# Copy environment templates
cp .env.example .env
cp convex.env.example convex.env
cp skyreach.env.example skyreach.env

# Edit environment files and add your actual API keys and secrets
nano convex.env
nano skyreach.env
```

**Required credentials for Convex:**
- Clerk authentication keys (production keys from dashboard.clerk.com)
- OpenAI API key
- Anthropic API key
- FontAwesome NPM auth token
- GitHub OAuth client ID and secret

**Required credentials for Skyreach:**
- Clerk authentication keys (production keys from dashboard.clerk.com)

### 3. Create Let's Encrypt Storage

```bash
# The acme.json file must have restricted permissions
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json
```

### 4. Create Host Directories for Bind Mounts

The Convex container persists its search log database to a host-mounted
directory so writes survive image rebuilds and container restarts. The
directory must exist before `docker compose up` runs, or the bind mount
will fail.

```bash
mkdir -p convex-search-log
```

### 5. Start Services

```bash
# Start all services
task up

# Follow logs to verify startup
task convex:logs
task skyreach:logs
task traefik:logs
```

### 6. Verify Deployment

- Visit `https://convex.alexgs.me` - should redirect to HTTPS and show valid certificate
- Visit `https://skyreach.alexgs.me` - should redirect to HTTPS and show valid certificate
- Check Traefik logs for any certificate errors: `task traefik:logs`
- Check Convex logs for application errors: `task convex:logs`
- Check Skyreach logs for application errors: `task skyreach:logs`

## Common Operations

### Deploy Updates

**Convex:**
```bash
# Pull latest image and restart service
task convex:update
```

**Skyreach:**
```bash
# Pull latest image and restart service
task skyreach:update
```

### View Logs

```bash
# Follow Convex logs
task convex:logs

# Follow Skyreach logs
task skyreach:logs

# Follow Traefik logs (for routing/SSL issues)
task traefik:logs

# View all service logs
docker compose logs -f
```

### Restart Services

```bash
# Restart just Convex
task convex:restart

# Restart just Skyreach
task skyreach:restart

# Restart all services
task down && task up
```

### Access Container Shell

```bash
# Open shell in Convex container
task convex:shell

# Open shell in Skyreach container
task skyreach:shell
```

### Stop All Services

```bash
task down
```

### Access Traefik Dashboard

The dashboard is only accessible from localhost for security. To access it:

```bash
# From your local machine, create an SSH tunnel
ssh -L 8080:localhost:8080 alexgs@enceladus

# Then visit in your browser
http://localhost:8080/dashboard/
```

## DNS Configuration

Each service requires a DNS record pointing to the Enceladus droplet:

**Option 1 - A Record:**
```
convex.alexgs.me    A    <Enceladus IP>
```

**Option 2 - CNAME (recommended):**
```
enceladus.alexgs.me    A       <Enceladus IP>
convex.alexgs.me       CNAME   enceladus.alexgs.me
skyreach.alexgs.me     CNAME   enceladus.alexgs.me
```

Using CNAME records means you only need to update the IP in one place if it changes.

## Troubleshooting

### SSL Certificate Issues

**Problem:** Let's Encrypt certificate not generating

**Solutions:**
1. Verify DNS record points to droplet: `dig convex.alexgs.me`
2. Verify ports 80 and 443 are open in firewall
3. Check Traefik logs: `task traefik:logs`
4. Verify `letsencrypt/acme.json` has correct permissions: `ls -la letsencrypt/`

### Service Won't Start

**Problem:** Container exits or won't start

**Solutions:**
1. Check logs: `task convex:logs`
2. Verify environment variables: `docker exec convex env | grep CLERK`
3. Verify image pulled: `docker images | grep convex`
4. Check docker-compose syntax: `docker compose config`

### Can't Access Service

**Problem:** Service not accessible at domain

**Solutions:**
1. Check if container is running: `docker ps`
2. Check Traefik routing: `task traefik:logs`
3. Verify DNS: `dig convex.alexgs.me`
4. Check Traefik can see service: `docker exec webserver cat /etc/traefik/traefik.yml`

## Adding New Services

To add another web application:

1. Add service definition to `docker-compose.yml` (use Convex as template)
2. Create `<service-name>.env.example` and `<service-name>.env` files
3. Add Traefik labels for routing and TLS
4. Add task commands to `Taskfile.yml`
5. Configure DNS (A or CNAME record)
6. Start with `task up`

## Application-Specific Notes

### Skyreach D&D Website

The Skyreach D&D campaign website is deployed as a containerized Astro SSR application with Clerk authentication.

**Key details:**
- Campaign data is baked into the Docker image at `/app/data/`
- No volumes needed for data persistence
- To update campaign content, rebuild the Docker image and run `task skyreach:update`
- Requires Clerk authentication - ensure production keys are configured in `skyreach.env`

**Deploy updates:**
```bash
task skyreach:update
```

**View logs:**
```bash
task skyreach:logs
```

**Troubleshooting:**
If the site isn't loading:
1. Check container status: `docker ps | grep skyreach`
2. Check logs: `task skyreach:logs`
3. Verify DNS record: `dig skyreach.alexgs.me`
4. Check Traefik routing: `task traefik:logs`
5. Verify Clerk credentials are correctly configured

## Directory Structure

```
enceladus/
├── docker-compose.yml      # Service definitions
├── Taskfile.yml           # Task automation commands
├── .env                   # Root environment variables (not committed)
├── *.env                  # Service-specific env files (not committed)
├── traefik/
│   └── traefik.yml       # Traefik configuration
├── letsencrypt/
│   └── acme.json         # Let's Encrypt certificates (not committed)
├── logs/                 # Application logs (not committed)
└── convex-search-log/    # Convex search log SQLite DB (not committed)
```

## Security Notes

- Never commit `.env` files or `letsencrypt/acme.json` to git
- Keep `acme.json` with `600` permissions
- Use production API keys in production environments
- Regularly update Docker images for security patches
