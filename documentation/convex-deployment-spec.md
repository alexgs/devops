## Deployment Spec for Claude Code: Convex on Enceladus

### Context

Deploy the Convex conversation archive application to the DigitalOcean Droplet "Enceladus" alongside other applications using Docker Compose and Traefik for routing.

### Current Infrastructure (Enceladus)

- **OS:** Ubuntu 24.04
- **User:** alexgs (with sudo)
- **Docker:** Installed and running
- **Existing setup:** Located in `/home/alexgs/devops/daphnis/` (cloned from git - note: directory name still references old Daphnis droplet)
- **Current services:** See `docker-compose.yml` in devops repo for reference

### Convex Application Details

- **Docker image:** Available on GHCR (GitHub Container Registry)
- **Image name:** `ghcr.io/alexgs/convex:latest` (verify exact name)
- **Port:** 4322
- **Domain:** `convex.alexgs.me`
- **Database:** Included in Docker image at `/app/data/processed/conversations.db`

### Required Environment Variables

Create `convex.env` file with:
```bash
NODE_ENV=production
PUBLIC_CLERK_PUBLISHABLE_KEY=pk_live_...
CLERK_SECRET_KEY=sk_live_...
PUBLIC_CLERK_SIGN_IN_URL=/sign-in
PUBLIC_CLERK_SIGN_UP_URL=/sign-up
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

### Tasks for Claude Code

#### 1. Update docker-compose.yml

Add a new service for Convex following the existing pattern:
- Service name: `convex`
- Container name: `convex`
- Image: from GHCR
- Restart policy: `unless-stopped`
- Env file: `convex.env`
- Network: `webapp-net` (existing network)
- Traefik labels for:
  - Router rule: `Host(`convex.alexgs.me`)`
  - TLS enabled with cert resolver
  - Port: 4321
  - HTTP to HTTPS redirect

**Reference existing services** (dnd-compendium, electric-lounge) for label formatting.

#### 2. Create convex.env template

Create `convex.env.example` with placeholder values showing what's needed.

#### 3. Update Documentation

Add to the devops repo README or create CONVEX_DEPLOYMENT.md with:
- How to deploy Convex
- Environment variable requirements
- How to update the Docker image
- How to view logs
- Troubleshooting common issues

#### 4. Deployment Commands

Document the deployment process:
```bash
# Pull latest image
docker pull ghcr.io/[username]/convex:latest

# Start/restart Convex
docker-compose up -d convex

# View logs
docker-compose logs -f convex
```

### Constraints

- **Do NOT modify** existing services (database, dnd-compendium, electric-lounge, webserver, soxy-proxy)
- **Use existing network** `webapp-net` - do not create new networks
- **Follow existing patterns** for Traefik configuration (see dnd-compendium labels as reference)
- **Keep Traefik config** in `traefik/traefik.yml` unchanged unless absolutely necessary

### Traefik Configuration Reference

The existing Traefik setup uses:
- Entry points: `web-default` (80) and `web-secure` (443)
- Certificate resolver: `enceladus-resolver` (HTTP challenge with NameCheap)
- Docker provider via soxy-proxy
- Automatic HTTP→HTTPS redirect

**Note:** Check the actual cert resolver name in `traefik/traefik.yml` - it may still be named `daphnis-resolver` from the old droplet. If so, use that name for consistency.

### Expected Output Files

1. Updated `docker-compose.yml` with Convex service
2. `convex.env.example` template file
3. Documentation (README update or new doc file)
4. Optional: `deploy-convex.sh` script for easy deployment

### Testing Checklist

After deployment:
- [ ] Container starts without errors
- [ ] Accessible at https://convex.alexgs.me
- [ ] SSL certificate auto-generated
- [ ] Can sign in with Clerk/GitHub OAuth
- [ ] Search functionality works
- [ ] Database queries work

### Notes

- The Convex Docker image already contains the SQLite database
- No volumes needed for database (it's in the image)
- Logs volume optional but recommended for debugging
- DNS already configured (A record for convex.alexgs.me → Enceladus IP)
