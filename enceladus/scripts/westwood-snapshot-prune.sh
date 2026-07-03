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
  --format ID,Name,CreatedAt \
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
