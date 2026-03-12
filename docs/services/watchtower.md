# Watchtower

## Overview

Watchtower automatically monitors Docker containers and pulls updated images when available, then restarts the containers with the new image. It runs on a schedule rather than polling continuously.

## Architecture Role

- No web UI — internal-only, no Traefik or Authelia integration required
- Accesses the Docker socket (read-only mount) to list containers and manage image updates
- Uses **label opt-in mode**: only containers with `com.centurylinklabs.watchtower.enable=true` are monitored
- Self-update is explicitly disabled (`com.centurylinklabs.watchtower.enable=false` on itself)

## Installation

- **Installed:** 2026-03-12
- **Version:** 1.7.1 (`containrrr/watchtower:latest`)
- **Change plan:** `plans/2026-03-12-1200-change-plan-watchtower-v1.md`

## Configuration Paths

| File | Purpose |
|---|---|
| `docker-compose/watchtower/docker-compose.yaml` | Service definition |
| `docker-compose/watchtower/.env` | Timezone (not committed) |
| `docker-compose/watchtower/.env.example` | Template |

## Schedule

Daily at **04:00 local time** (WET / UTC+0 or UTC+1 DST).

Cron expression: `0 0 4 * * *` (Watchtower 6-field cron: `second minute hour day month weekday`)

## Monitored Containers

Containers opted in via `com.centurylinklabs.watchtower.enable=true`:

| Container | Image |
|---|---|
| traefik | `traefik:latest` |
| portainer | `portainer/portainer-ce:latest` |
| authelia | `ghcr.io/authelia/authelia:4.38` |
| redis-authelia | `redis:7-alpine` |
| karakeep | `ghcr.io/karakeep-app/karakeep:release` |
| karakeep-chrome | `ghcr.io/browserless/chromium:latest` |
| meilisearch | `getmeili/meilisearch:v1.12` |
| cloudflared | `cloudflare/cloudflared:latest` |
| pihole | `pihole/pihole:latest` |
| dhcp-helper | `homeall/dhcphelper:latest` |

**Excluded (manual update):** `sure-web-1`, `sure-worker-1`, `sure-db-1`, `sure-redis-1` — Sure stack must be updated together; Postgres excluded for major version safety.

## Operations Guide

### Check status
```bash
docker logs watchtower --tail 50
docker ps | grep watchtower
```

### Force an immediate update check
```bash
docker exec watchtower watchtower --run-once
```

### Opt a container in or out
Add or remove the label in the service's `docker-compose.yaml`:
```yaml
labels:
  - "com.centurylinklabs.watchtower.enable=true"   # opt in
  - "com.centurylinklabs.watchtower.enable=false"  # opt out
```
Then `docker compose up -d` to recreate the container with updated labels.

### Stop Watchtower
```bash
cd ~/homelab/docker-compose/watchtower
docker compose down
```

## Known Issues / Notes

- **Docker API version**: This daemon requires minimum API version 1.44. Watchtower defaults to 1.25. Fixed via `DOCKER_API_VERSION=1.44` in environment.
- **WATCHTOWER_CLEANUP=true**: Old images are removed automatically after successful updates.
- **Pinned tags** (e.g. `meilisearch:v1.12`): Watchtower will still pull the same tag on schedule. If a new patch is published under that tag, it will update. If you want to prevent updates, set `com.centurylinklabs.watchtower.enable=false` on that container.

## Future Configuration Options

- **Notifications**: Watchtower supports Slack, email, Gotify, MSTeams via `--notification-url` (shoutrrr URL). Add when a notification channel is available.
- **Per-container update schedule**: Use `com.centurylinklabs.watchtower.schedule` label on individual containers to override the global schedule.
- **Monitor-only mode**: `WATCHTOWER_MONITOR_ONLY=true` — log available updates without applying them.
