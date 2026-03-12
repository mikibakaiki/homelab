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

### Path bypass rules

Some paths must bypass forward-auth entirely. Rules are evaluated top-to-bottom — place specific bypass rules **before** the catch-all `one_factor` rule.

**Why bypasses are needed:**

Two classes of requests cannot carry Authelia session cookies:

1. **OIDC callback URLs** — the redirect from Authelia back into the app arrives without a session cookie because it's a fresh navigation from the Authelia domain. Must bypass so the app can complete the code exchange.
2. **Browser sub-resource fetches without credentials** — browsers fetch some resources (web app manifests, certain static assets) with `credentials: omit` per spec, meaning no cookies are sent. Authelia sees these as unauthenticated and redirects them to the login page. The login page response has its own CSP, causing MIME type errors in the browser.

**Current bypass rules:**

```yaml
# Pi-hole: /admin/img/* fetched without credentials by browser (manifest, favicons)
- domain: 'pihole.YOUR_DOMAIN'
  resources:
    - '^/admin/img/.*$'
    - '^/admin/favicon\.ico$'
    - '^/admin/manifest\.json$'
  policy: 'bypass'

# Karakeep: NextAuth OIDC callback + Next.js public assets
- domain: 'karakeep.YOUR_DOMAIN'
  resources:
    - '^/api/auth/.*$'       # NextAuth OIDC callback — arrives without session cookie
    - '^/manifest\.json$'    # PWA manifest — fetched with credentials:omit
    - '^/favicon\.ico$'
    - '^/_next/static/.*$'   # Next.js static assets
  policy: 'bypass'
```

**When adding a new service**, check whether:
- It has OIDC callbacks that need bypass
- Its HTML references a `<link rel="manifest">` (bypass `/manifest.json` or equivalent)
- Its framework loads static assets that don't send cookies (`/_next/`, `/static/`, `/assets/`, etc.)

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
When a page makes background fetches (PWA manifest, static assets) during an OIDC redirect, those requests get intercepted by Authelia forward-auth and receive a cross-origin 302 → CORS error. Fix: add `bypass` rules in `access_control` for the affected paths (see Path bypass rules above).

### Service page loads but is unstyled (CSS/JS returned as text/html)

**Symptom**: A protected service opens but has no CSS. Browser console shows:
```
Refused to apply style from 'https://service.YOUR_DOMAIN/...' because its MIME type ('text/html') is not supported
```
Or the network tab shows CSS/JS requests returning 302 to `auth.YOUR_DOMAIN`.

**This is not an Authelia misconfiguration** — it means Authelia is correctly blocking unauthenticated requests, but the requests that should be authenticated (sub-resource fetches for CSS/JS) are arriving without the session cookie.

**Two distinct causes:**

1. **Traefik router conflict with path-doubling** — if the service has both a Docker label router and a file provider router, and the label router includes a path-prefix middleware, sub-resource paths get the prefix applied twice. The resulting URL doesn't exist on the service → service returns HTML → wrong MIME type. Fix: set `priority: 100` on the file provider router. See `docs/services/pihole.md` → "Pi-hole admin page loads but CSS/JS is broken" for the detailed diagnosis.

2. **Static assets fetched without credentials** — browsers fetch manifests and some assets with `credentials: omit`. No cookie → Authelia redirects → HTML instead of asset. Fix: add a `bypass` rule for those specific paths in `access_control`.

To distinguish the two: check Authelia logs for the failing path. If it shows a doubled prefix (e.g. `/admin/admin/...`), it's cause 1. If the path is correct but the request is anonymous, it's cause 2.

---

## Future Configuration Options

- Enable TOTP (already configured in `configuration.yml` with `totp:` block — users enrol on first login)
- Add WebAuthn (passkey) support (Authelia v4.38+ supports it via `webauthn:` config block)
- Migrate user store to LLDAP for multi-user management
- Configure SMTP notifier for proper email-based password resets
- Add `two_factor` policy for highest-sensitivity services
