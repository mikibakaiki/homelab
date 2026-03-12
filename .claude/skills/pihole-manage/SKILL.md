# /pihole-manage

Manage Pi-hole: gravity updates, whitelist/blacklist, and DHCP.

## Gravity (Blocklist) Update

```bash
docker exec pihole pihole -g
```
- Downloads and compiles all configured blocklists into `gravity.db`
- Runs automatically on a schedule; run manually after adding new lists
- Takes 1-5 minutes depending on list size
- Check result: `docker exec pihole pihole status`

## Whitelist / Blacklist Management

```bash
# Whitelist a domain
docker exec pihole pihole -w example.com

# Blacklist a domain
docker exec pihole pihole -b example.com

# List current whitelist
docker exec pihole pihole -w -l

# Remove from whitelist
docker exec pihole pihole -w -d example.com
```

## DNS Records (Local CNAMEs)

Local DNS records are managed via Pi-hole's web admin UI (Settings → DNS → Local DNS Records) or via `FTLCONF_*` env vars. Docker containers cannot use Pi-hole CNAMEs — use `extra_hosts` in compose instead.

## DHCP

Pi-hole DHCP config is set via environment variables in `docker-compose/pihole/.env`:
- `FTLCONF_LOCAL_IPV4` — Pi-hole host IP
- DHCP range and router are set in Pi-hole admin UI after first boot

DHCP broadcasts are relayed by the `dhcp-helper` container (host network mode). If DHCP stops working:
1. `docker compose restart dhcp-helper`
2. Check `docker logs pihole --tail 20 | grep -i dhcp`

## Useful Diagnostics

```bash
# Check Pi-hole status
docker exec pihole pihole status

# Query log (recent queries)
docker exec pihole pihole -c

# Check gravity database size
docker exec pihole sqlite3 /etc/pihole/gravity.db "SELECT COUNT(*) FROM gravity;"
```
