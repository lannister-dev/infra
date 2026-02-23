#!/usr/bin/env bash
set -Eeuo pipefail

# NOTE:
# Terraform is the primary deployment orchestrator.
# This script is kept as a manual bootstrap fallback for host-level preparation.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE=".env"

log()  { echo "[BOOTSTRAP] $*"; }
warn() { echo "[BOOTSTRAP][WARN] $*" >&2; }
die()  { echo "[BOOTSTRAP][FAIL] $*" >&2; exit 1; }

[[ ${EUID:-999} -eq 0 ]] || die "Run as root"

# -------------------------
# load env (optional)
# -------------------------
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
else
  warn ".env not found at ${ENV_FILE} (role may be set externally)"
fi

INFRA_ROLE="${INFRA_ROLE:-infra}"   # infra|manager|vpn|app
if [[ "${INFRA_ROLE}" == "infra" ]]; then
  INFRA_ROLE="manager"
fi

log "Repo: ${ROOT_DIR}"
log "Role: ${INFRA_ROLE}"

# -------------------------
# ensure executable perms FIRST (kills 'Permission denied')
# -------------------------
  chmod +x \
  "${ROOT_DIR}/scripts/legacy/bootstrap.sh" \
  "${ROOT_DIR}/scripts/core/sanity-check.sh" \
  "${ROOT_DIR}/wireguard/apply.sh" \
  "${ROOT_DIR}/wireguard/manager/wireguard-manager.sh" \
  2>/dev/null || true

# -------------------------
# role: manager (Swarm bootstrap + configs)
# -------------------------
bootstrap_manager() {
  log "Manager bootstrap: packages + swarm prechecks (foundation is managed by Terraform)"

  command -v docker >/dev/null 2>&1 || die "Docker is not installed"

  if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active; then
    die "Docker Swarm is not initialized (run: docker swarm init)"
  fi

  if ! docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null | grep -q true; then
    die "This node is not a Swarm manager (ControlAvailable=false)"
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    ca-certificates curl jq unzip zip \
    wireguard wireguard-tools iproute2 iptables qrencode gettext-base

  command -v terraform >/dev/null 2>&1 || warn "Terraform is not installed on manager (required for local emergency runs)"

  log "✅ Manager host prerequisites are ready."
  log "Next step (declarative): run Terraform + Ansible from repository root."
  cat <<'EOF'
export REPO_ROOT="$(pwd)"
export ANSIBLE_CONFIG="$(pwd)/ansible/ansible.cfg"

terraform -chdir=terraform/foundation init -input=false -backend-config="$(pwd)/terraform/backends/foundation.hcl"
terraform -chdir=terraform/foundation apply -input=false

terraform -chdir=terraform/nodes init -input=false -backend-config="$(pwd)/terraform/backends/nodes.hcl"
terraform -chdir=terraform/nodes apply -input=false

ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/reconcile-vpn-nodes.yml
ansible-playbook -i ansible/inventory/production.ini ansible/playbooks/deploy-stacks.yml
EOF
}

# -------------------------
# role: vpn (DE node) - WireGuard + Xray ONLY
# -------------------------
bootstrap_vpn() {
  log "VPN bootstrap: WireGuard (Xray runs as Swarm service)"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl jq wireguard wireguard-tools iproute2 iptables

  bash "${ROOT_DIR}/wireguard/apply.sh" --install

  log "✅ VPN bootstrap completed successfully"
}

# -------------------------
# role: app (placeholder)
# -------------------------
bootstrap_app() {
  log "App role: no bootstrap steps defined (ok)"
}

# -------------------------
# main
# -------------------------
case "${INFRA_ROLE}" in
  manager) bootstrap_manager ;;
  vpn)     bootstrap_vpn ;;
  app)     bootstrap_app ;;
  *)       die "Unknown INFRA_ROLE=${INFRA_ROLE} (expected: manager|vpn|app|infra)" ;;
esac


