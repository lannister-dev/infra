#!/usr/bin/env bash
set -euo pipefail

echo "=== Docker Swarm bootstrap (hashed configs) ==="

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------- PRECHECKS ----------
echo "[0/7] Prechecks"

command -v docker >/dev/null || { echo "Docker is not installed"; exit 1; }

docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active || {
  echo "Docker Swarm is not initialized"
  echo "Run: docker swarm init"
  exit 1
}
command -v sha256sum >/dev/null || { echo "sha256sum is required"; exit 1; }

# ---------- NETWORK ----------
echo "[1/7] Ensure traefik_swarm network"
docker network inspect traefik_swarm >/dev/null 2>&1 || \
docker network create --driver overlay --attachable traefik_swarm >/dev/null

# ---------- HELPERS ----------
hash8() {
  # sha256(file) -> first 8 chars
  sha256sum "$1" | awk '{print substr($1,1,8)}'
}
ensure_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "❌ File not found: $file"
    exit 1
  fi
}
create_config_hashed() {
  # Usage: create_config_hashed <base_name> <file_path> <out_var_name>
  local base="$1"
  local file="$2"
  local outvar="$3"

  ensure_file "$file"

  local h
  h="$(hash8 "$file")"
  local name="${base}_${h}"

  if docker config inspect "$name" >/dev/null 2>&1; then
    echo "✔ config exists: $name"
  else
    echo "➕ creating config: $name  (from $file)"
    docker config create "$name" "$file" >/dev/null
  fi

  # Export for later stack deploy (compose variable substitution)
  export "$outvar=$name"
  echo "   -> export $outvar=$name"
}

# ---------- CONFIGS (HASHED) ----------
echo "[2/7] Ensure Docker configs (hashed + exported)"

create_config_hashed "traefik_tls" \
  "$ROOT_DIR/docker/traefik/tls.yaml" \
  "CFG_TRAEFIK_TLS"

create_config_hashed "prometheus_config" \
  "$ROOT_DIR/monitoring/prometheus/prometheus.yml" \
  "CFG_PROMETHEUS_CONFIG"

create_config_hashed "grafana_ini" \
  "$ROOT_DIR/monitoring/grafana/grafana.ini" \
  "CFG_GRAFANA_INI"

create_config_hashed "grafana_datasources" \
  "$ROOT_DIR/monitoring/grafana/provisioning/datasources/prometheus.yml" \
  "CFG_GRAFANA_DATASOURCES"

create_config_hashed "grafana_dashboards" \
  "$ROOT_DIR/monitoring/grafana/provisioning/dashboards/dashboards.yml" \
  "CFG_GRAFANA_DASHBOARDS"

# Optional: persist exports for GitHub Actions / manual shells
ENV_OUT="$ROOT_DIR/.bootstrap.env"
cat > "$ENV_OUT" <<EOF
CFG_TRAEFIK_TLS=${CFG_TRAEFIK_TLS}
CFG_PROMETHEUS_CONFIG=${CFG_PROMETHEUS_CONFIG}
CFG_GRAFANA_INI=${CFG_GRAFANA_INI}
CFG_GRAFANA_DATASOURCES=${CFG_GRAFANA_DATASOURCES}
CFG_GRAFANA_DASHBOARDS=${CFG_GRAFANA_DASHBOARDS}
EOF
echo "✔ wrote $ENV_OUT"

# ---------- VOLUMES ----------
echo "[3/7] Ensure volumes"
docker volume inspect prometheus_data >/dev/null 2>&1 || docker volume create prometheus_data >/dev/null
docker volume inspect grafana_data >/dev/null 2>&1 || docker volume create grafana_data >/dev/null
docker volume inspect traefik_acme >/dev/null 2>&1 || docker volume create traefik_acme >/dev/null

# ---------- SUMMARY ----------
echo "[4/7] Active hashed config names:"
printf "  %-22s %s\n" "traefik tls:" "$CFG_TRAEFIK_TLS"
printf "  %-22s %s\n" "prometheus:" "$CFG_PROMETHEUS_CONFIG"
printf "  %-22s %s\n" "grafana ini:" "$CFG_GRAFANA_INI"
printf "  %-22s %s\n" "grafana datasources:" "$CFG_GRAFANA_DATASOURCES"
printf "  %-22s %s\n" "grafana dashboards:" "$CFG_GRAFANA_DASHBOARDS"

echo "[5/7] Docker volumes:"
docker volume ls | grep -E 'prometheus_data|grafana_data|traefik_acme' || true

echo "[6/7] Done. Use the exported vars for stack deploy."
echo "    Example:"
echo "      source ./.bootstrap.env"
echo "      docker stack deploy -c docker/stacks/traefik.yml traefik"
echo "      docker stack deploy -c docker/stacks/monitoring.yml monitoring"

echo "[7/7] Bootstrap completed successfully"