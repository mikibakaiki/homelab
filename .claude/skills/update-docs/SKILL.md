# /update-docs

Sync documentation after any infrastructure change.

## When to Use

After deploying a new service, changing Traefik/Authelia config, updating versions, or completing a phase of work.

## Steps

1. **Identify changed components**: What services were added/modified/removed? What config files changed?

2. **Update service docs**: For each changed service, update or create `docs/services/<service>.md`:
   - Service description and URL
   - Configuration notes
   - Authelia integration (if any)
   - Known issues / troubleshooting

3. **Update infrastructure state**: Review `docs/infrastructure-state.md` — update version numbers, deployment status, and stack summary.

4. **Update Traefik routing doc**: If routers/middlewares changed, update `docs/traefik-routing.md`.

5. **Update MEMORY.md**: If deployed stack changed, update the "Deployed Stack" section in memory.

6. **Mark plan complete**: In the relevant `plans/` file, add a completion note or mark steps as done.

7. **Commit docs**: Stage docs changes separately from config changes with a clear commit message like `docs: update <service> after phase X deployment`.

## Do NOT

- Add real IPs, domains, or absolute paths to docs — use `<PLACEHOLDER>` notation
- Commit `.env` files or acme.json
- Forget to update the MEMORY.md deployed stack list when versions change
