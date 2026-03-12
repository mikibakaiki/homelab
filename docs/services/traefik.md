# Traefik

> Installed: initial setup
> Discovered: 2026-03-11 (Phase 0)
> Version: v3.6.2 (image: `traefik:latest`)

---

## Overview

Traefik is the reverse proxy and TLS termination point for all homelab services. It runs on ports 80 and 443, auto-discovers services via Docker labels, and provisions wildcard Let's Encrypt certificates using Cloudflare DNS challenge.

- **Domain**: `traefik.YOUR_DOMAIN` (dashboard, BasicAuth protected)
- **Certificate**: `*.YOUR_DOMAIN` via Let's Encrypt + Cloudflare DNS challenge

---

## Architecture Role

```
Internet :80/:443
     │
  Traefik
     ├── Reads Docker socket for service autodiscovery
     ├── Reads /config.yaml for static middleware + file-provider routes
     ├── Reads /traefik.yaml for static configuration
     ├── Reads /acme.json for certificate storage
     └── Routes to: pihole, portainer, sure, traefik dashboard
```

Traefik is the only container with a public port binding. All other services are reached through it via the `proxy` Docker network.

---

## Configuration Paths

| File | Purpose |
|---|---|
| `docker-compose/traefik/docker-compose.yaml` | Stack definition |
| `docker-compose/traefik/.env` | Dashboard credentials, domain, ACME email (gitignored) |
| `docker-compose/traefik/cf-token` | Cloudflare API token (Docker secret, gitignored) |
| `docker/traefik/traefik.yaml` | Static config: entrypoints, providers, ACME resolver |
| `docker/traefik/config.yaml` | Dynamic config: shared middlewares, file-provider routes |
| `docker/traefik/acme.json` | Let's Encrypt certificate store (`chmod 600`, gitignored) |
| `docker/traefik/logs/traefik.log` | Error log |
| `docker/traefik/logs/access.log` | Access log |

---

## Environment Variables

| Variable | Source | Purpose |
|---|---|---|
| `TRAEFIK_DASHBOARD_CREDENTIALS` | `.env` | BasicAuth hash for dashboard (`htpasswd -nbB admin <pass>`) |
| `DOMAIN_NAME` | `.env` | Root domain (e.g. `YOUR_DOMAIN`) |
| `ACME_EMAIL` | `traefik.yaml` (hardcoded) | Let's Encrypt notification email |
| `CF_DNS_API_TOKEN_FILE` | Docker secret | Path to Cloudflare token file |

---

## Operations

```bash
# Start
cd ~/homelab/docker-compose/traefik && docker compose up -d

# Stop
docker compose down

# Restart (required after editing config.yaml — atomic writes change the inode
# and Traefik's file-provider watch loses track of the file)
docker compose restart

# Logs
docker logs traefik --tail 50
docker logs traefik -f

# View access log
tail -f ~/homelab/docker/traefik/logs/access.log

# Verify certificate
docker exec traefik cat /acme.json | python3 -m json.tool | grep -A2 '"domain"'

# Test Cloudflare token
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer $(cat ~/homelab/docker-compose/traefik/cf-token)"

# Generate new dashboard password
htpasswd -nbB admin <newpassword>
```

---

## Adding a New Service

See `docs/traefik-routing.md` for the full label template. Summary:

1. Add service to `proxy` network (`external: true` in compose).
2. Set `traefik.enable=true` and `traefik.docker.network=proxy` labels.
3. Define HTTP router (redirect to HTTPS) and HTTPS router (TLS + middleware + service).
4. Use only **one** `middlewares` label per router — comma-separate multiple values.
5. Run `docker compose config` to validate before deploying.

---

## Known Issues

- All images use `:latest` — Traefik version is known (v3.6.2) but not pinned in compose.
- `insecureSkipVerify: true` in `serversTransport` — necessary for Portainer self-signed cert but applies globally.
- `sslheader` middleware is defined in labels but not applied to any router.

---

## Future Configuration Options

- Pin image to `traefik:v3.6.2` instead of `latest`
- Scope `insecureSkipVerify` to Portainer service only via `serversTransport` per-service config
- Add Authelia forward auth middleware to `config.yaml` once Authelia is deployed
- Consider CrowdSec bouncer middleware (entrypoint hooks are already commented in `traefik.yaml`)
