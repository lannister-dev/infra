#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

log()  { echo "[SANITY] $*"; }
warn() { echo "[SANITY][WARN] $*" >&2; }
die()  { echo "[SANITY][FAIL] $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

# -------------------------
# load env (optional but preferred)
# -------------------------
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  warn ".env not found at ${ENV_FILE} (some checks will be skipped)"
fi

# -------------------------
# args
# -------------------------
ROLE="${INFRA_ROLE:-auto}"   # manager|vpn|app|auto
STRICT="${STRICT:-1}"        # 1 => fail if critical vars missing
VERBOSE="${VERBOSE:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:-}"; shift 2 ;;
    --strict) STRICT="1"; shift ;;
    --non-strict) STRICT="0"; shift ;;
    --verbose) VERBOSE="1"; shift ;;
    *) die "Unknown arg: $1" ;;
  esac
done

# -------------------------
# detect role (best-effort)
# -------------------------
detect_role() {
  # honor explicit role
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
# checks: manager
# -------------------------
check_manager() {
  log "Role=manager checks (Swarm manager / Traefik / routing)"

  need_cmd docker
  need_cmd curl
  need_cmd jq

  docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active \
    || die "Docker Swarm is not active on this node"

  docker info --format '{{.Swarm.ControlAvailable}}' | grep -q true \
    || die "This node is not a Swarm manager (ControlAvailable=false)"

  # overlay network
  docker network inspect traefik_swarm >/dev/null 2>&1 \
    || die "Overlay network traefik_swarm not found (run bootstrap on manager)"

  # stacks presence
  local stacks
  stacks="$(docker stack ls --format '{{.Name}}' | tr '\n' ' ')"
  [[ "${stacks}" == *"traefik"* ]] || die "Stack 'traefik' not found"
  [[ "${stacks}" == *"monitoring"* ]] || warn "Stack 'monitoring' not found"
  [[ "${stacks}" == *"swarmpit"* ]] || warn "Stack 'swarmpit' not found"
  [[ "${stacks}" == *"vpn"* ]] || warn "Stack 'vpn' not found (vpn-xray.yml not deployed?)"

  # traefik service exists
  docker service ls --format '{{.Name}} {{.Replicas}}' | grep -q '^traefik_traefik ' \
    || die "Service traefik_traefik not found (stack deploy failed?)"

  # domain checks (soft if missing)
  local vpn_domain="${VPN_DOMAIN:-}"
  local ws_path="${VPN_WS_PATH:-/api/v1/stream}"

  if [[ -z "${vpn_domain}" ]]; then
    warn "VPN_DOMAIN is empty; skipping HTTPS checks on manager node"
    [[ "${STRICT}" == "1" ]] && die "Set VPN_DOMAIN in .env for full verification"
    return
  fi

  # root should be reachable (fallback page recommended)
  log "Checking HTTPS reachability: https://${vpn_domain}/"
  local code_root
  code_root="$(curl -sS -o /dev/null -w '%{http_code}' "https://${vpn_domain}/" || true)"
  [[ "${code_root}" != "000" ]] || die "Cannot reach https://${vpn_domain}/ (DNS/TLS/CF/Traefik)"
  log "Root HTTP status: ${code_root} (ok)"

  # ws path routing: should not be 404/000 at edge
  log "Checking WS route (expect NOT 404): https://${vpn_domain}${ws_path}"
  local code_ws
  code_ws="$(curl -sS -o /dev/null -w '%{http_code}' \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: SGVsbG9Xb3JsZA==' \
    "https://${vpn_domain}${ws_path}" || true)"

  if [[ "${code_ws}" == "404" || "${code_ws}" == "000" ]]; then
    die "WS route check failed: status=${code_ws}. Traefik/CF not routing ${ws_path}"
  fi
  log "WS route HTTP status: ${code_ws} (ok if not 404)"

  # optional: upstream reachability over WG
  local upstream_ip="${VPN_UPSTREAM_WG_IP:-}"
  local upstream_port="${VPN_XRAY_PORT:-10000}"
  if [[ -n "${upstream_ip}" ]]; then
    need_cmd nc
    log "Checking upstream TCP reachability: ${upstream_ip}:${upstream_port}"
    nc -z -w 2 "${upstream_ip}" "${upstream_port}" >/dev/null 2>&1 \
      || die "Cannot reach upstream ${upstream_ip}:${upstream_port} from manager (WG route/firewall/xray)"
    log "Upstream TCP: OK"
  else
    warn "VPN_UPSTREAM_WG_IP not set; skipping direct upstream TCP check"
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

  # xray active
  systemctl is-active --quiet xray || die "xray service is not active"

  # config path contract: /etc/xray/config.json
  [[ -f /etc/xray/config.json ]] || die "/etc/xray/config.json not found (run vpn/install.sh)"
  jq . /etc/xray/config.json >/dev/null || die "/etc/xray/config.json is not valid JSON"

  # listen check
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

  # wireguard best-effort
  if command -v wg >/dev/null 2>&1; then
    wg show >/dev/null 2>&1 || warn "wg show failed; WireGuard may be down"
  else
    warn "wg not installed; skipping WG checks"
  fi

  log "VPN node checks: OK"
}

# -------------------------
# main
# -------------------------
main() {
  local detected
  detected="$(detect_role)"

  # infra alias
  if [[ "${detected}" == "infra" ]]; then
    detected="manager"
  fi

  log "Detected role: ${detected} (override via INFRA_ROLE or --role)"

  case "${detected}" in
    manager) check_manager ;;
    vpn)     check_vpn ;;
    app)     log "Role=app: no specific checks defined (ok)" ;;
    *)       die "Unknown role: ${detected}" ;;
  esac

  log "All checks passed"
}

main