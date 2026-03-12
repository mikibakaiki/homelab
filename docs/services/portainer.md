# Portainer

> Installed: initial setup
> Discovered: 2026-03-11 (Phase 0)
> Version: `portainer/portainer-ce:latest` (Community Edition)

---

## Overview

Portainer CE provides a web UI for managing the Docker environment — containers, images, networks, volumes, and compose stacks. It has read-only access to the Docker socket.

- **Domain**: `portainer.YOUR_DOMAIN`
- **Direct access**: `https://<PIHOLE_HOST_IP>:9443` (self-signed cert), `http://<PIHOLE_HOST_IP>:9000`

---

## Architecture Role

```
Traefik (file provider) → portainer.YOUR_DOMAIN → portainer:9000 (container name, proxy network)

Portainer → /var/run/docker.sock (read-only) → Docker Engine
```

Portainer is on the `proxy` network only. It has no internal network dependencies.

---

## Configuration Paths

| File | Purpose |
|---|---|
| `docker-compose/portainer/docker-compose.yaml` | Stack definition |
| `docker/portainer/data/` | Portainer state: users, endpoints, stacks, settings |

No `.env` file is required — only `TZ` is set via environment, which can be inline.

---

## Operations

```bash
# Start
cd ~/homelab/docker-compose/portainer && docker compose up -d

# Stop
docker compose down

# Logs
docker logs portainer --tail 50

# Reset admin password (if locked out)
docker exec -it portainer /usr/local/bin/portainer --admin-password-file /tmp/pass
```

---

## Routing Notes

All routing is handled by the Traefik file provider in `docker/traefik/config.yaml`. The compose file has `traefik.enable=false`.

- **HTTP router** (`portainer-http`): redirects to HTTPS via `https-redirectscheme`
- **HTTPS router** (`portainer`): routes to `http://portainer:9000` (container name on `proxy` network) with `portainer-security-headers` + `authelia`

No Docker label routing. No static IPs.

---

## Known Issues

- Image not pinned to a version tag.
- Host ports `9000:9000` and `9443:9443` are exposed — these allow direct LAN access bypassing Traefik and Authelia. Acceptable as an admin fallback but represents a wider attack surface.

---

## Future Configuration Options

- Pin image to a specific Portainer CE release tag
- Consolidate routing to labels-only (remove `config.yaml` portainer router and service)
- Add Authelia SSO once deployed — Portainer supports OIDC/LDAP for SSO
- Remove or restrict host port bindings (`:9000`, `:9443`) if direct fallback access is not needed
