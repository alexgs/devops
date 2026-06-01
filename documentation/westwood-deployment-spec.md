# Deployment Spec: Westwood on Enceladus

## Context

Deploy the Westwood application — a single-user Twitter timeline analyzer
— to the Enceladus droplet alongside Convex, Skyreach, Actual Budget, and
Plausible. Westwood follows the existing multi-tenant pattern: one
container behind the shared Traefik, joined to `webapp-net`, with its own
Postgres database as a sibling container.

This spec is the devops-repo side of Westwood's M5 milestone. The
Westwood-repo side (Docker image build, FE bundler fix, Clerk auth
middleware, bootstrap CLI) is governed by
`docs/specs/11-milestone-m5.md` in the Westwood repository.

## Current Infrastructure (Enceladus)

- **OS:** Ubuntu 24.04
- **User:** alexgs (with sudo)
- **Docker:** Installed and running
- **Existing setup:** `/home/alexgs/devops/enceladus/`
- **Network:** `webapp-net` (existing Docker network)
- **Traefik:** v3.6, `enceladus-resolver` (HTTP-01 ACME challenge),
  reads docker.sock directly
- **Existing services:** actual-budget, convex, skyreach, plausible
  (+ plausible_db, plausible_events_db), webserver (traefik)

## Westwood Application Details

- **Docker image:** GHCR — `ghcr.io/alexgs/westwood:latest` (image name
  and tag convention to confirm against the Westwood repo's build setup)
- **Container port:** TBD (whatever the Nest server's listen port is —
  3000 is the Nest default; confirm against the Westwood repo's
  `apps/be/src/main.ts`)
- **Domain:** `westwood.alexgs.me`
- **Database:** Dedicated Postgres 16 container (`westwood-db`) on
  `webapp-net`, named Docker volume for data, host port `127.0.0.1:5432`
  exposed for the one-time `task x:bootstrap` SSH-tunnel flow
- **Authentication:** Clerk (production application, separate from any
  dev/local Clerk app), with sign-up disabled in the dashboard and an
  allowlisted user ID enforced by the BE middleware

## Decisions and Divergences

Before CC starts, confirm these — the spec assumes all four go the
recommended way:

| Topic                       | Recommendation                                                            | Notes                                                                                                                                                          |
|-----------------------------|---------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Deployment target**       | Enceladus (multi-tenant), not a new droplet                               | Matches actual infrastructure pattern; design doc's "small DO droplet" language is a relic of pre-multi-tenant planning and worth a one-line edit              |
| **Postgres storage**        | Named Docker volume (`westwood-db-data`)                                  | Matches plausible_db pattern. Design doc says "persistent block storage device"; that's not what enceladus actually does                                       |
| **Backups**                 | Droplet-level DO snapshots (assumed already configured)                   | If not already configured, that's a one-time DO panel action, not a per-app deploy step. M5's backup item is satisfied at the droplet level                    |
| **Postgres host-port bind** | `127.0.0.1:5432:5432` on `westwood-db`                                    | Required for the `task x:bootstrap` SSH-tunnel flow. Localhost-only (safe). First database host-port binding on enceladus (plausible_db exposes none — fine). |

## Files to change in `enceladus/`

### 1. `docker-compose.yml`

Add two services and one named volume. Service definitions follow the
convex/skyreach pattern; database definition follows the plausible_db
pattern.

```yaml
  westwood:
    image: ghcr.io/alexgs/westwood:latest
    container_name: westwood
    restart: unless-stopped
    env_file: westwood.env
    depends_on:
      - westwood-db
    networks:
      - webapp-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.westwood.rule=Host(`westwood.alexgs.me`)"
      - "traefik.http.routers.westwood.tls=true"
      - "traefik.http.routers.westwood.tls.certresolver=enceladus-resolver"
      - "traefik.http.services.westwood.loadbalancer.server.port=3000"

  westwood-db:
    image: postgres:16-alpine
    container_name: westwood-db
    restart: unless-stopped
    env_file: westwood-db.env
    volumes:
      - westwood-db-data:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:5432:5432"
    networks:
      - webapp-net
```

Add to the `volumes:` block:

```yaml
  westwood-db-data:
```

(Plain named volume, no `driver_opts` — same pattern as `plausible-db-data`.)

Also add `- westwood` to `webserver.depends_on` so Traefik starts after
Westwood, matching the existing pattern.

**Port note for the Westwood service:** the Nest server inside the
container handles its own `/api/*` vs. static-asset routing — Traefik
just routes `westwood.alexgs.me` to a single container port. Confirm the
port number (3000 above is a placeholder) against the Westwood repo's
Nest config before CC runs.

### 2. `westwood.env.example`

Create following the convex.env.example / skyreach.env.example pattern:

```bash
# Application environment
NODE_ENV=production
PORT=3000

# Database (resolves via Docker network to the westwood-db service)
DATABASE_URL=postgresql://westwood:PASSWORD_HERE@westwood-db:5432/westwood

# Clerk authentication (PRODUCTION KEYS)
# Get these from https://dashboard.clerk.com (production application)
CLERK_PUBLISHABLE_KEY=pk_live_XXXXXXXXXXXXXXXXXXXXXXXXXXXX
CLERK_SECRET_KEY=sk_live_XXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Clerk allowlist — the operator's Clerk user ID
# Find via Clerk dashboard → Users → click the operator's row
CLERK_ALLOWED_USER_ID=user_XXXXXXXXXXXXXXXXXXXXXXXXXXX

# Anthropic API key
ANTHROPIC_API_KEY=sk-ant-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# X (Twitter) OAuth app credentials
# Refresh tokens are NOT here — they live in the x_tokens table
X_CLIENT_ID=XXXXXXXXXXXXXXXXXXXX
X_CLIENT_SECRET=XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

### 3. `westwood-db.env.example`

Create — this is the first per-database env file on enceladus (plausible
hardcodes `POSTGRES_PASSWORD=postgres` inline, which is a pattern worth
not propagating). Following Postgres image conventions:

```bash
POSTGRES_USER=westwood
POSTGRES_PASSWORD=GENERATE_A_STRONG_PASSWORD_HERE
POSTGRES_DB=westwood
```

The same password value goes into `westwood.env`'s `DATABASE_URL`.

### 4. `Taskfile.yml`

Add Westwood command block, following the convex/skyreach pattern. Place
between `# --- SKYREACH COMMANDS ---` and `# --- TRAEFIK COMMANDS ---`:

```yaml
  # --- WESTWOOD COMMANDS ---

  westwood:logs:
    cmds:
      - "docker compose logs -f {{.WESTWOOD_SERVICE}}"
    desc: Follow logs for Westwood service

  westwood:restart:
    cmds:
      - "docker compose restart {{.WESTWOOD_SERVICE}}"
    desc: Restart Westwood service

  westwood:shell:
    cmds:
      - "docker exec -it {{.WESTWOOD_SERVICE}} sh"
    desc: Open a shell on the Westwood container

  westwood:update:
    cmds:
      - docker pull ghcr.io/alexgs/westwood:latest
      - docker compose up -d {{.WESTWOOD_SERVICE}}
    desc: Pull latest Westwood image and restart service

  westwood:db:psql:
    cmds:
      - "docker exec -it westwood-db psql -U westwood -d westwood"
    desc: Connect to the Westwood database with psql
```

Add to the `vars:` block at top of file:

```yaml
  WESTWOOD_SERVICE: westwood
```

### 5. `README.md`

Two additions, following the pattern already established for Convex and
Skyreach.

**Add to the "Current services" list near the top:**

```markdown
- **Westwood**: Twitter timeline engagement analyzer (`westwood.alexgs.me`)
```

**Add a new section, following the "Skyreach D&D Website" pattern at
the bottom of "Application-Specific Notes":**

```markdown
### Westwood

Westwood is a single-user Twitter timeline analyzer that surfaces
engagement recommendations via Claude. Unlike the other apps on
enceladus, it requires a one-time OAuth bootstrap to populate its
`x_tokens` table before live mining works.

**Key details:**
- Dedicated Postgres 16 sibling container (`westwood-db`) with data in
  the `westwood-db-data` named volume
- Postgres exposes `127.0.0.1:5432` on the droplet host (localhost-only)
  for the bootstrap flow's SSH tunnel
- Flyway migrations run at container entrypoint — slow or failing
  migrations will block container start
- Sign-in via Clerk hosted UI (production Clerk app, separate from dev)

**First-time bootstrap (one-time, after first deploy):**

From the laptop:
```bash
# Open an SSH tunnel forwarding laptop:5432 to enceladus:127.0.0.1:5432
ssh -L 5432:127.0.0.1:5432 alexgs@enceladus

# In a separate terminal, with DATABASE_URL pointed at localhost:5432:
DATABASE_URL=postgresql://westwood:PASSWORD@localhost:5432/westwood \
  task x:bootstrap
```

The OAuth PKCE flow runs on the laptop; the resulting `x_tokens` row
lands in the production database through the tunnel. After this,
live mining works from the deployed instance.

**Deploy updates:**
```bash
task westwood:update
```

**View logs:**
```bash
task westwood:logs
```

**Database access:**
```bash
task westwood:db:psql
```

**Troubleshooting:**
If `westwood.alexgs.me` returns 502:
1. Check container status: `docker ps | grep westwood`
2. Check logs: `task westwood:logs` — Flyway migration failures will
   surface here
3. Verify the database is up: `docker ps | grep westwood-db`
4. Check Traefik routing: `task traefik:logs`

If `westwood.alexgs.me` loads but mining fails:
1. Confirm `x_tokens` row exists:
   `task westwood:db:psql` then `SELECT * FROM x_tokens;`
2. If empty, the bootstrap was never run — see above
3. If present but expired, re-run the bootstrap
```

### 6. `.gitignore`

Already covers `*.env` (excepting `.env.example`). No change needed —
`westwood.env` and `westwood-db.env` will be ignored automatically.

## DNS Configuration

Before deploying, add a DNS record. The repo's convention favors
CNAME so a future enceladus IP change updates only one record:

```
westwood.alexgs.me    CNAME    enceladus.alexgs.me
```

ACME's HTTP-01 challenge will fail if DNS hasn't propagated when
Traefik first tries to provision the cert, so this must happen
before `task up` brings the Westwood service online.

## Clerk Dashboard Configuration

One-time setup, outside the repo:

1. Create a **separate Clerk application** for Westwood production
   (do not reuse convex's or skyreach's Clerk app — different access
   policies, different user pool)
2. Allowed origin / redirect URLs: `https://westwood.alexgs.me`
   only (no wildcards)
3. **Restrictions → disable public sign-up.** Users can only be
   added by invite from the dashboard.
4. Invite yourself once. Record the resulting Clerk user ID — this
   is the value of `CLERK_ALLOWED_USER_ID` in `westwood.env`.

## Deployment Steps

Ordered procedure:

1. **On the laptop, in the devops repo:**
   ```bash
   git add docker-compose.yml westwood.env.example westwood-db.env.example \
           Taskfile.yml README.md
   git commit -m "feat: add Westwood deployment"
   git push
   ```

2. **DNS:** add the CNAME record. Wait for propagation
   (`dig westwood.alexgs.me` should resolve to the enceladus IP).

3. **Clerk:** create the production Westwood app per § "Clerk Dashboard
   Configuration" above. Record the keys and the operator user ID.

4. **On enceladus:**
   ```bash
   ssh alexgs@enceladus
   cd ~/devops/enceladus
   git pull

   # Create env files from templates
   cp westwood.env.example westwood.env
   cp westwood-db.env.example westwood-db.env

   # Edit env files and fill in actual values
   nano westwood-db.env   # set POSTGRES_PASSWORD
   nano westwood.env       # set the same password in DATABASE_URL, plus
                           # Clerk keys, Clerk user ID, Anthropic key,
                           # X OAuth credentials

   # Bring up the new services
   task up

   # Watch startup
   task westwood:logs
   ```

   Expected sequence in the logs:
   - westwood-db starts, Postgres is ready
   - westwood container starts, Flyway applies migrations, Nest boots
   - First request to `https://westwood.alexgs.me` triggers ACME cert
     provisioning via Traefik (visible in `task traefik:logs`)

5. **Verify auth guard:**
   ```bash
   curl -i https://westwood.alexgs.me/api/analysis/start
   ```
   Should return `401`. (This is the positive verification from M5 § 7.)

6. **First bootstrap, from the laptop:** see the README "First-time
   bootstrap" block above.

7. **First mine:** open `https://westwood.alexgs.me`, sign in via
   Clerk's hosted UI, click "Mine my timeline," act on a recommendation.

## Testing Checklist

After deployment:
- [ ] `westwood-db` container is running (`docker ps | grep westwood-db`)
- [ ] `westwood` container is running (`docker ps | grep westwood`)
- [ ] Flyway migrations ran cleanly on first start (`task westwood:logs`)
- [ ] `https://westwood.alexgs.me` returns the Westwood landing page
      (or redirects to Clerk's hosted sign-in)
- [ ] SSL certificate auto-provisioned (no cert warnings in browser)
- [ ] `curl -i https://westwood.alexgs.me/api/analysis/start` returns 401
- [ ] Sign-in via Clerk hosted UI completes and lands back on Westwood
- [ ] Authenticated request from the operator's session succeeds
- [ ] `task x:bootstrap` completes; `x_tokens` row exists
- [ ] "Mine my timeline" completes end-to-end against a live X timeline
- [ ] The cost dashboard reflects the live mine, reconciling within
      ~20% of the Anthropic and X developer consoles

## Constraints

- **Do NOT modify** existing services (actual-budget, convex, skyreach,
  plausible, plausible_db, plausible_events_db, webserver)
- **Do NOT modify** Traefik configuration (`traefik/traefik.yml`)
- **Use existing network** `webapp-net`
- **Use existing cert resolver** `enceladus-resolver`
- **Follow existing patterns** for service definition, env files,
  Taskfile commands, and README structure

## Expected Output Files

1. Updated `docker-compose.yml` (westwood and westwood-db services,
   westwood-db-data volume)
2. New `westwood.env.example`
3. New `westwood-db.env.example`
4. Updated `Taskfile.yml` (westwood commands + var)
5. Updated `README.md` (Current services bullet + Westwood section)

## Implications for the Westwood-repo M5 spec

The M5 spec in the Westwood repo (`docs/specs/11-milestone-m5.md`) was
drafted before this brief; some of its content is now duplicative with
or superseded by the devops-repo work:

- **§ 3 (Droplet infrastructure)** is mostly already done — enceladus
  exists, Traefik fronts it, the cert resolver is configured. M5's
  contribution here is just adding Westwood as a service, which is
  covered by this brief. Worth tightening § 3 to point here rather
  than re-specifying.
- **§ 5 (Environment variables)** is correct content but lives more
  naturally here (since the env file is in this repo). Worth keeping
  in the M5 spec as a contract for what the BE expects, with a note
  that the actual env file is in the devops repo.
- **§ 6.1 (Deploy-first, bootstrap-after)** is correctly Westwood-spec
  material, but the deployment-steps procedure here supersedes its
  step-by-step. Worth a cross-reference.
- **Block-storage Postgres** — § 3.1 of the M5 spec says "Postgres on a
  block storage device, separate from the droplet's root disk." That's
  not how enceladus does it. Worth correcting in M5 § 3.1 (and in
  `design.md` § Deployment) to "named Docker volume on the enceladus
  droplet, included in droplet-level DO snapshots."

These are doc-cleanup items, separate from this brief's execution. CC
does not need them resolved before running the deployment.
