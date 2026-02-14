#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# add-node.sh — Add a VPN node to the cluster in one command.
#
# Runs FROM the manager. Does everything over SSH:
#   1. Install Docker
#   2. Set up WireGuard peer (manager ↔ node)
#   3. Join Swarm + label role=vpn + channel=dev|prod
#   4. Push registry auth → Swarm schedules xray + node-agent
#
# Usage:
#   ./scripts/add-node.sh <IP> --name <peer-name> [--channel dev|prod] [--user root] [--port 22]
# ============================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------- Parse args ----------
usage() {
  echo "Usage: $0 <IP> --name <peer-name> [--channel dev|prod] [--user root] [--port 22]"
  exit 1
}

REMOTE_IP="${1:-}"
[[ -n "${REMOTE_IP}" ]] || usage
shift

SSH_USER="root"
SSH_PORT="22"
NODE_NAME=""
NODE_CHANNEL="prod"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NODE_NAME="$2"; shift 2 ;;
    --channel) NODE_CHANNEL="$2"; shift 2 ;;
    --user) SSH_USER="$2"; shift 2 ;;
    --port) SSH_PORT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "${NODE_NAME}" ]] || usage
[[ "${NODE_CHANNEL}" == "dev" || "${NODE_CHANNEL}" == "prod" ]] || die "--channel must be dev or prod"

# ---------- Helpers ----------
log()  { echo "[ADD-NODE] $*"; }
warn() { echo "[ADD-NODE][WARN] $*" >&2; }
die()  { echo "[ADD-NODE][FAIL] $*" >&2; exit 1; }

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -p ${SSH_PORT}"
ssh_cmd()  { ssh ${SSH_OPTS} "${SSH_USER}@${REMOTE_IP}" "$@"; }
scp_to()   { scp ${SSH_OPTS} "$1" "${SSH_USER}@${REMOTE_IP}:$2"; }

WG_INTERFACE="wg0"
WG_CLIENT_CONF="/etc/wireguard/clients/${NODE_NAME}-${WG_INTERFACE}.conf"

# ---------- Pre-checks (local) ----------
[[ ${EUID:-999} -eq 0 ]] || die "Run as root"

docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null | grep -q true \
  || die "Not a Swarm manager"

command -v wg >/dev/null 2>&1 || die "WireGuard not installed on manager"

log "Adding node: ${NODE_NAME} (${REMOTE_IP}), channel=${NODE_CHANNEL}"

# ---------- 1. SSH check ----------
log "[1/5] Checking SSH..."
ssh_cmd "true" || die "Cannot SSH into ${SSH_USER}@${REMOTE_IP}:${SSH_PORT}"

# ---------- 2. Docker ----------
log "[2/5] Installing Docker..."
ssh_cmd bash <<'EOF'
if command -v docker >/dev/null 2>&1; then
  echo "Docker already installed"
else
  export DEBIAN_FRONTEND=noninteractive
  curl -fsSL https://get.docker.com | sh
fi
EOF

# ---------- 3. WireGuard ----------
log "[3/5] Setting up WireGuard..."

# Add peer on manager side (idempotent)
if [[ -f "${WG_CLIENT_CONF}" ]]; then
  log "WG peer '${NODE_NAME}' already exists on manager"
else
  bash "${ROOT_DIR}/wireguard/apply.sh" --add "${NODE_NAME}"
fi

[[ -f "${WG_CLIENT_CONF}" ]] || die "Client config not found: ${WG_CLIENT_CONF}"

# Extract the allocated WG IP
WG_NODE_IP=$(grep -oP 'Address\s*=\s*\K[0-9.]+' "${WG_CLIENT_CONF}")
log "WG IP: ${WG_NODE_IP}"

# Install WG on remote, push config, start
ssh_cmd bash <<'EOF'
export DEBIAN_FRONTEND=noninteractive
if ! command -v wg >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y wireguard wireguard-tools
fi
mkdir -p /etc/wireguard
EOF

scp_to "${WG_CLIENT_CONF}" "/etc/wireguard/${WG_INTERFACE}.conf"

ssh_cmd bash <<WGSTART
chmod 600 /etc/wireguard/${WG_INTERFACE}.conf
systemctl enable --now wg-quick@${WG_INTERFACE} 2>/dev/null || wg-quick up ${WG_INTERFACE} 2>/dev/null || true
systemctl restart wg-quick@${WG_INTERFACE} 2>/dev/null || true
WGSTART

# Verify mesh
sleep 3
if ping -c 2 -W 3 "${WG_NODE_IP}" >/dev/null 2>&1; then
  log "WG mesh OK: manager <-> ${WG_NODE_IP}"
else
  warn "Cannot ping ${WG_NODE_IP} yet — may need a few seconds"
fi

# ---------- 4. Swarm join + label ----------
log "[4/5] Joining Swarm..."

SWARM_STATE=$(ssh_cmd "docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null" || echo "inactive")

if [[ "${SWARM_STATE}" == "active" ]]; then
  log "Already in Swarm"
else
  JOIN_TOKEN=$(docker swarm join-token worker -q)
  MANAGER_ADDR=$(docker node inspect self --format '{{.ManagerStatus.Addr}}')
  ssh_cmd "docker swarm join --token ${JOIN_TOKEN} ${MANAGER_ADDR}"
fi

sleep 2

NODE_ID=$(docker node ls --format '{{.ID}} {{.Hostname}}' | grep -i "${NODE_NAME}" | awk '{print $1}')
[[ -n "${NODE_ID}" ]] || die "Node '${NODE_NAME}' not found in swarm (docker node ls)"

docker node update --label-add role=vpn "${NODE_ID}" >/dev/null
docker node update --label-add channel="${NODE_CHANNEL}" "${NODE_ID}" >/dev/null
log "Labeled ${NODE_NAME}: role=vpn, channel=${NODE_CHANNEL}"

# ---------- 5. Registry auth ----------
log "[5/5] Pushing registry auth..."
for service in vpn_xray vpn_node-agent vpn-dev_xray; do
  docker service update --with-registry-auth --detach "${service}" >/dev/null 2>&1 || true
done

# ---------- Done ----------
log ""
log "Done. ${NODE_NAME} (${REMOTE_IP}) added."
log "  WireGuard IP : ${WG_NODE_IP}"
log "  Swarm Node   : ${NODE_ID}"
log ""
log "Swarm is scheduling xray + node-agent now (matching by channel label)."
log "Check prod: docker service ps vpn_xray && docker service ps vpn_node-agent"
log "Check dev : docker service ps vpn-dev_xray"
