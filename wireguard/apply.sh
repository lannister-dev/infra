#!/usr/bin/env bash
set -Eeuo pipefail

### -----------------------------
### CONFIG
### -----------------------------
WG_DIR="/etc/wireguard"
WG_IFACE="wg0"
WG_CONF="${WG_DIR}/${WG_IFACE}.conf"
PRIVATE_KEY_FILE="${WG_DIR}/privatekey"

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
PEERS_FILE="${BASE_DIR}/peers.yml"
TEMPLATE_FILE="${BASE_DIR}/wg0.conf.j2"

NODE_NAME="${1:-}"

### -----------------------------
### HELPERS
### -----------------------------
log() {
  echo "[WG][INFO] $*"
}

fatal() {
  echo "[WG][ERROR] $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fatal "Command not found: $1"
}

### -----------------------------
### PRECHECKS
### -----------------------------
[ -z "$NODE_NAME" ] && fatal "Usage: ./apply.sh <NODE_NAME>"

require_cmd wg
require_cmd wg-quick
require_cmd python3

[ -f "$PEERS_FILE" ]        || fatal "Missing peers.yml"
[ -f "$TEMPLATE_FILE" ]     || fatal "Missing wg0.conf.j2"
[ -s "$PRIVATE_KEY_FILE" ]  || fatal "Missing private key: $PRIVATE_KEY_FILE"

log "Node: $NODE_NAME"
log "Base dir: $BASE_DIR"

PRIVATE_KEY="$(cat "$PRIVATE_KEY_FILE")"

### -----------------------------
### RENDER CONFIG
### -----------------------------
TMP_CONF="$(mktemp)"

python3 - <<EOF
import sys, yaml
from jinja2 import Template

with open("${PEERS_FILE}") as f:
    data = yaml.safe_load(f)

nodes = data.get("nodes", {})
if "${NODE_NAME}" not in nodes:
    print(f"Node '${NODE_NAME}' not found in peers.yml", file=sys.stderr)
    sys.exit(1)

with open("${TEMPLATE_FILE}") as f:
    tpl = Template(f.read())

print(tpl.render(
    node=nodes["${NODE_NAME}"],
    node_name="${NODE_NAME}",
    nodes=nodes,
    network=data.get("network", {}),
    private_key="${PRIVATE_KEY}",
))
EOF

chmod 600 "${TMP_CONF}"

### -----------------------------
### APPLY CONFIG (IDEMPOTENT)
### -----------------------------
if [ -f "${WG_CONF}" ]; then
  if diff -q "${WG_CONF}" "${TMP_CONF}" >/dev/null; then
    log "Config unchanged"
  else
    log "Config changed → updating"
    diff -u "${WG_CONF}" "${TMP_CONF}" || true
    cp "${TMP_CONF}" "${WG_CONF}"
  fi
else
  log "Installing new config"
  cp "${TMP_CONF}" "${WG_CONF}"
fi

rm -f "${TMP_CONF}"
chmod 600 "${WG_CONF}"

### -----------------------------
### START / RELOAD
### -----------------------------
if systemctl is-active --quiet "wg-quick@${WG_IFACE}"; then
  log "WireGuard already running → reloading"
  systemctl restart "wg-quick@${WG_IFACE}"
else
  log "Starting WireGuard"
  systemctl enable --now "wg-quick@${WG_IFACE}"
fi

### -----------------------------
### SANITY CHECK
### -----------------------------
log "WireGuard status:"
wg show

log "Done."