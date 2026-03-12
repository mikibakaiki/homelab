# Karakeep

> Status: DEPLOYED
> Deployed: 2026-03-11
> Version: 0.31.0 (image: `ghcr.io/karakeep-app/karakeep:release`)
> Change plan: `plans/2026-03-11-1200-change-plan-karakeep-v1.md`
> Domain: `karakeep.YOUR_DOMAIN`

---

## Overview

Karakeep is a self-hosted "bookmark-everything" application. It stores links, notes, images, and PDFs with automatic metadata extraction, full-text search, and optional AI-powered tagging. The name comes from the Arabic "كراكيب" (karakeeb) — miscellaneous personally valuable items.

- **Image**: `ghcr.io/karakeep-app/karakeep:release` (multi-arch, includes `linux/arm64`)
- **Repository**: https://github.com/karakeep-app/karakeep
- **Installation docs**: https://docs.karakeep.app/installation/docker
- **Environment variable reference**: https://docs.karakeep.app/configuration/environment-variables

---

## Architecture Role

```
Traefik → karakeep.YOUR_DOMAIN → Karakeep [:3000]
                                       ↓               ↓
                                  Meilisearch     Chrome (headless)
                                    [:7700]           [:9222]
```

Three containers in one stack:

| Container | Image | Role | Network |
|---|---|---|---|
| `karakeep` | `ghcr.io/karakeep-app/karakeep:release` | Application, workers, SQLite DB | `proxy` + `karakeep_internal` |
| `meilisearch` | `getmeili/meilisearch:v1.12` | Full-text search index | `karakeep_internal` only |
| `karakeep-chrome` | `ghcr.io/browserless/chromium:latest` | Web scraping, screenshots | `karakeep_internal` only |

Meilisearch and Chrome are internal only — they are never exposed to the `proxy` network or host ports.

---

## Technology Stack

- **Frontend/Backend**: Next.js, React, TypeScript, Node.js, tRPC
- **Database**: SQLite (embedded at `/data/db.db`) — no external database required
- **Search**: Meilisearch (separate container)
- **Scraping**: Puppeteer + Browserless Chrome
- **Auth**: NextAuth.js (supports OAuth/OIDC for SSO)
- **Workers**: Integrated via s6-overlay process supervisor (single container, post v0.16)
- **AI**: OpenAI, Ollama, Gemini, or any OpenAI-compatible provider (optional)

---

## Configuration Paths

| File | Purpose |
|---|---|
| `docker-compose/karakeep/docker-compose.yaml` | Stack definition |
| `docker-compose/karakeep/.env.example` | Template (committed) |
| `docker-compose/karakeep/.env` | Live secrets (gitignored) |
| `docker/karakeep/data/` | SQLite DB, job queue, uploaded assets |
| `docker/karakeep/meilisearch/` | Meilisearch search index |

---

## Required Secrets

| Variable | Purpose | Generate with |
|---|---|---|
| `NEXTAUTH_SECRET` | Session signing key | `openssl rand -base64 36` |
| `MEILI_MASTER_KEY` | Meilisearch API key | `openssl rand -base64 36` |
| `NEXTAUTH_URL` | Full public URL | `https://karakeep.YOUR_DOMAIN` |

`CHROME_TOKEN` is no longer used — Chrome runs unauthenticated on the isolated `karakeep_internal` network.

---

## AI Tagging

**Current status: disabled.** Karakeep works fully without AI — auto-tagging is simply skipped. AI can be enabled at any time without redeployment; only a container restart is required after updating `.env`.

**Preferred provider: OpenAI GPT-4.1**

### Enabling OpenAI GPT-4.1

1. Obtain an API key from https://platform.openai.com/api-keys
2. Set a spend limit on your OpenAI account before enabling (AI features run on every bookmark save)
3. Add to `docker-compose/karakeep/.env`:

```env
OPENAI_API_KEY=sk-...
INFERENCE_TEXT_MODEL=gpt-4.1
INFERENCE_IMAGE_MODEL=gpt-4.1
INFERENCE_CONTEXT_LENGTH=4096
INFERENCE_ENABLE_AUTO_SUMMARIZATION=true
```

4. Restart Karakeep:

```bash
cd ~/homelab/docker-compose/karakeep && docker compose restart karakeep
```

5. Verify in logs:

```bash
docker logs karakeep --tail 30 | grep -i "openai\|inference\|tagging"
```

**Model notes for GPT-4.1:**
- `gpt-4.1` handles both text tagging and image analysis in a single model — no separate image model needed, but setting both to `gpt-4.1` is correct
- `INFERENCE_CONTEXT_LENGTH=4096` gives good tag quality for most content; raise to `8192` for long articles
- `INFERENCE_ENABLE_AUTO_SUMMARIZATION=true` adds AI-generated summaries to each bookmark (increases token usage)

**Cost control:**
- Each bookmark save triggers one API call
- A typical bookmark uses ~500–2000 tokens depending on page length and context setting
- Monitor usage at https://platform.openai.com/usage
- Set a monthly spend cap on the OpenAI dashboard before enabling

### Switching to a Different Provider Later

Karakeep uses the OpenAI API interface for all providers. To switch:

| Provider | Required env changes |
|---|---|
| Ollama (local) | `OPENAI_BASE_URL=http://ollama:11434/v1`, `INFERENCE_TEXT_MODEL=gemma3`, `INFERENCE_IMAGE_MODEL=llava` |
| Google Gemini | `OPENAI_BASE_URL=https://generativelanguage.googleapis.com/openai/`, `OPENAI_API_KEY=<gemini-key>` |
| OpenRouter | `OPENAI_BASE_URL=https://openrouter.ai/api/v1`, `OPENAI_API_KEY=<openrouter-key>` |

---

## Operations (post-deployment)

```bash
# Start
cd ~/homelab/docker-compose/karakeep && docker compose up -d

# Stop
docker compose down

# Logs
docker logs karakeep --tail 50
docker logs meilisearch --tail 20
docker logs karakeep-chrome --tail 20

# Re-index search
docker exec karakeep wget -qO- http://localhost:3000/api/trpc/search.reindex

# Backup
tar -czf karakeep-backup-$(date +%Y%m%d).tar.gz \
    ~/homelab/docker/karakeep/data/ \
    ~/homelab/docker/karakeep/meilisearch/

# Update
docker compose pull
docker compose up -d
```

---

## Authelia OIDC Integration

Karakeep uses Authelia as its OIDC provider. Password-based login is disabled — all authentication goes through Authelia.

**How it works**: `OAUTH_AUTO_REDIRECT=true` means when a user visits Karakeep unauthenticated, they are immediately redirected to `auth.YOUR_DOMAIN`. After logging in to Authelia, an OIDC token is issued and Karakeep logs the user in automatically — no second prompt.

Each Authelia user gets a separate Karakeep account (independent bookmarks, settings). Add users in `docker/authelia/config/users_database.yml`.

**Key env vars (in `.env`):**

| Variable | Value |
|---|---|
| `OAUTH_WELLKNOWN_URL` | `https://auth.YOUR_DOMAIN/.well-known/openid-configuration` |
| `OAUTH_CLIENT_ID` | `karakeep` |
| `OAUTH_PROVIDER_NAME` | `Authelia` |
| `OAUTH_AUTO_REDIRECT` | `true` |
| `DISABLE_PASSWORD_AUTH` | `true` |

**`extra_hosts` required**: Karakeep server-side requests to `auth.YOUR_DOMAIN` bypass Pi-hole DNS. The compose file includes:
```yaml
extra_hosts:
  - "auth.YOUR_DOMAIN:<PIHOLE_HOST_IP>"
```
This maps the domain to Traefik directly inside the container.

### Troubleshooting

**`OAuthSignin` error / `ENOTFOUND auth.YOUR_DOMAIN`**: The `extra_hosts` entry is missing or incorrect. Verify the Karakeep container has the host entry: `docker exec karakeep getent hosts auth.YOUR_DOMAIN`

**`OAuthAccountNotLinked` error on login**: A Karakeep account already exists with the same email address as the Authelia user, but was created with a different provider (e.g. credentials/password login before OIDC was set up). NextAuth refuses to link them automatically. Fix: delete the stale account from the SQLite database (safe if it has no bookmarks), then log in again via OIDC to create a fresh linked account.
```bash
# Check the user and their bookmark count
sqlite3 ~/homelab/docker/karakeep/data/db.db \
  "SELECT u.id, u.name, u.email, COUNT(b.id) as bookmarks
   FROM user u LEFT JOIN bookmarks b ON b.userId=u.id GROUP BY u.id;"

# Stop karakeep before writing to the DB
cd ~/homelab/docker-compose/karakeep && docker compose stop karakeep

# Delete the stale user (replace USER_ID with the id from above)
docker run --rm --user root \
  -v ~/homelab/docker/karakeep/data:/data \
  keinos/sqlite3 sqlite3 /data/db.db "
DELETE FROM session WHERE userId='USER_ID';
DELETE FROM account WHERE userId='USER_ID';
DELETE FROM apiKey WHERE userId='USER_ID';
DELETE FROM user WHERE id='USER_ID';
"
docker compose start karakeep
```
If the account has existing bookmarks, export them first via Karakeep's UI (Settings → Export) before deleting.

**Chrome shows "401 disconnected" in admin panel**: Karakeep polls `GET /json/version` on Browserless without passing a token. This is a Karakeep health check bug. The actual Playwright connections work correctly. Fix: remove `TOKEN` from the Chrome container env (unauthenticated is safe — Chrome is on an isolated internal network). See compose file.

**CORS errors during login**: Add bypass rules in Authelia's `access_control` for `/api/auth/.*`, `/manifest.json`, `/_next/static/.*` on `karakeep.YOUR_DOMAIN`. See `docs/services/authelia.md`.

---

## Future Configuration Options

- **Enable OpenAI GPT-4.1 tagging** — see AI Tagging section above for the exact steps
- Pin Chrome image to a specific version tag
- Configure S3-compatible storage for assets if local disk becomes a concern
