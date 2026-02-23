#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/manager/defaults.env"
LOCAL_DEFAULTS_FILE="${SCRIPT_DIR}/manager/defaults.env.local"
ENGINE="${SCRIPT_DIR}/manager/wireguard-manager.sh"

if [[ ! -f "${DEFAULTS_FILE}" ]]; then
  echo "[WG][ERROR] defaults.env not found: ${DEFAULTS_FILE}" >&2
  exit 1
fi

# Export all vars from defaults
set -a
# shellcheck source=wireguard/manager/defaults.env
# shellcheck disable=SC1091
source "${DEFAULTS_FILE}"

# Optional local overrides (not in git)
if [[ -f "${LOCAL_DEFAULTS_FILE}" ]]; then
  # shellcheck source=wireguard/manager/defaults.env.local
  # shellcheck disable=SC1091
  source "${LOCAL_DEFAULTS_FILE}"
fi
set +a

if [[ ! -x "${ENGINE}" ]]; then
  echo "[WG][ERROR] engine not executable: ${ENGINE}" >&2
  echo "Run: chmod +x ${ENGINE}" >&2
  exit 1
fi

exec "${ENGINE}" "$@"
