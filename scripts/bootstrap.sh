#!/usr/bin/env bash
set -euo pipefail

echo "=== Docker Swarm bootstrap (standard approach) ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------- PRECHECKS ----------
echo "[0/6] Prechecks"

command -v docker >/dev/null || { echo "❌ Docker not installed"; exit 1; }

docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active || {
  echo "❌ Docker Swarm is not initialized"
  exit 1
}

# ---------- NETWORK ----------
echo "[1/6] Ensure traefik_swarm network"

docker network inspect traefik_swarm >/dev/null 2>&1 || \
docker network create --driver overlay --attachable traefik_swarm >/dev/null

# ---------- VOLUMES ----------
echo "[2/6] Ensure volumes"

docker volume inspect traefik_acme >/dev/null 2>&1 || docker volume create traefik_acme >/dev/null
docker volume inspect prometheus_data >/dev/null 2>&1 || docker volume create prometheus_data >/dev/null
docker volume inspect grafana_data >/dev/null 2>&1 || docker volume create grafana_data >/dev/null

# ---------- DOCKER CONFIGS ----------
echo "[3/6] Ensure docker configs (immutable names)"

create_config() {
  local name="$1"
  local file="$2"

  [ -f "$file" ] || { echo "❌ File not found: $file"; exit 1; }

  if docker config inspect "$name" >/dev/null 2>&1; then
    echo "✔ config exists: $name"
  else
    echo "➕ creating config: $name"
    docker config create "$name" "$file" >/dev/null
  fi
}

create_config prometheus_config \
  "$ROOT_DIR/monitoring/prometheus/prometheus.yml"

create_config grafana_ini \
  "$ROOT_DIR/monitoring/grafana/grafana.ini"

create_config grafana_datasources \
  "$ROOT_DIR/monitoring/grafana/provisioning/datasources/prometheus.yml"

create_config grafana_dashboards \
  "$ROOT_DIR/monitoring/grafana/provisioning/dashboards/dashboards.yml"


echo "[4/5] Active docker configs:"
docker config ls | grep -E 'prometheus_config|grafana_'

echo "[5/5] Bootstrap completed successfully"