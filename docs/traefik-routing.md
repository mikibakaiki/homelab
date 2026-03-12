# Traefik Routing

> Created: 2026-03-11 (Phase 0 — Infrastructure Discovery)

---

## Traefik Version

v3.6.2 (image: `traefik:latest`)

---

## Entrypoints

| Name | Port | Behaviour |
|---|---|---|
| `http` | 80 | Redirects all traffic to `https` |
| `https` | 443 | TLS termination, routes to services |

---

## Providers

| Provider | Source | Notes |
|---|---|---|
| Docker | `/var/run/docker.sock` (read-only) | Autodiscovery via labels; `exposedByDefault: false` |
| File | `/config.yaml` | Shared middlewares and static service definitions |

---

## Certificate Resolver

Resolver name: `cloudflare`

- Type: ACME DNS challenge
- Provider: Cloudflare
- Token: injected via Docker secret at `/run/secrets/cf-token`
- Storage: `~/homelab/docker/traefik/acme.json` (chmod 600)
- Resolvers: `1.1.1.1:53`, `1.0.0.1:53`
- Wildcard: `*.YOUR_DOMAIN` (configured on Traefik labels of the traefik container)

---

## Active Routes

| Router | Entrypoint | Rule | Service | Middlewares | TLS |
|---|---|---|---|---|---|
| `traefik` (http) | http | `traefik.YOUR_DOMAIN` | — | traefik-https-redirect | No |
| `traefik-secure` (https) | https | `traefik.YOUR_DOMAIN` | `api@internal` | traefik-auth (BasicAuth) | Yes |
| `pihole-http` (file) | http | `pihole.YOUR_DOMAIN` | pihole | https-redirectscheme | No |
| `pihole` (file) | https | `pihole.YOUR_DOMAIN` | pihole (container :8080) | default-security-headers, **authelia** | Yes |
| `portainer-http` (file) | http | `portainer.YOUR_DOMAIN` | portainer | https-redirectscheme | No |
| `portainer` (file) | https | `portainer.YOUR_DOMAIN` | portainer (container :9000) | portainer-security-headers, **authelia** | Yes |
| `sure` (http) | http | `sure.YOUR_DOMAIN` | — | https-redirectscheme@file | No |
| `sure-secure` (https) | https | `sure.YOUR_DOMAIN` | sure (:3000) | sure-security-headers@file | Yes |
| `authelia` (http) | http | `auth.YOUR_DOMAIN` | — | https-redirectscheme@file | No |
| `authelia-secure` (https) | https | `auth.YOUR_DOMAIN` | authelia (:9091) | portainer-security-headers@file | Yes |
| `karakeep` (http) | http | `karakeep.YOUR_DOMAIN` | — | https-redirectscheme@file | No |
| `karakeep-secure` (https) | https | `karakeep.YOUR_DOMAIN` | karakeep (:3000) | karakeep-security-headers@file, **authelia@file** | Yes |

---

## Middleware Registry

### Defined in `config.yaml` (file provider)

| Name | Type | CSP | Applied To |
|---|---|---|---|
| `default-security-headers` | Headers | `default-src 'self'` (strict) | pihole (file router) |
| `portainer-security-headers` | Headers | None (relaxed) | portainer (file router), authelia |
| `sure-security-headers` | Headers | None (relaxed) | sure |
| `karakeep-security-headers` | Headers | None (relaxed) | karakeep |
| `https-redirectscheme` | Redirect HTTPS | — | HTTP routers |
| `authelia` | ForwardAuth | — | karakeep, portainer, pihole |

### Defined via Docker labels

| Name | Type | Applied To |
|---|---|---|
| `traefik-auth` | BasicAuth | Traefik dashboard |
| `traefik-https-redirect` | Redirect HTTPS | Traefik HTTP router |
| `sslheader` | RequestHeader | Defined but not applied to any router |

---

## Known Routing Issues

### 1. Sure — duplicate middlewares label

In `docker-compose/sure/compose.yml`, the `sure-secure` router has two middleware label lines:

```yaml
- "traefik.http.routers.sure-secure.middlewares=default-security-headers@file"
- "traefik.http.routers.sure-secure.middlewares=sure-security-headers@file"
```

Docker labels are a flat key-value map. The second line silently overwrites the first. Only `sure-security-headers@file` is applied. The first label has no effect.

### ~~2. Portainer — dual routing (labels + file provider)~~

Fixed 2026-03-12: All routing moved to file provider. `traefik.enable=false` on portainer compose. Service now routes to `http://portainer:9000` (container name, HTTP). The broken `portainer-headers` label middleware is removed.

### ~~3. Pi-hole — dual routing (labels + file provider)~~

Fixed 2026-03-12: All routing moved to file provider. `traefik.enable=false` on pihole compose. Service now routes to `http://pihole:8080` (container name). The `pihole-addprefix` middleware and `priority: 100` workaround are gone.

---

## Adding a New Service — Traefik Label Template

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=proxy"

  # HTTP → HTTPS redirect
  - "traefik.http.routers.<service>.entrypoints=http"
  - "traefik.http.routers.<service>.rule=Host(`<service>.YOUR_DOMAIN`)"
  - "traefik.http.routers.<service>.middlewares=https-redirectscheme@file"

  # HTTPS router
  - "traefik.http.routers.<service>-secure.entrypoints=https"
  - "traefik.http.routers.<service>-secure.rule=Host(`<service>.YOUR_DOMAIN`)"
  - "traefik.http.routers.<service>-secure.tls=true"
  - "traefik.http.routers.<service>-secure.tls.certresolver=cloudflare"
  - "traefik.http.routers.<service>-secure.service=<service>"
  - "traefik.http.routers.<service>-secure.middlewares=default-security-headers@file"

  # Service backend
  - "traefik.http.services.<service>.loadbalancer.server.port=<PORT>"
```

**Important**: Only one `middlewares` label key is allowed per router. To chain multiple middlewares, use a comma-separated list in a single label:

```yaml
- "traefik.http.routers.<service>-secure.middlewares=https-redirectscheme@file,default-security-headers@file"
```
