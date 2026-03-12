# /backup-status

Check the status of Restic backups to the USB drive.

## Steps

1. **Check USB mount**: `lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,MODEL | grep -v loop` — verify `/mnt/backup` is mounted.

2. **List snapshots**: `sudo restic -r /mnt/backup/restic snapshots --password-file /etc/restic-password 2>&1`

3. **Check last backup time**: Review most recent snapshot timestamp. Alert if >25 hours old (daily schedule at 02:00).

4. **Check backup size**: `sudo du -sh /mnt/backup/restic/`

5. **Verify backup service**: `docker ps | grep backup` or check cron/systemd for the backup script.

6. **Check backup logs**: `sudo bash -c "journalctl -u restic-backup --since yesterday 2>/dev/null || cat /var/log/restic-backup.log 2>/dev/null | tail -30"`

7. **Database backup check**: Confirm `pg_dump` for Sure Postgres is included in snapshots (look for `.sql` files in recent snapshots).

## Retention Policy

- 7 daily snapshots
- 4 weekly snapshots
- 3 monthly snapshots

## Alert Conditions

- No snapshot in >25 hours
- USB not mounted
- Backup job exit code non-zero
- Snapshot size anomaly (>50% change from previous)
