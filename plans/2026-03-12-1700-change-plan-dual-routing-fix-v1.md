# Change Plan: Fix Dual Routing on Portainer and Pi-hole

**Date**: 2026-03-12
**Phase**: Housekeeping
**Status**: In progress

## Problem

Portainer and Pi-hole each have two competing Traefik route definitions:
1. **File provider** (`docker/traefik/config.yaml`) — uses static IPs, has correct middlewares
2. **Compose labels** — Docker provider auto-discovery, has broken/conflicting middleware refs

### Portainer specifics
- Compose HTTPS router references `portainer-headers` middleware — its definition is entirely commented out → broken
- Compose service points to port 9000 (HTTP)
- File provider service points to `192.168.1.5:9443` (HTTPS, self-signed cert)
- File provider router has no `certResolver` specified (`tls: {}`)
- HTTP→HTTPS redirect only in compose labels — missing from file provider

### Pi-hole specifics
- Compose HTTPS router has `pihole-addprefix` → would prepend `/admin`, causing double `/admin/admin/`
- File provider router has `priority: 100` to beat compose router and skips addprefix
- File provider service points to `192.168.1.5:8080` (static IP)
- HTTP→HTTPS redirect only in compose labels — missing from file provider

## Fix

Consolidate all routing into the file provider. Strip Traefik routing labels from both compose files.

### config.yaml changes
1. Add HTTP→HTTPS redirect routers for portainer and pihole
2. Add `certResolver: cloudflare` to portainer TLS block
3. Fix portainer service: `http://portainer:9000` (container name, HTTP — avoids self-signed cert)
4. Fix pihole service: `http://pihole:8080` (container name instead of static IP)
5. Fix portainer router middleware: `portainer-security-headers` (was missing, only `https-redirectscheme` and `authelia` were present)

### Compose changes
- Portainer: remove all Traefik routing labels; keep `traefik.enable=false` and watchtower label
- Pi-hole: remove all Traefik routing labels; keep `traefik.enable=false` and watchtower label

## Rollback

If anything breaks: restore compose labels and restart containers.
The file provider change is instantly reversible by reverting config.yaml and restarting Traefik.

## Verification

1. Traefik restarts cleanly: `docker logs traefik --tail 20`
2. HTTP→HTTPS redirect works for both services
3. Portainer loads at `https://portainer.<domain>` with Authelia gate
4. Pi-hole loads at `https://pihole.<domain>` with Authelia gate (no double `/admin`)
5. `curl -s http://localhost:8080/api/http/routers | python3 -m json.tool | grep -E '"portainer|pihole"'` — only one router per service
