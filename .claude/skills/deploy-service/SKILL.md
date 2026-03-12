# /deploy-service

Deploy a new service to the homelab using the 7-step Infrastructure Safety Mode gate.

## Steps

1. **Plan** — Create a change plan in `plans/YYYY-MM-DD-HHMM-change-plan-<service>-v1.md` before any files are written. Describe the service, ports, networks, and any Traefik/Authelia integration.

2. **Compose** — Create `docker-compose/<service>/docker-compose.yaml` and `.env.example`. Copy structure from an existing service. Do NOT commit `.env`.

3. **Network** — Verify `proxy` network exists (`docker network ls | grep proxy`). Add service to `proxy` network with `external: true`. If the service needs backend isolation, create a named network.

4. **Labels** — Add standard Traefik labels:
   - HTTP router → `traefik.http.middlewares.redirect-to-https`
   - HTTPS router → `tls.certresolver=cloudflare`
   - If service needs relaxed CSP, add a custom security-headers middleware to `docker/traefik/config.yaml` (requires Traefik restart after edit).

5. **Secrets** — Add required secrets to `.env` (not `.env.example`). Verify `.gitignore` covers the file. Check Authelia `configuration.yml` if OIDC is needed.

6. **Deploy** — `cd docker-compose/<service> && docker compose up -d`. Verify container is running: `docker compose ps`.

7. **Verify** — Check logs (`docker logs <service> --tail 50`), confirm HTTPS works, confirm Authelia gate if applicable. Update `docs/services/<service>.md` and commit the plan + compose files.

## Authelia Integration Checklist
- Add bypass rules for manifest/favicon in `configuration.yml` (see `project_authelia_bypass_patterns.md` memory)
- Add access control rule (policy: `one_factor` or `two_factor`)
- Restart Authelia after config change
