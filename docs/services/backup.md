# Backup

Automated daily backup using Restic to a locally-attached USB drive.

---

## What Gets Backed Up

| Source | Method | Excludes |
|---|---|---|
| `~/homelab/docker/authelia/` | Restic direct | — |
| `~/homelab/docker/karakeep/data/` | Restic direct | — |
| `~/homelab/docker/traefik/traefik.yaml` | Restic direct | — |
| `~/homelab/docker/traefik/config.yaml` | Restic direct | — |
| `~/homelab/docker/traefik/acme.json` | Restic direct | — |
| `~/homelab/docker/pihole/pihole/` | Restic direct | `gravity_old.db`, `pihole-FTL.db`, `listsCache/` |
| Sure Postgres (`sure_production`) | `pg_dump` via stdin | — |
| `sure_app-storage` volume | Restic direct | — |

Services not backed up (stateless or git-managed): Cloudflared, DHCP Helper, Portainer, Sure Redis, Meilisearch, Karakeep Chrome, Redis (Authelia), Watchtower.

---

## Storage

- **Destination**: `/mnt/backup/restic` on USB drive (ext4, UUID `f6d8eba4-...`)
- **Encryption**: Restic AES-256 — password at `/etc/restic-password` (root-owned, mode 600)
- **Retention**: 7 daily / 4 weekly / 3 monthly snapshots (applied after each run)

---

## Schedule

Root crontab entry (runs daily at 02:00):

```
0 2 * * * /path/to/homelab/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```

Path is derived dynamically from script location — no hardcoded username.

---

## Scripts

- `scripts/backup.sh` — runs backup and prune. Execute manually to test or re-run.
- `scripts/restore.sh` — restore reference with functions for each component. Source or call sections manually.

---

## Monitoring

Log: `/var/log/homelab-backup.log`

```bash
# Tail the log
tail -50 /var/log/homelab-backup.log

# List snapshots
sudo restic -r /mnt/backup/restic --password-file /etc/restic-password snapshots

# Check integrity
sudo restic -r /mnt/backup/restic --password-file /etc/restic-password check
```

---

## Restore Procedures

### Before any restore

1. Stop affected containers.
2. Verify the USB drive is mounted: `mountpoint -q /mnt/backup`
3. List snapshots to identify the target: `sudo scripts/restore.sh` then call `list_snapshots`

### Restore bind mounts (Authelia, Karakeep, Traefik, Pi-hole)

```bash
# Stop affected services
cd ~/homelab/docker-compose/authelia && docker compose down
cd ~/homelab/docker-compose/karakeep && docker compose down
cd ~/homelab/docker-compose/traefik && docker compose down
cd ~/homelab/docker-compose/pihole && docker compose down

# Restore to original paths
sudo restic -r /mnt/backup/restic --password-file /etc/restic-password \
    restore latest --target /

# Restart services
cd ~/homelab/docker-compose/traefik && docker compose up -d
# (repeat for others)
```

After restoring `acme.json`, ensure permissions are correct:
```bash
chmod 600 ~/homelab/docker/traefik/acme.json
```

After restoring `docker/authelia/config/`, files will be root-owned (as expected by the container).

### Restore Postgres (Sure)

Sure web and worker must be stopped; db container must remain running.

```bash
cd ~/homelab/docker-compose/sure && docker compose stop web worker

# Drop and recreate
docker exec sure-db-1 psql -U sure_user -c "DROP DATABASE IF EXISTS sure_production;"
docker exec sure-db-1 psql -U sure_user -c "CREATE DATABASE sure_production;"

# Restore from dump
sudo restic -r /mnt/backup/restic --password-file /etc/restic-password \
    dump latest "postgres/sure_production.sql" \
    | docker exec -i sure-db-1 psql -U sure_user sure_production

# Restart
docker compose up -d
```

### Restore Sure app-storage volume

```bash
APP_PATH="$(docker volume inspect sure_app-storage --format '{{.Mountpoint}}')"
sudo restic -r /mnt/backup/restic --password-file /etc/restic-password \
    restore latest --target / --include "$APP_PATH"
```

---

## Troubleshooting

**USB not mounted at backup time**: Script aborts early with `ERROR: /mnt/backup is not mounted.` Check `/etc/fstab` and `systemctl status` for the mount unit.

**Postgres dump fails**: Check that `sure-db-1` is running: `docker ps | grep sure-db`. The `pg_dump` step does not require stopping the container.

**Restic lock stuck** (after interrupted run):
```bash
sudo restic -r /mnt/backup/restic --password-file /etc/restic-password unlock
```

**Check repository integrity**:
```bash
sudo restic -r /mnt/backup/restic --password-file /etc/restic-password check
```
