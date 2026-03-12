# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Directory Structure

```
docker-compose/<service>/   # Compose files, .env, secrets
docker/<service>/           # Persistent bind-mount data (runtime, gitignored)
docs/                       # Infrastructure documentation
docs/services/              # Per-service documentation
plans/                      # Change plans — named: YYYY-MM-DD-HHMM-change-plan-<service>-v1.md
templates/                  # Reusable compose and config templates
```

Every infrastructure change requires a change plan in `plans/` before deployment. See `plans/2026-03-11-0000-homelab-platform-agent-spec-v7.md` for the full platform operational spec and workflow.

## What This Repo Is

A Docker-based homelab on Raspberry Pi 4 running Pi-hole (DNS/DHCP + ad blocking), Traefik (reverse proxy + SSL), Portainer (container management), and Cloudflared (DNS-over-HTTPS). The domain is managed via Cloudflare with Let's Encrypt wildcard certificates using DNS challenge.

## Common Commands

```bash
# Start a service (run from its directory)
cd docker-compose/traefik && docker compose up -d
cd docker-compose/pihole && docker compose up -d
cd docker-compose/portainer && docker compose up -d

# Check status / logs
docker compose ps
docker logs traefik --tail 50
docker logs pihole --tail 50

# Restart a service
docker compose restart

# Update Pi-hole blocklists
docker exec pihole pihole -g

# Generate Traefik dashboard password (requires apache2-utils)
htpasswd -nbB admin yourpassword
```

## Network Architecture

Two Docker networks must exist before starting services:

1. **`proxy`** (external, created manually): Traefik routes HTTPS traffic to services over this network. Every service needing web access must join it.
   ```bash
   docker network create proxy
   ```

2. **`backend`** (internal, auto-created by pihole compose): Isolates Pi-hole ↔ Cloudflared communication. Subnet `172.31.0.0/24`, Pi-hole static IP `172.31.0.100`.

Pi-hole is the only service on **both** networks (it needs DNS port exposure and Traefik routing).

## Directory Structure

```
docker-compose/<service>/   # Docker Compose files, .env files, secrets
docker/<service>/           # Persistent data volumes (mounted into containers)
docker/traefik/traefik.yaml # Traefik static config (entrypoints, providers, ACME)
docker/traefik/config.yaml  # Traefik dynamic config (middlewares, routers, services)
```

The `docker/` directory holds live runtime data (databases, certs, logs) and is **not** fully committed — it contains gitignored sensitive files.

## Adding a New Service

1. Create `docker-compose/<service>/docker-compose.yaml` and `.env` (copy from an existing service as template).
2. Connect to the `proxy` network (mark it `external: true`).
3. Add Traefik labels for HTTP→HTTPS redirect and HTTPS router with `tls.certresolver=cloudflare`.
4. If the service needs a custom security header middleware, add it to `docker/traefik/config.yaml` (see existing `portainer-security-headers` pattern — Portainer and CSP-sensitive services need a relaxed CSP).

## Secrets and Environment Files

- `.env` files are gitignored — only `.env.example` files are committed.
- Cloudflare API token lives in `docker-compose/traefik/cf-token` (gitignored); injected as a Docker secret.
- `docker/traefik/acme.json` stores Let's Encrypt certificates — must be `chmod 600` and is gitignored.
- Template workflow: `cp .env.example .env`, then fill in values.

## Traefik Label Pattern

Each service uses this standard label pattern:
- HTTP router → redirects to HTTPS via middleware
- HTTPS router → TLS with `certresolver=cloudflare`, points to service
- Service → specifies the container port

Pi-hole additionally uses an `addprefix` middleware to prepend `/admin` to requests.

## Pi-hole DNS Config

Pi-hole v6 uses `FTLCONF_*` environment variables (not a config file). DNS upstream is Cloudflared on port 5053 (`cloudflared#5053`). DHCP is active for `<DHCP_RANGE_START>-<DHCP_RANGE_END>`, router at `<ROUTER_IP>`, Pi-hole host IP `<PIHOLE_HOST_IP>`. A `dhcp-helper` container running in host network mode relays DHCP broadcasts to Pi-hole on the bridge network.
