# Deployment Spec for Claude Code: Skyreach D&D Web App on Enceladus

## Context

Deploy the Skyreach D&D campaign website to the DigitalOcean Droplet "Enceladus" alongside the Convex application, using Docker Compose and Traefik for routing.

## Current Infrastructure (Enceladus)

- **OS:** Ubuntu 24.04
- **User:** alexgs (with sudo)
- **Docker:** Installed and running
- **Existing setup:** Located in `/home/alexgs/devops/enceladus/`
- **Current services:** Convex (conversation archive) and Traefik (reverse proxy)
- **Network:** `webapp-net` (existing Docker network)

## Skyreach D&D Application Details

- **Docker image:** Available on GHCR (GitHub Container Registry)
- **Image name:** `ghcr.io/alexgs/skyreach:main`
- **Port:** 4321 (internal container port)
- **Domain:** `skyreach.alexgs.me`
- **Database:** None - all campaign data is included in the Docker image at `/app/data/`
- **Authentication:** Clerk (required) 

## Required Environment Variables

Create `skyreach.env` file with:
```bash
NODE_ENV=production
HOST=0.0.0.0
PORT=4321

# Clerk authentication (required)
PUBLIC_CLERK_PUBLISHABLE_KEY=pk_live_...
CLERK_SECRET_KEY=sk_live_...
```

**Note:** FontAwesome Pro token is only needed at build time during `npm install`, not at runtime, so it should not be included in the environment file.

## Tasks for Claude Code

### 1. Update docker-compose.yml

Add a new service for Skyreach following the Convex pattern:
- Service name: `skyreach`
- Container name: `skyreach`
- Image: from GHCR (`ghcr.io/alexgs/skyreach:main`)
- Restart policy: `unless-stopped`
- Env file: `skyreach.env`
- Network: `webapp-net` (existing network)
- Traefik labels for:
  - Router rule: `Host(`skyreach.alexgs.me`)`
  - TLS enabled with cert resolver: `enceladus-resolver`
  - Service port: 4321
  - HTTP to HTTPS redirect (handled automatically by Traefik config)

**Reference the existing Convex service** for label formatting - they should be nearly identical except for service name and domain.

Example service definition:
```yaml
  skyreach:
    image: ghcr.io/alexgs/skyreach:main
    container_name: skyreach
    restart: unless-stopped
    env_file: skyreach.env
    networks:
      - webapp-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.skyreach.rule=Host(`skyreach.alexgs.me`)"
      - "traefik.http.routers.skyreach.tls=true"
      - "traefik.http.routers.skyreach.tls.certresolver=enceladus-resolver"
      - "traefik.http.services.skyreach.loadbalancer.server.port=4321"
```

### 2. Create skyreach.env template

Create `skyreach.env.example` with placeholder values showing what's needed:
```bash
NODE_ENV=production
HOST=0.0.0.0
PORT=4321

# Clerk authentication (required)
PUBLIC_CLERK_PUBLISHABLE_KEY=pk_live_your_key_here
CLERK_SECRET_KEY=sk_live_your_secret_here
```

### 3. Update Taskfile.yml

Add convenience commands for managing Skyreach, following the Convex pattern:

```yaml
vars:
  CONVEX_SERVICE: convex
  SKYREACH_SERVICE: skyreach  # Add this line

tasks:
  # Add these new tasks after the Convex commands:

  # --- SKYREACH COMMANDS ---

  skyreach:logs:
    cmds:
      - "docker compose logs -f {{.SKYREACH_SERVICE}}"
    desc: Follow logs for Skyreach service

  skyreach:restart:
    cmds:
      - "docker compose restart {{.SKYREACH_SERVICE}}"
    desc: Restart Skyreach service

  skyreach:shell:
    cmds:
      - "docker exec -it {{.SKYREACH_SERVICE}} sh"
    desc: Open a shell on the Skyreach container

  skyreach:update:
    cmds:
      - docker pull ghcr.io/alexgs/skyreach:main
      - docker compose up -d {{.SKYREACH_SERVICE}}
    desc: Pull latest Skyreach image and restart service
```

### 4. Update Documentation

Update `README.md` to add Skyreach to the list of current services:

In the "Current services" section, add:
```markdown
- **Skyreach**: D&D campaign website (`skyreach.alexgs.me`)
```

Add a new section or update existing deployment documentation with Skyreach-specific notes:
```markdown
## Skyreach D&D Website

The D&D campaign website is deployed as a containerized Astro SSR application.

### Deploy Updates

```bash
# Pull latest image and restart
task skyreach:update
```

### View Logs

```bash
task skyreach:logs
```

### Troubleshooting

If the site isn't loading:
1. Check container status: `docker ps | grep skyreach`
2. Check logs: `task skyreach:logs`
3. Verify DNS record: `dig skyreach.alexgs.me`
4. Check Traefik routing: `task traefik:logs`
```

### 5. DNS Configuration

**Before deploying**, ensure DNS is configured:

Add a DNS record (either A or CNAME) pointing to Enceladus:
```
skyreach.alexgs.me    CNAME    enceladus.alexgs.me
```

Or if using A record:
```
skyreach.alexgs.me    A    <Enceladus IP address>
```

**Note:** CNAME is recommended as it means you only need to update one A record (for enceladus.alexgs.me) if the IP changes.

## Deployment Steps

Once the code changes are complete:

1. **Commit and push changes:**
   ```bash
   git add docker-compose.yml skyreach.env.example Taskfile.yml README.md
   git commit -m "feat: add Skyreach D&D web app deployment"
   git push
   ```

2. **On Enceladus droplet:**
   ```bash
   ssh alexgs@enceladus
   cd ~/devops/enceladus
   git pull
   
   # Create actual environment file from template
   cp skyreach.env.example skyreach.env
   nano skyreach.env  # Edit with real values if needed
   
   # Start the service
   task up
   
   # Watch logs to verify startup
   task skyreach:logs
   ```

3. **Verify deployment:**
  - Visit `https://skyreach.alexgs.me`
  - Should redirect to HTTPS with valid Let's Encrypt certificate
  - Site should load and be functional

## Testing Checklist

After deployment:
- [ ] Container starts without errors (`docker ps`)
- [ ] Accessible at https://skyreach.alexgs.me
- [ ] SSL certificate auto-generated by Let's Encrypt
- [ ] Site loads correctly and is fully functional
- [ ] Campaign data displays properly
- [ ] No errors in logs (`task skyreach:logs`)

## Notes

- The Skyreach Docker image contains all campaign data at `/app/data/`
- No volumes needed for data persistence (it's in the image)
- To update campaign content, rebuild the Docker image and run `task skyreach:update`
- The app is stateless and can be easily replaced/updated
- Clerk authentication is required - ensure production keys are configured in `skyreach.env`

## Constraints

- **Do NOT modify** Traefik configuration (`traefik/traefik.yml`)
- **Use existing network** `webapp-net`
- **Follow existing patterns** from Convex service
- **Keep cert resolver** as `enceladus-resolver` (consistent with Convex)

## Expected Output Files

1. Updated `docker-compose.yml` with Skyreach service
2. `skyreach.env.example` template file
3. Updated `Taskfile.yml` with Skyreach commands
4. Updated `README.md` with Skyreach documentation

## Troubleshooting Guide

**Container won't start:**
- Check logs: `task skyreach:logs`
- Verify image pulled: `docker images | grep skyreach`
- Check docker-compose syntax: `docker compose config`

**Site not accessible:**
- Verify DNS: `dig skyreach.alexgs.me`
- Check Traefik routing: `task traefik:logs`
- Verify container is running: `docker ps | grep skyreach`
- Check firewall rules (ports 80 and 443 should be open)

**SSL certificate issues:**
- Verify DNS resolves correctly: `dig skyreach.alexgs.me`
- Check Traefik logs: `task traefik:logs`
- Verify `letsencrypt/acme.json` has correct permissions (600)
