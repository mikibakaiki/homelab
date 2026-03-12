# Infrastructure State Index

> Last updated: 2026-03-11
> Updated by: Phase 0 — Infrastructure Discovery

---

## Hardware

| Property | Value |
|---|---|
| Device | Raspberry Pi 4 |
| Architecture | aarch64 |
| RAM | 7.6 GiB |
| Storage | 115 GiB total, 9.0 GiB used |
| OS | Debian GNU/Linux 12 (Bookworm) |
| Docker Engine | 29.1.1 |
| Docker Compose | v2.40.3 |

---

## Domain

- **Root domain**: `YOUR_DOMAIN`
- **DNS provider**: Cloudflare
- **Certificate strategy**: Let's Encrypt wildcard via Cloudflare DNS challenge (`*.YOUR_DOMAIN`)

---

## Deployed Services

| Service | Image | Version | Domain | Status |
|---|---|---|---|---|
| Traefik | `traefik:latest` | v3.6.2 | `traefik.YOUR_DOMAIN` | Running |
| Pi-hole | `pihole/pihole:latest` | latest | `pihole.YOUR_DOMAIN` | Running (healthy) |
| Cloudflared | `cloudflare/cloudflared:latest` | latest | internal only | Running |
| DHCP Helper | `homeall/dhcphelper:latest` | latest | internal only | Running (healthy) |
| Portainer CE | `portainer/portainer-ce:latest` | latest | `portainer.YOUR_DOMAIN` | Running |
| Sure (web) | `ghcr.io/we-promise/sure:latest` | latest | `sure.YOUR_DOMAIN` | Running |
| Sure (worker) | `ghcr.io/we-promise/sure:latest` | latest | internal | Running |
| Sure (db) | `postgres:16` | 16 | internal | Running (healthy) |
| Sure (redis) | `redis:latest` | latest | internal | Running (healthy) |
| Karakeep | `ghcr.io/karakeep-app/karakeep:release` | 0.31.0 | `karakeep.YOUR_DOMAIN` | Running (healthy) |
| Meilisearch | `getmeili/meilisearch:v1.12` | v1.12 | internal only | Running (healthy) |
| Karakeep Chrome | `ghcr.io/browserless/chromium:latest` | latest | internal only | Running |
| Authelia | `ghcr.io/authelia/authelia:4.38` | v4.38.19 | `auth.YOUR_DOMAIN` | Running (healthy) |
| Redis (Authelia) | `redis:7-alpine` | 7 | internal only | Running (healthy) |

---

## Docker Networks

| Network | Driver | Scope | Connected Services |
|---|---|---|---|
| `proxy` | bridge | external (manual) | traefik, pihole, portainer, sure-web-1, karakeep, authelia |
| `pihole_backend` | bridge | auto (pihole compose) | pihole, cloudflared — subnet `172.31.0.0/24` |
| `sure_sure_net` | bridge | auto (sure compose) | sure-web-1, sure-worker-1, sure-db-1, sure-redis-1 |
| `karakeep_karakeep_internal` | bridge | auto (karakeep compose) | karakeep, meilisearch, karakeep-chrome |
| `authelia_authelia_internal` | bridge | auto (authelia compose) | authelia, redis-authelia |

---

## Persistent Storage

### Named Docker Volumes

| Volume | Used By |
|---|---|
| `sure_app-storage` | sure-web-1, sure-worker-1 |
| `sure_postgres-data` | sure-db-1 |
| `sure_redis-data` | sure-redis-1 |

### Bind Mounts

| Host Path | Container | Notes |
|---|---|---|
| `~/homelab/docker/traefik/traefik.yaml` | traefik | Static config (read-only) |
| `~/homelab/docker/traefik/config.yaml` | traefik | Dynamic config (read-only) |
| `~/homelab/docker/traefik/acme.json` | traefik | Let's Encrypt certificate storage |
| `~/homelab/docker/traefik/logs/` | traefik | Access and error logs |
| `~/homelab/docker/pihole/pihole/` | pihole | Pi-hole config and databases |
| `~/homelab/docker/pihole/etc-dnsmasq.d/` | pihole | Custom dnsmasq config |
| `~/homelab/docker/portainer/data/` | portainer | Portainer state |
| `/var/run/docker.sock` | traefik, portainer | Docker API access (read-only) |
| `/etc/localtime` | traefik | Timezone sync |

---

## Service Dependencies

```
Internet
  └─► Traefik (80/443)
        ├─► Pi-hole web (pihole.YOUR_DOMAIN → 172.31.0.100:8080)
        ├─► Portainer (portainer.YOUR_DOMAIN → <PIHOLE_HOST_IP>:9443)
        ├─► Sure (sure.YOUR_DOMAIN → sure-web-1:3000)
        └─► Traefik dashboard (traefik.YOUR_DOMAIN → api@internal)

LAN Clients
  └─► Pi-hole DNS (:53)
        └─► Cloudflared DoH (port 5053)
              └─► Cloudflare 1.1.1.1 / Quad9 9.9.9.9

Pi-hole DHCP (:67/udp)
  └─► dhcp-helper (host network, relays LAN DHCP broadcasts → 172.31.0.100)

Sure (web)
  ├─► sure-db-1 (PostgreSQL 16)
  └─► sure-redis-1 (Redis, Sidekiq queue)
```

---

## Traefik Middleware Registry

Defined in `~/homelab/docker/traefik/config.yaml`:

| Middleware | Type | Used By |
|---|---|---|
| `default-security-headers` | Headers (strict CSP) | pihole (file router) |
| `portainer-security-headers` | Headers (no CSP) | portainer (file router), authelia |
| `sure-security-headers` | Headers (no CSP) | sure (label router) |
| `karakeep-security-headers` | Headers (no CSP) | karakeep (label router) |
| `https-redirectscheme` | Redirect HTTPS | HTTP routers |
| `authelia` | ForwardAuth | karakeep, portainer, pihole |

Defined via Traefik labels (dynamic):

| Middleware | Type | Used By |
|---|---|---|
| `traefik-auth` | BasicAuth | traefik dashboard |
| `traefik-https-redirect` | Redirect | traefik HTTP router |
| `sslheader` | RequestHeaders | (defined, not applied) |
| `pihole-https-redirect` | Redirect | pihole HTTP router |
| `pihole-addprefix` | AddPrefix (`/admin`) | pihole HTTPS router |
| `portainer-https-redirect` | Redirect | portainer HTTP router |
| `portainer-headers` | Headers | portainer HTTPS router (label ref, empty) |
| `sure` HTTP middlewares | Redirect | sure HTTP router |

---

## Planned Services

| Service | Domain | Change Plan | Status |
|---|---|---|---|
| Karakeep | `karakeep.YOUR_DOMAIN` | `plans/2026-03-11-1200-change-plan-karakeep-v1.md` | Deployed (Phase 3 complete) |
| Authelia | `auth.YOUR_DOMAIN` | `plans/2026-03-11-1430-change-plan-authelia-v1.md` | Deployed (Phase 4 complete) |
| Watchtower | internal | TBD (Phase 5) | Planned |

---

## Known Issues (Discovered Phase 0)

1. **Duplicate middleware label on Sure**: The `sure-secure` router has two `traefik.http.routers.sure-secure.middlewares` labels — only the last one (`sure-security-headers@file`) is applied. The redirect middleware label is silently overridden.

2. **Sure port 3000 exposed on host**: `ports: 3000:3000` in sure compose bypasses Traefik and exposes the app directly to the LAN. This is a security concern — the port should not be host-exposed if Traefik is the intended access point.

3. **Dual routing for Portainer and Pi-hole**: Both are defined in `config.yaml` (file provider) *and* via Docker labels. This creates redundant routes. The file provider routes use static IPs (`<PIHOLE_HOST_IP>:9443`) while labels use container discovery.

4. **All images use `:latest` tag**: No version pinning. Uncontrolled updates on `docker compose pull`.

5. ~~**No Authelia**~~: Authelia deployed (Phase 4). Karakeep, Portainer, Pi-hole protected. Traefik dashboard intentionally kept on BasicAuth only (diagnostic tool — must remain reachable if Authelia fails).

6. **No Watchtower**: No automated update management.

7. **No monitoring or observability stack**: No metrics, alerting, or dashboards.

8. **No backup solution**: No automated backup for bind mounts or named volumes.

9. **Missing infrastructure directories**: `docs/`, `plans/`, `templates/` did not exist (created in Phase 0).

---

## Change History

| Date | Plan | Summary |
|---|---|---|
| 2026-03-11 | Phase 0 | Initial infrastructure discovery |
| 2026-03-11 | Phase 1 | Documentation: service docs, auth-architecture, disaster-recovery, service template |
| 2026-03-11 | Phase 2 | Karakeep architecture: change plan and service doc created |
| 2026-03-11 | Phase 3 | Karakeep deployed — resolved ARM64 Chrome image, Meilisearch healthcheck, Browserless v2 WebSocket auth |
| 2026-03-11 | Phase 4 | Authelia deployed — forward-auth SSO, OIDC provider for Karakeep, user `miki` |
