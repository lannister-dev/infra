#!/usr/bin/env bash
set -Eeuo pipefail

fail() {
  echo "[WG][RECONCILE][ERROR] $*" >&2
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
WG_CLIENTS_DIR="${WG_CLIENTS_DIR:-/etc/wireguard/clients}"
WG_CONF="${WG_ETC_DIR}/${WG_INTERFACE}.conf"
WG_SERVER_PUB="${WG_ETC_DIR}/${WG_INTERFACE}.pub"
WG_SUBNET="${WG_IPV4_SUBNET:-10.100.0.0/24}"
WG_ALLOWED="${WG_CLIENT_ALLOWED_IPS:-10.100.0.0/24}"
WG_KEEPALIVE="${WG_PERSISTENT_KEEPALIVE:-25}"
LOCK_FILE="${WG_ETC_DIR}/.vpn-infra-reconcile.lock"
WG_CLIENT_CONF="${WG_CLIENTS_DIR}/${NAME}-${WG_INTERFACE}.conf"

[[ -n "${WG_ENDPOINT:-}" ]] || fail "WG_ENDPOINT is empty in defaults"
[[ -n "${WG_PORT:-}" ]] || fail "WG_PORT is empty in defaults"
[[ -f "${WG_CONF}" ]] || fail "Missing WireGuard config: ${WG_CONF}"
[[ -f "${WG_SERVER_PUB}" ]] || fail "Missing WireGuard server pubkey: ${WG_SERVER_PUB}"
command -v flock >/dev/null 2>&1 || fail "flock is required"

exec 9>"${LOCK_FILE}"
flock -w 30 9

# Existing peer with client config -> no-op
if grep -qE "^# ${NAME} start$" "${WG_CONF}" && [[ -f "${WG_CLIENT_CONF}" ]]; then
  exit 0
fi

# Existing peer without client config -> remove stale block
if grep -qE "^# ${NAME} start$" "${WG_CONF}"; then
  old_pub="$(sed -n "/^# ${NAME} start$/,/^# ${NAME} end$/p" "${WG_CONF}" | awk '/^PublicKey = /{print $3; exit}')"
  if [[ -n "${old_pub}" ]] && wg show "${WG_INTERFACE}" >/dev/null 2>&1; then
    wg set "${WG_INTERFACE}" peer "${old_pub}" remove || true
  fi
  sed -i "/^# ${NAME} start$/,/^# ${NAME} end$/d" "${WG_CONF}"
fi

prefix="$(echo "${WG_SUBNET}" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3}')"
used="$(awk '/^AllowedIPs = /{
  split($3,a,","); split(a[1],b,"/"); split(b[1],c,"."); print c[4]
}' "${WG_CONF}" | sort -n | uniq || true)"

octet=""
for n in $(seq 2 254); do
  if ! echo "${used}" | grep -qx "${n}"; then
    octet="${n}"
    break
  fi
done
[[ -n "${octet}" ]] || fail "No free WireGuard IPv4 in ${WG_SUBNET}"

client_ip="${prefix}.${octet}"
client_priv="$(wg genkey)"
client_pub="$(printf '%s' "${client_priv}" | wg pubkey)"

{
  echo "# ${NAME} start"
  echo "[Peer]"
  echo "PublicKey = ${client_pub}"
  echo "AllowedIPs = ${client_ip}/32"
  echo "# ${NAME} end"
  echo
} >> "${WG_CONF}"

mkdir -p "${WG_CLIENTS_DIR}"
chmod 700 "${WG_CLIENTS_DIR}"

{
  echo "# vpn-infra managed client"
  echo "[Interface]"
  echo "Address = ${client_ip}/32"
  echo "PrivateKey = ${client_priv}"
  if [[ -n "${WG_CLIENT_DNS:-}" ]]; then
    echo "DNS = ${WG_CLIENT_DNS}"
  fi
  echo
  echo "[Peer]"
  echo "PublicKey = $(cat "${WG_SERVER_PUB}")"
  echo "Endpoint = ${WG_ENDPOINT}:${WG_PORT}"
  echo "AllowedIPs = ${WG_ALLOWED}"
  echo "PersistentKeepalive = ${WG_KEEPALIVE}"
} > "${WG_CLIENT_CONF}"
chmod 600 "${WG_CLIENT_CONF}"

if wg show "${WG_INTERFACE}" >/dev/null 2>&1; then
  wg set "${WG_INTERFACE}" peer "${client_pub}" allowed-ips "${client_ip}/32"
  wg syncconf "${WG_INTERFACE}" <(wg-quick strip "${WG_INTERFACE}") || true
else
  systemctl restart "wg-quick@${WG_INTERFACE}" >/dev/null 2>&1 || true
fi

exit 10
