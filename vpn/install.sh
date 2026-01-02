#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

log() { echo "[VPN] $*"; }
die() { echo "[VPN][ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root"

[[ -f "${ENV_FILE}" ]] || die ".env not found at ${ENV_FILE}"
set -a
source "${ENV_FILE}"
set +a

# ==============================
# REQUIRED ENV (SOURCE OF TRUTH)
# ==============================
: "${VPN_WS_PATH:?VPN_WS_PATH is required}"
: "${VPN_WG_BIND_IP:?VPN_WG_BIND_IP is required}"
: "${VPN_XRAY_PORT:?VPN_XRAY_PORT is required}"

CLIENTS_FILE="${ROOT_DIR}/vpn/xray/clients.json"
[[ -f "${CLIENTS_FILE}" ]] || die "clients.json not found: ${CLIENTS_FILE}"

log "Installing Xray (WS, no TLS) bind=${VPN_WG_BIND_IP}:${VPN_XRAY_PORT}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl jq uuid-runtime

# ==============================
# INSTALL XRAY
# ==============================
if ! command -v xray >/dev/null 2>&1; then
  log "Installing Xray"
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
fi

# ==============================
# RENDER VALID JSON CONFIG
# ==============================
log "Rendering Xray config"
mkdir -p /etc/xray

VPN_CLIENTS_JSON="$(jq -c . "${CLIENTS_FILE}")"

jq -n \
  --arg listen "${VPN_WG_BIND_IP}" \
  --arg ws_path "${VPN_WS_PATH}" \
  --argjson port "${VPN_XRAY_PORT}" \
  --argjson clients "${VPN_CLIENTS_JSON}" \
  '{
    log: { loglevel: "warning" },
    inbounds: [{
      listen: $listen,
      port: $port,
      protocol: "vless",
      settings: {
        clients: $clients,
        decryption: "none"
      },
      streamSettings: {
        network: "ws",
        security: "none",
        wsSettings: {
          path: $ws_path
        }
      }
    }],
    outbounds: [{
      protocol: "freedom",
      settings: {}
    }]
  }' > /etc/xray/config.json

chmod 600 /etc/xray/config.json

# sanity: JSON must be valid
jq . /etc/xray/config.json >/dev/null || die "Generated config.json is invalid"

# ==============================
# START SERVICE
# ==============================
systemctl enable xray --now
systemctl restart xray

log "Xray installed and running"