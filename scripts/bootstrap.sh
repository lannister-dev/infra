#!/usr/bin/env bash
set -euo pipefail

echo "=== Docker Swarm bootstrap ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------- PRECHECKS ----------
echo "[0/6] Prechecks"

command -v docker >/dev/null || {
  echo "Docker is not installed"
  exit 1
}
docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active || {
  echo "Docker Swarm is not initialized"
  echo "Run: docker swarm init"
  exit 1
}

# ---------- NETWORK ----------
echo "[1/6] Ensure traefik_swarm network"

docker network inspect traefik_swarm >/dev/null 2>&1 || \
docker network create \
  --driver overlay \
  --attachable \
  traefik_swarm

# ---------- CONFIGS ----------
echo "[2/6] Ensure Docker configs"

create_config() {
  local name="$1"
  local file="$2"

  if [ ! -f "$file" ]; then
    echo "❌ Config file not found: $file"
    exit 1
  fi

  docker config inspect "$name" >/dev/null 2>&1 && {
    echo "✔ config $name exists"
    return
  }

  echo "➕ creating config $name"
  docker config create "$name" "$file"
}

create_config traefik_tls \
  "$ROOT_DIR/docker/traefik/tls.yaml"

create_config prometheus_config \
  "$ROOT_DIR/monitoring/prometheus/prometheus.yml"

create_config grafana_ini \
  "$ROOT_DIR/monitoring/grafana/grafana.ini"

create_config grafana_datasources \
  "$ROOT_DIR/monitoring/grafana/provisioning/datasources/prometheus.yml"

create_config grafana_dashboards \
  "$ROOT_DIR/monitoring/grafana/provisioning/dashboards/dashboards.yml"

# ---------- VOLUMES ----------
echo "[3/6] Ensure volumes"

docker volume inspect prometheus_data >/dev/null 2>&1 || docker volume create prometheus_data
docker volume inspect grafana_data >/dev/null 2>&1 || docker volume create grafana_data
docker volume inspect traefik_acme >/dev/null 2>&1 || docker volume create traefik_acme

# ---------- SUMMARY ----------
echo "[4/6] Docker configs:"
docker config ls

echo "[5/6] Docker volumes:"
docker volume ls | grep -E 'prometheus_data|grafana_data|traefik_acme'

echo "[6/6] Bootstrap completed successfully"