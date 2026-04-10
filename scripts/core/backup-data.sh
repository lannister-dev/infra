#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Backup PostgreSQL databases running in Docker Swarm services.
#
# Usage:
#   backup-data.sh --service <swarm_service> [--target-dir /backups] [--retention 7]
#
# The script finds the running container for the given Swarm service,
# executes pg_dump inside it, and saves a timestamped .sql.gz file.
# Old backups beyond the retention count are pruned automatically.
# ---------------------------------------------------------------------
set -Eeo pipefail
set -u

SERVICE=""
TARGET_DIR="/opt/backups"
RETENTION=7

usage() {
  echo "Usage: $0 --service <swarm_service> [--target-dir DIR] [--retention N]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)      SERVICE="$2"; shift 2 ;;
    --target-dir)   TARGET_DIR="$2"; shift 2 ;;
    --retention)    RETENTION="$2"; shift 2 ;;
    *)              usage ;;
  esac
done

[ -n "${SERVICE}" ] || usage

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${TARGET_DIR}/${SERVICE}"
mkdir -p "${BACKUP_DIR}"

# Find the running container for the Swarm service
CONTAINER_ID="$(docker ps --filter "label=com.docker.swarm.service.name=${SERVICE}" --format '{{.ID}}' | head -n1)"
if [ -z "${CONTAINER_ID}" ]; then
  echo "ERROR: No running container found for service ${SERVICE}" >&2
  exit 1
fi

# Read database credentials from the container environment
PG_USER="$(docker exec "${CONTAINER_ID}" printenv POSTGRES_USER 2>/dev/null || echo "postgres")"
PG_DB="$(docker exec "${CONTAINER_ID}" printenv POSTGRES_DB 2>/dev/null || echo "postgres")"

BACKUP_FILE="${BACKUP_DIR}/${PG_DB}_${TIMESTAMP}.sql.gz"

echo "Backing up ${SERVICE} (db=${PG_DB}, user=${PG_USER}) -> ${BACKUP_FILE}"
docker exec "${CONTAINER_ID}" pg_dump -U "${PG_USER}" -d "${PG_DB}" | gzip > "${BACKUP_FILE}"

if [ ! -s "${BACKUP_FILE}" ]; then
  echo "ERROR: Backup file is empty" >&2
  rm -f "${BACKUP_FILE}"
  exit 1
fi

echo "Backup complete: $(du -h "${BACKUP_FILE}" | cut -f1)"

# Rotate old backups
BACKUP_COUNT="$(find "${BACKUP_DIR}" -name '*.sql.gz' -type f | wc -l | tr -d ' ')"
if [ "${BACKUP_COUNT}" -gt "${RETENTION}" ]; then
  REMOVE_COUNT=$((BACKUP_COUNT - RETENTION))
  echo "Pruning ${REMOVE_COUNT} old backup(s) (retention=${RETENTION})"
  # shellcheck disable=SC2012
  ls -1t "${BACKUP_DIR}"/*.sql.gz | tail -n "${REMOVE_COUNT}" | xargs rm -f
fi

echo "Done. Backups in ${BACKUP_DIR}: $(find "${BACKUP_DIR}" -name '*.sql.gz' -type f | wc -l | tr -d ' ')"
