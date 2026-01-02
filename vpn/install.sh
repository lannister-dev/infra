#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

log() { echo "[VPN] $*"; }
die() { echo "[VPN][ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root"

if [[ ! -f "${ENV_FILE}" ]]; then
  die ".env not found at ${ENV_FILE}. In CD you already write it from INFRA_ENV_PROD."
fi

set -a
source "${ENV_FILE}"
set +a

VPN_DOMAIN="${VPN_DOMAIN:-}"
VPN_EMAIL="${VPN_EMAIL:-}"
VLESS_PORT="${VLESS_PORT:-443}"
VLESS_WS_PATH="${VLESS_WS_PATH:-/api/v1/stream}"
VLESS_UUID="${VLESS_UUID:-auto}"
VLESS_FALLBACK_PORT="${VLESS_FALLBACK_PORT:-8080}"
TZ="${TZ:-Europe/Berlin}"

[[ -n "${VPN_DOMAIN}" ]] || die "VPN_DOMAIN is empty"
[[ -n "${VPN_EMAIL}" ]] || die "VPN_EMAIL is empty"

export VPN_DOMAIN VPN_EMAIL VLESS_PORT VLESS_WS_PATH VLESS_UUID VLESS_FALLBACK_PORT TZ

log "Installing VLESS (WS+TLS) on domain=${VPN_DOMAIN} port=${VLESS_PORT} path=${VLESS_WS_PATH}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  ca-certificates curl jq uuid-runtime \
  nginx certbot python3-certbot-nginx

timedatectl set-timezone "${TZ}" >/dev/null 2>&1 || true

# Install Xray if missing
if ! command -v xray >/dev/null 2>&1; then
  log "Installing Xray"
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
fi

# UUID generate if needed
if [[ "${VLESS_UUID}" == "auto" || -z "${VLESS_UUID}" ]]; then
  VLESS_UUID="$(uuidgen)"
  export VLESS_UUID
  log "Generated VLESS_UUID=${VLESS_UUID}"
fi

# Prepare web root (fallback site)
mkdir -p /var/www/vpn-fallback
cp -f "${ROOT_DIR}/vpn/nginx/index.html" /var/www/vpn-fallback/index.html

# TLS cert (only if not exists)
if [[ ! -d "/etc/letsencrypt/live/${VPN_DOMAIN}" ]]; then
  log "Issuing Let's Encrypt cert for ${VPN_DOMAIN}"
  certbot certonly \
    --nginx \
    -d "${VPN_DOMAIN}" \
    --non-interactive \
    --agree-tos \
    -m "${VPN_EMAIL}"
else
  log "Cert already exists for ${VPN_DOMAIN}"
fi

# Render nginx vhost
log "Rendering nginx vhost"
envsubst < "${ROOT_DIR}/vpn/nginx/vless.conf.j2" > /etc/nginx/sites-available/vless.conf
ln -sf /etc/nginx/sites-available/vless.conf /etc/nginx/sites-enabled/vless.conf
rm -f /etc/nginx/sites-enabled/default || true

nginx -t
systemctl enable nginx --now
systemctl reload nginx

# Render Xray config
log "Rendering xray config"
mkdir -p /etc/xray
envsubst < "${ROOT_DIR}/vpn/xray/config.json.j2" > /etc/xray/config.json
chmod 600 /etc/xray/config.json

# Restart Xray
systemctl enable xray --now
systemctl restart xray

# Show info
log "DONE. Client URI:"
echo "vless://${VLESS_UUID}@${VPN_DOMAIN}:${VLESS_PORT}?type=ws&security=tls&path=${VLESS_WS_PATH}&sni=${VPN_DOMAIN}#${VPN_DOMAIN}"