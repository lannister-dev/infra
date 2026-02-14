#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE=".env"

log()  { echo "[BOOTSTRAP] $*"; }
warn() { echo "[BOOTSTRAP][WARN] $*" >&2; }
die()  { echo "[BOOTSTRAP][FAIL] $*" >&2; exit 1; }

[[ ${EUID:-999} -eq 0 ]] || die "Run as root"

# -------------------------
# load env (optional)
# -------------------------
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  warn ".env not found at ${ENV_FILE} (role may be set externally)"
fi

INFRA_ROLE="${INFRA_ROLE:-infra}"   # infra|manager|vpn|app
if [[ "${INFRA_ROLE}" == "infra" ]]; then
  INFRA_ROLE="manager"
fi

log "Repo: ${ROOT_DIR}"
log "Role: ${INFRA_ROLE}"

# -------------------------
# ensure executable perms FIRST (kills 'Permission denied')
# -------------------------
chmod +x \
  "${ROOT_DIR}/scripts/bootstrap.sh" \
  "${ROOT_DIR}/scripts/sanity-check.sh" \
  "${ROOT_DIR}/scripts/firewall.sh" \
  "${ROOT_DIR}/wireguard/apply.sh" \
  "${ROOT_DIR}/wireguard/manager/wireguard-manager.sh" \
  2>/dev/null || true

# -------------------------
# role: manager (Swarm bootstrap + configs)
# -------------------------
bootstrap_manager() {
  log "Manager bootstrap: packages + swarm prechecks + network/volumes/configs"

  command -v docker >/dev/null 2>&1 || die "Docker is not installed"

  if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active; then
    die "Docker Swarm is not initialized (run: docker swarm init)"
  fi

  if ! docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null | grep -q true; then
    die "This node is not a Swarm manager (ControlAvailable=false)"
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    ca-certificates curl jq unzip zip \
    wireguard wireguard-tools iproute2 iptables qrencode gettext-base

  echo "=== Docker Swarm bootstrap (configs-first) ==="

  # -------------------------
  # CONFIG VERSIONS (SOURCE OF TRUTH)
  # -------------------------
  PROMETHEUS_CONFIG_VERSION="${PROMETHEUS_CONFIG_VERSION:-V1_4}"
  GRAFANA_INI_VERSION="${GRAFANA_INI_VERSION:-V1_0}"
  GRAFANA_DATASOURCES_VERSION="${GRAFANA_DATASOURCES_VERSION:-V1_1}"
  GRAFANA_DASHBOARDS_VERSION="${GRAFANA_DASHBOARDS_VERSION:-V1_0}"


  # XRAY CONFIG VERSION: bump this when you WANT to create a new Swarm config
  XRAY_CONFIG_VERSION="${XRAY_CONFIG_VERSION:-V3_1}"

  # Fallback assets
  VPN_FALLBACK_INDEX_VERSION="${VPN_FALLBACK_INDEX_VERSION:-V1_1}"
  VPN_FALLBACK_NGINX_CONFIG_VERSION="${VPN_FALLBACK_NGINX_CONFIG_VERSION:-V1_1}"

  # -------------------------
  # NETWORKS
  # -------------------------
  log "[1/5] Ensuring traefik_swarm network"
  docker network inspect traefik_swarm >/dev/null 2>&1 || \
    docker network create --driver overlay --attachable traefik_swarm >/dev/null

  log "[1/5] Ensuring monitoring network"
  docker network inspect monitoring >/dev/null 2>&1 || \
    docker network create --driver overlay --attachable monitoring >/dev/null

  log "[1/5] Ensuring vpn-net network"
  docker network inspect vpn-net >/dev/null 2>&1 || \
    docker network create --driver overlay --attachable vpn-net >/dev/null

  # -------------------------
  # VOLUMES
  # -------------------------
  log "[2/5] Ensuring volumes"
  for v in traefik_acme prometheus_data grafana_data; do
    docker volume inspect "$v" >/dev/null 2>&1 || docker volume create "$v" >/dev/null
  done

  # -------------------------
  # DOCKER CONFIGS (IMMUTABLE)
  # -------------------------
  log "[3/5] Ensuring docker configs (versioned)"

  ensure_config() {
    local name="$1"
    local file="$2"

    [[ -f "$file" ]] || die "Config source not found: $file"

    if docker config inspect "$name" >/dev/null 2>&1; then
      log "✔ config exists: $name"
    else
      log "➕ creating config: $name"
      docker config create "$name" "$file" >/dev/null
    fi
  }

  ensure_config "prometheus_config__${PROMETHEUS_CONFIG_VERSION}" \
    "$ROOT_DIR/monitoring/prometheus/prometheus.yml"

  ensure_config "grafana_ini__${GRAFANA_INI_VERSION}" \
    "$ROOT_DIR/monitoring/grafana/grafana.ini"

  ensure_config "grafana_datasources__${GRAFANA_DATASOURCES_VERSION}" \
    "$ROOT_DIR/monitoring/grafana/provisioning/datasources/prometheus.yml"

  ensure_config "grafana_dashboards__${GRAFANA_DASHBOARDS_VERSION}" \
    "$ROOT_DIR/monitoring/grafana/provisioning/dashboards/dashboards.yml"

  # -------------------------
  # XRAY CONFIG RENDER (FROM J2)
  # -------------------------
  log "[4/5] Rendering Xray config from template (clients managed via Xray API)"

  XRAY_RENDER_DIR="/tmp/xray"
  XRAY_RENDERED_CONFIG="${XRAY_RENDER_DIR}/config.json"
  mkdir -p "${XRAY_RENDER_DIR}"

  [[ -f "$ROOT_DIR/vpn/xray/config.json.j2" ]] \
    || die "Xray template not found: vpn/xray/config.json.j2"

  envsubst < "$ROOT_DIR/vpn/xray/config.json.j2" > "${XRAY_RENDERED_CONFIG}"

  jq . "${XRAY_RENDERED_CONFIG}" >/dev/null \
    || die "Rendered Xray config is invalid JSON"

  ensure_config "xray_config__${XRAY_CONFIG_VERSION}" \
    "${XRAY_RENDERED_CONFIG}"

  # -------------------------
  # VPN fallback assets
  # -------------------------
  if [[ -f "$ROOT_DIR/vpn/nginx/index.html" ]]; then
    ensure_config "vpn_fallback_index__${VPN_FALLBACK_INDEX_VERSION}" \
      "$ROOT_DIR/vpn/nginx/index.html"
  else
    warn "vpn/nginx/index.html not found; skipping vpn_fallback_index docker config"
  fi

  if [[ -f "$ROOT_DIR/vpn/nginx/server.conf" ]]; then
    ensure_config "vpn_fallback_nginx_conf__${VPN_FALLBACK_NGINX_CONFIG_VERSION}" \
      "$ROOT_DIR/vpn/nginx/server.conf"
  else
    die "vpn/nginx/server.conf not found (required for fallback)"
  fi

  # -------------------------
  # SUMMARY
  # -------------------------
  log "[5/5] Active docker configs:"
  docker config ls | grep -E 'prometheus_config__|grafana_|vpn_fallback_(index|nginx)_conf__|xray_config__' || true

  log "✅ Manager bootstrap completed successfully"
}

# -------------------------
# role: vpn (DE node) - WireGuard + Xray ONLY
# -------------------------
bootstrap_vpn() {
  log "VPN bootstrap: WireGuard (Xray runs as Swarm service)"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl jq wireguard wireguard-tools iproute2 iptables

  bash "${ROOT_DIR}/wireguard/apply.sh" --install

  log "✅ VPN bootstrap completed successfully"
}

# -------------------------
# role: app (placeholder)
# -------------------------
bootstrap_app() {
  log "App role: no bootstrap steps defined (ok)"
}

# -------------------------
# main
# -------------------------
case "${INFRA_ROLE}" in
  manager) bootstrap_manager ;;
  vpn)     bootstrap_vpn ;;
  app)     bootstrap_app ;;
  *)       die "Unknown INFRA_ROLE=${INFRA_ROLE} (expected: manager|vpn|app|infra)" ;;
esac
