#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  echo "[WG][DECOMMISSION][ERROR] $*" >&2
  exit 1
}

ROOT=""
NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    --name)
      NAME="${2:-}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${ROOT}" ]] || fail "--root is required"
[[ -n "${NAME}" ]] || fail "--name is required"

DEFAULTS_FILE="${ROOT}/wireguard/manager/defaults.env"
LOCAL_DEFAULTS_FILE="${ROOT}/wireguard/manager/defaults.env.local"
[[ -f "${DEFAULTS_FILE}" ]] || fail "defaults file not found: ${DEFAULTS_FILE}"

# shellcheck source=wireguard/manager/defaults.env
# shellcheck disable=SC1091
source "${DEFAULTS_FILE}"
if [[ -f "${LOCAL_DEFAULTS_FILE}" ]]; then
  # shellcheck source=wireguard/manager/defaults.env.local
  # shellcheck disable=SC1091
  source "${LOCAL_DEFAULTS_FILE}"
fi

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_ETC_DIR="${WG_ETC_DIR:-/etc/wireguard}"
WG_CONF="${WG_ETC_DIR}/${WG_INTERFACE}.conf"
WG_CLIENTS_DIR="${WG_CLIENTS_DIR:-/etc/wireguard/clients}"
CLIENT_CONF="${WG_CLIENTS_DIR}/${NAME}-${WG_INTERFACE}.conf"
LOCK_FILE="${WG_ETC_DIR}/.vpn-infra-reconcile.lock"

command -v flock >/dev/null 2>&1 || fail "flock is required"
exec 9>"${LOCK_FILE}"
flock -w 30 9

changed=0
while read -r node_id; do
  [[ -n "${node_id}" ]] || continue
  changed=1
  docker node update --availability drain "${node_id}" >/dev/null 2>&1 || true
  docker node rm --force "${node_id}" >/dev/null 2>&1 || true
done < <(docker node ls --filter "label=peer_name=${NAME}" -q || true)

if [[ -f "${WG_CONF}" ]] && grep -qE "^# ${NAME} start$" "${WG_CONF}"; then
  changed=1
  pub="$(sed -n "/^# ${NAME} start$/,/^# ${NAME} end$/p" "${WG_CONF}" | awk '/^PublicKey = /{print $3; exit}')"
  if [[ -n "${pub}" ]] && wg show "${WG_INTERFACE}" >/dev/null 2>&1; then
    wg set "${WG_INTERFACE}" peer "${pub}" remove || true
  fi
  sed -i "/^# ${NAME} start$/,/^# ${NAME} end$/d" "${WG_CONF}"
  if wg show "${WG_INTERFACE}" >/dev/null 2>&1; then
    wg syncconf "${WG_INTERFACE}" <(wg-quick strip "${WG_INTERFACE}") || true
  fi
fi

if [[ -f "${CLIENT_CONF}" ]]; then
  changed=1
  rm -f "${CLIENT_CONF}"
fi

if [[ "${changed}" == "1" ]]; then
  exit 10
fi
exit 0
