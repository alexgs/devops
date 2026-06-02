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
