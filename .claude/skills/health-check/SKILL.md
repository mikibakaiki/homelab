# /health-check

Full homelab health sweep: containers, DNS, TLS, and routing.

## Steps

1. **Container status**: `docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}"` — flag any non-running or recently restarted containers.

2. **Traefik routing**: `curl -s "http://localhost:8080/api/overview" 2>/dev/null | python3 -m json.tool | head -30` — check router/service counts. Verify no errors.

3. **DNS resolution**: For each service, run `nslookup <service>.<domain> <pihole-ip>` — verify CNAME resolves correctly.

4. **TLS check**: `openssl s_client -connect <service>.<domain>:443 -servername <service>.<domain> </dev/null 2>&1 | grep -E "subject|issuer|notAfter"` — verify cert is valid and not expiring within 30 days.

5. **Pi-hole status**: `docker exec pihole pihole status` — confirm DNS and DHCP are active.

6. **Authelia check**: Confirm Authelia is responding; test a protected endpoint returns 302 to auth page.

7. **Recent errors**: `docker logs traefik --tail 20 2>&1 | grep -i error`, same for pihole, authelia, karakeep.

## Output Format

```
Component    | Status | Notes
-------------|--------|-------
traefik      | OK     | 12 routers active
pihole       | OK     | DNS+DHCP running
authelia     | OK     | responding
karakeep     | OK     | TLS valid until YYYY-MM-DD
...
```
