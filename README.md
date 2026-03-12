# 🏠 Homelab Infrastructure

A Docker-based homelab on Raspberry Pi 4 running a full self-hosted stack with reverse proxy, DNS/DHCP, SSO, bookmarks, backups, and automated updates.

## 🚀 Overview

This repository contains the infrastructure for a production-grade homelab built around:
- **Network-wide ad blocking** with Pi-hole v6 + Cloudflared DNS-over-HTTPS
- **HTTPS reverse proxy** with Traefik and Let's Encrypt wildcard certificates
- **Single Sign-On** with Authelia (forward-auth + OIDC provider)
- **Container management** with Portainer
- **Bookmarks** with Karakeep (OIDC via Authelia)
- **Internal app** Sure (Authelia gate + app-level login)
- **Automated image updates** with Watchtower (daily 04:00, label opt-in)
- **Daily encrypted backups** with Restic to USB drive

## 📋 Services

| Service | Purpose | Access | Auth | Status |
|---------|---------|---------|---------|---------|
| **Traefik** | Reverse proxy + SSL termination | `https://traefik.your.domain` | BasicAuth | 🟢 Active |
| **Pi-hole** | DNS/DHCP + ad blocking | `https://pihole.your.domain` | Authelia | 🟢 Active |
| **Cloudflared** | DNS-over-HTTPS proxy | Internal only | — | 🟢 Active |
| **Portainer** | Container management | `https://portainer.your.domain` | Authelia | 🟢 Active |
| **Authelia** | SSO gateway + OIDC provider | `https://auth.your.domain` | — | 🟢 Active |
| **Karakeep** | Bookmark manager | `https://karakeep.your.domain` | Authelia OIDC (SSO) | 🟢 Active |
| **Sure** | Internal app | `https://sure.your.domain` | Authelia + app login | 🟢 Active |
| **Watchtower** | Automated image updates | Internal only | — | 🟢 Active |
| **Restic Backup** | Daily encrypted backup to USB | Internal only | — | 🟢 Active |

## 🏗️ Architecture

```mermaid
graph TD
    A[Internet] --> B[Traefik :80/:443]
    B --> AU[Authelia auth.your.domain]
    B --> C[Pi-hole pihole.your.domain]
    B --> D[Portainer portainer.your.domain]
    B --> E[Traefik Dashboard traefik.your.domain]
    B --> K[Karakeep karakeep.your.domain]
    B --> S[Sure sure.your.domain]

    AU -- ForwardAuth gate --> C
    AU -- ForwardAuth gate --> D
    AU -- ForwardAuth gate --> K
    AU -- ForwardAuth gate --> S
    AU -- OIDC provider --> K

    F[LAN Clients] --> G[Pi-hole DNS/DHCP :53]
    G --> H[Cloudflared DoH :5053]
    H --> I[Cloudflare 1.1.1.1 / Quad9 9.9.9.9]

    J[DHCP Helper host-net] --> G

    S --> SDB[(PostgreSQL 16)]
    S --> SR[(Redis)]
    K --> MS[(Meilisearch)]
    K --> CH[Chromium headless]
    AU --> RA[(Redis)]

    WA[Watchtower] -. daily pull .-> B
    RB[Restic Backup] -. daily 02:00 .-> USB[/mnt/backup USB]

    subgraph "proxy network"
        B
        AU
        C
        D
        K
        S
    end

    subgraph "pihole_backend 172.31.0.0/24"
        C
        H
    end
```

## 🔧 Quick Start

### Prerequisites
- Docker Engine 20.10+
- Docker Compose v2+
- Domain name with Cloudflare DNS management
- Port forwarding: 80/443 (HTTP/HTTPS), 53 (DNS)

### Setup

1. **Clone and prepare environment files**:
   ```bash
   git clone <your-repo>
   cd homelab

   cp docker-compose/traefik/.env.example docker-compose/traefik/.env
   cp docker-compose/pihole/.env.example docker-compose/pihole/.env
   cp docker-compose/authelia/.env.example docker-compose/authelia/.env
   cp docker-compose/karakeep/.env.example docker-compose/karakeep/.env
   ```

2. **Configure secrets**:
   ```bash
   echo "your_cloudflare_api_token" > docker-compose/traefik/cf-token
   chmod 600 docker-compose/traefik/cf-token
   ```

3. **Create Docker networks**:
   ```bash
   docker network create proxy
   ```

4. **Start services** (Traefik and Pi-hole first):
   ```bash
   cd docker-compose/traefik && docker compose up -d
   cd docker-compose/pihole && docker compose up -d
   cd docker-compose/authelia && docker compose up -d
   cd docker-compose/karakeep && docker compose up -d
   cd docker-compose/sure && docker compose up -d
   cd docker-compose/portainer && docker compose up -d
   cd docker-compose/watchtower && docker compose up -d
   ```

5. **Verify**:
   ```bash
   docker ps
   docker network inspect proxy
   ```

## 📁 Repository Structure

```
homelab/
├── docker-compose/              # Service compose files + env templates
│   ├── traefik/
│   ├── pihole/
│   ├── portainer/
│   ├── authelia/
│   ├── karakeep/
│   ├── sure/
│   ├── watchtower/
│   └── backup/
├── docker/                      # Persistent bind-mount data (runtime, gitignored)
│   ├── traefik/
│   │   ├── traefik.yaml         # Traefik static config
│   │   ├── config.yaml          # Traefik dynamic config (middlewares, file routers)
│   │   ├── acme.json            # Let's Encrypt certificates (chmod 600, gitignored)
│   │   └── logs/
│   ├── pihole/
│   └── authelia/
│       └── config/              # configuration.yml + users_database.yml (root-owned)
├── docs/                        # Infrastructure documentation
│   └── services/                # Per-service docs
├── plans/                       # Change plans (YYYY-MM-DD-HHMM-change-plan-<svc>-v1.md)
├── templates/                   # Reusable compose + config templates
├── .claude/
│   ├── skills/                  # Claude Code slash-command skills
│   └── agents/                  # Claude Code sub-agents
├── .gitignore
└── README.md
```

## 🔒 Security

### Secrets & Environment Files
- `.env` files are gitignored — only `.env.example` files are committed
- Cloudflare API token in `docker-compose/traefik/cf-token` (gitignored, injected as Docker secret)
- `docker/traefik/acme.json` must be `chmod 600` and is gitignored
- Template workflow: `cp .env.example .env` then fill in values

### Network Isolation
- **`proxy` network** (external, created manually): all services needing HTTPS access join this
- **`pihole_backend`** (internal, auto-created): Pi-hole ↔ Cloudflared only, subnet `172.31.0.0/24`
- **Service-internal networks**: Sure, Karakeep, and Authelia each have isolated internal networks for their databases/caches

### Authentication
- **Authelia** gates all services via Traefik ForwardAuth middleware
- **Traefik dashboard** intentionally uses BasicAuth only (must remain reachable if Authelia is down)
- **Karakeep** uses Authelia as OIDC provider — single login, no local credentials
- **Sure** uses Authelia gate + its own app-level login

## 🛠️ Configuration Details

### Docker Networks

| Network | Driver | Scope | Connected Services |
|---------|--------|-------|-------------------|
| `proxy` | bridge | external (manual) | traefik, pihole, portainer, sure-web, karakeep, authelia |
| `pihole_backend` | bridge | auto (pihole compose) | pihole, cloudflared |
| `sure_sure_net` | bridge | auto | sure-web, sure-worker, sure-db, sure-redis |
| `karakeep_internal` | bridge | auto | karakeep, meilisearch, karakeep-chrome |
| `authelia_internal` | bridge | auto | authelia, redis-authelia |

### Traefik Middleware Registry

Defined in `docker/traefik/config.yaml` (file provider):

| Middleware | Type | Used By |
|-----------|------|---------|
| `default-security-headers` | Headers (strict CSP) | pihole |
| `portainer-security-headers` | Headers (no CSP) | portainer, authelia |
| `sure-security-headers` | Headers (no CSP) | sure |
| `karakeep-security-headers` | Headers (no CSP) | karakeep |
| `https-redirectscheme` | Redirect HTTPS | HTTP routers |
| `authelia` | ForwardAuth | karakeep, portainer, pihole, sure |

### DNS Configuration
- Upstream: Cloudflared DoH → Cloudflare (1.1.1.1) + Quad9 (9.9.9.9)
- DHCP range and static IP configured via `FTLCONF_*` environment variables (Pi-hole v6)
- `dhcp-helper` container runs in host network mode to relay LAN DHCP broadcasts to Pi-hole on bridge network

### Network Configuration
- **Domain**: `your.domain` (Cloudflare managed)
- **Certificates**: Let's Encrypt wildcard `*.your.domain` via Cloudflare DNS challenge
- **Pi-hole IP**: `<PIHOLE_HOST_IP>`
- **Router Gateway**: `<ROUTER_IP>`
- **DHCP Range**: `<DHCP_RANGE_START>`–`<DHCP_RANGE_END>`

## 📊 Monitoring & Maintenance

### Health Checks
```bash
docker compose ps
docker stats
docker logs traefik --tail 50
docker logs pihole --tail 50
docker logs authelia --tail 50
```

### Watchtower (Automated Updates)
Watchtower runs daily at 04:00 and updates containers that have the opt-in label:
```yaml
labels:
  - "com.centurylinklabs.watchtower.enable=true"
```
Containers without this label are never touched automatically.

### Restic Backup
Daily backup runs at 02:00 via a systemd timer (or cron). Targets:
- All bind-mount data under `docker/`
- `pg_dump` of the Sure PostgreSQL database

Retention policy: **7 daily / 4 weekly / 3 monthly** snapshots.
Repository location: `/mnt/backup` (USB drive, ext4).

```bash
# Check backup status manually
restic -r /mnt/backup snapshots

# Trigger manual backup
systemctl start restic-backup  # or run the backup script directly
```

### Pi-hole Blocklist Updates
```bash
docker exec pihole pihole -g
```

## 🐛 Troubleshooting

### Traefik `config.yaml` Changes Require Restart
Docker bind mounts cache the inode. After any edit to `docker/traefik/config.yaml`, always restart Traefik:
```bash
cd docker-compose/traefik && docker compose restart traefik
```

### Authelia Config Files Are Root-Owned
Files in `docker/authelia/config/` are owned by root (created by Docker on first run). They cannot be edited directly with normal user tools. Use:
```bash
# Write to a temp file, then copy into the container
docker cp /tmp/configuration.yml authelia:/config/configuration.yml
docker restart authelia
```

### Containers Can't Resolve Local Domains
Docker's internal resolver (127.0.0.11) does not use Pi-hole. Containers needing to reach local CNAMEs (e.g., `auth.your.domain`) must use `extra_hosts` in their compose file:
```yaml
extra_hosts:
  - "auth.your.domain:<PIHOLE_HOST_IP>"
```

### "network proxy not found"
```bash
docker network create proxy
cd docker-compose/traefik && docker compose down && docker compose up -d
```

### DNS Resolution Problems
```bash
docker exec pihole pihole status
docker logs cloudflared --tail 30
```

### HTTPS Certificate Issues
```bash
docker logs traefik | grep -i acme
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer $(cat docker-compose/traefik/cf-token)"
```

### Authelia Portal Unstyled / CORS During OIDC
Add bypass rules for static assets (`.js`, `.css`, manifest, favicon) in `docker/authelia/config/configuration.yml` under `access_control.rules`. See `docs/services/authelia.md` for the pattern.

### Pi-hole Admin CSS Broken
Ensure the file provider router for Pi-hole in `docker/traefik/config.yaml` has `priority: 100` to prevent the Docker label router from taking precedence. See `docs/services/pihole.md`.

## 🚧 Adding New Services

Every infrastructure change requires a change plan in `plans/` before deployment. Use the `/deploy-service` skill to scaffold a new service:

```
/deploy-service <service-name>
```

Manual checklist:
1. Create `docker-compose/<service>/docker-compose.yaml` and `.env.example`
2. Join the `proxy` network (`external: true`)
3. Add Traefik labels for HTTP→HTTPS redirect and HTTPS router with `tls.certresolver=cloudflare`
4. Add an Authelia ForwardAuth middleware if the service needs SSO protection
5. If the service makes outbound requests to local domains, add `extra_hosts`
6. Add a security-headers middleware to `docker/traefik/config.yaml` if a relaxed CSP is needed
7. Restart Traefik after any `config.yaml` edits
8. Add the Watchtower opt-in label if you want automatic updates

## 📚 Documentation

- `docs/infrastructure-state.md` — full hardware, network, and service inventory
- `docs/services/` — per-service docs (traefik, pihole, authelia, karakeep, sure, portainer, watchtower, backup)
- `plans/` — change plans for every deployed phase
- `CLAUDE.md` — instructions for Claude Code agents working in this repo

---

## 📈 Status

**Last Updated**: 2026-03-12
**Hardware**: Raspberry Pi 4, aarch64, Debian 12 (Bookworm)
**Docker Engine**: 29.1.1 / Docker Compose v2.40.3
**Active Services**: 8 (Traefik, Pi-hole, Cloudflared, Portainer, Authelia, Karakeep, Sure, Watchtower + Restic)
**TLS**: Let's Encrypt wildcard via Cloudflare DNS challenge
**Backup**: Restic daily to USB, 7d/4w/3m retention
