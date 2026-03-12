# Change Plan — Watchtower Deployment
**Date:** 2026-03-12
**Phase:** 5
**Service:** Watchtower

---

## Overview

Deploy Watchtower to automatically pull and restart Docker containers when updated images are available. Watchtower has no web UI, so no Traefik or Authelia integration is needed. It runs as a privileged Docker socket consumer on a scheduled poll.

**Design decision — label-based opt-in:**
Rather than updating all containers blindly, Watchtower will use `--label-enable` mode. Only containers with the label `com.centurylinklabs.watchtower.enable=true` will be monitored. This prevents accidental updates to stateful services (databases, Authelia user store) and keeps control explicit.

---

## Proposed Changes

1. Create `docker-compose/watchtower/` directory
2. Write `docker-compose.yaml` with label-enable mode and daily schedule
3. Write `.env.example`
4. Write `.env` (TZ only — no secrets required)
5. Add `com.centurylinklabs.watchtower.enable=true` label to services that should auto-update
6. Lint and simulate
7. Deploy
8. Create `docs/services/watchtower.md`
9. Update `docs/infrastructure-state.md`
10. Commit

---

## Containers Proposed for Auto-Update

| Container | Rationale |
|---|---|
| `traefik` | Stateless — safe to update |
| `portainer` | Stateless — safe to update |
| `authelia` | Stateless config — safe (config is file-mounted, not embedded in image) |
| `redis-authelia` | Stateless cache — safe |
| `karakeep` | App only — data in Meilisearch / bind mounts |
| `karakeep-chrome` | Stateless browser — safe |
| `meilisearch` | Index data in bind mount — image is safe to update |
| `cloudflared` | Stateless DNS proxy — safe |
| `pihole` | Stateless config — safe |
| `dhcp-helper` | Stateless relay — safe |

**Excluded from auto-update:**
- `sure-db-1` (postgres:16) — postgres major version upgrades require manual migration; pinned to `postgres:16` tag already, but safer to exclude
- `sure-web-1`, `sure-worker-1`, `sure-redis-1` — Sure app stack; update together manually to avoid partial upgrades

---

## Configuration Preview

### `docker-compose/watchtower/docker-compose.yaml`

```yaml
# Watchtower - automatic container image updater
# Only updates containers with label: com.centurylinklabs.watchtower.enable=true
services:
  watchtower:
    container_name: watchtower
    image: containrrr/watchtower:latest
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    environment:
      - TZ=${TZ}
      - WATCHTOWER_LABEL_ENABLE=true
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_SCHEDULE=0 0 4 * * *   # 04:00 daily
      - WATCHTOWER_ROLLING_RESTART=false
      - WATCHTOWER_INCLUDE_STOPPED=false
      - WATCHTOWER_NOTIFICATIONS=log
      - WATCHTOWER_NOTIFICATION_LOG_TEMPLATE=""
      - WATCHTOWER_NO_STARTUP_MESSAGE=false
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - "com.centurylinklabs.watchtower.enable=false"  # don't self-update by default
```

### `.env.example`

```env
TZ=YOUR_TIMEZONE
```

### Opt-in label to add to monitored services

Each service that should auto-update gets this additional label:

```yaml
labels:
  - "com.centurylinklabs.watchtower.enable=true"
```

This label is added inside each service's `docker-compose.yaml`.

---

## Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| Breaking update to a service | Low | Label opt-in — only whitelisted containers update |
| Watchtower self-updates and breaks | Low | `watchtower.enable=false` on itself |
| Unexpected postgres major version bump | N/A | Postgres excluded from opt-in |
| Sure app partial update (web+worker out of sync) | N/A | Sure stack excluded |
| Docker socket access (security) | Inherent | Read-only mount (`:ro`) is sufficient for pulls |
| Update at inconvenient time | Low | Scheduled at 04:00 local time |

No persistent data volume. Watchtower carries no state — rollback is trivial.

---

## Rollback Plan

```bash
cd ~/homelab/docker-compose/watchtower
docker compose down
```

To revert a container that was updated incorrectly, pull the prior tag manually:

```bash
docker pull <image>:<previous-tag>
docker compose up -d   # in the service's directory
```

---

## Files to Create / Modify

**New files:**
- `docker-compose/watchtower/docker-compose.yaml`
- `docker-compose/watchtower/.env.example`
- `docker-compose/watchtower/.env` (gitignored)
- `docs/services/watchtower.md`

**Modified files (add watchtower opt-in label):**
- `docker-compose/traefik/docker-compose.yaml`
- `docker-compose/portainer/docker-compose.yaml`
- `docker-compose/authelia/docker-compose.yaml`
- `docker-compose/karakeep/docker-compose.yaml`
- `docker-compose/pihole/docker-compose.yaml`

**Updated files:**
- `docs/infrastructure-state.md`

---

## Linting Checklist

- [ ] `docker compose config` — YAML and env resolution
- [ ] No Traefik labels required (no web UI)
- [ ] `docker compose up --no-start` — dry-run container creation
- [ ] Confirm `/var/run/docker.sock` exists on host
- [ ] Confirm opt-in labels present on target containers after compose edits

---

## Pending Approval

Ready to proceed on approval.
