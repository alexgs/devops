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
  `webapp-net`, with data on a DigitalOcean Block Storage volume
  mounted at `/mnt/blockstore` on enceladus (separate from the
  droplet's root disk). Host port `127.0.0.1:5432` exposed for the
  one-time `task x:bootstrap` SSH-tunnel flow.
- **Authentication:** Clerk (production application, separate from any
  dev/local Clerk app), with sign-up disabled in the dashboard and an
  allowlisted user ID enforced by the BE middleware

## Pre-deployment infrastructure changes

Four one-time infrastructure adjustments to enceladus precede the
Westwood service rollout. None of them touch the existing apps' code
or env vars; they all sit at the droplet / container-runtime level.

### 1. Resize enceladus 2GB → 4GB

The current 2GB tier is running at ~65% memory utilization with the
existing services. Adding Westwood (Nest server + Postgres sibling
container) pushes the headroom below comfortable. Resize the droplet
to the 4GB tier via the DO control panel. Confirm in the resize
dialog whether this is a soft resize (in-place, no IP change, no data
loss, ~5 min) or a hard resize (rebuild required, ~30 min downtime,
existing snapshots restored onto a new image). The 2GB → 4GB pair
should be soft on modern DO; if it isn't, schedule the downtime
window accordingly.

### 2. Attach and mount the block storage volume

Create a new 10GB DigitalOcean Block Storage volume in the same region
as enceladus, attach it via the DO panel. DO's panel generates the
mount commands when the volume is attached — copy them rather than
hand-rolling, since the device path includes the volume's unique ID.
Mount point is `/mnt/blockstore`.

After mount:

```bash
# Verify mount survives reboot — DO's auto-generated commands include
# the /etc/fstab entry, but double-check it landed
cat /etc/fstab | grep blockstore

# Create the westwood-db data directory with the right ownership
# (postgres:16-alpine runs as UID 999)
sudo mkdir -p /mnt/blockstore/westwood-db-data
sudo chown 999:999 /mnt/blockstore/westwood-db-data
```

The volume is sized for Westwood's M5 needs only — Westwood's database
is tiny (small tweet payloads, infrequent mining, single-user). 10GB
is the DO minimum and is wildly more than v1 requires. If/when the
other apps' data is migrated onto the same volume later, the volume
can grow without downtime (DO Block Storage supports online resize
upward; downward is not supported).

Block storage volume snapshots are configured separately via cron and
`doctl` (see § 3 below). Droplet snapshots do NOT cover attached
block storage volumes — they're a separate snapshot mechanism, and
DO does not provide a built-in schedule for volume snapshots the way
it does for droplet backups, which is why the cron pipeline exists.
The volume snapshots are the backup mechanism for Westwood's database
and are the right home for the design doc's "backups are also secrets
backups" caveat (X refresh tokens live in the database).

### 3. Configure automated block storage snapshots

DO does not offer scheduled snapshots for block storage volumes —
volume snapshots are on-demand only via the DO panel, the API, or
`doctl`. To get the daily-with-7-day-retention posture the design doc
calls for, install `doctl` on enceladus, configure it with a scoped
API token, and run two cron jobs daily (one to snapshot, one to
prune).

**3a. Install doctl on enceladus.**

```bash
# Download the latest release from the official repo (replace the
# version number with whatever is current at install time — check
# https://github.com/digitalocean/doctl/releases)
DOCTL_VERSION=1.159.0
cd /tmp
curl -sL "https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-amd64.tar.gz" | tar xz
sudo mv doctl /usr/local/bin/
doctl version  # Sanity check
```

**3b. Create a scoped DO API token.**

In the DO control panel, generate a Personal Access Token with
**custom scopes** limited to:

- `volume:read`
- `volume:write`
- `snapshot:read`
- `snapshot:write`

Do NOT use a full-access token. The token lives only on enceladus, in
`enceladus/.env`, and is loaded into the cron job's environment via
the Taskfile's `dotenv` directive.

**3c. Add the token and the volume ID to `enceladus/.env`.**

```bash
# After creating the token in the DO panel and finding the volume's
# UUID via `doctl compute volume list --format ID,Name`:
DIGITALOCEAN_ACCESS_TOKEN=dop_v1_...
WESTWOOD_VOLUME_ID=<volume UUID>
```

The existing `enceladus/.env.example` becomes the template — add both
variables there with placeholder values (per § "Files to change"
below).

**3d. Snapshot and prune scripts** (covered as files in § "Files to
change" below).

**3e. Cron entries on enceladus.** Add via `crontab -e` (with the
canonical copy committed to `enceladus/crontab.txt`, per § "Files to
change"):

```
# Westwood block storage volume — daily snapshot at 06:00 UTC,
# prune anything older than 7 days at 06:30 UTC.
  0  6  *  *  *  /home/alexgs/bin/task --taskfile /home/alexgs/devops/enceladus/Taskfile.yml cron:westwood-snapshot >> /home/alexgs/cron.log 2>&1
 30  6  *  *  *  /home/alexgs/bin/task --taskfile /home/alexgs/devops/enceladus/Taskfile.yml cron:westwood-snapshot-prune >> /home/alexgs/cron.log 2>&1
```

The format matches the pattern from `daphnis/crontab.txt` —
cron-calls-Task, log-redirect at the end. Output and errors both go
to `/home/alexgs/cron.log` for inspection. If a snapshot fails, the
next day's snapshot still runs, and the prune script only removes
entries older than 7 days, so a single missed day produces a gap (6
snapshots instead of 7) rather than data loss.

**3f. Test once manually before relying on the cron.**

```bash
task --taskfile /home/alexgs/devops/enceladus/Taskfile.yml cron:westwood-snapshot
# Verify the snapshot appears:
doctl compute snapshot list --resource volume
```

This confirms doctl is authenticated, the volume ID is correct, and
the script is executable before the first scheduled run.

### 4. Cap ClickHouse memory usage

ClickHouse on `plausible_events_db` runs on defaults, which target
significantly more RAM than even the resized enceladus has. With more
headroom available post-resize, ClickHouse will grow into it, which
defeats the purpose of the resize for Westwood. Two complementary
caps:

**Docker hard cap** — add `mem_limit: 1g` to the `plausible_events_db`
service in `docker-compose.yml`:

```yaml
  plausible_events_db:
    image: clickhouse/clickhouse-server:24.3.3.102-alpine
    container_name: plausible_events_db
    restart: unless-stopped
    mem_limit: 1g
    volumes:
      # ... unchanged
```

**ClickHouse internal soft cap** — add `<max_server_memory_usage>` to
`clickhouse/clickhouse-config.xml`:

```xml
<clickhouse>
    <logger>
        <level>warning</level>
        <console>true</console>
    </logger>
    <max_server_memory_usage>805306368</max_server_memory_usage>
    <!-- 768 MB; soft cap, paired with docker mem_limit: 1g hard cap -->
    <query_log remove="remove"/>
    <!-- ... rest unchanged ... -->
</clickhouse>
```

The pair is belt-and-suspenders: the soft cap (768 MB) makes
ClickHouse keep itself within bounds gracefully (rejecting queries
that would push past the limit, rather than letting the kernel
OOM-kill the container); the hard cap (1 GB) provides headroom for
queries-in-flight plus a safety net if the soft cap is somehow
exceeded. Both values are starting points and tunable — if Plausible
starts rejecting queries it shouldn't be, raise both proportionally.

Restart the `plausible_events_db` service to apply both changes:
`docker compose up -d plausible_events_db`. Verify with
`docker stats plausible_events_db` that the new limit is in effect.

## Decisions and Divergences

Before CC starts, confirm these — the spec assumes all four go the
recommended way:

| Topic                       | Recommendation                                                            | Notes                                                                                                                                                       |
|-----------------------------|---------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Deployment target**       | Enceladus (multi-tenant), resized to 4GB                                  | Resize is in-place via DO panel; matches existing infrastructure pattern. Two-droplet split considered and declined — see prior conversation.               |
| **Postgres storage**        | Bind mount on attached block storage volume at `/mnt/blockstore`          | Reverts to design-doc original intent. Other apps stay on root disk for now; their migration is separate, later work.                                       |
| **Backups**                 | Block storage volume snapshots, automated via cron + `doctl` on enceladus | DO doesn't offer scheduled snapshots for volumes (unlike droplet backups), so the schedule is built locally. Daily, 7-day retention. See § 3.            |
| **Postgres host-port bind** | `127.0.0.1:5432:5432` on `westwood-db`                                    | Required for `task x:bootstrap` SSH-tunnel flow. Localhost-only (safe). First database host-port binding on enceladus (plausible_db exposes none — fine). |

## Files to change in `enceladus/`

### 1. `docker-compose.yml`

Add two services. Service definitions follow the convex/skyreach
pattern; the database service uses a bind mount onto the attached
block storage volume rather than a named Docker volume.

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
      - /mnt/blockstore/westwood-db-data:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:5432:5432"
    networks:
      - webapp-net
```

Add to the `volumes:` block: nothing new for Westwood — the bind
mount above doesn't need a top-level `volumes:` entry. Don't add a
`westwood-db-data` named volume; the data lives directly on the block
storage filesystem.

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

  # --- CRON JOBS --- (Hidden)
  # Invoked by /etc/crontab on enceladus per crontab.txt; not normally
  # called by hand.

  cron:westwood-snapshot:
    cmds:
      - bash /home/alexgs/devops/enceladus/scripts/westwood-snapshot.sh
    silent: true

  cron:westwood-snapshot-prune:
    cmds:
      - bash /home/alexgs/devops/enceladus/scripts/westwood-snapshot-prune.sh
    silent: true
```

Add to the `vars:` block at top of file:

```yaml
  WESTWOOD_SERVICE: westwood
```

### 5. `scripts/westwood-snapshot.sh` (new)

Create the directory if it doesn't exist (`enceladus/scripts/`).

```bash
#!/usr/bin/env bash
set -euo pipefail

# Create a snapshot of the Westwood block storage volume.
# Invoked daily by cron via `task cron:westwood-snapshot`.
#
# Requires (loaded by Task's dotenv directive from enceladus/.env):
#   - DIGITALOCEAN_ACCESS_TOKEN  (scoped: volume:rw, snapshot:rw)
#   - WESTWOOD_VOLUME_ID         (UUID from `doctl compute volume list`)

doctl compute volume snapshot "$WESTWOOD_VOLUME_ID" \
  --snapshot-name "westwood-db-$(date -u +%Y%m%d-%H%M%S)"
```

Make it executable: `chmod +x scripts/westwood-snapshot.sh` (and
verify the file mode is preserved through git — `git update-index
--chmod=+x scripts/westwood-snapshot.sh` if not).

### 6. `scripts/westwood-snapshot-prune.sh` (new)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Delete Westwood volume snapshots older than RETENTION_DAYS.
# Invoked daily by cron via `task cron:westwood-snapshot-prune`.
#
# Name-prefix filter (`westwood-db-*`) ensures this script never
# touches snapshots created by anything else, even if a future
# script or manual snapshot adds non-westwood volume snapshots to
# the account.

RETENTION_DAYS=7
CUTOFF_TS=$(date -u -d "${RETENTION_DAYS} days ago" +%s)

doctl compute snapshot list \
  --resource volume \
  --format ID,Name,Created \
  --no-header | \
while read -r SNAP_ID NAME CREATED_AT; do
  case "$NAME" in
    westwood-db-*) ;;
    *) continue ;;
  esac

  CREATED_TS=$(date -u -d "$CREATED_AT" +%s)
  if [ "$CREATED_TS" -lt "$CUTOFF_TS" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) deleting $NAME ($SNAP_ID), created $CREATED_AT"
    doctl compute snapshot delete "$SNAP_ID" --force
  fi
done
```

Same `chmod +x` requirement as `westwood-snapshot.sh`.

### 7. `crontab.txt` (new)

The enceladus folder doesn't currently carry a `crontab.txt` (only
daphnis does). Create one as the canonical reference for what's in
the operator's actual crontab on enceladus. Contents:

```
# Reference copy of the operator's crontab on enceladus.
# To apply changes, edit this file in the repo, then run
# `crontab -e` on enceladus and sync manually.

# Westwood block storage volume — daily snapshot at 06:00 UTC,
# prune anything older than 7 days at 06:30 UTC.
  0  6  *  *  *  /home/alexgs/bin/task --taskfile /home/alexgs/devops/enceladus/Taskfile.yml cron:westwood-snapshot >> /home/alexgs/cron.log 2>&1
 30  6  *  *  *  /home/alexgs/bin/task --taskfile /home/alexgs/devops/enceladus/Taskfile.yml cron:westwood-snapshot-prune >> /home/alexgs/cron.log 2>&1
```

### 8. `.env.example` (modify)

The existing `enceladus/.env.example` is a placeholder
("currently no shared environment variables are needed"). Replace
with:

```bash
# Shared environment variables for enceladus infrastructure.
# Copy this file to `.env` and fill in actual values.

# DigitalOcean API access for the Westwood snapshot cron jobs.
# Token must have custom scopes: volume:read, volume:write,
# snapshot:read, snapshot:write. Do NOT use a full-access token.
DIGITALOCEAN_ACCESS_TOKEN=dop_v1_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Westwood block storage volume UUID.
# Find via: doctl compute volume list --format ID,Name
WESTWOOD_VOLUME_ID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

### 9. `README.md`

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
- Dedicated Postgres 16 sibling container (`westwood-db`) with data
  on the attached block storage volume at
  `/mnt/blockstore/westwood-db-data`. Block storage volume snapshots
  are automated via cron + `doctl` (daily, 7-day retention) since DO
  doesn't provide built-in volume snapshot scheduling — see "Backups"
  below.
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

**Backups:**

Block storage volume snapshots run via cron on enceladus (06:00 UTC
daily snapshot, 06:30 UTC prune; canonical schedule in
`crontab.txt`). To inspect:

```bash
# List all Westwood volume snapshots
doctl compute snapshot list --resource volume \
  --format ID,Name,Created,Size

# Manual one-off snapshot (e.g. before a risky migration)
task cron:westwood-snapshot

# Check the cron log for snapshot/prune output
tail -100 /home/alexgs/cron.log
```

If a scheduled snapshot didn't run, check `/home/alexgs/cron.log` and
verify the `DIGITALOCEAN_ACCESS_TOKEN` in `.env` is still valid.

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

### 10. `.gitignore`

Already covers `*.env` (excepting `.env.example`). No change needed —
`westwood.env`, `westwood-db.env`, and the updated `.env` will all be
ignored automatically.

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

1. **Pre-deployment infrastructure changes on enceladus** — execute
   the four steps in § "Pre-deployment infrastructure changes" above:
   resize the droplet to 4GB, attach and mount the block storage
   volume, set up automated snapshots (doctl + cron), cap ClickHouse
   memory. They're largely independent, but the sensible order is
   resize → mount → snapshots → ClickHouse cap, since snapshots
   depend on the volume existing. All must complete before step 5
   below. The block storage volume must exist, be mounted at
   `/mnt/blockstore`, contain a `westwood-db-data` subdirectory with
   `999:999` ownership, and have the first manual snapshot run
   successfully (§ 3f).

2. **On the laptop, in the devops repo:**
   ```bash
   git add docker-compose.yml \
           westwood.env.example westwood-db.env.example .env.example \
           Taskfile.yml README.md crontab.txt \
           scripts/westwood-snapshot.sh scripts/westwood-snapshot-prune.sh \
           clickhouse/clickhouse-config.xml
   git commit -m "feat: add Westwood deployment + ClickHouse memory cap"
   git push
   ```

3. **DNS:** add the CNAME record. Wait for propagation
   (`dig westwood.alexgs.me` should resolve to the enceladus IP).

4. **Clerk:** create the production Westwood app per § "Clerk Dashboard
   Configuration" above. Record the keys and the operator user ID.

5. **On enceladus:**
   ```bash
   ssh alexgs@enceladus
   cd ~/devops/enceladus
   git pull

   # Create env files from templates
   cp .env.example .env
   cp westwood.env.example westwood.env
   cp westwood-db.env.example westwood-db.env

   # Edit env files and fill in actual values
   nano .env              # DIGITALOCEAN_ACCESS_TOKEN, WESTWOOD_VOLUME_ID
   nano westwood-db.env   # set POSTGRES_PASSWORD
   nano westwood.env       # set the same password in DATABASE_URL, plus
                           # Clerk keys, Clerk user ID, Anthropic key,
                           # X OAuth credentials

   # Add the cron lines from crontab.txt via `crontab -e`

   # Bring up the new services
   task up

   # Watch startup
   task westwood:logs
   ```

   Expected sequence in the logs:
  - westwood-db starts, Postgres is ready (data on the block storage
    mount under `/mnt/blockstore/westwood-db-data`)
  - westwood container starts, Flyway applies migrations, Nest boots
  - First request to `https://westwood.alexgs.me` triggers ACME cert
    provisioning via Traefik (visible in `task traefik:logs`)

6. **Verify auth guard:**
   ```bash
   curl -i https://westwood.alexgs.me/api/analysis/start
   ```
   Should return `401`. (This is the positive verification from M5 § 7.)

7. **First bootstrap, from the laptop:** see the README "First-time
   bootstrap" block above.

8. **First mine:** open `https://westwood.alexgs.me`, sign in via
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
- [ ] Manual `task cron:westwood-snapshot` succeeds and the snapshot
  appears in `doctl compute snapshot list --resource volume`
- [ ] After the first scheduled run (or a manual trigger), a snapshot
  named `westwood-db-<timestamp>` exists in the DO panel

## Constraints

- **Do NOT modify** existing services except for the
  `plausible_events_db` memory cap explicitly specified in
  § "Pre-deployment infrastructure changes." Don't touch
  actual-budget, convex, skyreach, plausible (the main service),
  plausible_db, or webserver.
- **Do NOT modify** Traefik configuration (`traefik/traefik.yml`)
- **Use existing network** `webapp-net`
- **Use existing cert resolver** `enceladus-resolver`
- **Follow existing patterns** for service definition, env files,
  Taskfile commands, and README structure

## Expected Output Files

1. Updated `docker-compose.yml` (westwood and westwood-db services
   added; `mem_limit: 1g` added to plausible_events_db)
2. Updated `clickhouse/clickhouse-config.xml` (added
   `<max_server_memory_usage>` element)
3. New `westwood.env.example`
4. New `westwood-db.env.example`
5. Updated `.env.example` (added `DIGITALOCEAN_ACCESS_TOKEN` and
   `WESTWOOD_VOLUME_ID`)
6. Updated `Taskfile.yml` (westwood commands + cron tasks + var)
7. New `scripts/westwood-snapshot.sh` (executable)
8. New `scripts/westwood-snapshot-prune.sh` (executable)
9. New `crontab.txt`
10. Updated `README.md` (Current services bullet + Westwood section
    including Backups subsection)

Out-of-repo prerequisites (done before the above are deployed):
- Enceladus droplet resized 2GB → 4GB (DO panel)
- Block storage volume created, attached, mounted at `/mnt/blockstore`
  (DO panel + droplet shell)
- `doctl` installed on enceladus
- DO API token created with scoped permissions
  (`volume:read,write`, `snapshot:read,write`)
- Cron entries added to operator's crontab on enceladus
  (`crontab -e`, content per `crontab.txt`)

## Implications for the Westwood-repo M5 spec

The M5 spec in the Westwood repo (`docs/specs/11-milestone-m5.md`)
has been updated in parallel with this brief to reflect the
enceladus-with-block-storage deployment posture. § 3 of that spec
points at this brief for the devops-side work; § 9 names the
design-doc edits needed for `design.md` § Deployment. No further
cross-repo cleanup needed at brief-execution time.
