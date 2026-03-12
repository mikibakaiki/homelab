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

## Network Architecture

Two Docker networks must exist before starting services:

1. **`proxy`** (external, created manually): Traefik routes HTTPS traffic to services over this network. Every service needing web access must join it.
   ```bash
   docker network create proxy
   ```

2. **`backend`** (internal, auto-created by pihole compose): Isolates Pi-hole ↔ Cloudflared communication. Subnet `172.31.0.0/24`, Pi-hole static IP `172.31.0.100`.

Pi-hole is the only service on **both** networks (it needs DNS port exposure and Traefik routing).

The `docker/` directory holds live runtime data (databases, certs, logs) and is **not** fully committed — it contains gitignored sensitive files.

## Adding a New Service

Use `/deploy-service` skill — it runs a 7-step Infrastructure Safety Mode gate (plan → compose → network → labels → secrets → deploy → verify).

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

## Critical Operational Gotchas

- **Traefik restart required after config.yaml edits**: Docker bind mount caches inode. Run `cd docker-compose/traefik && docker compose restart traefik` after any `docker/traefik/config.yaml` change.
- **Authelia config files are root-owned**: Cannot edit with Write/Edit tools. Write to `/tmp` → `docker cp` into container.
- **Docker containers cannot resolve Pi-hole local CNAMEs**: Docker's internal DNS (127.0.0.11) bypasses Pi-hole. Fix with `extra_hosts` in compose.
- **Portainer/Pi-hole routing uses file provider**: Traefik middleware for these services is in `docker/traefik/config.yaml`, NOT compose labels.

## Useful Commands

```bash
# Update Pi-hole blocklists
docker exec pihole pihole -g

# Generate Traefik dashboard password
htpasswd -nbB admin yourpassword
```

## When Compacting

Run `/update-docs` skill to sync documentation after any multi-service change.
