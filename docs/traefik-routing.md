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
| `pihole` (http label) | http | `pihole.YOUR_DOMAIN` | — | pihole-https-redirect | No |
| `pihole-secure` (https label) | https | `pihole.YOUR_DOMAIN` | pihole (:8080) | pihole-addprefix, **authelia** | Yes |
| `pihole` (file) | https | `pihole.YOUR_DOMAIN` | pihole (static IP :8080) | default-security-headers, **authelia** | Yes |
| `portainer` (file) | https | `portainer.YOUR_DOMAIN` | portainer (static IP :9443) | portainer-security-headers, https-redirectscheme, **authelia** | Yes |
| `portainer` (label http) | http | `portainer.YOUR_DOMAIN` | — | portainer-https-redirect | No |
| `portainer-secure` (label https) | https | `portainer.YOUR_DOMAIN` | portainer (:9000) | portainer-headers, **authelia@file** | Yes |
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
| `pihole-https-redirect` | Redirect HTTPS | Pi-hole HTTP router |
| `pihole-addprefix` | AddPrefix `/admin` | Pi-hole HTTPS router |
| `portainer-https-redirect` | Redirect HTTPS | Portainer HTTP router |
| `portainer-headers` | Headers | Portainer HTTPS router (label defined but body empty) |

---

## Known Routing Issues

### 1. Sure — duplicate middlewares label

In `docker-compose/sure/compose.yml`, the `sure-secure` router has two middleware label lines:

```yaml
- "traefik.http.routers.sure-secure.middlewares=default-security-headers@file"
- "traefik.http.routers.sure-secure.middlewares=sure-security-headers@file"
```

Docker labels are a flat key-value map. The second line silently overwrites the first. Only `sure-security-headers@file` is applied. The first label has no effect.

### 2. Portainer — dual routing (labels + file provider)

Portainer has routes defined in both the Docker labels and `config.yaml`. The file provider route uses the static LAN IP (`<PIHOLE_HOST_IP>:9443`), while the label route uses container port `:9000`. This creates two competing routers for the same hostname. Should be consolidated.

### 3. Pi-hole — dual routing (labels + file provider)

Same issue as Portainer. Pi-hole is routed via labels (port 8080 via container discovery) and via `config.yaml` (static IP <PIHOLE_HOST_IP>:8080). Should be consolidated.

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
