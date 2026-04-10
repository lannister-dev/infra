#!/usr/bin/env bash
set -Eeuo pipefail

# One-time migration helper:
# imports already-existing Docker foundation resources into Terraform state.
# Not required for regular day-2 operations or CI/CD deploy flow.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_FOUNDATION_DIR="${TF_FOUNDATION_DIR:-${ROOT_DIR}/terraform/foundation}"

log() { echo "[TF-IMPORT] $*"; }

tf_state_has() {
  local addr="$1"
  terraform -chdir="${TF_FOUNDATION_DIR}" state show "$addr" >/dev/null 2>&1
}

tf_import_if_present() {
  local addr="$1"
  local id="$2"

  if tf_state_has "$addr"; then
    log "already in state: $addr"
    return
  fi

  if [[ -z "$id" ]]; then
    log "skip import (resource not found yet): $addr"
    return
  fi

  log "import: $addr <- $id"
  terraform -chdir="${TF_FOUNDATION_DIR}" import "$addr" "$id" >/dev/null
}

PROMETHEUS_CONFIG_VERSION="${PROMETHEUS_CONFIG_VERSION:-V1_4}"
GRAFANA_INI_VERSION="${GRAFANA_INI_VERSION:-V1_0}"
GRAFANA_DATASOURCES_VERSION="${GRAFANA_DATASOURCES_VERSION:-V1_1}"
GRAFANA_DASHBOARDS_VERSION="${GRAFANA_DASHBOARDS_VERSION:-V1_0}"
XRAY_CONFIG_VERSION="${XRAY_CONFIG_VERSION:-V3_2}"
XRAY_CONFIG_DEV_VERSION="${XRAY_CONFIG_DEV_VERSION:-V2_9}"
VPN_FALLBACK_INDEX_VERSION="${VPN_FALLBACK_INDEX_VERSION:-V1_1}"
VPN_FALLBACK_NGINX_CONFIG_VERSION="${VPN_FALLBACK_NGINX_CONFIG_VERSION:-V1_1}"
ENABLE_VPN_DEV_STACK="${ENABLE_VPN_DEV_STACK:-false}"

PROMETHEUS_CONFIG_NAME="prometheus_config__${PROMETHEUS_CONFIG_VERSION}"
GRAFANA_INI_CONFIG_NAME="grafana_ini__${GRAFANA_INI_VERSION}"
GRAFANA_DATASOURCES_CONFIG_NAME="grafana_datasources__${GRAFANA_DATASOURCES_VERSION}"
GRAFANA_DASHBOARDS_CONFIG_NAME="grafana_dashboards__${GRAFANA_DASHBOARDS_VERSION}"
XRAY_CONFIG_NAME="xray_config__${XRAY_CONFIG_VERSION}"
XRAY_CONFIG_DEV_NAME="xray_config_dev__${XRAY_CONFIG_DEV_VERSION}"
VPN_FALLBACK_INDEX_CONFIG_NAME="vpn_fallback_index__${VPN_FALLBACK_INDEX_VERSION}"
VPN_FALLBACK_NGINX_CONFIG_NAME="vpn_fallback_nginx_conf__${VPN_FALLBACK_NGINX_CONFIG_VERSION}"

log "sync terraform state with existing swarm resources"

tf_import_if_present "docker_network.traefik_swarm" "$(docker network inspect -f '{{ .Id }}' traefik_swarm 2>/dev/null || true)"
tf_import_if_present "docker_network.monitoring" "$(docker network inspect -f '{{ .Id }}' monitoring 2>/dev/null || true)"
tf_import_if_present "docker_network.vpn_net" "$(docker network inspect -f '{{ .Id }}' vpn-net 2>/dev/null || true)"

tf_import_if_present "docker_volume.traefik_acme" "$(docker volume inspect -f '{{ .Name }}' traefik_acme 2>/dev/null || true)"
tf_import_if_present "docker_volume.prometheus_data" "$(docker volume inspect -f '{{ .Name }}' prometheus_data 2>/dev/null || true)"
tf_import_if_present "docker_volume.grafana_data" "$(docker volume inspect -f '{{ .Name }}' grafana_data 2>/dev/null || true)"

tf_import_if_present "docker_config.prometheus_config" "$(docker config inspect -f '{{ .ID }}' "${PROMETHEUS_CONFIG_NAME}" 2>/dev/null || true)"
tf_import_if_present "docker_config.grafana_ini_config" "$(docker config inspect -f '{{ .ID }}' "${GRAFANA_INI_CONFIG_NAME}" 2>/dev/null || true)"
tf_import_if_present "docker_config.grafana_datasources_config" "$(docker config inspect -f '{{ .ID }}' "${GRAFANA_DATASOURCES_CONFIG_NAME}" 2>/dev/null || true)"
tf_import_if_present "docker_config.grafana_dashboards_config" "$(docker config inspect -f '{{ .ID }}' "${GRAFANA_DASHBOARDS_CONFIG_NAME}" 2>/dev/null || true)"
tf_import_if_present "docker_config.xray_config" "$(docker config inspect -f '{{ .ID }}' "${XRAY_CONFIG_NAME}" 2>/dev/null || true)"
tf_import_if_present "docker_config.vpn_fallback_index" "$(docker config inspect -f '{{ .ID }}' "${VPN_FALLBACK_INDEX_CONFIG_NAME}" 2>/dev/null || true)"
tf_import_if_present "docker_config.vpn_fallback_nginx_conf" "$(docker config inspect -f '{{ .ID }}' "${VPN_FALLBACK_NGINX_CONFIG_NAME}" 2>/dev/null || true)"

tf_import_if_present "docker_config.xray_config_dev" "$(docker config inspect -f '{{ .ID }}' "${XRAY_CONFIG_DEV_NAME}" 2>/dev/null || true)"

log "state sync done"
