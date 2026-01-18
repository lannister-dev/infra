#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

: "${VPN_DOMAIN:?}"
: "${VPN_WS_PATH:?}"
: "${VPN_XHTTP_PATH:?}"
: "${XRAY_SWARM_SERVICE:=vpn_xray}"

CLIENTS_FILE="/var/lib/vpn/clients.json"
TEMPLATE="$ROOT_DIR/vpn/xray/config.json.j2"

TMP_DIR="/tmp/xray-render"
RENDERED="$TMP_DIR/config.json"

VERSION="V$(date +%Y%m%d_%H%M%S)"
CONFIG_NAME="xray_config__${VERSION}"

mkdir -p "$TMP_DIR"

VPN_CLIENTS_JSON="$(jq -c . "$CLIENTS_FILE")"
export VPN_CLIENTS_JSON

envsubst < "$TEMPLATE" > "$RENDERED"
jq . "$RENDERED" >/dev/null

docker config create "$CONFIG_NAME" "$RENDERED"

OLD_CONFIG=$(docker service inspect "$XRAY_SWARM_SERVICE" \
  --format '{{range .Spec.TaskTemplate.ContainerSpec.Configs}}{{.ConfigName}}{{end}}')

docker service update \
  --config-rm "$OLD_CONFIG" \
  --config-add source="$CONFIG_NAME",target=/etc/xray/config.json,mode=0444 \
  "$XRAY_SWARM_SERVICE"

echo "✔ Xray updated → $CONFIG_NAME"