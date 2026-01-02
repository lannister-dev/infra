#!/usr/bin/env bash
set -euo pipefail

# vpn-infra WireGuard Manager (non-interactive)
# Focus: predictable infra, domain endpoint, no Unbound/nftables/NAT magic.
#
# Commands:
#   --install
#   --start | --stop | --restart
#   --list
#   --add <name>
#   --remove <name>
#   --backup
#   --restore <zip> <password>
#
# Uses:
#   /etc/wireguard/<WG_INTERFACE>.conf
#   /etc/wireguard/clients/<name>-<WG_INTERFACE>.conf

log() { echo "[WG][INFO] $*"; }
err() { echo "[WG][ERROR] $*" >&2; }
die() { err "$*"; exit 1; }

need_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run as root."
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage:
  ./apply.sh --install
  ./apply.sh --start
  ./apply.sh --stop
  ./apply.sh --restart
  ./apply.sh --list
  ./apply.sh --add <peer_name>
  ./apply.sh --remove <peer_name>
  ./apply.sh --backup
  ./apply.sh --restore <zip_path> <password>

Notes:
- Configure defaults in wireguard/manager/defaults.env
- Endpoint uses WG_ENDPOINT (domain) + WG_PORT
EOF
}

# ---------- Config / env ----------
# These are expected to be exported by defaults.env (via apply.sh).
WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_PORT="${WG_PORT:-443}"
WG_ENDPOINT="${WG_ENDPOINT:-}"
WG_IPV4_SUBNET="${WG_IPV4_SUBNET:-10.100.0.0/24}"
WG_ENABLE_IPV6="${WG_ENABLE_IPV6:-0}"
WG_IPV6_SUBNET="${WG_IPV6_SUBNET:-fd10:100::/64}"
WG_MTU="${WG_MTU:-1420}"
WG_PERSISTENT_KEEPALIVE="${WG_PERSISTENT_KEEPALIVE:-25}"
WG_CLIENT_ALLOWED_IPS="${WG_CLIENT_ALLOWED_IPS:-10.100.0.0/24}"
WG_CLIENT_DNS="${WG_CLIENT_DNS:-}"
WG_ENABLE_FORWARDING="${WG_ENABLE_FORWARDING:-1}"
WG_ETC_DIR="${WG_ETC_DIR:-/etc/wireguard}"
WG_CLIENTS_DIR="${WG_CLIENTS_DIR:-/etc/wireguard/clients}"
WG_BACKUP_DIR="${WG_BACKUP_DIR:-/var/backups}"
WG_BACKUP_FILE="${WG_BACKUP_FILE:-/var/backups/wireguard-vpn-infra.zip}"

WG_CONF="${WG_ETC_DIR}/${WG_INTERFACE}.conf"

# ---------- Helpers ----------
sanitize_name() {
  local n="$1"
  [[ "$n" =~ ^[a-zA-Z0-9._-]+$ ]] || die "Invalid peer name '$n'. Allowed: letters, digits, dot, underscore, dash."
}

subnet_ipv4_prefix() {
  # from 10.100.0.0/24 -> 10.100.0
  echo "${WG_IPV4_SUBNET}" | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3}'
}

subnet_ipv4_cidr() {
  echo "${WG_IPV4_SUBNET}" | cut -d/ -f2
}

server_ipv4() {
  echo "$(subnet_ipv4_prefix).1"
}

client_ipv4_for_octet() {
  local oct="$1"
  echo "$(subnet_ipv4_prefix).${oct}"
}

subnet_ipv6_cidr() {
  echo "${WG_IPV6_SUBNET}" | cut -d/ -f2
}

# server ipv6 = first address in prefix (…::1)
server_ipv6() {
  echo "$(echo "${WG_IPV6_SUBNET}" | cut -d/ -f1 | sed 's/::$/::/'):1"
}

client_ipv6_for_id() {
  local id="$1"
  echo "$(echo "${WG_IPV6_SUBNET}" | cut -d/ -f1 | sed 's/::$/::/'):${id}"
}

is_systemd() {
  [[ -d /run/systemd/system ]]
}

ensure_dirs() {
  mkdir -p "${WG_ETC_DIR}" "${WG_CLIENTS_DIR}" "${WG_BACKUP_DIR}"
  chmod 700 "${WG_ETC_DIR}" "${WG_CLIENTS_DIR}"
}

install_pkgs_debian() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y wireguard wireguard-tools qrencode zip unzip
}

detect_and_install() {
  if command -v wg >/dev/null 2>&1; then
    log "WireGuard tools already installed."
    return
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID:-}" in
      ubuntu|debian|raspbian|pop|kali|linuxmint|neon)
        log "Installing packages (Debian/Ubuntu family)..."
        install_pkgs_debian
        ;;
      *)
        die "Unsupported distro for auto-install in this manager (ID=${ID:-unknown}). Install 'wireguard-tools' manually."
        ;;
    esac
  else
    die "/etc/os-release not found; cannot detect distro. Install wireguard-tools manually."
  fi
}

enable_forwarding() {
  [[ "${WG_ENABLE_FORWARDING}" == "1" ]] || return 0

  log "Enabling IP forwarding via /etc/sysctl.d/99-${WG_INTERFACE}.conf"
  local sysctl_file="/etc/sysctl.d/99-${WG_INTERFACE}.conf"
  {
    echo "net.ipv4.ip_forward=1"
    if [[ "${WG_ENABLE_IPV6}" == "1" ]]; then
      echo "net.ipv6.conf.all.forwarding=1"
    fi
  } > "${sysctl_file}"
  sysctl --system >/dev/null 2>&1 || true
}

ensure_service_enabled() {
  if is_systemd; then
    systemctl enable --now "wg-quick@${WG_INTERFACE}" >/dev/null 2>&1 || true
  fi
}

service_start() {
  if is_systemd; then
    systemctl start "wg-quick@${WG_INTERFACE}" || true
  else
    wg-quick up "${WG_INTERFACE}" || true
  fi
}

service_stop() {
  if is_systemd; then
    systemctl stop "wg-quick@${WG_INTERFACE}" || true
  else
    wg-quick down "${WG_INTERFACE}" || true
  fi
}

service_restart() {
  if is_systemd; then
    systemctl restart "wg-quick@${WG_INTERFACE}" || true
  else
    wg-quick down "${WG_INTERFACE}" || true
    wg-quick up "${WG_INTERFACE}" || true
  fi
}

ensure_wg_conf_exists() {
  [[ -f "${WG_CONF}" ]] || die "WireGuard config not found: ${WG_CONF}. Run: ./apply.sh --install"
}

gen_server_keys_if_needed() {
  local priv_file="${WG_ETC_DIR}/${WG_INTERFACE}.key"
  local pub_file="${WG_ETC_DIR}/${WG_INTERFACE}.pub"

  if [[ -s "${priv_file}" && -s "${pub_file}" ]]; then
    return
  fi

  log "Generating server keys..."
  umask 077
  wg genkey | tee "${priv_file}" | wg pubkey > "${pub_file}"
}

server_privkey() { cat "${WG_ETC_DIR}/${WG_INTERFACE}.key"; }
server_pubkey()  { cat "${WG_ETC_DIR}/${WG_INTERFACE}.pub"; }

conf_has_peer() {
  local name="$1"
  grep -qE "^# ${name} start$" "${WG_CONF}"
}

peer_public_key_from_conf() {
  local name="$1"
  sed -n "/^# ${name} start$/,/^# ${name} end$/p" "${WG_CONF}" | awk '/^PublicKey = /{print $3; exit}'
}

next_free_octet() {
  # allocate from .2 to .254
  # Parse existing AllowedIPs v4 from config blocks and find first free.
  local used
  used="$(awk '/^AllowedIPs = /{
    split($3,a,",");
    split(a[1],b,"/");
    split(b[1],c,".");
    print c[4]
  }' "${WG_CONF}" | sort -n | uniq || true)"

  local oct
  for oct in $(seq 2 254); do
    if ! echo "${used}" | grep -qx "${oct}"; then
      echo "${oct}"
      return
    fi
  done
  die "No free IPv4 addresses left in ${WG_IPV4_SUBNET}"
}

write_server_conf_if_missing() {
  if [[ -f "${WG_CONF}" ]]; then
    log "Config exists: ${WG_CONF}"
    return
  fi

  [[ -n "${WG_ENDPOINT}" ]] || die "WG_ENDPOINT is empty. Set it in defaults.env"

  gen_server_keys_if_needed
  ensure_dirs
  enable_forwarding

  local v4_cidr v4_addr
  v4_cidr="$(subnet_ipv4_cidr)"
  v4_addr="$(server_ipv4)"

  umask 077
  {
    echo "# vpn-infra managed"
    echo "# endpoint=${WG_ENDPOINT}:${WG_PORT}"
    echo "# ipv4_subnet=${WG_IPV4_SUBNET}"
    echo "# client_allowed_ips=${WG_CLIENT_ALLOWED_IPS}"
    echo
    echo "[Interface]"
    echo "Address = ${v4_addr}/${v4_cidr}"
    if [[ "${WG_ENABLE_IPV6}" == "1" ]]; then
      echo "Address = $(server_ipv6)/$(subnet_ipv6_cidr)"
    fi
    echo "ListenPort = ${WG_PORT}"
    echo "MTU = ${WG_MTU}"
    echo "PrivateKey = $(server_privkey)"
    echo "SaveConfig = false"
    echo
  } > "${WG_CONF}"

  chmod 600 "${WG_CONF}"
  log "Created ${WG_CONF}"
}

render_client_conf() {
  local name="$1"
  local client_priv="$2"
  local client_addr_v4="$3"
  local client_addr_v6="${4:-}"

  local client_file="${WG_CLIENTS_DIR}/${name}-${WG_INTERFACE}.conf"

  umask 077
  {
    echo "# vpn-infra client config"
    echo "[Interface]"
    echo "Address = ${client_addr_v4}/32"
    if [[ "${WG_ENABLE_IPV6}" == "1" && -n "${client_addr_v6}" ]]; then
      echo "Address = ${client_addr_v6}/128"
    fi
    if [[ -n "${WG_CLIENT_DNS}" ]]; then
      echo "DNS = ${WG_CLIENT_DNS}"
    fi
    echo "PrivateKey = ${client_priv}"
    echo
    echo "[Peer]"
    echo "PublicKey = $(server_pubkey)"
    echo "Endpoint = ${WG_ENDPOINT}:${WG_PORT}"
    echo "AllowedIPs = ${WG_CLIENT_ALLOWED_IPS}"
    echo "PersistentKeepalive = ${WG_PERSISTENT_KEEPALIVE}"
  } > "${client_file}"

  chmod 600 "${client_file}"
  echo "${client_file}"
}

add_peer_to_conf() {
  local name="$1"
  local client_pub="$2"
  local client_addr_v4="$3"
  local client_addr_v6="${4:-}"

  {
    echo "# ${name} start"
    echo "[Peer]"
    echo "PublicKey = ${client_pub}"
    if [[ "${WG_ENABLE_IPV6}" == "1" && -n "${client_addr_v6}" ]]; then
      echo "AllowedIPs = ${client_addr_v4}/32,${client_addr_v6}/128"
    else
      echo "AllowedIPs = ${client_addr_v4}/32"
    fi
    echo "# ${name} end"
    echo
  } >> "${WG_CONF}"
}

apply_peer_runtime_add() {
  local client_pub="$1"
  local client_addr_v4="$2"
  local client_addr_v6="${3:-}"

  if ! wg show "${WG_INTERFACE}" >/dev/null 2>&1; then
    log "Interface not running; starting..."
    service_start
  fi

  if [[ "${WG_ENABLE_IPV6}" == "1" && -n "${client_addr_v6}" ]]; then
    wg set "${WG_INTERFACE}" peer "${client_pub}" allowed-ips "${client_addr_v4}/32,${client_addr_v6}/128"
  else
    wg set "${WG_INTERFACE}" peer "${client_pub}" allowed-ips "${client_addr_v4}/32"
  fi
}

apply_runtime_reload() {
  # Ensures wg uses updated config (without full down/up)
  if wg show "${WG_INTERFACE}" >/dev/null 2>&1; then
    wg syncconf "${WG_INTERFACE}" <(wg-quick strip "${WG_INTERFACE}") || true
  fi
}

cmd_install() {
  need_root
  require_cmd awk
  require_cmd sed
  require_cmd grep

  detect_and_install
  require_cmd wg
  require_cmd wg-quick
  require_cmd zip
  require_cmd unzip

  ensure_dirs
  enable_forwarding
  write_server_conf_if_missing
  ensure_service_enabled
  service_restart

  log "Installed. Status:"
  wg show "${WG_INTERFACE}" || true
}

cmd_start() { need_root; ensure_wg_conf_exists; service_start; wg show "${WG_INTERFACE}" || true; }
cmd_stop() { need_root; service_stop; }
cmd_restart() { need_root; ensure_wg_conf_exists; service_restart; wg show "${WG_INTERFACE}" || true; }

cmd_list() {
  need_root
  if wg show "${WG_INTERFACE}" >/dev/null 2>&1; then
    wg show "${WG_INTERFACE}"
  else
    log "Interface not running. Showing config peers from ${WG_CONF}:"
    ensure_wg_conf_exists
    grep -E '^# .* start$' "${WG_CONF}" | sed 's/^# //; s/ start$//'
  fi
}

cmd_add() {
  need_root
  local name="${1:-}"
  [[ -n "${name}" ]] || die "--add requires <peer_name>"
  sanitize_name "${name}"

  [[ -n "${WG_ENDPOINT}" ]] || die "WG_ENDPOINT is empty. Set it in defaults.env"

  ensure_dirs
  write_server_conf_if_missing

  if conf_has_peer "${name}"; then
    die "Peer '${name}' already exists in ${WG_CONF}"
  fi

  local oct client_addr_v4 client_addr_v6=""
  oct="$(next_free_octet)"
  client_addr_v4="$(client_ipv4_for_octet "${oct}")"

  if [[ "${WG_ENABLE_IPV6}" == "1" ]]; then
    client_addr_v6="$(client_ipv6_for_id "${oct}")"
  fi

  log "Allocating: ${name} -> ${client_addr_v4}${client_addr_v6:+, ${client_addr_v6}}"

  umask 077
  local client_priv client_pub
  client_priv="$(wg genkey)"
  client_pub="$(printf '%s' "${client_priv}" | wg pubkey)"

  add_peer_to_conf "${name}" "${client_pub}" "${client_addr_v4}" "${client_addr_v6}"

  # Apply to running interface without down/up
  apply_peer_runtime_add "${client_pub}" "${client_addr_v4}" "${client_addr_v6}"
  apply_runtime_reload

  local client_file
  client_file="$(render_client_conf "${name}" "${client_priv}" "${client_addr_v4}" "${client_addr_v6}")"

  log "Client config created: ${client_file}"

  if command -v qrencode >/dev/null 2>&1; then
    log "QR:"
    qrencode -t ansiutf8 < "${client_file}" || true
  fi
}

cmd_remove() {
  need_root
  local name="${1:-}"
  [[ -n "${name}" ]] || die "--remove requires <peer_name>"
  sanitize_name "${name}"
  ensure_wg_conf_exists

  if ! conf_has_peer "${name}"; then
    die "Peer '${name}' not found in ${WG_CONF}"
  fi

  local pub
  pub="$(peer_public_key_from_conf "${name}")"
  [[ -n "${pub}" ]] || die "Cannot parse PublicKey for peer '${name}'"

  if wg show "${WG_INTERFACE}" >/dev/null 2>&1; then
    wg set "${WG_INTERFACE}" peer "${pub}" remove || true
  fi

  # Remove peer block from config
  sed -i "/^# ${name} start$/,/^# ${name} end$/d" "${WG_CONF}"
  apply_runtime_reload

  local client_file="${WG_CLIENTS_DIR}/${name}-${WG_INTERFACE}.conf"
  if [[ -f "${client_file}" ]]; then
    rm -f "${client_file}"
  fi

  log "Removed peer '${name}'."
}

cmd_backup() {
  need_root
  ensure_wg_conf_exists
  ensure_dirs
  require_cmd zip
  require_cmd openssl

  local password
  password="$(openssl rand -hex 25)"

  # zip only wg conf + server keys + clients
  local tmpdir
  tmpdir="$(mktemp -d)"
  cp -a "${WG_CONF}" "${tmpdir}/"
  if [[ -f "${WG_ETC_DIR}/${WG_INTERFACE}.key" ]]; then cp -a "${WG_ETC_DIR}/${WG_INTERFACE}.key" "${tmpdir}/"; fi
  if [[ -f "${WG_ETC_DIR}/${WG_INTERFACE}.pub" ]]; then cp -a "${WG_ETC_DIR}/${WG_INTERFACE}.pub" "${tmpdir}/"; fi
  if [[ -d "${WG_CLIENTS_DIR}" ]]; then
    mkdir -p "${tmpdir}/clients"
    cp -a "${WG_CLIENTS_DIR}/." "${tmpdir}/clients/" || true
  fi

  rm -f "${WG_BACKUP_FILE}" || true
  (cd "${tmpdir}" && zip -P "${password}" -r "${WG_BACKUP_FILE}" . >/dev/null)

  rm -rf "${tmpdir}"

  log "Backup created: ${WG_BACKUP_FILE}"
  log "Backup password: ${password}"
  log "Store the password securely."
}

cmd_restore() {
  need_root
  local zip_path="${1:-}"
  local password="${2:-}"

  [[ -n "${zip_path}" && -n "${password}" ]] || die "--restore requires <zip_path> <password>"
  [[ -f "${zip_path}" ]] || die "Backup file not found: ${zip_path}"

  ensure_dirs
  require_cmd unzip

  local tmpdir
  tmpdir="$(mktemp -d)"

  unzip -o -P "${password}" "${zip_path}" -d "${tmpdir}" >/dev/null || {
    rm -rf "${tmpdir}"
    die "Unzip failed. Wrong password or corrupted archive."
  }

  # Restore files
  cp -a "${tmpdir}/${WG_INTERFACE}.conf" "${WG_CONF}" || die "Missing ${WG_INTERFACE}.conf in backup."
  chmod 600 "${WG_CONF}"

  if [[ -f "${tmpdir}/${WG_INTERFACE}.key" ]]; then
    cp -a "${tmpdir}/${WG_INTERFACE}.key" "${WG_ETC_DIR}/${WG_INTERFACE}.key"
    chmod 600 "${WG_ETC_DIR}/${WG_INTERFACE}.key"
  fi
  if [[ -f "${tmpdir}/${WG_INTERFACE}.pub" ]]; then
    cp -a "${tmpdir}/${WG_INTERFACE}.pub" "${WG_ETC_DIR}/${WG_INTERFACE}.pub"
    chmod 600 "${WG_ETC_DIR}/${WG_INTERFACE}.pub"
  fi

  if [[ -d "${tmpdir}/clients" ]]; then
    rm -rf "${WG_CLIENTS_DIR}"
    mkdir -p "${WG_CLIENTS_DIR}"
    cp -a "${tmpdir}/clients/." "${WG_CLIENTS_DIR}/" || true
    chmod 700 "${WG_CLIENTS_DIR}"
    find "${WG_CLIENTS_DIR}" -type f -exec chmod 600 {} \; || true
  fi

  rm -rf "${tmpdir}"

  enable_forwarding
  ensure_service_enabled
  service_restart

  log "Restore completed. Status:"
  wg show "${WG_INTERFACE}" || true
}

# ---------- Main ----------
main() {
  local cmd="${1:-}"
  case "${cmd}" in
    --install) shift; cmd_install "$@" ;;
    --start) shift; cmd_start "$@" ;;
    --stop) shift; cmd_stop "$@" ;;
    --restart) shift; cmd_restart "$@" ;;
    --list) shift; cmd_list "$@" ;;
    --add) shift; cmd_add "$@" ;;
    --remove) shift; cmd_remove "$@" ;;
    --backup) shift; cmd_backup "$@" ;;
    --restore) shift; cmd_restore "$@" ;;
    --help|-h|"") usage ;;
    *)
      err "Unknown command: ${cmd}"
      usage
      exit 1
      ;;
  esac
}

main "$@"