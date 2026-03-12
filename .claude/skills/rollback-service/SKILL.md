# /rollback-service

Safely roll back a service to a previous image version.

## Steps

1. **Identify current version**: `docker inspect <service> | grep Image` — note the current image digest/tag.

2. **Find previous version**: Check `docker-compose/<service>/.env` or compose file for the image tag. Check git log for the last known-good version: `git log --oneline docker-compose/<service>/`.

3. **Check for data migrations**: If the service uses a database (Postgres, SQLite), check the changelog for the version being rolled back from. Rollback may require a DB migration reversal — if so, restore from backup instead.

4. **Stop the service**: `cd docker-compose/<service> && docker compose stop <service>`

5. **Update image tag**: Edit `.env` or `docker-compose.yaml` to set the previous version tag.

6. **Pull the image**: `docker compose pull <service>`

7. **Start and verify**: `docker compose up -d <service> && docker logs <service> --tail 30`

8. **Document**: Note the rollback in the relevant plan file with reason and date.

## Watchtower Note

Watchtower runs daily at 04:00 and will auto-update opted-in services. After a rollback, if the issue is with the latest image, either:
- Pin the version in `.env` (Watchtower will not override a pinned tag)
- Add `com.centurylinklabs.watchtower.enable: "false"` label temporarily

## If Rollback Fails

If the previous image is unavailable or DB state is incompatible, restore from Restic backup. Run `/backup-status` to verify snapshot availability before attempting.
