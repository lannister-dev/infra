#!/usr/bin/env bash
# ---------------------------------------------------------------------
# Backup PostgreSQL databases running in K8s StatefulSets.
#
# Usage:
#   backup-data.sh --namespace <ns> --pod <pod-name> [--target-dir /backups] [--retention 7]
#
# Examples:
#   backup-data.sh --namespace data-prod --pod data-prod-postgres-0
#   backup-data.sh --namespace data-dev  --pod data-dev-postgres-0 --retention 3
#
# The script runs pg_dump inside the pod via kubectl exec and saves a
# timestamped .sql.gz file locally.  Old backups beyond the retention
# count are pruned automatically.
# ---------------------------------------------------------------------
set -Eeo pipefail
set -u

NAMESPACE=""
POD=""
TARGET_DIR="/opt/backups"
RETENTION=7

usage() {
  echo "Usage: $0 --namespace <ns> --pod <pod> [--target-dir DIR] [--retention N]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace|-n) NAMESPACE="$2"; shift 2 ;;
    --pod|-p)       POD="$2";       shift 2 ;;
    --target-dir)   TARGET_DIR="$2"; shift 2 ;;
    --retention)    RETENTION="$2";  shift 2 ;;
    *)              usage ;;
  esac
done

[ -n "${NAMESPACE}" ] || usage
[ -n "${POD}" ]       || usage

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="${TARGET_DIR}/${NAMESPACE}"
mkdir -p "${BACKUP_DIR}"

# Read database credentials from the pod environment
PG_USER="$(kubectl exec -n "${NAMESPACE}" "${POD}" -- printenv POSTGRES_USER 2>/dev/null || echo "postgres")"
PG_DB="$(kubectl exec -n "${NAMESPACE}" "${POD}" -- printenv POSTGRES_DB 2>/dev/null || echo "postgres")"

BACKUP_FILE="${BACKUP_DIR}/${PG_DB}_${TIMESTAMP}.sql.gz"

echo "Backing up ${NAMESPACE}/${POD} (db=${PG_DB}, user=${PG_USER}) -> ${BACKUP_FILE}"
kubectl exec -n "${NAMESPACE}" "${POD}" -- pg_dump -U "${PG_USER}" -d "${PG_DB}" | gzip > "${BACKUP_FILE}"

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
