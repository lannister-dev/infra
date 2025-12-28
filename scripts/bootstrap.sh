#!/usr/bin/env bash
set -euo pipefail

echo "=== Docker Swarm bootstrap (immutable configs) ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------- PRECHECKS ----------
echo "[0/7] Prechecks"

command -v docker >/dev/null || { echo "❌ Docker not installed"; exit 1; }
command -v sha256sum >/dev/null || { echo "❌ sha256sum required"; exit 1; }

docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active || {
  echo "❌ Docker Swarm is not initialized"
  exit 1
}

# ---------- NETWORK ----------
echo "[1/7] Ensure traefik_swarm network"

docker network inspect traefik_swarm >/dev/null 2>&1 || \
docker network create --driver overlay --attachable traefik_swarm >/dev/null

# ---------- HELPERS ----------
hash8() {
  sha256sum "$1" | awk '{print substr($1,1,8)}'
}

ensure_file() {
  [ -f "$1" ] || { echo "❌ File not found: $1"; exit 1; }
}

create_config_versioned() {
  local base="$1"
  local file="$2"

  ensure_file "$file"

  local hash name
  hash="$(hash8 "$file")"
  name="${base}_${hash}"

  if docker config inspect "$name" >/dev/null 2>&1; then
    echo "✔ config exists: $name"
  else
    echo "➕ creating config: $name"
    docker config create "$name" "$file" >/dev/null
  fi

  echo "$name"
}

update_service_config() {
  local service="$1"
  local alias="$2"
  local new_config="$3"
  local target="$4"

  echo "🔁 Updating $service: $alias → $new_config"

  docker service update \
    --config-rm "$alias" \
    --config-add "source=$new_config,target=$target" \
    "$service" >/dev/null
}

# ---------- CONFIGS ----------
echo "[2/7] Create versioned configs"

TRAEFIK_TLS_CFG=$(create_config_versioned traefik_tls \
  "$ROOT_DIR/docker/traefik/tls.yaml")

PROM_CFG=$(create_config_versioned prometheus_config \
  "$ROOT_DIR/monitoring/prometheus/prometheus.yml")

GRAF_INI_CFG=$(create_config_versioned grafana_ini \
  "$ROOT_DIR/monitoring/grafana/grafana.ini")

GRAF_DS_CFG=$(create_config_versioned grafana_datasources \
  "$ROOT_DIR/monitoring/grafana/provisioning/datasources/prometheus.yml")

GRAF_DB_CFG=$(create_config_versioned grafana_dashboards \
  "$ROOT_DIR/monitoring/grafana/provisioning/dashboards/dashboards.yml")

# ---------- VOLUMES ----------
echo "[3/7] Ensure volumes"

docker volume inspect prometheus_data >/dev/null 2>&1 || docker volume create prometheus_data >/dev/null
docker volume inspect grafana_data >/dev/null 2>&1 || docker volume create grafana_data >/dev/null
docker volume inspect traefik_acme >/dev/null 2>&1 || docker volume create traefik_acme >/dev/null

# ---------- STACK DEPLOY ----------
echo "[4/7] Deploy stacks"

docker stack deploy -c docker/stacks/traefik.yml traefik
docker stack deploy -c docker/stacks/monitoring.yml monitoring

sleep 5

# ---------- CONFIG REBIND ----------
echo "[5/7] Rebind configs to services"

update_service_config traefik_traefik \
  traefik_tls "$TRAEFIK_TLS_CFG" /etc/traefik/tls.yaml

update_service_config monitoring_prometheus \
  prometheus_config "$PROM_CFG" /etc/prometheus/prometheus.yml

update_service_config monitoring_grafana \
  grafana_ini "$GRAF_INI_CFG" /etc/grafana/grafana.ini

update_service_config monitoring_grafana \
  grafana_datasources "$GRAF_DS_CFG" /etc/grafana/provisioning/datasources/prometheus.yml

update_service_config monitoring_grafana \
  grafana_dashboards "$GRAF_DB_CFG" /etc/grafana/provisioning/dashboards/dashboards.yml

# ---------- DONE ----------
echo "[6/7] Active configs:"
docker config ls | grep -E 'traefik_tls|prometheus_config|grafana_'

echo "[7/7] Bootstrap completed successfully"