#!/usr/bin/env bash
set -euo pipefail

# Wrapper entrypoint for vpn-infra WireGuard management.
# Loads defaults and forwards CLI args to engine.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULTS_FILE="${SCRIPT_DIR}/manager/defaults.env"
ENGINE="${SCRIPT_DIR}/manager/wireguard-manager.sh"

if [[ ! -f "${DEFAULTS_FILE}" ]]; then
  echo "[WG][ERROR] defaults.env not found: ${DEFAULTS_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${DEFAULTS_FILE}"

if [[ ! -x "${ENGINE}" ]]; then
  echo "[WG][ERROR] engine not executable: ${ENGINE}" >&2
  echo "Run: chmod +x ${ENGINE}" >&2
  exit 1
fi

exec bash "${ENGINE}" "$@"