#!/bin/bash
# =============================================================================
# Homelab daily backup
# Runs as root via cron — see docs/services/backup.md for full details
#
# Restic repository: /mnt/backup/restic
# Log:              /var/log/homelab-backup.log
# Password file:    /etc/restic-password (root-owned, mode 600)
#
# Retention: 7 daily / 4 weekly / 3 monthly snapshots
# =============================================================================

set -euo pipefail

# Derive homelab dir from script location — no hardcoded username
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_DIR="$(dirname "$SCRIPT_DIR")"

RESTIC_REPO="/mnt/backup/restic"
RESTIC_PASSWORD_FILE="/etc/restic-password"
POSTGRES_CONTAINER="sure-db-1"
POSTGRES_USER="sure_user"
POSTGRES_DB="sure_production"
APP_STORAGE_VOLUME="sure_app-storage"
LOG="/var/log/homelab-backup.log"

export RESTIC_REPOSITORY="$RESTIC_REPO"
export RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "=== Backup started ==="

# Abort if USB drive is not mounted
if ! mountpoint -q /mnt/backup; then
    log "ERROR: /mnt/backup is not mounted. Aborting."
    exit 1
fi

# -----------------------------------------------------------------------------
# 1. Postgres logical dump (sure_production)
#    pg_dump produces a consistent snapshot regardless of live writes.
#    No container stop needed.
# -----------------------------------------------------------------------------
log "Dumping Postgres (${POSTGRES_DB})..."
docker exec "$POSTGRES_CONTAINER" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
    | restic backup --stdin --stdin-filename "postgres/${POSTGRES_DB}.sql"

# -----------------------------------------------------------------------------
# 2. Bind-mount data directories
#    Excluded:
#      - traefik/logs/          — not needed for restore
#      - pihole/gravity_old.db  — previous gravity.db kept by Pi-hole as rollback
#      - pihole/pihole-FTL.db   — DNS query history, not needed for restore
#      - pihole/listsCache/     — cached raw adlist downloads, regeneratable
# -----------------------------------------------------------------------------
log "Backing up bind mounts..."
restic backup \
    "$HOMELAB_DIR/docker/authelia" \
    "$HOMELAB_DIR/docker/karakeep/data" \
    "$HOMELAB_DIR/docker/traefik/traefik.yaml" \
    "$HOMELAB_DIR/docker/traefik/config.yaml" \
    "$HOMELAB_DIR/docker/traefik/acme.json" \
    "$HOMELAB_DIR/docker/pihole/pihole" \
    --exclude "$HOMELAB_DIR/docker/traefik/logs" \
    --exclude "$HOMELAB_DIR/docker/pihole/pihole/gravity_old.db" \
    --exclude "$HOMELAB_DIR/docker/pihole/pihole/pihole-FTL.db" \
    --exclude "$HOMELAB_DIR/docker/pihole/pihole/listsCache"

# -----------------------------------------------------------------------------
# 3. Sure file upload volume (sure_app-storage)
#    Path resolved dynamically from Docker — no hardcoded volume path.
# -----------------------------------------------------------------------------
log "Backing up Sure app-storage volume..."
APP_STORAGE_PATH="$(docker volume inspect "$APP_STORAGE_VOLUME" \
    --format '{{.Mountpoint}}')"
restic backup "$APP_STORAGE_PATH" --tag sure_app-storage

# -----------------------------------------------------------------------------
# 4. Prune old snapshots
# -----------------------------------------------------------------------------
log "Pruning old snapshots (7 daily / 4 weekly / 3 monthly)..."
restic forget --prune \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3

log "=== Backup complete ==="
