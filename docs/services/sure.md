# Sure

> Installed: ~2026-03-09 (discovered Phase 0, 2026-03-11)

---

## Overview

Sure is a self-hosted Rails application (project management / task tracking). It runs as a multi-container stack: a Rails web server, a Sidekiq background worker, PostgreSQL 16, and Redis.

- **Repository**: `https://github.com/we-promise/sure`
- **Image**: `ghcr.io/we-promise/sure:latest`
- **Domain**: `sure.YOUR_DOMAIN`

---

## Architecture Role

```
Traefik → sure-web-1 (:3000) → sure-db-1 (PostgreSQL)
                              → sure-redis-1 (Redis / Sidekiq queue)
sure-worker-1 → sure-db-1 → sure-redis-1
```

`sure-web-1` is on both `proxy` (Traefik-accessible) and `sure_sure_net` (internal app tier). All other Sure containers are internal only.

---

## Configuration Paths

| File | Purpose |
|---|---|
| `docker-compose/sure/compose.yml` | Stack definition |
| `docker-compose/sure/.env` | Secrets (gitignored) |

---

## Volumes

| Volume | Mount | Contents |
|---|---|---|
| `sure_app-storage` | `/rails/storage` | Active Storage files |
| `sure_postgres-data` | `/var/lib/postgresql/data` | Database |
| `sure_redis-data` | `/data` | Redis persistence |

---

## Environment Variables

| Variable | Default | Notes |
|---|---|---|
| `POSTGRES_USER` | `sure_user` | DB user |
| `POSTGRES_PASSWORD` | `sure_password` | **Change in production** |
| `POSTGRES_DB` | `sure_production` | DB name |
| `SECRET_KEY_BASE` | (hardcoded default) | **Must be rotated** |
| `SELF_HOSTED` | `true` | Enables self-hosted mode |
| `RAILS_FORCE_SSL` | `false` | SSL handled by Traefik |
| `RAILS_ASSUME_SSL` | `false` | |
| `OPENAI_ACCESS_TOKEN` | (empty) | Optional, enables AI features |

---

## Operations

```bash
# Start
cd ~/homelab/docker-compose/sure && docker compose up -d

# Stop
docker compose down

# Logs
docker logs sure-web-1 --tail 50
docker logs sure-worker-1 --tail 50

# Database shell
docker exec -it sure-db-1 psql -U sure_user -d sure_production

# Rails console
docker exec -it sure-web-1 bundle exec rails console
```

---

## Known Issues

1. **Port 3000 exposed on host** — `ports: 3000:3000` in compose.yml allows direct LAN access bypassing Traefik. Should be removed if external access is only via HTTPS.

2. **Duplicate middleware label** — Two `middlewares` keys on `sure-secure` router; only `sure-security-headers@file` is applied.

3. **Default secrets** — `SECRET_KEY_BASE` and `POSTGRES_PASSWORD` have hardcoded defaults in compose.yml. These should be overridden in a `.env` file.

4. **No healthcheck on web/worker** — The `web` and `worker` containers have no Docker healthcheck defined.

---

## Future Configuration Options

- Add Docker healthcheck to `web` container
- Remove host port `3000:3000` and rely solely on Traefik routing
- Override default secrets via `.env` file
- Pin image to a specific release tag instead of `latest`
- Consider Authelia SSO protection once Authelia is deployed
