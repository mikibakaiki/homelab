# /troubleshoot

Diagnose homelab issues using known error patterns.

## Known Error Patterns

### Traefik / Routing
- **Service returns 404**: Check if router exists in `docker/traefik/config.yaml` (file provider) vs compose labels. Pi-hole and Portainer use file provider — compose labels are ignored for these.
- **Service CSS broken / unstyled**: Wrong security-headers middleware. CSP-sensitive services need `portainer-security-headers` (relaxed CSP), not `default-security-headers`.
- **Traefik change not taking effect**: `docker/traefik/config.yaml` edits require a Traefik restart — inode caching issue with bind mounts.
- **Duplicate router conflict**: Two routers with the same rule but no priority. File provider router needs `priority: 100` to win over compose labels.

### Authelia
- **OAuthSignin / ENOTFOUND**: Container can't resolve local domain. Add `extra_hosts` entry to compose for the auth service domain pointing to Pi-hole host IP.
- **CORS errors during OIDC flow**: Missing bypass rule for the service's manifest/favicon. Add `AuthRequestRedirectHeader` bypass in Authelia config.
- **CSS broken on Authelia login page**: Wrong middleware on Authelia's Traefik router. Use `portainer-security-headers`, not `default-security-headers`.
- **"forbidden" on OIDC callback**: Authelia access_control rule missing or too restrictive for the service subdomain.

### Pi-hole
- **DNS not resolving**: Check Pi-hole container is on both `proxy` and `backend` networks. Verify Cloudflared is running on port 5053.
- **DHCP not working**: Check `dhcp-helper` container is running in host network mode. Verify DHCP range and router IP in Pi-hole env vars.
- **Admin page 404**: Pi-hole Traefik router needs `addprefix` middleware to prepend `/admin`.

### Containers
- **Container won't start**: Check `docker logs <service> --tail 50`. Common causes: missing `.env`, wrong network, port conflict.
- **Can't reach internal service**: Verify service is on `proxy` network. Check `docker network inspect proxy`.

## Diagnosis Workflow

1. Identify the symptom (HTTP error code, DNS failure, auth redirect loop, etc.)
2. Check relevant container logs
3. Match against patterns above
4. If no match: run `/health-check` for full sweep
5. Check `docs/services/<service>.md` troubleshooting section
