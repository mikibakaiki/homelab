# Change Plan — Backup Architecture
**Date:** 2026-03-12
**Phase:** 6

---

## Overview

Deploy a daily automated backup using Restic to a locally-attached USB drive mounted at `/mnt/backup`. Backs up all stateful data that cannot be trivially regenerated. Uses Restic's deduplication and encryption so daily snapshots after the first are small (only changed blocks).

**Retention policy:** 7 daily, 4 weekly, 3 monthly snapshots.

---

## Full Service Audit

Every deployed service reviewed for backup need:

| Service | Back up? | What | Reason |
|---|---|---|---|
| Traefik | ✅ Partial | `traefik.yaml`, `config.yaml`, `acme.json` only | Not in git. `acme.json` especially critical — LE rate limits on re-issue. Exclude `logs/`. |
| Pi-hole | ✅ Partial | All except `gravity_old.db`, `pihole-FTL.db`, `listsCache/` | `gravity.db` must be included — contains adlist source URLs. See gravity.db note below. |
| Cloudflared | ❌ | — | Stateless — config is env vars in compose. |
| DHCP Helper | ❌ | — | Stateless relay. |
| Portainer | ❌ | — | Stack configs are all in git. Easy to reconfigure. |
| Sure (web/worker) | ✅ Postgres + app-storage | Via `pg_dump` + volume path | User application data. |
| Sure (db) | ✅ | `pg_dump` | Logical dump — safe against live writes. Raw file copy would be unsafe. |
| Sure (redis) | ❌ | — | Sidekiq job queue only — ephemeral, safe to lose. |
| Karakeep | ✅ Partial | `data/` only | User bookmarks. Exclude `meilisearch/` — derived search index, rebuilt on startup. |
| Meilisearch | ❌ | — | Derived from Karakeep data. Rebuilt automatically. |
| Karakeep Chrome | ❌ | — | Stateless browser. |
| Authelia | ✅ | `config/` + `data/` | Config, users, sqlite session/audit db. |
| Redis (Authelia) | ❌ | — | Session cache only. Sessions expire naturally. |
| Watchtower | ❌ | — | Stateless. No persistent data. |

---

## Background Notes

### gravity.db and `pihole -g`
Pi-hole v6 stores everything in SQLite. `gravity.db` contains two things: the compiled blocklist entries (bulk) AND the adlist source URLs (small but critical). `pihole -g` means "run gravity update" — it re-downloads all adlists from the configured source URLs and rebuilds the compiled entries. If `gravity.db` is lost, those URLs are gone and `pihole -g` starts from scratch with no lists. This is why `gravity.db` must be included despite its size (~103MB).

`pihole -a -t` (teleporter backup CLI) does not work in Pi-hole v6. Backup is done directly via Restic.

### Traefik `acme.json`
Stores the Let's Encrypt wildcard certificate for `*.YOUR_DOMAIN`. If lost, a new certificate can be requested, but Let's Encrypt enforces a rate limit of 5 duplicate certificates per domain per week. During a disaster recovery scenario, hitting this limit could leave the homelab without HTTPS for days.

### Postgres `pg_dump`
The Sure Postgres container runs live. Copying raw data files from a live database is unsafe and may produce a corrupt backup. `pg_dump` produces a consistent logical dump regardless of concurrent writes — no container stop needed.

---

## What Gets Backed Up

| Source | Method | Excludes |
|---|---|---|
| `~/homelab/docker/authelia/` | Restic direct | — |
| `~/homelab/docker/karakeep/data/` | Restic direct | `meilisearch/` subdir excluded |
| `~/homelab/docker/traefik/traefik.yaml` | Restic direct | — |
| `~/homelab/docker/traefik/config.yaml` | Restic direct | — |
| `~/homelab/docker/traefik/acme.json` | Restic direct | — |
| `~/homelab/docker/pihole/pihole/` | Restic direct | `gravity_old.db`, `pihole-FTL.db`, `listsCache/` |
| Sure Postgres | `pg_dump` → stdin | — |
| `sure_app-storage` volume | Restic direct | — |

**Approximate first backup size:** ~350MB. Subsequent daily runs will be far smaller.

---

## Proposed Changes

1. Install `restic` on host
2. Generate repository password, store at `/etc/restic-password` (root-owned, mode 600)
3. Initialise Restic repository at `/mnt/backup/restic`
4. Create `scripts/backup.sh`
5. Create `scripts/restore.sh`
6. Register daily root cron job at 02:00
7. Run first backup manually to verify
8. Create `docs/services/backup.md`
9. Update `docs/infrastructure-state.md`
10. Commit

---

## Configuration Preview

### `scripts/backup.sh`

```bash
#!/bin/bash
# Homelab daily backup — runs as root via cron
# Restic repository: /mnt/backup/restic

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

if ! mountpoint -q /mnt/backup; then
    log "ERROR: /mnt/backup is not mounted. Aborting."
    exit 1
fi

# 1. Postgres logical dump
log "Dumping Postgres (${POSTGRES_DB})..."
docker exec "$POSTGRES_CONTAINER" pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
    | restic backup --stdin --stdin-filename "postgres/${POSTGRES_DB}.sql"

# 2. Bind-mount data
log "Backing up bind mounts..."
restic backup \
    "$HOMELAB_DIR/docker/authelia" \
    "$HOMELAB_DIR/docker/karakeep/data" \
    "$HOMELAB_DIR/docker/traefik/traefik.yaml" \
    "$HOMELAB_DIR/docker/traefik/config.yaml" \
    "$HOMELAB_DIR/docker/traefik/acme.json" \
    "$HOMELAB_DIR/docker/pihole/pihole" \
    --exclude "$HOMELAB_DIR/docker/pihole/pihole/gravity_old.db" \
    --exclude "$HOMELAB_DIR/docker/pihole/pihole/pihole-FTL.db" \
    --exclude "$HOMELAB_DIR/docker/pihole/pihole/listsCache"

# 3. Sure file uploads volume
log "Backing up Sure app-storage volume..."
APP_STORAGE_PATH="$(docker volume inspect "$APP_STORAGE_VOLUME" \
    --format '{{.Mountpoint}}')"
restic backup "$APP_STORAGE_PATH" --tag sure_app-storage

# 4. Prune per retention policy
log "Pruning old snapshots (7 daily / 4 weekly / 3 monthly)..."
restic forget --prune \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3

log "=== Backup complete ==="
```

### Cron entry (root crontab)

```
0 2 * * * /home/YOUR_USERNAME/homelab/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| USB drive failure | Medium | Single-drive local backup — adequate for homelab. Remote layer can be added later via rclone. |
| Pi and USB fail together | Low | Power surge scenario. Mitigated in future by offsite backup. |
| Postgres backup while live | N/A | `pg_dump` produces consistent snapshot regardless of writes. |
| USB not mounted at backup time | Low | Script aborts with logged error if `/mnt/backup` not mounted. |
| Restic repo corruption | Very low | Restic has built-in integrity check: `restic check`. |

---

## Rollback Plan

The backup is read-only relative to the live system — cannot cause disruption. To remove:

```bash
sudo crontab -e            # remove backup line
rm ~/homelab/scripts/backup.sh ~/homelab/scripts/restore.sh
sudo rm /etc/restic-password
sudo rm -rf /mnt/backup/restic
```

---

## Pending Approval

Ready to proceed on approval.
