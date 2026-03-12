# /cert-renew

Check Let's Encrypt certificate expiry and trigger renewal if needed.

## Steps

1. **Check cert expiry**:
   ```bash
   openssl s_client -connect <domain>:443 -servername <domain> </dev/null 2>&1 | openssl x509 -noout -dates
   ```
   Alert if `notAfter` is within 30 days.

2. **Check acme.json**: `docker/traefik/acme.json` — verify it's non-empty and `chmod 600`.
   ```bash
   cat docker/traefik/acme.json | python3 -m json.tool | grep -E '"domain"|"expiry"'
   ```

3. **Check Traefik ACME logs**: `docker logs traefik --tail 50 2>&1 | grep -i "acme\|cert\|renew\|letsencrypt"`

4. **Verify DNS challenge config**: In `docker/traefik/traefik.yaml`, confirm `certificatesResolvers.cloudflare` is configured with `dnsChallenge` and `provider: cloudflare`.

5. **Force renewal if needed**: Remove the certificate entry from `acme.json` and restart Traefik. Traefik will request a new cert on startup.
   - CAUTION: This causes a brief TLS outage during renewal
   - Let's Encrypt rate limit: 5 certs per domain per week

6. **Verify renewal**: After restart, check logs for successful ACME challenge, then re-check expiry.

## Notes

- Wildcard cert covers `*.<domain>` — all services share one cert
- DNS challenge uses Cloudflare API token in `docker-compose/traefik/cf-token`
- Traefik auto-renews 30 days before expiry — manual intervention only needed if auto-renew fails
