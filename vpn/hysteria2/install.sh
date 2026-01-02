#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

log() { echo "[HY2] $*"; }
die() { echo "[HY2][ERROR] $*" >&2; exit 1; }

[[ ${EUID:-999} -eq 0 ]] || die "Run as root"
[[ -f "${ENV_FILE}" ]] || die ".env not found at ${ENV_FILE}"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

: "${HY2_AUTH_PASSWORD:?HY2_AUTH_PASSWORD is required}"
: "${HY2_OBFS_PASSWORD:?HY2_OBFS_PASSWORD is required}"

HY2_LISTEN_PORT="${HY2_LISTEN_PORT:-443}"
HY2_SNI="${HY2_SNI:-cloudflare.com}"

export HY2_LISTEN_PORT HY2_AUTH_PASSWORD HY2_OBFS_PASSWORD HY2_SNI

log "Installing Hysteria2 on UDP/${HY2_LISTEN_PORT} (self-signed TLS, obfs=salamander)"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl openssl

# Install hysteria2 binary if missing
if ! command -v hysteria >/dev/null 2>&1; then
  log "Installing hysteria2 binary"
  # Official release script (simple, reliable)
  bash <(curl -fsSL https://get.hy2.sh/) || die "hysteria2 install failed"
fi

# Prepare dirs
mkdir -p /etc/hysteria
chmod 700 /etc/hysteria

# Generate self-signed cert if missing
if [[ ! -f /etc/hysteria/cert.pem || ! -f /etc/hysteria/key.pem ]]; then
  log "Generating self-signed TLS cert"
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout /etc/hysteria/key.pem \
    -out /etc/hysteria/cert.pem \
    -subj "/CN=${HY2_SNI}" >/dev/null 2>&1
  chmod 600 /etc/hysteria/key.pem /etc/hysteria/cert.pem
fi

# Render config
log "Rendering config /etc/hysteria/config.yaml"
envsubst < "${ROOT_DIR}/vpn/hysteria2/config.yaml.j2" > /etc/hysteria/config.yaml
chmod 600 /etc/hysteria/config.yaml

# systemd unit
log "Installing systemd unit"
cat >/etc/systemd/system/hysteria2.service <<'EOF'
[Unit]
Description=Hysteria2 Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hysteria2 --now
systemctl restart hysteria2

# Open UDP port (best-effort). If ufw not used, this is harmless.
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${HY2_LISTEN_PORT}/udp" >/dev/null 2>&1 || true
fi

log "Hysteria2 installed and running"
log "Client URI (generic):"
echo "hysteria2://${HY2_AUTH_PASSWORD}@$(hostname -I | awk '{print $1}'):${HY2_LISTEN_PORT}/?insecure=1&obfs=salamander&obfs-password=${HY2_OBFS_PASSWORD}&sni=${HY2_SNI}#infra-hy2"