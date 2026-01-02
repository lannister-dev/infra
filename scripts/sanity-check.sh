#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

# -------------------------
# helpers
# -------------------------
log() { echo "[SANITY] $*"; }
warn() { echo "[SANITY][WARN] $*" >&2; }
die() { echo "[SANITY][FAIL] $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

is_root() {
  [[ ${EUID:-999} -eq 0 ]]
}

# -------------------------
# load env (optional but preferred)
# -------------------------
load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
  else
    warn ".env not found at ${ENV_FILE} (some checks will be skipped)"
  fi
}

# -------------------------
# args
# -------------------------
ROLE="${INFRA_ROLE:-auto}"   # manager|vpn|app|auto
STRICT="${STRICT:-1}"        # 1 => fail on missing critical checks
VERBOSE="${VERBOSE:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="$2"; shift 2;;
    --non-strict) STRICT="0"; shift;;
    --verbose) VERBOSE="1"; shift;;
    *) die "Unknown arg: $1";;
  esac
done

# -------------------------
# detect role (best-effort)
# -------------------------
detect_role() {
  # if explicitly set
  if [[ "${ROLE}" != "auto" ]]; then
    echo "${ROLE}"
    return
  fi

  # manager if docker swarm control available
  if command -v docker >/dev/null 2>&1; then
    if docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null | grep -q true; then
      echo "manager"
      return
    fi
  fi

  # vpn if xray service exists
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -q '^xray\.service$'; then
      echo "vpn"
      return
    fi
  fi

  echo "app"
}

# -------------------------
# checks: manager (B)
# -------------------------
check_manager() {
  log "Role=manager checks (Swarm manager / Traefik / routing)"

  need_cmd docker
  need_cmd curl
  need_cmd jq

  # Swarm must be active
  docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active \
    || die "Docker Swarm is not active on this node"

  docker info --format '{{.Swarm.ControlAvailable}}' | grep -q true \
    || die "This node is not a Swarm manager (ControlAvailable=false)"

  # Network exists
  if ! docker network inspect traefik_swarm >/dev/null 2>&1; then
    die "Overlay network traefik_swarm not found (bootstrap not applied or wrong node)"
  fi

  # Stacks present (soft check for vpn stack)
  local stacks
  stacks="$(docker stack ls --format '{{.Name}}' | tr '\n' ' ')"
  [[ "${stacks}" == *"traefik"* ]] || die "Stack 'traefik' not found"
  [[ "${stacks}" == *"monitoring"* ]] || warn "Stack 'monitoring' not found"
  [[ "${stacks}" == *"swarmpit"* ]] || warn "Stack 'swarmpit' not found"
  [[ "${stacks}" == *"vpn"* ]] || warn "Stack 'vpn' not found (vpn-xray.yml not deployed?)"

  # Traefik service healthy-ish
  if ! docker service ls --format '{{.Name}} {{.Replicas}}' | grep -q '^traefik_traefik '; then
    die "Service traefik_traefik not found (stack deploy failed?)"
  fi

  # If WireGuard is used for upstream to DE: check handshake presence (best-effort)
  if command -v wg >/dev/null 2>&1; then
    if wg show >/dev/null 2>&1; then
      if ! wg show | grep -q 'peer:'; then
        warn "WireGuard has no peers (wg show shows no peers)"
      fi
    else
      warn "wg command exists but wg show failed"
    fi
  else
    warn "wg not installed; skipping WG handshake checks"
  fi

  # Domain + websocket router check (critical)
  local vpn_domain="${VPN_DOMAIN:-}"
  local ws_path="${VPN_WS_PATH:-/api/v1/stream}"

  if [[ -z "${vpn_domain}" ]]; then
  warn "VPN_DOMAIN is empty; skipping HTTPS checks on manager node"
  return
  fi

  log "Checking HTTPS reachability: https://${vpn_domain}/"
  local code_root
  code_root="$(curl -sS -o /dev/null -w '%{http_code}' "https://${vpn_domain}/" || true)"
  [[ "${code_root}" != "000" ]] || die "Cannot reach https://${vpn_domain}/ (TLS/DNS/CF/Traefik problem)"
  log "Root HTTP status: ${code_root}"

  # WebSocket path should NOT be 404 from edge if router exists.
  # We'll attempt a WS handshake. Expected: 101 (ideal) or 400/426/502, but NOT 404.
  log "Checking WS path routing (expect NOT 404): https://${vpn_domain}${ws_path}"
  local code_ws
  code_ws="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: SGVsbG9Xb3JsZA==' \
    "https://${vpn_domain}${ws_path}" || true)"

  if [[ "${code_ws}" == "404" || "${code_ws}" == "000" ]]; then
    die "WS route check failed: status=${code_ws}. Router likely missing or CF/Traefik not routing ${ws_path}"
  fi
  log "WS route HTTP status: ${code_ws} (ok if not 404)"

  # Upstream TCP reachability from B to DE via WireGuard (optional, but recommended)
  local upstream_ip="${VPN_UPSTREAM_WG_IP:-}"
  local upstream_port="${VPN_XRAY_PORT:-10000}"
  if [[ -n "${upstream_ip}" ]]; then
    need_cmd nc
    log "Checking upstream TCP reachability: ${upstream_ip}:${upstream_port}"
    if ! nc -z -w 2 "${upstream_ip}" "${upstream_port}" >/dev/null 2>&1; then
      die "Cannot reach upstream ${upstream_ip}:${upstream_port} from manager (WireGuard route/firewall/service down)"
    fi
    log "Upstream TCP: OK"
  else
    warn "VPN_UPSTREAM_WG_IP not set; skipping direct upstream TCP check (set it to DE WG IP for stronger verification)"
  fi
}

# -------------------------
# checks: vpn node (DE)
# -------------------------
check_vpn() {
  log "Role=vpn checks (Xray node / systemd / bind / WireGuard presence)"

  need_cmd systemctl
  need_cmd ss
  need_cmd jq

  # xray service active
  systemctl is-active --quiet xray || die "xray service is not active"

  # config valid json
  if [[ -f /etc/xray/config.json ]]; then
    jq . /etc/xray/config.json >/dev/null || die "/etc/xray/config.json is not valid JSON"
  else
    die "/etc/xray/config.json not found"
  fi

  # listening port check
  local port="${VPN_XRAY_PORT:-10000}"
  local bind_ip="${VPN_WG_BIND_IP:-}"
  log "Checking xray listen on port=${port} (bind_ip=${bind_ip:-any})"

  if [[ -n "${bind_ip}" ]]; then
    ss -lntp | grep -E ":${port}\b" | grep -q "${bind_ip}" \
      || die "xray is not listening on ${bind_ip}:${port} (check config listen/bind)"
  else
    ss -lntp | grep -E ":${port}\b" >/dev/null \
      || die "xray is not listening on port ${port}"
  fi

  # WireGuard interface check (best-effort)
  if command -v wg >/dev/null 2>&1; then
    if ! wg show >/dev/null 2>&1; then
      warn "wg show failed; WireGuard may be down"
    fi
  else
    warn "wg not installed; skipping WG checks"
  fi

  log "VPN node checks: OK"
}

# -------------------------
# main
# -------------------------
main() {
  load_env
  local detected
  detected="$(detect_role)"

  # infra is an alias for manager
  if [[ "${detected}" == "infra" ]]; then
    detected="manager"
  fi

  log "Detected role: ${detected} (override via INFRA_ROLE or --role)"

  case "${detected}" in
    manager) check_manager;;
    vpn) check_vpn;;
    app) log "Role=app: no specific checks defined (ok)";;
    *) die "Unknown role: ${detected}";;
  esac

  log "All checks passed"
}

main