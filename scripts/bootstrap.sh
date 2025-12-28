#!/usr/bin/env bash
set -euo pipefail

echo "=== Docker Swarm bootstrap (configs-first) ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ==============================
# CONFIG VERSIONS (SOURCE OF TRUTH)
# ==============================
PROMETHEUS_CONFIG_VERSION="V1_0"
GRAFANA_INI_VERSION="V1_0"
GRAFANA_DATASOURCES_VERSION="V1_0"
GRAFANA_DASHBOARDS_VERSION="V1_0"

# ==============================
# PRECHECKS
# ==============================
command -v docker >/dev/null || {
  echo "❌ Docker is not installed"
  exit 1
}

if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active; then
  echo "❌ Docker Swarm is not initialized"
  exit 1
fi

# ==============================
# NETWORKS
# ==============================
echo "[1/4] Ensuring traefik_swarm network"

docker network inspect traefik_swarm >/dev/null 2>&1 || \
docker network create --driver overlay --attachable traefik_swarm >/dev/null

# ==============================
# VOLUMES
# ==============================
echo "[2/4] Ensuring volumes"

for v in traefik_acme prometheus_data grafana_data; do
  docker volume inspect "$v" >/dev/null 2>&1 || docker volume create "$v" >/dev/null
done

# ==============================
# DOCKER CONFIGS (IMMUTABLE)
# ==============================
echo "[3/4] Ensuring docker configs (versioned)"

ensure_config() {
  local name="$1"
  local file="$2"

  if [[ ! -f "$file" ]]; then
    echo "❌ Config source not found: $file"
    exit 1
  fi

  if docker config inspect "$name" >/dev/null 2>&1; then
    echo "✔ config exists: $name"
  else
    echo "➕ creating config: $name"
    docker config create "$name" "$file" >/dev/null
  fi
}

ensure_config "prometheus_config__${PROMETHEUS_CONFIG_VERSION}" \
  "$ROOT_DIR/docker/monitoring/prometheus/prometheus.yml"

ensure_config "grafana_ini__${GRAFANA_INI_VERSION}" \
  "$ROOT_DIR/docker/monitoring/grafana/grafana.ini"

ensure_config "grafana_datasources__${GRAFANA_DATASOURCES_VERSION}" \
  "$ROOT_DIR/docker/monitoring/grafana/provisioning/datasources/prometheus.yml"

ensure_config "grafana_dashboards__${GRAFANA_DASHBOARDS_VERSION}" \
  "$ROOT_DIR/docker/monitoring/grafana/provisioning/dashboards/dashboards.yml"

# ==============================
# SUMMARY
# ==============================
echo "[4/4] Active docker configs:"
docker config ls | grep -E 'prometheus_config__|grafana_'

echo "✅ Bootstrap completed successfully"