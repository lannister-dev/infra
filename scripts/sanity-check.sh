#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE=".env"

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
VERBOSE="${VERBOSE:-0}"      # 1 => extra logs

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
# edge mode: vpn|web
# vpn: allow insecure TLS for edge checks (VPN endpoint may use any cert chain / CF state)
# web: strict TLS checks (regular website semantics)
# -------------------------
VPN_EDGE_MODE="${VPN_EDGE_MODE:-vpn}"
case "${VPN_EDGE_MODE}" in
  vpn|web) : ;;
  *)
    warn "Invalid VPN_EDGE_MODE='${VPN_EDGE_MODE}', falling back to 'vpn'"
    VPN_EDGE_MODE="vpn"
    ;;
esac

if [[ "${VERBOSE}" == "1" ]]; then
  log "Config: ROLE=${ROLE}, STRICT=${STRICT}, VPN_EDGE_MODE=${VPN_EDGE_MODE}"
fi

# -------------------------
# detect role (best-effort)
# -------------------------
detect_role() {
  if [[ "${ROLE}" != "auto" ]]; then
    echo "${ROLE}"
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    if docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null | grep -q true; then
      echo "manager"
      return
    fi
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -q '^xray\.service$'; then
      echo "vpn"
      return
    fi
  fi

  echo "app"
}

# -------------------------
# helper: curl wrapper for edge mode
# -------------------------
curl_edge() {
  # usage: curl_edge <url> [extra curl args...]
  local url="$1"; shift || true
  if [[ "${VPN_EDGE_MODE}" == "vpn" ]]; then
    # VPN edge: do not fail due to CA chain issues on runners; prefer WS compatibility
    curl -k --http1.1 "$url" "$@"
  else
    curl "$url" "$@"
  fi
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

  docker network inspect traefik_swarm >/dev/null 2>&1 \
    || die "Overlay network traefik_swarm not found (run bootstrap on manager)"

  local stacks
  stacks="$(docker stack ls --format '{{.Name}}' | tr '\n' ' ')"
  [[ "${stacks}" == *"traefik"* ]] || die "Stack 'traefik' not found"
  [[ "${stacks}" == *"monitoring"* ]] || warn "Stack 'monitoring' not found"
  [[ "${stacks}" == *"swarmpit"* ]] || warn "Stack 'swarmpit' not found"
  [[ "${stacks}" == *"vpn"* ]] || warn "Stack 'vpn' not found (vpn-xray.yml not deployed?)"

  docker service ls --format '{{.Name}} {{.Replicas}}' | grep -q '^traefik_traefik ' \
    || die "Service traefik_traefik not found (stack deploy failed?)"

  local vpn_domain="${VPN_DOMAIN:-}"
  local ws_path="${VPN_WS_PATH:-/api/v1/stream}"

  if [[ -z "${vpn_domain}" ]]; then
    warn "VPN_DOMAIN is empty; skipping edge HTTPS checks"
    [[ "${STRICT}" == "1" ]] && die "Set VPN_DOMAIN in .env for full verification"
    return
  fi

  # In web mode, root check is meaningful; in vpn mode it is not.
  if [[ "${VPN_EDGE_MODE}" == "web" ]]; then
    log "Checking HTTPS reachability (web mode): https://${vpn_domain}/"
    local code_root
    code_root="$(curl -sS -o /dev/null -w '%{http_code}' "https://${vpn_domain}/" || true)"
    [[ "${code_root}" != "000" ]] || die "Cannot reach https://${vpn_domain}/ (DNS/TLS/edge)"
    log "Root HTTP status: ${code_root}"
  else
    log "VPN edge mode: skipping HTTPS root check (not a web endpoint)"
  fi

  # Quick TCP check: separates DNS/TCP failure from TLS/Traefik
  # (Runs only if curl can resolve; still useful as a fast fail)
  if command -v nc >/dev/null 2>&1; then
    log "Checking TCP/443 reachability: ${vpn_domain}:443"
    nc -z -w 3 "${vpn_domain}" 443 >/dev/null 2>&1 || warn "TCP/443 check failed (DNS/TCP/firewall). Curl may still provide details."
  fi

  # WS route check
  log "Checking WS route presence (Traefik-level only): ${vpn_domain}${ws_path}"

  code_ws="$(curl -k -sS -o /dev/null -w '%{http_code}' \
    "https://${vpn_domain}${ws_path}" || true)"

  if [[ "${code_ws}" == "000" ]]; then
    die "WS route unreachable (000). DNS/TLS/Traefik failure"
  fi

  log "WS edge reachable (HTTP ${code_ws}); protocol-level handling delegated to Xray"

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

  systemctl is-active --quiet xray || die "xray service is not active"

  [[ -f /etc/xray/config.json ]] || die "/etc/xray/config.json not found (run vpn/install.sh)"
  jq . /etc/xray/config.json >/dev/null || die "/etc/xray/config.json is not valid JSON"

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
