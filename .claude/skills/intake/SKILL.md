# /intake

Requirements interview for adding a new service to the homelab.

## Interview Questions

Ask the user (or infer from context) the following before creating any files:

1. **Service name and purpose**: What is the service? What does it do?

2. **Docker image**: What image/tag will be used? Is it on Docker Hub or a private registry?

3. **Port**: What port does the container expose internally?

4. **Subdomain**: What subdomain should it be accessible at? (e.g., `<service>.<domain>`)

5. **Authentication**: Should this service be behind Authelia?
   - `one_factor` (password only)
   - `two_factor` (TOTP/WebAuthn)
   - `bypass` (public, no auth)
   - OIDC client (single sign-on — like Karakeep)

6. **Persistent data**: Does it need a bind mount? Where should data live? (`docker/<service>/data`)

7. **Database**: Does it need Postgres, MySQL, or SQLite? Should it be a separate container or embedded?

8. **Environment variables**: What env vars are required? Which contain secrets?

9. **Watchtower**: Should it be auto-updated? (default: yes, add label `com.centurylinklabs.watchtower.enable: "true"`)

10. **Special networking**: Does it need access to other containers? Does it need host networking?

## After Intake

Summarize the requirements and confirm with the user before running `/deploy-service`.
