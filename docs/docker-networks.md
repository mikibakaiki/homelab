# Docker Networks

> Created: 2026-03-11 (Phase 0 — Infrastructure Discovery)

---

## Network Overview

| Network | Driver | Created By | Subnet | Purpose |
|---|---|---|---|---|
| `proxy` | bridge | Manual (`docker network create proxy`) | Docker default | Traefik-facing network for all web services |
| `pihole_backend` | bridge | pihole compose | `172.31.0.0/24` | Internal DNS traffic between Pi-hole and Cloudflared |
| `sure_sure_net` | bridge | sure compose | Docker default | Internal app tier isolation for Sure stack |

---

## proxy

```bash
docker network create proxy
```

This network must exist before any service stack is started. It is declared `external: true` in all compose files.

**Connected containers**: `traefik`, `pihole`, `portainer`, `sure-web-1`

**Rule**: Any container that needs HTTPS access via Traefik must join this network.
When adding a new service, always include:

```yaml
networks:
  proxy:
    external: true
```

and attach the service to it.

---

## pihole_backend

Auto-created by `docker-compose/pihole/docker-compose.yaml`.

```yaml
networks:
  backend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.31.0.0/24
```

**Connected containers**:
- `pihole` — static IP `172.31.0.100`
- `cloudflared` — dynamic IP

Pi-hole uses the Cloudflared container name as DNS upstream: `cloudflared#5053`.

---

## sure_sure_net

Auto-created by `docker-compose/sure/compose.yml`.

**Connected containers**: `sure-web-1`, `sure-worker-1`, `sure-db-1`, `sure-redis-1`

Only `sure-web-1` also joins the `proxy` network. The database and Redis are isolated.

---

## Adding a New Service Network Checklist

- [ ] Service joins `proxy` network (declared `external: true`)
- [ ] If the service has internal dependencies (db, cache), create a dedicated internal network in the same compose file
- [ ] Internal network is NOT declared external — it is auto-created by compose
- [ ] Verify after deployment: `docker network inspect proxy`
