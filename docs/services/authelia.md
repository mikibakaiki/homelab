# Authelia

> Status: DEPLOYED — 2026-03-11
> Change plan: `plans/2026-03-11-1430-change-plan-authelia-v1.md`
> Domain: `auth.YOUR_DOMAIN`
> Version: v4.38.19 (image: `ghcr.io/authelia/authelia:4.38`)

---

## Overview

Authelia is a forward-auth SSO gateway sitting between Traefik and protected services. All requests to protected services are checked against Authelia before being proxied. Unauthenticated users are redirected to `auth.YOUR_DOMAIN`.

- **Repository**: https://github.com/authelia/authelia
- **Docs**: https://www.authelia.com/
- **Traefik integration**: https://www.authelia.com/integration/proxies/traefik/

---

## Architecture Role

```
Client → Traefik → [authelia@file forwardAuth] → Authelia :9091
                          ↓ authenticated
                       Service (karakeep, portainer, pihole, traefik)
```

Two containers:

| Container | Image | Role | Network |
|---|---|---|---|
| `authelia` | `ghcr.io/authelia/authelia:4.38` | SSO portal + forward-auth endpoint | `proxy` + `authelia_internal` |
| `redis-authelia` | `redis:7-alpine` | Session storage | `authelia_internal` only |

---

## Protected Services

| Service | Policy | Notes |
|---|---|---|
| `karakeep.YOUR_DOMAIN` | `one_factor` | OIDC SSO — no second login prompt |
| `portainer.YOUR_DOMAIN` | `one_factor` | |
| `pihole.YOUR_DOMAIN` | `one_factor` | |
| `traefik.YOUR_DOMAIN` | BasicAuth only | Kept independent — diagnostic tool, no Authelia |
| `auth.YOUR_DOMAIN` | `bypass` (portal itself) | |

### Karakeep path bypasses

The following Karakeep paths bypass forward-auth (required for OIDC callback and public assets):

```yaml
- domain: 'karakeep.YOUR_DOMAIN'
  resources:
    - '^/api/auth/.*$'       # NextAuth OIDC callback
    - '^/manifest\.json$'    # PWA manifest
    - '^/favicon\.ico$'
    - '^/_next/static/.*$'   # Next.js static assets
  policy: 'bypass'
```

---

## Configuration Paths

| File | Purpose |
|---|---|
| `docker-compose/authelia/docker-compose.yaml` | Stack definition |
| `docker-compose/authelia/.env.example` | Secret template (committed) |
| `docker-compose/authelia/.env` | Live secrets (gitignored) |
| `docker/authelia/config/configuration.yml` | Main Authelia config |
| `docker/authelia/config/users_database.yml` | User store (gitignored — contains email) |
| `docker/authelia/data/db.sqlite3` | Session + audit database |
| `docker/authelia/data/notification.txt` | Password reset links (filesystem notifier) |
| `docker/authelia/redis/` | Redis session persistence |

---

## Required Secrets

| Variable | Purpose | Generate with |
|---|---|---|
| `AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET` | JWT signing | `openssl rand -base64 64 \| tr -d '\n'` |
| `AUTHELIA_SESSION_SECRET` | Session encryption | `openssl rand -base64 64 \| tr -d '\n'` |
| `AUTHELIA_STORAGE_ENCRYPTION_KEY` | SQLite encryption | `openssl rand -base64 64 \| tr -d '\n'` |
| `REDIS_PASSWORD` + `AUTHELIA_SESSION_REDIS_PASSWORD` | Redis auth (same value) | `openssl rand -base64 32 \| tr -d '\n'` |

---

## User Management

Users are stored in `docker/authelia/config/users_database.yml` (file-based backend).

### Adding a user

1. Generate a password hash:
```bash
docker run --rm ghcr.io/authelia/authelia:4.38 \
  authelia crypto hash generate argon2 --password 'yourpassword'
```

2. Add to `users_database.yml`:
```yaml
users:
  username:
    displayname: 'Display Name'
    password: '$argon2id$v=19$...'
    email: 'user@example.com'
    groups:
      - admins
```

3. Authelia reloads the user database automatically — no restart needed.

### Changing a password

Generate a new hash (step 1 above) and replace the `password` field. Authelia watches the file for changes.

### Password reset (no SMTP)

The filesystem notifier writes reset links to `/data/notification.txt` inside the container:
```bash
docker exec authelia cat /data/notification.txt
```
Copy the link and open it in a browser.

---

## Operations

```bash
# Start
cd ~/homelab/docker-compose/authelia && docker compose up -d

# Stop
docker compose down

# Logs
docker logs authelia --tail 50
docker logs redis-authelia --tail 20

# Reload config (most changes are hot-reloaded; restart for structural changes)
docker compose restart authelia

# Check session store
docker exec redis-authelia redis-cli -a "$REDIS_PASSWORD" info keyspace
```

---

## Adding Authelia Protection to a New Service

1. Add to `access_control.rules` in `docker/authelia/config/configuration.yml` (or it falls under `default_policy: deny`)
2. Add `authelia@file` to the service's Traefik HTTPS router middlewares label:
   ```yaml
   - "traefik.http.routers.<service>-secure.middlewares=<existing-headers>@file,authelia@file"
   ```
3. Recreate the service container: `docker compose up -d --force-recreate <service>`
4. No Traefik restart needed — labels are picked up dynamically.

---

## OIDC Provider

Authelia is configured as an OpenID Connect identity provider. Currently Karakeep is the only OIDC client.

**Discovery endpoint**: `https://auth.YOUR_DOMAIN/.well-known/openid-configuration`

### Registering a new OIDC client

Add to the `identity_providers.oidc.clients` list in `configuration.yml`:

```yaml
- client_id: 'myapp'
  client_name: 'My App'
  client_secret: '<argon2id hash>'   # hash with: authelia crypto hash generate argon2 --password 'secret'
  public: false
  authorization_policy: 'one_factor'
  redirect_uris:
    - 'https://myapp.YOUR_DOMAIN/api/auth/callback/authelia'
  scopes: [openid, email, profile]
  userinfo_signed_response_alg: 'none'
```

Then restart Authelia: `docker compose restart authelia`

### Rotating OIDC client secret

1. Generate new secret: `openssl rand -base64 32 | tr -d '\n'`
2. Hash it: `docker run --rm ghcr.io/authelia/authelia:4.38 authelia crypto hash generate argon2 --password 'newsecret'`
3. Update `client_secret` hash in `configuration.yml`
4. Update `OAUTH_CLIENT_SECRET` in the client app's `.env`
5. Restart Authelia + client app

---

## Troubleshooting

### Authelia portal CSS broken / unstyled
Authelia generates its own nonce-based CSP for its UI. Do **not** apply `default-security-headers` (which has `contentSecurityPolicy: "default-src 'self'"`) to the Authelia router — it overrides Authelia's own CSP and breaks the UI. Use `portainer-security-headers@file` instead (no CSP directive).

### CSP violation errors in browser console on consent/login page
Lines like `Applying inline style violates Content Security Policy ... inject.js` are caused by **browser extensions** (password managers, dark mode tools, etc.) trying to inject styles into Authelia's UI. Authelia's built-in nonce-based CSP intentionally blocks this. This is harmless — the page works correctly. Not a configuration issue.

### User login fails with "Authentication failed" after username rename
If a user was renamed in `users_database.yml` (e.g. `admin` → `miki`) and the old username still works while the new one fails with `user not found` in the logs, the running Authelia container may be reading a stale inode of the file (file hot-reload picked up the change but loaded a cached parse). Fix: restart Authelia.
```bash
cd ~/homelab/docker-compose/authelia && docker compose restart authelia
```
After restart, verify the file is loaded correctly:
```bash
docker logs authelia --tail 5   # should show "Startup complete"
docker exec authelia cat /config/users_database.yml  # confirm correct content
```

### OIDC `OAuthSignin` error in client app
Usually means the client container cannot resolve the Authelia domain via DNS. Docker containers use Docker's internal DNS (not Pi-hole), so local CNAMEs like `auth.YOUR_DOMAIN` are unknown. Fix: add `extra_hosts` to the client container's compose service:
```yaml
extra_hosts:
  - "auth.YOUR_DOMAIN:<PIHOLE_HOST_IP>"
```

### CORS errors on background requests during OIDC flow
When a page makes background fetches (PWA manifest, static assets) during an OIDC redirect, those requests get intercepted by Authelia forward-auth and receive a cross-origin 302 → CORS error. Fix: add `bypass` rules in `access_control` for the affected paths (see Karakeep path bypasses above).

---

## Future Configuration Options

- Enable TOTP (already configured in `configuration.yml` with `totp:` block — users enrol on first login)
- Add WebAuthn (passkey) support (Authelia v4.38+ supports it via `webauthn:` config block)
- Migrate user store to LLDAP for multi-user management
- Configure SMTP notifier for proper email-based password resets
- Add `two_factor` policy for highest-sensitivity services
