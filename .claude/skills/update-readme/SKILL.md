# /update-readme

Update README.md to reflect the current state of the homelab stack.

## When to Use

After any of the following:
- A new service is deployed or removed
- A service version changes significantly
- The architecture changes (new networks, auth layer, backup, etc.)
- The repository structure changes

## Steps

Invoke the `readme-updater` subagent. It will:

1. Read the current `README.md`
2. Scan the live stack: `docker ps`, compose files, `.env.example` files
3. Read `docs/infrastructure-state.md` and memory for the current deployed versions
4. Rewrite README.md sections that are stale:
   - Services table (names, purpose, access URL pattern, status)
   - Architecture diagram (mermaid)
   - Repository structure tree
   - Quick Start (env vars, setup steps)
   - Monitoring & Maintenance (Watchtower, Restic backup)
   - Troubleshooting (current known issues)
   - Status block (date, service count, versions)
5. Preserve sections that are still accurate
6. Run `/privacy-audit` on the result before writing
7. Commit with message: `docs: update README to reflect current stack`

## Rules

- No real IPs, domains, or usernames — use `<PLACEHOLDER>` or `your.domain`
- Preserve the existing emoji + heading style
- Keep the mermaid diagram updated with all active services
- The Status block date must reflect today's date
