#!/bin/bash
# =============================================================================
# Homelab restore reference
# See docs/services/backup.md for full restore procedures and context.
#
# Usage: run the relevant section manually — this script is a reference,
# not a one-shot restore. Each section restores a different component.
# =============================================================================

RESTIC_REPO="/mnt/backup/restic"
RESTIC_PASSWORD_FILE="/etc/restic-password"

export RESTIC_REPOSITORY="$RESTIC_REPO"
export RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE"

# -----------------------------------------------------------------------------
# List available snapshots
# -----------------------------------------------------------------------------
list_snapshots() {
    restic snapshots
}

# -----------------------------------------------------------------------------
# Restore bind mounts (authelia, karakeep, traefik, pihole)
# Restores to original paths. Stop affected containers first.
# -----------------------------------------------------------------------------
restore_bind_mounts() {
    local SNAPSHOT="${1:-latest}"
    echo "Restoring bind mounts from snapshot: $SNAPSHOT"
    echo "Stop containers first: docker compose down (in each service directory)"
    restic restore "$SNAPSHOT" --target /
}

# -----------------------------------------------------------------------------
# Restore Postgres (Sure)
# Drops and recreates the database from the logical dump.
# -----------------------------------------------------------------------------
restore_postgres() {
    local SNAPSHOT="${1:-latest}"
    local POSTGRES_CONTAINER="sure-db-1"
    local POSTGRES_USER="sure_user"
    local POSTGRES_DB="sure_production"

    echo "Restoring Postgres from snapshot: $SNAPSHOT"
    echo "Sure stack must be stopped first (except the db container):"
    echo "  cd ~/homelab/docker-compose/sure && docker compose stop web worker"

    # Drop and recreate the database
    docker exec "$POSTGRES_CONTAINER" \
        psql -U "$POSTGRES_USER" -c "DROP DATABASE IF EXISTS ${POSTGRES_DB};"
    docker exec "$POSTGRES_CONTAINER" \
        psql -U "$POSTGRES_USER" -c "CREATE DATABASE ${POSTGRES_DB};"

    # Restore from dump
    restic dump "$SNAPSHOT" "postgres/${POSTGRES_DB}.sql" \
        | docker exec -i "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" "$POSTGRES_DB"

    echo "Postgres restored. Restart Sure: docker compose up -d"
}

# -----------------------------------------------------------------------------
# Restore Sure app-storage volume
# -----------------------------------------------------------------------------
restore_app_storage() {
    local SNAPSHOT="${1:-latest}"
    local APP_STORAGE_PATH
    APP_STORAGE_PATH="$(docker volume inspect sure_app-storage \
        --format '{{.Mountpoint}}')"

    echo "Restoring Sure app-storage from snapshot: $SNAPSHOT"
    restic restore "$SNAPSHOT" \
        --target / \
        --include "$APP_STORAGE_PATH"
}

# -----------------------------------------------------------------------------
# Verify repository integrity
# -----------------------------------------------------------------------------
check_repo() {
    echo "Checking repository integrity..."
    restic check
}

# -----------------------------------------------------------------------------
# Main — print usage if run directly
# -----------------------------------------------------------------------------
echo "Homelab restore reference script."
echo ""
echo "Available functions (source this script or call manually):"
echo "  list_snapshots"
echo "  restore_bind_mounts [snapshot-id]"
echo "  restore_postgres [snapshot-id]"
echo "  restore_app_storage [snapshot-id]"
echo "  check_repo"
echo ""
echo "See docs/services/backup.md for full procedures."
