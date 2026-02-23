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
#   ./scripts/legacy/add-node.sh <IP> --name <peer-name> [--channel dev|prod] [--user root] [--port 22]
# ============================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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
[[ "${NODE_CHANNEL}" == "dev" || "${NODE_CHANNEL}" == "prod" ]] || {
  echo "[ADD-NODE][FAIL] --channel must be dev or prod" >&2
  usage
}

# ---------- Helpers ----------
log()  { echo "[ADD-NODE] $*"; }
warn() { echo "[ADD-NODE][WARN] $*" >&2; }
die()  { echo "[ADD-NODE][FAIL] $*" >&2; exit 1; }

# Reuse the same SSH connection to avoid repeated password prompts (works for ssh + scp).
SSH_CONTROL_PATH="/tmp/vpn-infra-ssh-%r@%h:%p"
SSH_OPTS_COMMON=(
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
  -o ControlMaster=auto
  -o ControlPersist=10m
  -o "ControlPath=${SSH_CONTROL_PATH}"
)

SSH_OPTS_SSH=("${SSH_OPTS_COMMON[@]}" -p "${SSH_PORT}")
SSH_OPTS_SCP=("${SSH_OPTS_COMMON[@]}" -P "${SSH_PORT}")

# shellcheck disable=SC2029
ssh_cmd()  { ssh "${SSH_OPTS_SSH[@]}" "${SSH_USER}@${REMOTE_IP}" "$@"; }
scp_to()   {
  local src="$1"
  local dst="$2"
  local dst_dir
  # scp cannot create parent directories; ensure they exist first.
  dst_dir="$(dirname -- "${dst}")"
  ssh_cmd "install -d -m 700 -- '${dst_dir}'"
  scp "${SSH_OPTS_SCP[@]}" "${src}" "${SSH_USER}@${REMOTE_IP}:${dst}"
}

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
wait_for_apt_idle() {
  local waited=0
  local timeout=600
  while pgrep -f 'apt-get|apt.systemd.daily|unattended-upgrade|dpkg' >/dev/null 2>&1; do
    if (( waited >= timeout )); then
      echo "Timed out waiting for apt/dpkg lock holders"
      return 1
    fi
    echo "Waiting for apt/dpkg to become available... (${waited}s)"
    sleep 5
    waited=$((waited + 5))
  done
}

if command -v docker >/dev/null 2>&1; then
  echo "Docker already installed"
else
  export DEBIAN_FRONTEND=noninteractive
  for attempt in 1 2 3 4 5; do
    wait_for_apt_idle || exit 1
    if curl -fsSL https://get.docker.com | sh; then
      exit 0
    fi
    echo "Docker install attempt ${attempt}/5 failed, retrying..."
    sleep 10
  done
  echo "Docker install failed after retries"
  exit 1
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
wait_for_apt_idle() {
  local waited=0
  local timeout=600
  while pgrep -f 'apt-get|apt.systemd.daily|unattended-upgrade|dpkg' >/dev/null 2>&1; do
    if (( waited >= timeout )); then
      echo "Timed out waiting for apt/dpkg lock holders"
      return 1
    fi
    echo "Waiting for apt/dpkg to become available... (${waited}s)"
    sleep 5
    waited=$((waited + 5))
  done
}

apt_install() {
  local attempt
  for attempt in 1 2 3 4 5; do
    wait_for_apt_idle || return 1
    if apt-get -o DPkg::Lock::Timeout=120 update -y \
      && apt-get -o DPkg::Lock::Timeout=120 install -y "$@"; then
      return 0
    fi
    echo "apt install attempt ${attempt}/5 failed, retrying..."
    sleep 5
  done
  return 1
}

export DEBIAN_FRONTEND=noninteractive
if ! command -v wg >/dev/null 2>&1; then
  apt_install wireguard wireguard-tools
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

# Derive the node ID reliably from the node itself (hostname may not match --name).
REMOTE_NODE_ID="$(ssh_cmd "docker info --format '{{.Swarm.NodeID}}' 2>/dev/null" || true)"
REMOTE_DOCKER_NAME="$(ssh_cmd "docker info --format '{{.Name}}' 2>/dev/null" || true)"

NODE_ID="${REMOTE_NODE_ID}"
if [[ -z "${NODE_ID}" ]]; then
  # Fallback: best-effort match by hostname.
  NODE_ID="$(docker node ls --format '{{.ID}} {{.Hostname}}' | grep -i "${NODE_NAME}" | awk '{print $1}' || true)"
fi

[[ -n "${NODE_ID}" ]] || die "Cannot determine node ID (remote docker name='${REMOTE_DOCKER_NAME}', peer name='${NODE_NAME}')"

# Wait until the manager sees the node (eventual consistency right after join).
for _ in {1..30}; do
  docker node inspect "${NODE_ID}" >/dev/null 2>&1 && break
  sleep 1
done
docker node inspect "${NODE_ID}" >/dev/null 2>&1 || die "Node '${NODE_ID}' not visible in swarm yet (docker node inspect)"

docker node update --label-add role=vpn "${NODE_ID}" >/dev/null
docker node update --label-add channel="${NODE_CHANNEL}" "${NODE_ID}" >/dev/null
docker node update --label-add peer_name="${NODE_NAME}" "${NODE_ID}" >/dev/null || true
log "Labeled ${NODE_NAME} (docker name='${REMOTE_DOCKER_NAME}', node id=${NODE_ID}): role=vpn, channel=${NODE_CHANNEL}"

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
