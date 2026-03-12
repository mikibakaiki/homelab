# /privacy-audit

Scan staged changes and recent commits for privacy leaks before committing.

## When to Use

Before any commit, especially after editing config files, `.env.example` files, docs, or plans.

## Scan Steps

1. **Staged diff scan**: `git diff --cached` — search for:
   - Absolute paths: `/home/<username>/`
   - IP addresses: patterns like `192.168.`, `10.0.`, `172.`
   - Domain names: any `*.tld` that looks like a real domain
   - Tokens/secrets: strings >30 chars of mixed alphanumeric, API key patterns
   - Hardcoded credentials: `password=`, `secret=`, `token=` with real values

2. **Recent commit scan**: `git log --oneline -10` — check commit messages for leaked paths or domains.

3. **File content spot-check**: For any `.env.example`, plans, or docs files in the staged set, read them and verify placeholders are used (`<DOMAIN_NAME>`, `<YOUR_IP>`, etc.) rather than real values.

## Remediation

- Replace real IPs with `<ROUTER_IP>`, `<PIHOLE_HOST_IP>`, `<DHCP_RANGE_START>-<DHCP_RANGE_END>`
- Replace real domains with `<DOMAIN_NAME>` or `<SERVICE>.<DOMAIN_NAME>`
- Replace absolute paths with `~/homelab/` or relative paths
- Replace tokens with `replace_with_<description>`
- If a past commit has leaked data: note it for the user; do NOT run `git filter-branch` without explicit user instruction

## Rules (from feedback_commits.md)

- No personal paths, IPs, or domains in committed file content
- Scripts use dynamic path detection, not hardcoded absolute paths
- Commit messages must not contain paths, IPs, or domains
