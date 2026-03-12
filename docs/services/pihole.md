# Pi-hole

> Installed: initial setup
> Discovered: 2026-03-11 (Phase 0)
> Version: `pihole/pihole:latest` (Pi-hole v6)

---

## Overview

Pi-hole v6 provides network-wide DNS filtering, ad blocking, and DHCP for the LAN. DNS queries from all DHCP clients are routed through Pi-hole → Cloudflared (DNS-over-HTTPS) → Cloudflare 1.1.1.1 / Quad9 9.9.9.9.

- **Domain**: `pihole.YOUR_DOMAIN` (web admin, via Traefik)
- **LAN IP**: `<PIHOLE_HOST_IP>`
- **Docker IP**: `172.31.0.100` (on `pihole_backend` network)
- **Blocked domains**: 894,108+ (12 adlists)

---

## Architecture Role

```
LAN clients
  └─► Pi-hole :53 (DNS)
        └─► Cloudflared :5053 (DoH)
              └─► Cloudflare 1.1.1.1 / Quad9 9.9.9.9

LAN clients
  └─► DHCP broadcast → dhcp-helper (host network)
        └─► Pi-hole DHCP :67 (172.31.0.100)

Traefik (file provider) → Pi-hole pihole:8080 (web admin)
  Pi-hole's own web server redirects / → /admin internally
```

Pi-hole is on two Docker networks: `pihole_backend` (DNS/DHCP internal) and `proxy` (Traefik routing).

---

## Stack Components

| Container | Image | Role | Network |
|---|---|---|---|
| `pihole` | `pihole/pihole:latest` | DNS + DHCP + web UI | `pihole_backend` + `proxy` |
| `cloudflared` | `cloudflare/cloudflared:latest` | DoH upstream | `pihole_backend` |
| `dhcp-helper` | `homeall/dhcphelper:latest` | DHCP relay (bridge → Pi-hole) | host |

---

## Configuration Paths

| File | Purpose |
|---|---|
| `docker-compose/pihole/docker-compose.yaml` | Stack definition |
| `docker-compose/pihole/.env` | Passwords, timezone, domain (gitignored) |
| `docker/pihole/pihole/` | Pi-hole runtime data: gravity.db, leases, config |
| `docker/pihole/etc-dnsmasq.d/99-dhcp-dns.conf` | Custom dnsmasq config |
| `docker/pihole/pihole/hosts/custom.list` | Custom static DNS entries |

Pi-hole v6 uses `FTLCONF_*` environment variables — there is no editable `pihole.toml` in the repo; config lives in the container and is backed up to `docker/pihole/pihole/config_backups/`.

---

## Environment Variables

| Variable | Purpose |
|---|---|
| `TZ` | Timezone |
| `PIHOLE_PASSWORD` | Admin web interface password |
| `DOMAIN_NAME` | Root domain for CNAME records |
| `FTLCONF_dns_upstreams` | `cloudflared#5053` |
| `FTLCONF_dhcp_active` | `true` |
| `FTLCONF_dhcp_start/end` | `<DHCP_RANGE_START>` / `<DHCP_RANGE_END>` |
| `FTLCONF_dhcp_router` | `<ROUTER_IP>` |
| `FTLCONF_dns_cnameRecords` | Routes all service subdomains → `apps.YOUR_DOMAIN` → `<PIHOLE_HOST_IP>` |

---

## DNS CNAME Configuration

Pi-hole resolves service domains locally without going to Cloudflare:

```
sure.YOUR_DOMAIN      → apps.YOUR_DOMAIN → <PIHOLE_HOST_IP>
traefik.YOUR_DOMAIN   → apps.YOUR_DOMAIN → <PIHOLE_HOST_IP>
pihole.YOUR_DOMAIN    → apps.YOUR_DOMAIN → <PIHOLE_HOST_IP>
portainer.YOUR_DOMAIN → apps.YOUR_DOMAIN → <PIHOLE_HOST_IP>
```

When adding a new service subdomain, add it to `FTLCONF_dns_cnameRecords` in the compose file and recreate the container.

---

## Operations

```bash
# Start
cd ~/homelab/docker-compose/pihole && docker compose up -d

# Stop (DNS will go down for LAN)
docker compose down

# Update blocklists (gravity)
docker exec pihole pihole -g

# Check status
docker exec pihole pihole status

# Test DNS resolution
nslookup google.com <PIHOLE_HOST_IP>
docker exec pihole nslookup google.com 127.0.0.1

# View DHCP leases
docker exec pihole cat /etc/pihole/dhcp.leases

# Logs
docker logs pihole --tail 50
docker logs cloudflared --tail 20
docker logs dhcp-helper --tail 20

# Backup Pi-hole data
tar -czf pihole-backup-$(date +%Y%m%d).tar.gz ~/homelab/docker/pihole/
```

---

## Adding a New Service DNS Entry

1. Add to `FTLCONF_dns_cnameRecords` in `docker-compose/pihole/docker-compose.yaml`:
   ```
   newservice.YOUR_DOMAIN,apps.YOUR_DOMAIN
   ```
2. Recreate the pihole container:
   ```bash
   docker compose up -d --force-recreate pihole
   ```
3. Verify: `nslookup newservice.YOUR_DOMAIN <PIHOLE_HOST_IP>`

---

## Troubleshooting

### DHCP: Device gets 169.254.x.x (APIPA) instead of <LAN_IP>

A `169.254.x.x` address means the device sent DHCP broadcasts but received no response. The DHCP relay path is:

```
device (WiFi/LAN)
  → DHCP broadcast (UDP port 67) → eth0 (<PIHOLE_HOST_IP>)
    → dhcp-helper (host network) sets giaddr=<PIHOLE_HOST_IP>
      → unicast to Pi-hole at 172.31.0.100:67
        → Pi-hole responds with lease from <DHCP_RANGE_START>–<DHCP_RANGE_END>
          → dhcp-helper broadcasts response back to device
```

**Step 1 — Verify Pi-hole is receiving requests:**
```bash
docker exec pihole cat /var/log/pihole/pihole.log | grep -i dhcp | tail -20
```
If you see no new entries after a device tries to connect, the relay isn't forwarding. Go to Step 2.

If you see `no address range available for DHCP request via eth0/eth1` — Pi-hole is receiving but can't match the request to a range. This usually means dhcp-helper is using a wrong IP (Step 2).

**Step 2 — Verify dhcp-helper is forwarding to the correct Pi-hole IP:**
```bash
docker exec dhcp-helper cat /proc/1/cmdline | tr '\0' ' '
# Expected: dhcp-helper -n -s 172.31.0.100
```

If it shows a different IP (e.g. `172.20.0.100`), the container is stale — recreate it:
```bash
cd ~/homelab/docker-compose/pihole && docker compose up -d dhcp-helper --force-recreate
```
This happened in practice when Pi-hole's backend network subnet changed but dhcp-helper wasn't recreated. The `.env` file doesn't set `IP=` (it's hardcoded in the compose), so an old container retains the old value indefinitely.

**Step 3 — Verify DHCP traffic is reaching the Pi:**
```bash
# Run in one terminal, toggle device WiFi in the other
docker run --rm --net=host --cap-add=NET_ADMIN nicolaka/netshoot \
  tcpdump -i eth0 -n 'port 67 or port 68'
```
You should see DHCP DISCOVER packets from the device. If you don't, the broadcasts aren't reaching the Pi's eth0 (check router/AP VLAN config).

**Step 4 — Enable DHCP debug logging:**
```bash
docker exec pihole pihole-FTL --config dhcp.logging true
# Restart FTL to apply:
docker restart pihole
```
Detailed per-packet DHCP logs will appear in `/var/log/pihole/pihole.log`.

**Check current leases:**
```bash
docker exec pihole cat /etc/pihole/dhcp.leases
```

---

### DHCP: `no address range available for DHCP request via eth0`

Root cause: dhcp-helper is forwarding to the wrong IP. See Step 2 above.

Why it happens: Pi-hole's container eth0 is on the `pihole_backend` network (172.31.0.0/24). dnsmasq receives the DHCP request on this interface and, if the `giaddr` is not correctly set to <PIHOLE_HOST_IP>, it tries to find a range matching the 172.31.0.x subnet — which doesn't exist. This is always a relay misconfiguration.

---

### DNS: Devices not using Pi-hole as DNS

If a device has a valid <LAN_IP> lease but DNS isn't going through Pi-hole, check:

1. **Pi-hole pushes its own IP as DNS option 6** via `FTLCONF_misc_dnsmasq_lines: 'dhcp-option=6,<PIHOLE_HOST_IP>'`. Verify it's in the active dnsmasq config:
   ```bash
   docker exec pihole grep "dhcp-option=6" /etc/pihole/dnsmasq.conf
   ```
2. **Device uses a static DNS** — override it manually or check device settings.
3. **Router overrides DNS** — some routers inject their own DNS in DHCP responses; disable that in router settings.

Test DNS from a device:
```bash
nslookup google.com <PIHOLE_HOST_IP>        # from the Pi
# Or from any LAN device:
nslookup google.com                    # should show <PIHOLE_HOST_IP> as server
```

---

### DNS: Local domains (*.YOUR_DOMAIN) not resolving on LAN

Pi-hole resolves local service CNAMEs (e.g. `pihole.YOUR_DOMAIN → apps.YOUR_DOMAIN → <PIHOLE_HOST_IP>`). If they stop resolving:

```bash
# Verify the CNAME chain
nslookup pihole.YOUR_DOMAIN <PIHOLE_HOST_IP>
nslookup apps.YOUR_DOMAIN <PIHOLE_HOST_IP>

# Check the running CNAME config
docker exec pihole grep "^cname" /etc/pihole/dnsmasq.conf
```

If missing, the `FTLCONF_dns_cnameRecords` or `FTLCONF_dns_hosts` env vars are not applied — recreate the container:
```bash
cd ~/homelab/docker-compose/pihole && docker compose up -d --force-recreate pihole
```

---

### Pi-hole admin page loads but CSS/JS is broken (unstyled, console shows MIME type errors)

**Symptom**: Pi-hole admin opens but has no styling. Browser console shows errors like:

```
Refused to apply style from 'https://pihole.YOUR_DOMAIN/admin/vendor/bootstrap/css/bootstrap.min.css'
because its MIME type ('text/html') is not a supported stylesheet MIME type
```

Or manifest errors redirecting through `auth.YOUR_DOMAIN`:

```
Loading a manifest from 'https://auth.YOUR_DOMAIN/?rd=https%3A%2F%2Fpihole.YOUR_DOMAIN%2Fadmin%2Fadmin%2Fimg%2F...'
violates Content Security Policy
```

**Root cause (historical)**: When both a Docker label router and file provider router matched `pihole.YOUR_DOMAIN`, the label router's `pihole-addprefix` middleware doubled the `/admin` prefix on sub-resource URLs, causing MIME type errors and Authelia CSP redirect loops.

**Fix applied 2026-03-12**: Dual routing eliminated. All Pi-hole routing now lives in the file provider (`docker/traefik/config.yaml`). Compose file has `traefik.enable=false`. The `pihole-addprefix` middleware and `priority: 100` workaround no longer exist. Pi-hole's own web server handles the `/` → `/admin` redirect internally.

---

### DNS: Docker containers can't resolve *.YOUR_DOMAIN

Docker's internal resolver (127.0.0.11) does not use Pi-hole. Containers that need to reach local CNAMEs must use `extra_hosts`:
```yaml
extra_hosts:
  - "auth.YOUR_DOMAIN:<PIHOLE_HOST_IP>"
  - "karakeep.YOUR_DOMAIN:<PIHOLE_HOST_IP>"
```

---

## Known Issues

- ~~**Dual router conflict**~~: Fixed 2026-03-12. All routing in file provider; compose has `traefik.enable=false`.
- Image not pinned to a version tag.

---

## Future Configuration Options

- Pin image to a specific Pi-hole v6 release tag
- Add regex filter groups for tracking domains
- Evaluate moving from `FTLCONF_misc_dnsmasq_lines` DHCP option to native config
