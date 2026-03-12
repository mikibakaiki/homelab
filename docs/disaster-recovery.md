# Disaster Recovery

> Created: 2026-03-11 (Phase 1)
> Status: Manual procedures only — automated backup not yet deployed

---

## What Needs to Be Recovered

### Critical Data (must back up)

| Path | Contents | Owned by |
|---|---|---|
| `~/homelab/docker/traefik/acme.json` | Let's Encrypt certificates | Traefik |
| `~/homelab/docker/traefik/traefik.yaml` | Static Traefik config | Traefik |
| `~/homelab/docker/traefik/config.yaml` | Dynamic Traefik config | Traefik |
| `~/homelab/docker/pihole/pihole/` | Pi-hole databases, gravity, leases, config | Pi-hole |
| `~/homelab/docker/pihole/etc-dnsmasq.d/` | Custom dnsmasq config | Pi-hole |
| `~/homelab/docker/portainer/data/` | Portainer state: users, stacks, settings | Portainer |
| `~/homelab/docker-compose/` | All compose files | All services |
| Named Docker volumes | Sure app storage, PostgreSQL data, Redis data | Sure |

### Regeneratable (do not need backup)

- Container images (pulled from registries)
- Traefik logs (`docker/traefik/logs/`)
- Pi-hole query logs (in FTL database, but non-critical)

---

## Manual Backup Procedure

Run from the Pi:

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="~/backups/homelab"
DATE=$(date +%Y%m%d-%H%M)
mkdir -p "$BACKUP_DIR"

# Bind mount data
tar -czf "$BACKUP_DIR/docker-data-$DATE.tar.gz" \
    ~/homelab/docker/traefik/acme.json \
    ~/homelab/docker/traefik/traefik.yaml \
    ~/homelab/docker/traefik/config.yaml \
    ~/homelab/docker/pihole/ \
    ~/homelab/docker/portainer/data/

# Compose files and config (repo is in git, but local .env files are not)
tar -czf "$BACKUP_DIR/compose-config-$DATE.tar.gz" \
    ~/homelab/docker-compose/

# Named Docker volumes (Sure stack)
docker run --rm \
    -v sure_postgres-data:/data \
    -v "$BACKUP_DIR":/backup \
    alpine tar -czf /backup/sure-postgres-$DATE.tar.gz /data

docker run --rm \
    -v sure_app-storage:/data \
    -v "$BACKUP_DIR":/backup \
    alpine tar -czf /backup/sure-appstorage-$DATE.tar.gz /data

echo "Backup complete: $BACKUP_DIR"
ls -lh "$BACKUP_DIR"
```

> Note: `.env` files and `cf-token` are gitignored. They must be backed up separately or kept in a password manager.

---

## Recovery: Full Wipe and Restore

### Prerequisites

- Fresh Raspberry Pi OS (Debian 12 Bookworm)
- Docker Engine and Docker Compose installed
- Git, htpasswd (apache2-utils) installed
- Backup archive accessible

### Steps

```bash
# 1. Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# 2. Clone repo
git clone <repo-url> ~/homelab

# 3. Restore bind-mount data
tar -xzf docker-data-YYYYMMDD.tar.gz -C /

# 4. Restore compose configs (env files, tokens)
tar -xzf compose-config-YYYYMMDD.tar.gz -C /
# Verify .env files and cf-token are present

# 5. Fix acme.json permissions
chmod 600 ~/homelab/docker/traefik/acme.json

# 6. Create proxy network
docker network create proxy

# 7. Start services in order
cd ~/homelab/docker-compose/traefik && docker compose up -d
cd ~/homelab/docker-compose/pihole  && docker compose up -d
cd ~/homelab/docker-compose/portainer && docker compose up -d
cd ~/homelab/docker-compose/sure && docker compose up -d

# 8. Restore named volumes (Sure)
docker run --rm \
    -v sure_postgres-data:/data \
    -v /path/to/backup:/backup \
    alpine tar -xzf /backup/sure-postgres-YYYYMMDD.tar.gz -C /

docker run --rm \
    -v sure_app-storage:/data \
    -v /path/to/backup:/backup \
    alpine tar -xzf /backup/sure-appstorage-YYYYMMDD.tar.gz -C /

# 9. Restart Sure to pick up restored DB
cd ~/homelab/docker-compose/sure && docker compose restart
```

---

## Recovery: Single Service

### Traefik

```bash
cd ~/homelab/docker-compose/traefik
docker compose down
docker compose up -d
# Certs are loaded from acme.json — no re-issue needed if file is intact
```

### Pi-hole

```bash
cd ~/homelab/docker-compose/pihole
docker compose down
docker compose up -d
# Restore gravity and config from backup if needed:
# tar -xzf pihole-backup.tar.gz -C /
docker exec pihole pihole -g  # rebuild gravity if needed
```

### Sure (application only, DB intact)

```bash
cd ~/homelab/docker-compose/sure
docker compose pull
docker compose up -d
```

### Sure (full restore including DB)

```bash
cd ~/homelab/docker-compose/sure
docker compose down
docker volume rm sure_postgres-data sure_app-storage sure_redis-data
docker volume create sure_postgres-data
docker volume create sure_app-storage
# Restore from backup (see above)
docker compose up -d
```

---

## Recovery: acme.json Lost (Certificate Re-issue)

If `acme.json` is lost or corrupted:

```bash
# Delete corrupted file and recreate empty with correct permissions
rm ~/homelab/docker/traefik/acme.json
touch ~/homelab/docker/traefik/acme.json
chmod 600 ~/homelab/docker/traefik/acme.json

# Restart Traefik — it will request new certificates from Let's Encrypt
cd ~/homelab/docker-compose/traefik && docker compose restart
docker logs traefik -f  # watch for cert issuance
```

> Let's Encrypt rate limits: 5 certificate requests per domain per week. Use the staging CA during testing if needed (toggle in `traefik.yaml`).

---

## Recovery: Pi-hole DHCP Data Lost

DHCP leases can be re-built automatically as clients renew. Static leases and custom DNS entries must be restored from backup or re-entered via the web UI.

```bash
# Check what's in the custom hosts file
cat ~/homelab/docker/pihole/pihole/hosts/custom.list
```

---

## Planned: Automated Backup

**Phase 6 — Backup Architecture** will implement automated backup with:

- Scheduled backup script (cron or Systemd timer)
- Off-device destination (external drive, S3-compatible, or NAS)
- Retention policy (e.g. 7 daily, 4 weekly)
- Backup verification step

---

## DNS Failover During Pi-hole Outage

If Pi-hole is down, LAN clients will lose DNS. Mitigations:

- Set a secondary DNS on your router (e.g. `1.1.1.1`) as fallback — clients use Pi-hole first, Cloudflare as backup.
- Pi-hole `restart: unless-stopped` handles automatic restart after crashes.
- The `dhcp-helper` also has `restart: unless-stopped`.
