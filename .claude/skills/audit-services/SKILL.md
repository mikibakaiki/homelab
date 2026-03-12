# /audit-services

Audit ALL running services before making multi-service changes.

## When to Use

Before any change that touches shared infrastructure: Traefik config, Authelia config, Docker networks, or any middleware that multiple services depend on.

## Audit Steps

1. **Inventory running containers**: `docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"`

2. **Check Traefik routing**: Review `docker/traefik/config.yaml` for all routers and middlewares. Note which services use file provider vs compose labels.

3. **Check Authelia access rules**: Review `docker/authelia/config/configuration.yml` access_control section. List all rules and their policies.

4. **Identify shared dependencies**: Which services share a middleware? Which use the same network? Which depend on Authelia OIDC?

5. **Impact assessment**: For each service, note whether the proposed change could break it. Flag high-risk services (Portainer, Pi-hole, Authelia itself).

6. **Document findings**: List all services, their current state, and any risks from the proposed change before proceeding.

## Output Format

```
Service     | Status  | Traefik Router | Authelia Rule | Risk
------------|---------|----------------|---------------|------
traefik     | running | file provider  | bypass        | low
pihole      | running | file provider  | one_factor    | medium
portainer   | running | file provider  | one_factor    | low
authelia    | running | compose labels | bypass        | HIGH
...
```
